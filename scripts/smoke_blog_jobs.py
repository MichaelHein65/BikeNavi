"""Exercise detached Pi blog jobs with labelled public data, then delete the test ride."""
import json
from pathlib import Path
import time
from uuid import uuid4

import httpx

ROOT = Path(__file__).resolve().parents[1]
settings = {}
for line in (ROOT / '.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        settings[key.strip()] = value.strip().strip('"').strip("'")
headers = {'Authorization': 'Bearer ' + settings['BIKENAVI_TOKEN']}
route = json.loads((ROOT / 'tests/fixtures/heidelberg-elevation-route.json').read_text())
ride_id, generation_id = str(uuid4()), str(uuid4())
stamp = time.time()
ride = dict(id=ride_id, kind='ride', title='Heidelberg · Öffentliche Beispieltour · Fortschrittstest',
            createdAt=stamp, updatedAt=stamp, startedAt=stamp, endedAt=stamp+1200,
            recordingState='finished', movingDuration=1200, route=route,
            track=[dict(coordinate=point, timestamp=stamp+index, accuracy=5, speed=4, segment=0)
                   for index, point in enumerate(route['coordinates'])])
mutation = dict(mutationID=str(uuid4()), baseRevision=0, document=ride)
with httpx.Client(base_url=settings['BIKENAVI_SERVER_URL'], headers=headers, timeout=30) as client:
    assert client.get('/health').status_code == 200
    saved = client.post('/v1/mutations', json=mutation)
    saved.raise_for_status()
    try:
        path = f'/v1/rides/{ride_id}/blog-jobs'
        assert client.get(path, headers={'Authorization': ''}).status_code == 401
        assert client.get(path).json() is None
        point = dict(id=str(uuid4()), rideID=ride_id, coordinate=route['coordinates'][0], capturedAt=stamp,
                     title='Neckar · Öffentliche Beispieldaten', note='Synthetische Beispielnotiz; kein tatsächlicher Besuch.')
        response = client.post('/v1/blog-points', json=point)
        response.raise_for_status()
        begin = time.monotonic()
        started = client.post(path, params={'generation_id': generation_id})
        assert started.status_code == 202
        assert client.post(path, params={'generation_id': generation_id}).json()['generationID'] == generation_id
        seen = []
        while time.monotonic() - begin < 240:
            response = client.get(path + '/' + generation_id)
            response.raise_for_status()
            status = response.json()
            if status['phase'] not in seen:
                seen.append(status['phase'])
                print('Pi-Phase:', status['phase'], flush=True)
            assert client.get(path).json()['generationID'] == generation_id
            if status['phase'] in ('completed', 'failed'):
                break
            time.sleep(2)
        assert status['phase'] == 'completed', status.get('message')
        draft = client.get(f'/v1/rides/{ride_id}/blog', params={'draft_id': status['draftID']})
        draft.raise_for_status()
        assert draft.json()['id'] == status['draftID'] and draft.json()['mode'] == 'openai'
        print('Öffentlicher KI-Beispielauftrag erfolgreich:', round(time.monotonic()-begin, 1), 'Sekunden,', draft.json()['sourceCount'], 'Quellen.', flush=True)
    finally:
        response = client.post('/v1/mutations', json={**mutation, 'mutationID': str(uuid4()), 'baseRevision': saved.json()['revision'], 'deleted': True})
        response.raise_for_status()
        assert client.get(f'/v1/rides/{ride_id}/blog').status_code == 404
        assert client.get(path + '/' + generation_id).status_code == 404
        print('Technische Beispieltour mit Orten und Blog wieder entfernt.', flush=True)
