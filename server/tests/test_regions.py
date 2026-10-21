import base64
import hashlib
import json
import httpx
from fastapi.testclient import TestClient
from bikenavi.main import create_app
from bikenavi.offline import compile_tile
from bikenavi.regions import extract_pois, tile_package
from test_offline import elements, TOKEN, AUTH


def test_quality_is_observed_and_unknown_not_flat():
    unknown = compile_tile(elements({'surface': 'unknown'}), 1, 1)['edges'][0]
    assert unknown['surface'] == 0 and unknown['inclineKnown'] is False
    assert unknown['roadClass'] == 'residential' and unknown['cycleway'] is False
    edges = compile_tile(elements({'highway': 'cycleway', 'incline': '6%'}), 1, 1)['edges']
    assert edges[0]['cycleway'] is True and edges[0]['inclineKnown'] is True
    assert {edge['incline'] for edge in edges} == {6, -6}
    assert compile_tile(elements({'bicycle': 'no'}), 1, 1)['edges'] == []


def test_region_endpoint_checksum_auth_and_bounds(tmp_path):
    app = create_app(f'sqlite:///{tmp_path / "db"}', token=TOKEN, overpass_url='https://example.test',
                     transport=httpx.MockTransport(lambda _: httpx.Response(200, json={'elements': elements()})))
    with TestClient(app) as client:
        assert client.get('/v1/region-tiles/3760/2780').status_code == 401
        assert client.get('/v1/region-tiles/-1/2780', headers=AUTH).status_code == 422
        response = client.get('/v1/region-tiles/3760/2780', headers=AUTH)
        assert response.status_code == 200
        package = response.json(); data = base64.b64decode(package['data'])
        assert package['sha256'] == hashlib.sha256(data).hexdigest()
        assert package['bytes'] == len(data)
        assert json.loads(data)['compilerRevision'] == 3
        assert tile_package(json.loads(data)) == package


def test_offline_pois_provenance_filters_and_unicode():
    base = {'type': 'node', 'id': 1, 'lat': 49, 'lon': 8, 'tags': {'amenity': 'drinking_water', 'name': 'Öffentliches Beispiel'}}
    result = extract_pois([base])
    assert result[0]['category'] == 'water' and result[0]['source'] == 'OpenStreetMap'
    assert result[0]['id'] == 'node/1'
    for tags in [{'access': 'private'}, {'drinking_water': 'no'}]:
        assert extract_pois([{**base, 'tags': {**base['tags'], **tags}}]) == []
    assert extract_pois([{**base, 'lat': 100}]) == []
    assert extract_pois([{**base, 'tags': {'tourism': 'museum'}}])[0]['category'] == 'tourism'


def test_quality_route_sync_roundtrip_and_invalid_indices(tmp_path):
    from test_api import mutation
    # Use the same minimal legacy mutation fixture as the API suite.
    change = mutation()
    change['document']['profile'] = {'cyclePreference': 'quiet'}
    change['document']['route'] = {'id': change['document']['id'], 'coordinates': [
        {'latitude': 49, 'longitude': 8}, {'latitude': 49.001, 'longitude': 8.001}],
        'distance': 120, 'duration': 30, 'ascent': 0, 'descent': 0, 'maneuvers': [], 'surfaces': [],
        'warnings': [], 'provider': 'BikeNavi iPhone · OpenStreetMap', 'calculatedAt': 1,
        'cycleQuality': [{'startIndex': 0, 'endIndex': 1, 'surface': 0, 'source': 'OpenStreetMap'}]}
    app = create_app(f'sqlite:///{tmp_path / "sync.db"}', token=TOKEN)
    with TestClient(app) as client:
        result = client.post('/v1/mutations', json=change, headers=AUTH)
        assert result.status_code == 200
        assert result.json()['document']['route']['cycleQuality'][0]['roadClass'] is None
        assert client.post('/v1/mutations', json=change, headers=AUTH).status_code == 200
        change['document']['route']['cycleQuality'][0]['endIndex'] = 2
        assert client.post('/v1/mutations', json=change, headers=AUTH).status_code == 422
