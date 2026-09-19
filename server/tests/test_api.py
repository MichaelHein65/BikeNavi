from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from bikenavi.main import create_app
from bikenavi.models import Mutation
from bikenavi.storage import Receipt

TOKEN = "test-token-" + "a" * 40
AUTH = {"Authorization": "Bearer " + TOKEN}


@pytest.fixture
def client(tmp_path):
    app = create_app(f"sqlite:///{tmp_path / 'test.sqlite'}", token=TOKEN, ors_key="")
    with TestClient(app) as client:
        yield client


def mutation(document_id=None, revision=0, title="Testtour"):
    return {"mutationID": str(uuid4()), "baseRevision": revision, "deleted": False,
            "document": {"id": str(document_id or uuid4()), "kind": "plan", "title": title,
                         "createdAt": 1, "updatedAt": 2, "waypoints": []}}


def route_request(surface="any"):
    return {"waypoints": [{"id": str(uuid4()), "name": "A", "coordinate": {"longitude": 8.68, "latitude": 49.41}},
                          {"id": str(uuid4()), "name": "B", "coordinate": {"longitude": 8.69, "latitude": 49.42}}],
            "profile": {"bike": "touring", "electric": False, "surface": surface}}


def upstream_route(surface=3, distance=100):
    return {"features": [{"geometry": {"type": "LineString", "coordinates": [[8.68, 49.41, 101], [8.69, 49.42, 110]]},
                          "properties": {"summary": {"distance": distance, "duration": 90}, "ascent": 9,
                                         "segments": [{"steps": [{"instruction": "Rechts abbiegen", "distance": 100, "way_points": [0, 1], "type": 1}]}],
                                         "extras": {"surface": {"values": [[0, 1, surface]], "summary": [{"value": surface, "distance": distance, "amount": 100}]}}}}]}


def test_authentication_and_no_secret_exposure(client):
    assert client.get("/health").json() == {"status": "ok", "version": "0.1.0"}
    for path in ["/v1/status", "/v1/changes"]:
        assert client.get(path).status_code == 401
    assert client.post("/v1/mutations", json=mutation()).status_code == 401
    assert TOKEN not in client.get("/v1/status", headers=AUTH).text


def test_retry_does_not_duplicate_a_tour_or_change(client):
    change = mutation()
    a = client.post("/v1/mutations", json=change, headers=AUTH)
    b = client.post("/v1/mutations", json=change, headers=AUTH)
    assert a.status_code == b.status_code == 200
    assert a.json() == b.json()
    page = client.get("/v1/changes", headers=AUTH).json()
    assert len(page["records"]) == 1
    assert page["records"][0]["revision"] == 1


def test_reusing_mutation_id_with_different_content_is_rejected(client):
    change = mutation()
    assert client.post("/v1/mutations", json=change, headers=AUTH).status_code == 200
    change["document"]["title"] = "Changed"
    assert client.post("/v1/mutations", json=change, headers=AUTH).status_code == 409


def test_offline_concurrent_edits_never_silently_overwrite(client):
    initial = mutation()
    client.post("/v1/mutations", json=initial, headers=AUTH)
    a = mutation(initial["document"]["id"], revision=1, title="Gerät A")
    b = mutation(initial["document"]["id"], revision=1, title="Gerät B")
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda m: client.post("/v1/mutations", json=m, headers=AUTH), [a, b]))
    assert sorted(r.status_code for r in results) == [200, 409]
    assert len(client.get("/v1/changes", headers=AUTH).json()["records"]) == 2


def test_tombstone_and_cursor(client):
    change = mutation()
    client.post("/v1/mutations", json=change, headers=AUTH)
    cursor = client.get("/v1/changes", headers=AUTH).json()["cursor"]
    deletion = mutation(change["document"]["id"], revision=1)
    deletion["deleted"] = True
    assert client.post("/v1/mutations", json=deletion, headers=AUTH).status_code == 200
    page = client.get(f"/v1/changes?after={cursor}", headers=AUTH).json()
    assert len(page["records"]) == 1 and page["records"][0]["deleted"]
    assert client.get(f"/v1/changes?after={page['cursor']}", headers=AUTH).json()["records"] == []


def test_missing_key_is_actionable_and_does_not_fake_routes(client):
    response = client.post("/v1/route", json=route_request(), headers=AUTH)
    assert response.status_code == 503
    assert "API-Schlüssel" in response.json()["detail"]


