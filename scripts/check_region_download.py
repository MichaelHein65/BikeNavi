"""Check a real 3x3/5x5 region through the authenticated Pi API, including cache.

Uses local .env credentials without logging them. Saves only public OSM packages
under ignored build/region-live for an optional Swift client compatibility check.
"""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import time
import httpx


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--latitude',type=float,required=True)
    parser.add_argument('--longitude',type=float,required=True)
    parser.add_argument('--radius',type=int,choices=[1,2],default=1)
    args=parser.parse_args()
    if not math.isfinite(args.latitude) or not math.isfinite(args.longitude) or abs(args.latitude)>=75 or abs(args.longitude)>=179:
        parser.error('Choose a center within supported region bounds')
    root=Path(__file__).resolve().parents[1]
    settings={k.strip():v.strip().strip('\"\'') for line in (root/'.env').read_text().splitlines()
              if '=' in line and not line.lstrip().startswith('#') for k,v in [line.split('=',1)]}
    directory=root/'build/region-live';directory.mkdir(parents=True,exist_ok=True)
    x,y=math.floor((args.longitude+180)/.05),math.floor((args.latitude+90)/.05)
    total_bytes=0;nodes=set();edges=0;pois=set();packages=[];started=time.monotonic()
    with httpx.Client(base_url=settings['BIKENAVI_SERVER_URL'].rstrip('/'),timeout=120,
                      headers={'Authorization':'Bearer '+settings['BIKENAVI_TOKEN']}) as client:
        status=client.get('/v1/status');status.raise_for_status()
        assert status.json().get('offlineRegionsAvailable') is True
        assert client.get(f'/v1/region-tiles/{x}/{y}',headers={'Authorization':''}).status_code==401
        for yy in range(y-args.radius,y+args.radius+1):
            for xx in range(x-args.radius,x+args.radius+1):
                start=time.monotonic();response=client.get(f'/v1/region-tiles/{xx}/{yy}');response.raise_for_status()
                package=response.json();data=base64.b64decode(package['data'],validate=True)
                assert package['schema']==1 and package['bytes']==len(data)<=32*1024*1024
                assert hashlib.sha256(data).hexdigest()==package['sha256']
                tile=json.loads(data)
                assert tile['version']==1 and tile['compilerRevision']==3 and (tile['x'],tile['y'])==(xx,yy)
                assert 0<=time.time()-tile['generatedAt']<=30*86400
                total_bytes+=len(data);nodes.update(n['id'] for n in tile['nodes']);edges+=len(tile['edges']);pois.update(p['id'] for p in tile.get('pois',[]))
                packages.append((xx,yy,package['sha256']))
                (directory/f'{xx}-{yy}.json').write_text(json.dumps(package))
                print(f'{xx}/{yy}: {len(data)} bytes, {len(tile["nodes"])} nodes, {len(tile["edges"])} edges, {len(tile.get("pois",[]))} POIs, {time.monotonic()-start:.2f}s',flush=True)
        for xx,yy,digest in packages:
            response=client.get(f'/v1/region-tiles/{xx}/{yy}');response.raise_for_status()
            assert response.json()['sha256']==digest
        assert nodes and edges and total_bytes<=250*1024*1024
        assert len(nodes)<=50000 and edges<=200000
    (directory/'tiles.json').write_text(json.dumps([{'x':xx,'y':yy} for xx,yy,_ in packages]))
    print(f'PASS: {len(packages)} tiles + identical cache replay; {total_bytes} bytes; {len(nodes)} unique nodes; {edges} edges before merge; {len(pois)} unique POIs; {time.monotonic()-started:.2f}s',flush=True)


if __name__=='__main__':main()
