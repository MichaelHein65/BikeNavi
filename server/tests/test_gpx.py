"""Synthetic GPX API/storage contract; no provider or private data access."""
from copy import deepcopy
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from bikenavi.main import create_app

AUTH = {"Authorization": "Bearer " + "gpx-test-" + "a" * 40}


@pytest.fixture
def client(tmp_path):
    with TestClient(create_app(f"sqlite:///{tmp_path / 'gpx.sqlite'}", token="gpx-test-" + "a" * 40, ors_key="")) as value:
        yield value


def mutation():
    return {"mutationID": str(uuid4()), "baseRevision": 0, "document": {
        "id": str(uuid4()), "kind": "plan", "title": "Synthetisches GPX-Beispiel", "createdAt": 1, "updatedAt": 1,
        "route": {"id": str(uuid4()), "coordinates": [{"latitude": 49.4, "longitude": 8.7, "altitude": 100},
            {"latitude": 49.401, "longitude": 8.701}], "distance": 130, "duration": 30, "ascent": 0, "descent": 0,
            "provider": "GPX · Originalspur", "calculatedAt": 1, "gpxTrack": {"kind": "trk", "points": [
                {"name": "A & B", "time": "2026-10-21T08:00:00.125+02:00"}, {}], "waypoints": [
                {"coordinate": {"latitude": 49.4, "longitude": 8.7}, "details": {"name": "Beispielpause"}}]}}}}


def test_capability_roundtrip_and_idempotent_receipt(client):
    assert client.get("/v1/status", headers=AUTH).json()["gpxImportAvailable"] is True
    body = mutation()
    first = client.post("/v1/mutations", headers=AUTH, json=body)
    assert first.status_code == 200
    saved = first.json()["document"]["route"]
    assert saved["gpxTrack"]["points"][0] == body["document"]["route"]["gpxTrack"]["points"][0]
    assert saved["coordinates"][0] == body["document"]["route"]["coordinates"][0]
    assert saved["gpxTrack"]["waypoints"][0]["details"]["name"] == "Beispielpause"
    assert client.post("/v1/mutations", headers=AUTH, json=body).json() == first.json()
    page = client.get("/v1/changes", headers=AUTH).json()
    assert page["records"][0]["document"]["route"] == saved


def test_legacy_payload_omits_new_optional_field(client):
    body = mutation()
    del body["document"]["route"]["gpxTrack"]
    body["document"]["route"]["provider"] = "legacy"
    response = client.post("/v1/mutations", headers=AUTH, json=body)
    assert response.status_code == 200
    assert "gpxTrack" not in response.json()["document"]["route"]
    assert client.post("/v1/mutations", headers=AUTH, json=body).json() == response.json()


def test_old_client_cannot_silently_strip_gpx_metadata_but_can_delete(client):
    body = mutation()
    assert client.post("/v1/mutations", headers=AUTH, json=body).status_code == 200
    changed = deepcopy(body)
    changed.update(mutationID=str(uuid4()), baseRevision=1)
    del changed["document"]["route"]["gpxTrack"]
    assert client.post("/v1/mutations", headers=AUTH, json=changed).status_code == 422
    changed["deleted"] = True
    assert client.post("/v1/mutations", headers=AUTH, json=changed).status_code == 200


@pytest.mark.parametrize("change", ["length", "kind", "provider", "name", "coordinate", "maneuvers"])
def test_invalid_metadata_contract_rejected(client, change):
    body = mutation()
    route = body["document"]["route"]
    if change == "length": route["gpxTrack"]["points"].pop()
    if change == "kind": route["gpxTrack"]["kind"] = "invalid"
    if change == "provider": route["provider"] = "calculated"
    if change == "name": route["gpxTrack"]["points"][0]["name"] = "x" * 301
    if change == "coordinate": route["gpxTrack"]["waypoints"][0]["coordinate"]["latitude"] = 91
    if change == "maneuvers": route["maneuvers"] = [{"instruction": "Turn", "distance": 1, "coordinateIndex": 0, "type": 1}]
    assert client.post("/v1/mutations", headers=AUTH, json=body).status_code == 422
