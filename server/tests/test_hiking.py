import json
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from bikenavi.main import create_app
from bikenavi.models import Route
from bikenavi.hiking import merge_routes
from bikenavi.providers import parse_route

AUTH = {"Authorization": "Bearer test-token-long-enough-123456789012345"}
POINTS = [[8.68, 49.41], [8.681, 49.41], [8.682, 49.41]]


def data(points, difficulty=0, distance=200):
    return {"features": [{"geometry": {"coordinates": points}, "properties": {
        "summary": {"distance": distance, "duration": distance}, "way_points": [0, len(points)-1],
        "segments": [{"steps": [
            {"instruction": "Weiter", "distance": distance, "way_points": [0], "type": 11},
            {"instruction": "Ziel", "distance": 0, "way_points": [len(points)-1], "type": 10}]}],
        "extras": {"waytype": {"values": [[0, len(points)-1, 3]]}, "traildifficulty": {"values": [[0, len(points)-1, difficulty]]},
                   "surface": {"values": [[0, len(points)-1, 3]],
                               "summary": [{"value": 3, "distance": distance, "amount": 100}]}}}}]}


def request(mode="hiking"):
    return {"profile": {"travelMode": mode, "surface": "pavedOnly", "electric": False},
            "waypoints": [{"id": str(uuid4()), "name": "Beispiel", "coordinate":
                           {"longitude": p[0], "latitude": p[1]}} for p in [POINTS[0], POINTS[-1]]]}


def client(tmp_path, handler):
    return TestClient(create_app(f"sqlite:///{tmp_path / 'hiking.sqlite'}", "test-token-long-enough-123456789012345",
                                "test-ors", httpx.MockTransport(handler)))


@pytest.mark.parametrize("difficulty,expected", [(0,200),(1,200),(2,422),(3,422),(4,422),(5,422),(6,422)])
def test_walking_filters_difficulty_and_ignores_bike_surface(tmp_path, difficulty, expected):
    def handler(req):
        assert "foot-walking" in req.url.path
        body = json.loads(req.content)
        assert "traildifficulty" in body["extra_info"]
        assert "options" not in body  # bike surface/hill controls never sent to foot profile
        return httpx.Response(200, json=data(POINTS, difficulty))
    with client(tmp_path, handler) as app:
        response = app.post("/v1/route?include_context=false", headers=AUTH, json=request())
        assert response.status_code == expected
        if expected == 200:
            route = response.json()
            assert route["walkingStartIndex"] == 0 and route["cyclingDistance"] == 0
            assert route["walkingDistance"] == route["distance"]
            assert any("Fehlende" in w for w in route["warnings"])


@pytest.mark.parametrize("ranges", [[], [[0,1,0]], [[0,2,0],[1,2,1]], [[0,2,-1]], [[0,2,True]]])
def test_missing_malformed_or_incomplete_difficulty_is_not_approved(tmp_path, ranges):
    raw = data(POINTS)
    raw["features"][0]["properties"]["extras"]["traildifficulty"]["values"] = ranges
    with client(tmp_path, lambda r: httpx.Response(200,json=raw)) as app:
        assert app.post("/v1/route?include_context=false", headers=AUTH,json=request()).status_code in (422,502)


def test_mixed_routing_keeps_mandatory_stops_and_marks_connected_transition(tmp_path):
    body = request("bikeAndHike")
    body["waypoints"].insert(1, dict(body["waypoints"][0], id=str(uuid4()), coordinate={"longitude":8.6805,"latitude":49.41}))
    bike_calls = []
    def handler(req):
        payload = json.loads(req.content)
        if "/snap/" in req.url.path:
            return httpx.Response(200, json={"locations": [{"location": POINTS[1]} for p in payload["locations"]]})
        coords = payload["coordinates"]
        if "cycling" in req.url.path:
            bike_calls.append(coords)
            if coords[-1] == POINTS[-1]:
                return httpx.Response(404)
            raw = data(coords, distance=100)
            raw["features"][0]["properties"]["way_points"] = list(range(len(coords)))
            return httpx.Response(200, json=raw)
        return httpx.Response(200, json=data(coords, distance=80))
    with client(tmp_path, handler) as app:
        result = app.post("/v1/route?include_context=false",headers=AUTH,json=body)
        assert result.status_code == 200, result.text
        route = result.json()
        assert route["walkingStartIndex"] == 2
        assert route["coordinates"][2]["longitude"] == POINTS[1][0]
        assert route["waypointIndices"] == [0,1,3]
        assert route["walkingDistance"] == 80 and route["cyclingDistance"] == 100
        assert route["distance"] == 180
        assert len(route["surfaceSections"]) == 2
        assert any("Rad abstellen" in m["instruction"] for m in route["maneuvers"])
        assert all(coords[1] == [8.6805,49.41] for coords in bike_calls)
        Route.model_validate(route)


