from datetime import datetime, timezone, timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3

import httpx
import osmium
import pytest
from fastapi.testclient import TestClient
from bikenavi.main import create_app
from bikenavi.offline import compile_tile
from bikenavi.osm_extract import LocalExtracts, extract_elements
from test_offline import AUTH, TOKEN

spec = importlib.util.spec_from_file_location('prepare_extract', Path(__file__).resolve().parents[2] / 'scripts/prepare_offline_extract.py')
prepare = importlib.util.module_from_spec(spec); spec.loader.exec_module(prepare)


def make_extract(tmp_path, age=1):
    pbf = tmp_path / 'source.osm.pbf'
    header = osmium.io.Header()
    stamp = (datetime.now(timezone.utc)-timedelta(days=age)).strftime('%Y-%m-%dT%H:%M:%SZ')
    header.set('osmosis_replication_timestamp', stamp)
    with osmium.SimpleWriter(str(pbf), header=header) as writer:
        for id,lon,tags in [(1,15.62,{}),(2,15.64,{'amenity':'drinking_water'}),
                            (3,15.67,{'barrier':'gate','access':'private'}),
                            (4,15.63,{}),(5,15.631,{})]:
            writer.add_node(osmium.osm.mutable.Node(id=id,location=(lon,43.77),version=7,tags=tags))
        writer.add_way(osmium.osm.mutable.Way(id=10,nodes=[1,2,3],tags={'highway':'residential','surface':'asphalt'}))
        writer.add_way(osmium.osm.mutable.Way(id=11,nodes=[4,5],tags={'amenity':'shelter'}))
        writer.add_relation(osmium.osm.mutable.Relation(id=20,members=[('w',10,'from'),('n',2,'via'),('w',30,'to')],
                                                     tags={'type':'restriction','restriction':'no_left_turn'}))
        writer.add_relation(osmium.osm.mutable.Relation(id=21,members=[('w',11,'outer')],tags={'tourism':'museum'}))
    poly = tmp_path / 'coverage.poly'
    poly.write_text('synthetic example\n1\n15.5 43.6\n15.8 43.6\n15.8 43.9\n15.5 43.9\n15.5 43.6\nEND\nEND\n')
    output = tmp_path / 'example.sqlite'
    prepare.prepare(pbf, poly, output)
    return output


def test_extract_complete_ways_restrictions_pois_and_node_access(tmp_path):
    output = make_extract(tmp_path)
    elements, stamp = LocalExtracts(tmp_path).tile(3912,2675)
    assert all('nodes' not in e for e in elements if e['type']=='way' and e['id']==11)
    assert {n['id'] for n in elements if n['type']=='node'} >= {1,2,3}
    tile = compile_tile(elements,3912,2675,generated_at=stamp)
    assert tile['generatedAt'] == stamp
    assert tile['blockedNodes'] == [3]  # outside bbox, still retained from complete way
    assert len(tile['edges']) == 2
    assert tile['restrictions'][0]['fromWay'] == 10
    assert {p['id'] for p in tile['pois']} == {'node/2','way/11','relation/21'}
    assert len(tile['pois']) == 3  # road node selected twice does not duplicate a POI
    assert tile['nodes'][0]['osmVersion'] == 7
    assert LocalExtracts(tmp_path).tile(3900,2675) is None
    # Boundary and ocean gaps are not silently presented as a complete country tile.
    assert LocalExtracts(tmp_path).tile(3910,2672) is None
    with pytest.raises(ValueError, match='new versioned'):
        prepare.prepare(tmp_path/'source.osm.pbf',tmp_path/'coverage.poly',output)


def test_extract_age_and_integrity(tmp_path):
    make_extract(tmp_path,age=31)
    assert LocalExtracts(tmp_path).tile(3912,2675) is None
    metadata = tmp_path/'example.json'
    data=json.loads(metadata.read_text());data['sourceDate']=datetime.now(timezone.utc).isoformat();metadata.write_text(json.dumps(data))
    with pytest.raises(ValueError,match='provenance'):
        LocalExtracts(tmp_path).tile(3912,2675)
    data['sha256']='0'*64;metadata.write_text(json.dumps(data))
    with pytest.raises(ValueError,match='checksum'):
        LocalExtracts(tmp_path).tile(3912,2675)


def test_missing_referenced_node_is_not_partial_success(tmp_path):
    output=make_extract(tmp_path)
    with sqlite3.connect(output) as conn:conn.execute('DELETE FROM nodes WHERE id=3')
    with pytest.raises(ValueError,match='incomplete'):
        extract_elements(output,(15.6,43.75,15.65,43.8))


def test_region_endpoint_works_without_overpass_and_refresh_retains_source_date(tmp_path,monkeypatch):
    directory=tmp_path/'maps';directory.mkdir();make_extract(directory)
    monkeypatch.setenv('OFFLINE_EXTRACT_DIR',str(directory))
    calls=[]
    def upstream(request):
        calls.append(request);return httpx.Response(503)
    app=create_app(f'sqlite:///{tmp_path/"api.sqlite"}',token=TOKEN,overpass_url='',transport=httpx.MockTransport(upstream))
    with TestClient(app) as client:
        first=client.get('/v1/region-tiles/3912/2675',headers=AUTH)
        assert first.status_code==200
        assert client.get('/v1/region-tiles/3912/2675?refresh=true',headers=AUTH).json()==first.json()
        assert client.get('/v1/region-tiles/3900/2675',headers=AUTH).status_code==503
        assert calls==[]


def test_corrupt_local_source_can_use_configured_provider(tmp_path,monkeypatch):
    directory=tmp_path/'maps';directory.mkdir();(directory/'broken.json').write_text('{')
    monkeypatch.setenv('OFFLINE_EXTRACT_DIR',str(directory))
    from test_offline import elements
    app=create_app(f'sqlite:///{tmp_path/"api.sqlite"}',token=TOKEN,overpass_url='https://example.test',
                   transport=httpx.MockTransport(lambda _:httpx.Response(200,json={'elements':elements()})))
    with TestClient(app) as client:
        assert client.get('/v1/region-tiles/3912/2675',headers=AUTH).status_code==200
