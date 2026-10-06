import json
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from bikenavi.main import create_app

TOKEN = 'elevation-test-' + 'x' * 40
AUTH = {'Authorization': 'Bearer ' + TOKEN}
POINTS = [{'longitude': 15.6413587, 'latitude': 43.7989022},
          {'longitude': 15.6418, 'latitude': 43.7993}]


def app(tmp_path, handler, key='test-ors-key'):
    return create_app(f'sqlite:///{tmp_path / "elevation.sqlite"}', token=TOKEN,
                      ors_key=key, transport=httpx.MockTransport(handler))


def test_height_lookup_preserves_geometry_and_uses_server_key(tmp_path):
    calls = []
    def upstream(request):
        calls.append(request)
        assert str(request.url) == 'https://api.heigit.org/openelevationservice/v0/line'
        assert request.headers['Authorization'] == 'test-ors-key'
        data = json.loads(request.content)
        assert data == {'format_in': 'polyline', 'format_out': 'polyline',
                        'geometry': [[c['longitude'], c['latitude']] for c in POINTS]}
        return httpx.Response(200, json={'geometry': [[*p, h] for p, h in zip(data['geometry'], [0, -20])]})
    with TestClient(app(tmp_path, upstream)) as client:
        assert client.post('/v1/elevation', json={'coordinates': POINTS}).status_code == 401
        result = client.post('/v1/elevation', headers=AUTH, json={'coordinates': POINTS})
        assert result.status_code == 200
        assert result.json() == {'altitudes': [0, -20], 'source': 'openrouteservice · SRTM'}
        assert len(calls) == 1
        assert 'test-ors-key' not in result.text


@pytest.mark.parametrize('failure', ['timeout', 'quota', 'null', 'missing', 'reordered', 'nodata', 'nonjson'])
def test_upstream_failures_are_explicit_not_zero_heights(tmp_path, failure):
    def upstream(request):
        points = [[c['longitude'], c['latitude'], 10] for c in POINTS]
        if failure == 'timeout':
            raise httpx.ReadTimeout('secret-upstream-detail', request=request)
        if failure == 'quota':
            return httpx.Response(429, text='secret-upstream-detail')
        if failure == 'null': points[0][2] = None
        if failure == 'missing': points.pop()
        if failure == 'reordered': points.reverse()
        if failure == 'nodata': points[0][2] = -32768
        if failure == 'nonjson': return httpx.Response(200, text='not json')
        return httpx.Response(200, json={'geometry': points})
    with TestClient(app(tmp_path, upstream)) as client:
        result = client.post('/v1/elevation', headers=AUTH, json={'coordinates': POINTS})
        assert result.status_code == 503
        assert 'secret-upstream-detail' not in result.text
        assert 'altitudes' not in result.json()


def test_limits_and_missing_configuration(tmp_path):
    def upstream(_):
        pytest.fail('Invalid requests must not call upstream')
    with TestClient(app(tmp_path, upstream, key='')) as client:
        assert client.post('/v1/elevation', headers=AUTH, json={'coordinates': POINTS}).status_code == 503
        for points in [POINTS[:1], POINTS * 1001, [{'latitude': 91, 'longitude': 0}] * 2]:
            assert client.post('/v1/elevation', headers=AUTH, json={'coordinates': points}).status_code == 422


def test_profile_sync_round_trip_and_validation(tmp_path):
    with TestClient(app(tmp_path, lambda _: httpx.Response(503))) as client:
        profile = [{'distance': 0, 'altitude': 0}, {'distance': 25, 'altitude': 5}, {'distance': 50, 'altitude': 1}]
        route = dict(id=str(uuid4()), coordinates=POINTS, distance=50, duration=10,
                     ascent=5, descent=4, calculatedAt=1, provider='BikeNavi iPhone · OpenStreetMap',
                     elevationProfile=profile, elevationSource='openrouteservice · SRTM')
        document = dict(id=str(uuid4()), kind='plan', title='Öffentliche Höhentestpunkte', createdAt=1, updatedAt=1, route=route)
        body = dict(mutationID=str(uuid4()), baseRevision=0, deleted=False, document=document)
        result = client.post('/v1/mutations', headers=AUTH, json=body)
        assert result.status_code == 200
        loaded = client.get('/v1/changes', headers=AUTH).json()['records'][0]['document']['route']
        assert loaded['elevationProfile'] == profile
        assert loaded['elevationSource'] == route['elevationSource']
        assert loaded['ascent'] == 5
        route['elevationProfile'] = [profile[0], profile[2], profile[1]]
        body['mutationID'] = str(uuid4())
        assert client.post('/v1/mutations', headers=AUTH, json=body).status_code == 422


def test_small_interior_void_is_aligned_and_interpolated(tmp_path):
    points = [{'longitude': 8 + i * 0.0004, 'latitude': 49} for i in range(5)]
    def upstream(request):
        geometry = json.loads(request.content)['geometry']
        # Like the Tribunj route: one omitted sample, all later heights shifted
        # in the upstream array. Matching by coordinate keeps their correct index.
        return httpx.Response(200, json={'geometry': [[*p, i * 10] for i, p in enumerate(geometry) if i != 2]})
    with TestClient(app(tmp_path, upstream)) as client:
        result = client.post('/v1/elevation', headers=AUTH, json={'coordinates': points})
        assert result.status_code == 200
        assert result.json()['altitudes'] == pytest.approx([0, 10, 20, 30, 40])
        assert '1 fehlender Höhenpunkt interpoliert' in result.json()['source']


@pytest.mark.parametrize('removed,spacing', [([0], .0004), ([4], .0004),
                                             ([1, 2, 3], .0001), ([2], .002)])
def test_missing_endpoints_or_long_voids_remain_unavailable(removed, spacing):
    from bikenavi.elevation import align_heights
    points = [[8 + i * spacing, 49] for i in range(5)]
    values = [[*p, 10] for i, p in enumerate(points) if i not in removed]
    with pytest.raises(ValueError):
        align_heights(points, values)


def test_multiple_short_voids_keep_zero_and_negative_values():
    from bikenavi.elevation import align_heights
    points = [[8 + i * .0002, 49] for i in range(6)]
    values = [[*points[i], h] for i, h in [(0, -10), (3, 20), (5, 0)]]
    heights, count = align_heights(points, values)
    assert heights == pytest.approx([-10, 0, 10, 20, 10, 0], abs=1e-6)
    assert count == 3