def test_all_cycle_needs_no_parking_and_never_calls_foot(tmp_path):
    def handler(req):
        assert "cycling" in req.url.path
        return httpx.Response(200,json=data(POINTS))
    with client(tmp_path,handler) as app:
        route=app.post("/v1/route?include_context=false",headers=AUTH,json=request("bikeAndHike")).json()
        assert route.get("walkingStartIndex") is None
        assert any("vollständig" in w for w in route["warnings"])


def test_disconnected_transition_never_draws_a_straight_connection():
    bike = parse_route(data(POINTS[:2]))
    walk = parse_route(data([POINTS[0],POINTS[-1]]))
    with pytest.raises(Exception, match="nicht verbunden"):
        merge_routes(bike,walk)


@pytest.mark.parametrize("changes", [{"walkingStartIndex":3}, {"walkingDistance":500}, {"cyclingDistance":None},
                                        {"walkingStartIndex":0,"cyclingDistance":10,"walkingDistance":190}])
def test_invalid_mode_indices_and_distances_cannot_enter_archive(changes):
    route = parse_route(data(POINTS))
    route.update(walkingStartIndex=1, walkingDistance=100, cyclingDistance=100)
    route.update(changes)
    with pytest.raises(ValueError):
        Route.model_validate(route)


def test_snapped_far_from_target_is_rejected(tmp_path):
    with client(tmp_path, lambda r: httpx.Response(200,json=data([[8.67,49.41],[8.671,49.41]]))) as app:
        assert app.post("/v1/route?include_context=false",headers=AUTH,json=request()).status_code == 422


def test_mixed_skips_unreachable_candidate_and_minimizes_actual_walk(tmp_path):
    candidates = [[8.6818,49.41],[8.6815,49.41],[8.681,49.41]]
    def handler(req):
        payload=json.loads(req.content)
        if '/snap/' in req.url.path:
            return httpx.Response(200,json={'locations':[{'location':candidates[min(i,2)]} for i in range(len(payload['locations']))]})
        coords=payload['coordinates']
        if 'cycling' in req.url.path:
            if coords[-1] in [POINTS[-1],candidates[0]]:
                return httpx.Response(404)
            return httpx.Response(200,json=data(coords,distance=100))
        if coords[0] == POINTS[0]:
            return httpx.Response(200,json=data([POINTS[0],[8.686,49.41],POINTS[-1]],distance=600))
        return httpx.Response(200,json=data(coords,distance=50 if coords[0]==candidates[2] else 200))
    with client(tmp_path,handler) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=request('bikeAndHike'))
        assert result.status_code==200,result.text
        route=result.json()
        assert route['walkingDistance']==50
        assert route['coordinates'][route['walkingStartIndex']]['longitude']==candidates[2][0]


def test_long_cycle_approach_only_requests_walking_in_target_area(tmp_path):
    body=request('bikeAndHike')
    body['waypoints'][0]['coordinate']['longitude']=8.0
    calls=[]
    def handler(req):
        payload=json.loads(req.content)
        if '/snap/' in req.url.path:
            calls.append(payload['radius'])
            return httpx.Response(200,json={'locations':[{'location':POINTS[1]} for p in payload['locations']]})
        coords=payload['coordinates']
        if 'cycling' in req.url.path:
            if coords[-1]==POINTS[-1]:
                return httpx.Response(404)
            return httpx.Response(200,json=data(coords))
        assert coords[0][0]>8.68  # never ask walking from remote bike start
        return httpx.Response(200,json=data(coords))
    with client(tmp_path,handler) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=body)
        assert result.status_code==200,result.text
        assert calls==[5000,100]


