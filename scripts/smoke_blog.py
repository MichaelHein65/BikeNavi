"""Generate a public, labelled sample blog through the Pi; remove its test ride afterwards."""
import argparse
import base64
from pathlib import Path
import time
from uuid import uuid4

import httpx

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--photo', type=Path)
args = parser.parse_args()
settings = {}
for line in (ROOT/'.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k, v = line.split('=',1); settings[k.strip()] = v.strip().strip('"').strip("'")
url = settings['BIKENAVI_SERVER_URL']
assert url.startswith('https://')
headers = {'Authorization': 'Bearer '+settings['BIKENAVI_TOKEN']}
route = __import__('json').loads((ROOT/'tests/fixtures/heidelberg-elevation-route.json').read_text())
stamp=time.time()
ride = {'id': str(uuid4()), 'kind': 'ride', 'title': 'Heidelberg am Neckar · Öffentliche Beispieltour', 'createdAt': stamp, 'updatedAt': stamp,
        'startedAt': stamp, 'endedAt': stamp+1200, 'recordingState': 'finished', 'movingDuration': 1200, 'route': route,
        'track': [{'coordinate': c, 'timestamp': stamp+i, 'accuracy': 5, 'speed': 4, 'segment': 0} for i,c in enumerate(route['coordinates'])]}
mutation={'mutationID':str(uuid4()),'baseRevision':0,'document':ride}
with httpx.Client(base_url=url, headers=headers, timeout=180) as client:
    assert client.get('/health').status_code == 200
    assert client.get(f'/v1/rides/{ride["id"]}/blog',headers={'Authorization':''}).status_code == 401
    saved=client.post('/v1/mutations',json=mutation); saved.raise_for_status()
    try:
        stops=[('Neckarblick · Beispieldaten',{'latitude':49.414601,'longitude':8.681496},'Synthetische Beispielnotiz: eine kleine Pause am Neckar. Das Beispielbild ist das BikeNavi-Icon, kein vor Ort aufgenommenes Foto.'),
               ('Alte Brücke · Beispieldaten',{'latitude':49.4144,'longitude':8.7090},'Synthetische Beispielnotiz: kurzer Stopp mit Blick auf die Brücke. Kein tatsächlicher Besuch.'),
               ('Altstadt · Beispieldaten',{'latitude':49.4123,'longitude':8.7108},'Synthetische Beispielnotiz: Häuser und Gassen bewusst anschauen. Kein tatsächlicher Besuch.')]
        for i,(name,c,note) in enumerate(stops):
            point={'id':str(uuid4()),'rideID':ride['id'],'coordinate':c,'capturedAt':stamp+i*300,'title':name,'note':note}
            if i==0 and args.photo: point['photo']=base64.b64encode(args.photo.read_bytes()).decode()
            upload=client.post('/v1/blog-points',json=point); upload.raise_for_status()
            assert client.post('/v1/blog-points',json=point).json()==upload.json()
        begin=time.monotonic()
        response=client.post(f'/v1/rides/{ride["id"]}/blog'); response.raise_for_status()
        blog=response.json()
        assert blog['html'].startswith('<!doctype html>')
        assert client.get(f'/v1/rides/{ride["id"]}/blog').json()['id']==blog['id']
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(blog['html'])
        print('Pi-Blog erstellt: Modus',blog['mode'],'·',blog['sourceCount'],'Quellen ·',round(time.monotonic()-begin,1),'Sekunden')
        print('Hinweise:', *blog['warnings'], sep='\n')
        print('Öffentliches HTML-Beispiel:',args.output)
        if blog['mode'] != 'openai': raise RuntimeError('Live-KI-Schreibprüfung hat nur einen Vorlagenentwurf geliefert.')
    finally:
        deletion={**mutation,'mutationID':str(uuid4()),'baseRevision':saved.json()['revision'],'deleted':True}
        cleanup=client.post('/v1/mutations',json=deletion); cleanup.raise_for_status()
        assert client.get(f'/v1/rides/{ride["id"]}/blog').status_code==404
        print('Technische Beispielaufzeichnung samt Blog-Orten und Pi-Entwurf wieder entfernt.')
