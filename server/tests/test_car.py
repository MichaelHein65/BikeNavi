import asyncio
import copy
import json
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from bikenavi.models import Document, Profile, Route, RouteRequest
from bikenavi.providers import ORS


def request():
    return RouteRequest.model_validate({"waypoints": [
        {"id": str(uuid4()), "name": "Öffentliches Beispiel", "coordinate": {"longitude": 8.68, "latitude": lat}}
        for lat in [49.41, 49.414]], "profile": {"travelMode": "car", "bike": "mountain", "electric": True,
        "surface": "pavedOnly", "gentleHills": True, "carOptions": {"avoidHighways": True, "avoidTolls": True, "avoidFerries": True}}})


def response():
    return {"features": [{"geometry": {"coordinates": [[8.68, 49.41], [8.68, 49.412], [8.68, 49.414]]},
        "properties": {"way_points": [0, 2], "summary": {"distance": 445, "duration": 60}, "segments": [{"steps": [
            {"instruction": "In den Kreisverkehr fahren, dritte Ausfahrt B 3", "name": "B 3", "exit_number": 3,
             "type": 7, "distance": 220, "duration": 40, "way_points": [0, 1]},
            {"instruction": "Rechts auf die B 3 abbiegen", "type": 1, "distance": 225, "duration": 20, "way_points": [1, 2]},
            {"instruction": "Ziel erreicht", "type": 10, "distance": 0, "duration": 0, "way_points": [2, 2]}]}]}}]}


def calculate(upstream, req=None):
    async def run():
        def handler(call):
            assert call.url.path.endswith("/directions/driving-car/geojson")
            return httpx.Response(200, json=upstream)
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await ORS("test", client).route(req or request())
    return asyncio.run(run())


def test_car_payload_uses_fastest_preferences_and_never_bike_filters():
    async def run():
        def handler(call):
            payload = json.loads(call.content)
            assert call.url.path.endswith("/directions/driving-car/geojson")
            assert payload["preference"] == "fastest"
            assert payload["options"] == {"avoid_features": ["highways", "tollways", "ferries"]}
            assert "extra_info" not in payload and "elevation" not in payload
            return httpx.Response(200, json=response())
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            route = await ORS("test", client).route(request())
        parsed = Route.model_validate(route)
        assert parsed.duration == 60 and [s.seconds for s in parsed.carTimeSections] == [40, 20]
        assert parsed.maneuvers[0].roadName == "B 3" and parsed.maneuvers[0].exitNumber == 3
        assert parsed.provider.endswith("Pkw") and parsed.intersectionContexts == []
    asyncio.run(run())


def test_reroute_carries_driving_direction_without_constraining_other_stops():
    async def run():
        req = request(); req.startBearing = 90
        def handler(call):
            payload = json.loads(call.content)
            assert payload["bearings"] == [[90, 60], []]
            assert payload["optimized"] is False
            return httpx.Response(200, json=response())
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await ORS("test", client).route(req)
    asyncio.run(run())


def test_reachable_car_endpoint_is_explicit_without_invented_foot_route():
    upstream = response()
    upstream["features"][0]["geometry"]["coordinates"][-1][1] -= 0.0005
    route = calculate(upstream)
    assert 40 < route["destinationAccessDistance"] < 70
    assert "Restweg" in route["warnings"][-1] and "walkingStartIndex" not in route


def test_unreachable_start_or_intermediate_is_not_silently_moved():
    upstream = response()
    upstream["features"][0]["geometry"]["coordinates"][0][1] -= 0.001
    with pytest.raises(HTTPException) as error:
        calculate(upstream)
    assert error.value.status_code == 422


@pytest.mark.parametrize("damage", ["missing_time", "time_sum", "gap", "waypoints", "negative_time"])
def test_incomplete_car_navigation_is_rejected(damage):
    upstream = response()
    props = upstream["features"][0]["properties"]
    step = props["segments"][0]["steps"][0]
    if damage == "missing_time": del step["duration"]
    elif damage == "time_sum": step["duration"] = 5
    elif damage == "gap": step["way_points"] = [1, 2]
    elif damage == "waypoints": props["way_points"] = [0, 99]
    else: step["duration"] = -1
    with pytest.raises(HTTPException) as error:
        calculate(upstream)
    assert error.value.status_code == 502


def test_car_navigation_roundtrip_and_destination_must_remain_pending():
    req = request()
    route = calculate(response(), req)
    doc = {"id": str(uuid4()), "kind": "ride", "title": "Pkw-Beispiel", "createdAt": 1, "updatedAt": 2,
           "profile": req.profile.model_dump(exclude_none=True), "waypoints": [w.model_dump(mode="json") for w in req.waypoints],
           "route": route, "localNavigation": {"carRoute": route, "carPendingWaypointOrdinals": [1]}}
    assert Document.model_validate_json(Document.model_validate(doc).model_dump_json()).localNavigation.carRoute.duration == 60
    invalid = copy.deepcopy(doc); invalid["localNavigation"]["carPendingWaypointOrdinals"] = []
    with pytest.raises(ValidationError): Document.model_validate(invalid)
    assert "carOptions" not in Profile().model_dump(exclude_none=True)