@pytest.mark.parametrize('locations', [[None], [{'location':[999,49]}], []])
def test_missing_or_malformed_cycle_connections_fail_cleanly(tmp_path, locations):
    def handler(req):
        if '/snap/' in req.url.path:
            count=len(json.loads(req.content)['locations'])
            values=locations * count if locations else []
            return httpx.Response(200,json={'locations':values})
        if 'cycling' in req.url.path:
            return httpx.Response(404)
        return httpx.Response(200,json=data(POINTS))
    with client(tmp_path,handler) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=request('bikeAndHike'))
        assert result.status_code in (422,502)


def test_walking_mode_and_transition_survive_sync(tmp_path):
    route=parse_route(data(POINTS))
    route.update(walkingStartIndex=1,walkingDistance=80,cyclingDistance=120)
    with client(tmp_path,lambda req:httpx.Response(200,json=data(POINTS))) as app:
        change={'mutationID':str(uuid4()),'baseRevision':0,'document':{
            'id':str(uuid4()),'kind':'plan','title':'Rad & Wandern · Beispiel',
            'createdAt':0,'updatedAt':0,'profile':{'travelMode':'bikeAndHike'},'route':route}}
        result=app.post('/v1/mutations',headers=AUTH,json=change)
        assert result.status_code==200,result.text
        saved=app.get('/v1/changes',headers=AUTH).json()['records'][0]['document']
        assert saved['profile']['travelMode']=='bikeAndHike'
        assert saved['route']['walkingStartIndex']==1
        assert saved['route']['walkingDistance']==80


def test_poi_outside_both_networks_keeps_bike_approach_and_marks_missing_access(tmp_path):
    body=request('bikeAndHike')
    body['waypoints'][-1]['coordinate']['latitude']=49.413
    def handler(req):
        if '/snap/foot-walking/' in req.url.path:
            return httpx.Response(200,json={'locations':[{'location':POINTS[-1]}]})
        assert 'cycling' in req.url.path
        return httpx.Response(200,json=data(POINTS))
    with client(tmp_path,handler) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=body)
        assert result.status_code==200,result.text
        route=result.json()
        assert route['walkingStartIndex']==len(POINTS)-1
        assert route['walkingDistance']==0 and route['cyclingDistance']==route['distance']
        assert 330 < route['unmappedDestinationDistance'] < 340
        assert len(route['coordinates'])==len(POINTS)  # no invented access edge
        assert any('nicht auf Kletterfreiheit geprüft' in w for w in route['warnings'])
        Route.model_validate(route)


def test_walking_poi_can_be_away_from_network_with_explicit_missing_access(tmp_path):
    body=request()
    body['waypoints'][-1]['coordinate']['latitude']=49.413
    with client(tmp_path,lambda req:httpx.Response(200,json=data(POINTS))) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=body)
        assert result.status_code==200,result.text
        assert result.json()['unmappedDestinationDistance']>330
        assert any('Ziel' in w and 'nicht berechnet' in w for w in result.json()['warnings'])