@pytest.mark.parametrize("surface", [0, 2, 8, 10, 11, 15])
def test_strict_paved_rejects_unknown_and_unpaved(tmp_path, surface):
    transport = httpx.MockTransport(lambda request: httpx.Response(200, json=upstream_route(surface)))
    with TestClient(create_app(f"sqlite:///{tmp_path / 'paved.sqlite'}", TOKEN, "secret-ors", transport)) as client:
        response = client.post("/v1/route", headers=AUTH, json=route_request("pavedOnly"))
        assert response.status_code == 422
        assert "nicht gelockert" in response.text


def test_route_coordinates_elevation_and_maneuvers(tmp_path):
    def handler(request):
        assert request.headers["Authorization"] == "secret-ors"
        return httpx.Response(200, json=upstream_route())
    with TestClient(create_app(f"sqlite:///{tmp_path / 'route.sqlite'}", TOKEN, "secret-ors", httpx.MockTransport(handler))) as client:
        result = client.post("/v1/route", headers=AUTH, json=route_request("pavedOnly"))
        assert result.status_code == 200
        route = result.json()
        assert route["coordinates"][0] == {"latitude": 49.41, "longitude": 8.68, "altitude": 101}
        assert route["maneuvers"][0]["coordinateIndex"] == 0
        assert route["surfaces"][0]["name"] == "Asphalt"


def test_route_contains_real_osm_roads_around_turns(tmp_path):
    overpass = {"elements": [
        {"type": "way", "id": 10, "tags": {"highway": "residential"}, "geometry": [
            {"lat": 49.4098, "lon": 8.6800}, {"lat": 49.4100, "lon": 8.6800}, {"lat": 49.4102, "lon": 8.6800}]},
        {"type": "way", "id": 11, "tags": {"highway": "cycleway"}, "geometry": [
            {"lat": 49.4100, "lon": 8.6798}, {"lat": 49.4100, "lon": 8.6800}, {"lat": 49.4100, "lon": 8.6802}]}
    ]}

    def handler(request):
        if request.url.host == "overpass.test":
            assert "way%28around" in request.content.decode()
            return httpx.Response(200, json=overpass)
        return httpx.Response(200, json=upstream_route())

    app = create_app(f"sqlite:///{tmp_path / 'roads.sqlite'}", TOKEN, "secret-ors",
                     httpx.MockTransport(handler), overpass_url="https://overpass.test/api")
    with TestClient(app) as client:
        response = client.post("/v1/route", headers=AUTH, json=route_request("pavedOnly"))
        assert response.status_code == 200
        contexts = response.json()["intersectionContexts"]
        assert contexts[0]["coordinateIndex"] == 0
        assert len(contexts[0]["roads"]) == 2
        assert {road["kind"] for road in contexts[0]["roads"]} == {0, 1}


def test_invalid_coordinates_are_rejected_before_provider_call(client):
    body = route_request()
    body["waypoints"][0]["coordinate"]["latitude"] = 100
    assert client.post("/v1/route", json=body, headers=AUTH).status_code == 422


def test_transient_provider_failure_does_not_expose_upstream_body(tmp_path):
    transport = httpx.MockTransport(lambda request: httpx.Response(500, text="secret-upstream-details"))
    with TestClient(create_app(f"sqlite:///{tmp_path / 'error.sqlite'}", TOKEN, "secret-ors", transport)) as client:
        response = client.post("/v1/route", headers=AUTH, json=route_request())
        assert response.status_code == 502
        assert "secret" not in response.text


def test_prefer_paved_can_keep_first_candidate_when_second_is_unavailable(tmp_path):
    def handler(request):
        if "cycling-road" in request.url.path:
            return httpx.Response(404)
        return httpx.Response(200, json=upstream_route())
    with TestClient(create_app(f"sqlite:///{tmp_path / 'fallback.sqlite'}", TOKEN, "secret-ors", httpx.MockTransport(handler))) as client:
        assert client.post("/v1/route", headers=AUTH, json=route_request("preferPaved")).status_code == 200


def test_place_name_is_authenticated_and_keeps_coordinates_out_of_result(tmp_path):
    def handler(request):
        assert request.url.path == "/geocode/reverse"
        assert request.headers["Authorization"] == "secret-ors"
        assert request.url.params["point.lon"] == "8.68"
        assert request.url.params["point.lat"] == "49.41"
        return httpx.Response(200, json={"features": [{"properties": {"label": "Neckarwiese, Heidelberg"},
                                                       "geometry": {"coordinates": [8.681, 49.411]}}]})
    with TestClient(create_app(f"sqlite:///{tmp_path / 'names.sqlite'}", TOKEN, "secret-ors", httpx.MockTransport(handler))) as client:
        url = "/v1/place-name?lat=49.41&lon=8.68"
        assert client.get(url).status_code == 401
        assert client.get(url, headers=AUTH).json() == {"name": "Neckarwiese, Heidelberg"}
        assert client.get("/v1/place-name?lat=100&lon=8.68", headers=AUTH).status_code == 422


def test_place_without_geocoding_result_has_no_invented_name(tmp_path):
    transport = httpx.MockTransport(lambda request: httpx.Response(200, json={"features": []}))
    with TestClient(create_app(f"sqlite:///{tmp_path / 'empty.sqlite'}", TOKEN, "secret-ors", transport)) as client:
        assert client.get("/v1/place-name?lat=49.41&lon=8.68", headers=AUTH).json() == {"name": None}


def test_automatic_title_preference_survives_sync(client):
    change = mutation(title="Rodgau → Seligenstadt")
    change["document"]["usesAutomaticTitle"] = True
    result = client.post("/v1/mutations", json=change, headers=AUTH)
    assert result.status_code == 200
    assert result.json()["document"]["usesAutomaticTitle"] is True
    assert client.get("/v1/changes", headers=AUTH).json()["records"][0]["document"]["usesAutomaticTitle"] is True


@pytest.mark.parametrize("with_route", [False, True])
def test_old_receipt_still_accepts_retry_without_naming_field(client, with_route):
    import hashlib
    import json
    change = mutation()
    if with_route:
        from bikenavi.providers import parse_route
        change["document"]["route"] = parse_route(upstream_route())
        change["document"]["route"].pop("surfaceSections")
    legacy_payload = Mutation.model_validate(change).model_dump(mode="json")
    legacy_payload["document"].pop("usesAutomaticTitle")
    legacy_payload["document"].pop("awaitingStart")
    if with_route:
        legacy_payload["document"]["route"].pop("surfaceSections")
    digest = hashlib.sha256(json.dumps(legacy_payload, sort_keys=True).encode()).hexdigest()
    envelope = {"document": legacy_payload["document"], "revision": 1, "deleted": False}
    with client.app.state.storage.sessions.begin() as session:
        session.add(Receipt(id=change["mutationID"], digest=digest, envelope=envelope))
    result = client.post("/v1/mutations", json=change, headers=AUTH)
    assert result.status_code == 200
    assert result.json() == envelope


def test_surface_ranges_follow_geometry_and_survive_storage(client):
    from bikenavi.providers import parse_route
    raw = upstream_route()
    raw["features"][0]["geometry"]["coordinates"].append([8.7, 49.43, 120])
    raw["features"][0]["properties"]["extras"]["surface"]["values"] = [[0, 1, 3], [1, 2, 10]]
    route = parse_route(raw)
    expected = [{"startIndex": 0, "endIndex": 1, "surface": 3}, {"startIndex": 1, "endIndex": 2, "surface": 10}]
    assert route["surfaceSections"] == expected
    change = mutation()
    change["document"]["route"] = route
    result = client.post("/v1/mutations", json=change, headers=AUTH)
    assert result.status_code == 200
    assert result.json()["document"]["route"]["surfaceSections"] == expected
    assert client.get("/v1/changes", headers=AUTH).json()["records"][0]["document"]["route"]["surfaceSections"] == expected


@pytest.mark.parametrize("sections", [
    [{"startIndex": 0, "endIndex": 2, "surface": 3}],
    [{"startIndex": 1, "endIndex": 1, "surface": 3}],
    [{"startIndex": 0, "endIndex": 1, "surface": 3}, {"startIndex": 0, "endIndex": 1, "surface": 10}],
])
def test_invalid_surface_indices_cannot_enter_archive(client, sections):
    from bikenavi.providers import parse_route
    change = mutation()
    change["document"]["route"] = parse_route(upstream_route())
    change["document"]["route"]["surfaceSections"] = sections
    assert client.post("/v1/mutations", json=change, headers=AUTH).status_code == 422


def test_destination_without_start_survives_archive_roundtrip(client):
    change = mutation()
    destination = route_request()["waypoints"][-1]
    change["document"].update({"awaitingStart": True, "waypoints": [destination]})
    saved = client.post("/v1/mutations", json=change, headers=AUTH)
    assert saved.status_code == 200
    loaded = client.get("/v1/changes", headers=AUTH).json()["records"][0]["document"]
    assert loaded["awaitingStart"] is True
    assert len(loaded["waypoints"]) == 1
    assert loaded["waypoints"][0] == {
        **destination,
        "coordinate": {**destination["coordinate"], "altitude": None},
    }