def test_terminal_generic_path_becomes_walking_even_when_bike_provider_reaches_goal(tmp_path):
    # A long trail used to consume every nearby parking candidate. Exact trail
    # boundary must now be checked, and pedestrian bike output rejected.
    points = [[8.68,49.41], [8.69,49.41], [8.70,49.41]]
    body = request("bikeAndHike")
    body["profile"]["surface"] = "preferPaved"
    body["waypoints"][-1]["coordinate"]["longitude"] = 8.70
    snaps = []
    def handler(req):
        payload = json.loads(req.content)
        if "/snap/" in req.url.path:
            snaps.extend(payload["locations"])
            return httpx.Response(200, json={"locations": [{"location": p} for p in payload["locations"]]})
        coords = payload["coordinates"]
        if coords[-1] == points[-1] and ("cycling" in req.url.path or coords[0] == points[0]):
            raw = data(points, distance=1450)
            raw["features"][0]["properties"]["extras"]["waytype"]["values"] = [[0,1,3],[1,2,4]]
            return httpx.Response(200,json=raw)
        return httpx.Response(200,json=data(coords, distance=725 if "cycling" in req.url.path else
                                             725 + (8.69-coords[0][0])*100000))
    with client(tmp_path,handler) as app:
        result = app.post('/v1/route?include_context=false',headers=AUTH,json=body)
        assert result.status_code == 200, result.text
        route = result.json()
        assert route['walkingDistance'] == 725
        assert route['cyclingDistance'] == 725
        assert route['coordinates'][route['walkingStartIndex']]['longitude'] == 8.69
        assert snaps[0] == points[1]
        assert all(p[0] <= 8.69 for p in snaps)
        Route.model_validate(route)


def test_strict_surface_does_not_block_foot_leg_and_reports_all_walking_fallback(tmp_path):
    def handler(req):
        payload=json.loads(req.content)
        if '/snap/' in req.url.path:
            return httpx.Response(200,json={'locations':[{'location':POINTS[1]} for p in payload['locations']]})
        raw=data(payload['coordinates'],distance=200)
        if 'cycling' in req.url.path:
            raw['features'][0]['properties']['extras']['surface']['summary']=[{'value':0,'distance':200,'amount':100}]
        return httpx.Response(200,json=raw)
    with client(tmp_path,handler) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=request('bikeAndHike'))
        assert result.status_code==200,result.text
        route=result.json()
        assert route['cyclingDistance']==0 and route['walkingStartIndex']==0
        assert route['walkingDistance']==route['distance']
        assert any('Radanteil 0 m' in w for w in route['warnings'])


@pytest.mark.parametrize('kind', [4,7,8])
def test_combined_mode_rejects_pedestrian_bike_prefix(kind):
    from bikenavi.hiking import validate_cycling
    raw=data(POINTS)
    raw['features'][0]['properties']['extras']['waytype']['values']=[[0,2,kind]]
    with pytest.raises(Exception,match='Wanderanteil'):
        validate_cycling(raw,parse_route(raw))


@pytest.mark.parametrize('values', [[],[[0,1,3]],[[0,2,True]],[[1,2,3]]])
def test_incomplete_waytypes_do_not_approve_cycling(values):
    from bikenavi.hiking import validate_cycling
    raw=data(POINTS)
    raw['features'][0]['properties']['extras']['waytype']['values']=values
    with pytest.raises(Exception,match='Wegarten'):
        validate_cycling(raw,parse_route(raw))


def test_strict_foot_fallback_does_not_move_mandatory_stop_to_walking(tmp_path):
    body=request('bikeAndHike')
    body['waypoints'].insert(1,dict(body['waypoints'][0],id=str(uuid4()),coordinate={'longitude':8.6805,'latitude':49.41}))
    def handler(req):
        payload=json.loads(req.content)
        if '/snap/' in req.url.path:
            return httpx.Response(200,json={'locations':[{'location':POINTS[1]} for p in payload['locations']]})
        raw=data(payload['coordinates'],distance=200)
        if 'cycling' in req.url.path:
            raw['features'][0]['properties']['extras']['surface']['summary']=[{'value':0,'distance':200,'amount':100}]
        return httpx.Response(200,json=raw)
    with client(tmp_path,handler) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=body)
        assert result.status_code==422,result.text


def test_ordinary_cycling_keeps_existing_provider_path_behavior(tmp_path):
    body=request('cycling')
    body['profile']['surface']='any'
    raw=data(POINTS)
    raw['features'][0]['properties']['extras']['waytype']['values']=[[0,2,4]]
    with client(tmp_path,lambda req:httpx.Response(200,json=raw)) as app:
        result=app.post('/v1/route?include_context=false',headers=AUTH,json=body)
        assert result.status_code==200,result.text
        assert result.json().get('walkingStartIndex') is None
