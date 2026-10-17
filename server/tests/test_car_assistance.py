"""Synthetic public coordinates; no real traffic/limit claims."""
import asyncio
import copy
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from bikenavi.car import TomTomCar, parse_route
from bikenavi.models import Route, RouteRequest
from bikenavi.storage import Storage


def request():
    return RouteRequest.model_validate(dict(waypoints=[dict(id=str(uuid4()), name="Öffentliches synthetisches Beispiel",
        coordinate=dict(latitude=lat, longitude=8.68)) for lat in (49.410, 49.412, 49.414)],
        profile=dict(travelMode="car", carOptions=dict(avoidHighways=True, avoidTolls=True, avoidFerries=True)), startBearing=270))


def response():
    points = [dict(latitude=49.410 + i * .001, longitude=8.68) for i in range(5)]
    return dict(routes=[dict(summary=dict(lengthInMeters=445, travelTimeInSeconds=90, trafficDelayInSeconds=30),
        legs=[dict(points=points[:3]), dict(points=points[2:])],
        progress=[dict(pointIndex=0, travelTimeInSeconds=0), dict(pointIndex=2, travelTimeInSeconds=60), dict(pointIndex=5, travelTimeInSeconds=90)],
        guidance=dict(instructions=[dict(maneuver="DEPART", pointIndex=0, message="Losfahren"),
            dict(maneuver="TURN_RIGHT", pointIndex=2, message="Rechts abbiegen", street="Beispielstraße"),
            dict(maneuver="ARRIVE", pointIndex=5, message="Ziel erreicht")]),
        sections=[dict(sectionType="LANES", startPointIndex=0, endPointIndex=2,
                       lanes=[dict(directions=["LEFT"]), dict(directions=["STRAIGHT", "RIGHT"], follow="RIGHT")]),
                  dict(sectionType="SPEED_LIMIT", startPointIndex=0, endPointIndex=2, maxSpeedLimitInKmh=50),
                  dict(sectionType="TRAFFIC", startPointIndex=2, endPointIndex=5, delayInSeconds=30, simpleCategory="JAM")])])


def test_guidance_limits_traffic_and_intermediate_stops_share_geometry():
    route = parse_route(response(), request(), 1000)
    assert route["waypointIndices"] == [0, 2, 5]
    assert route["carTimeSections"] == [dict(startIndex=0, endIndex=2, seconds=60), dict(startIndex=2, endIndex=5, seconds=30)]
    assert route["carLaneSections"][0]["lanes"][1]["follow"] == "RIGHT"
    assert route["carSpeedLimits"][0]["kilometersPerHour"] == 50
    assert route["carTraffic"]["fetchedAt"] == 1000
    assert route["carTraffic"]["sections"][0]["category"] == "JAM"
    assert route["maneuvers"][1]["type"] == 1


@pytest.mark.parametrize("value", [None, 0, -1, 999, float("nan"), "50", True])
def test_unknown_limits_never_become_numeric_limits(value):
    data = response(); data["routes"][0]["sections"][1]["maxSpeedLimitInKmh"] = value
    assert parse_route(data, request(), 1000)["carSpeedLimits"] == []


@pytest.mark.parametrize("change", ["indices", "time", "stops", "disconnected", "instructions"])
def test_malformed_route_is_not_accepted(change):
    data = response(); route = data["routes"][0]
    if change == "indices": route["sections"][0]["endPointIndex"] = 999
    if change == "time": route["progress"][1]["travelTimeInSeconds"] = 91
    if change == "stops": route["legs"].pop()
    if change == "disconnected": route["legs"][1]["points"][0] = dict(latitude=50, longitude=9)
    if change == "instructions": route["guidance"] = {}
    with pytest.raises((ValueError, IndexError)):
        parse_route(data, request(), 1000)


def test_unknown_lane_direction_is_omitted_not_guessed():
    data = response(); data["routes"][0]["sections"][0]["lanes"][1]["follow"] = "FUTURE_DIRECTION"
    assert parse_route(data, request(), 1000)["carLaneSections"] == []


def test_persisted_contract_rejects_overlaps_and_invalid_recommendations():
    route = parse_route(response(), request(), 1000)
    invalid = copy.deepcopy(route); invalid["carSpeedLimits"].append(invalid["carSpeedLimits"][0])
    with pytest.raises(ValidationError): Route.model_validate(invalid)
    invalid = copy.deepcopy(route); invalid["carLaneSections"][0]["lanes"][0]["follow"] = "RIGHT"
    with pytest.raises(ValidationError): Route.model_validate(invalid)


def test_free_budget_is_atomic_persistent_and_rolls_over(tmp_path):
    url = "sqlite:///" + str(tmp_path / "budget.sqlite")
    storage = Storage(url)
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: storage.reserve_provider_month("tomtom", "2026-10", 7), range(40)))
    assert sum(results) == 7
    storage.engine.dispose(); storage = Storage(url)
    assert not storage.reserve_provider_month("tomtom", "2026-10", 7)
    assert storage.reserve_provider_month("tomtom", "2026-11", 7)
    storage.engine.dispose()


def test_requests_include_live_traffic_lanes_limits_avoidance_and_heading(tmp_path):
    async def run():
        def handle(call):
            assert call.url.host == "api.tomtom.com"
            assert call.url.params["traffic"] == "true"
            assert call.url.params["departAt"] == "now"
            assert set(call.url.params.get_list("sectionType")) == {"lanes", "speedLimit", "traffic", "motorway", "tollRoad", "ferry"}
            assert set(call.url.params.get_list("avoid")) == {"motorways", "tollRoads", "ferries"}
            assert call.url.params["vehicleHeading"] == "270"
            return httpx.Response(200, json=response())
        storage = Storage("sqlite:///" + str(tmp_path / "requests.sqlite"))
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            route = await TomTomCar("synthetic-key", client, storage).route(request())
        assert route["carTraffic"]["delaySeconds"] == 30
        storage.engine.dispose()
    asyncio.run(run())


@pytest.mark.parametrize("status", [401, 403, 429, 500])
def test_failure_has_no_paid_fallback_or_secret_and_backs_off(tmp_path, status):
    async def run():
        calls = []
        def handle(call):
            calls.append(call)
            return httpx.Response(status, json={"secret": "synthetic-key"})
        storage = Storage("sqlite:///" + str(tmp_path / "error.sqlite"))
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            provider = TomTomCar("synthetic-key", client, storage)
            for _ in range(2):
                with pytest.raises(HTTPException) as error: await provider.route(request())
                assert "synthetic-key" not in str(error.value.detail)
        assert len(calls) == 1
        storage.engine.dispose()
    asyncio.run(run())


def test_exhausted_budget_does_not_touch_network(tmp_path, monkeypatch):
    async def run():
        storage = Storage("sqlite:///" + str(tmp_path / "full.sqlite"))
        monkeypatch.setattr(storage, "reserve_provider_month", lambda *args: False)
        def handle(call): raise AssertionError("Network must not be used")
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            with pytest.raises(HTTPException) as error:
                await TomTomCar("synthetic-key", client, storage).route(request())
            assert error.value.status_code == 429
        storage.engine.dispose()
    asyncio.run(run())


def test_sparse_time_profile_is_split_at_poi_stop():
    data = response(); data["routes"][0]["progress"].pop(1)
    route = parse_route(data, request(), 1000)
    assert [s["endIndex"] for s in route["carTimeSections"]] == [2, 5]
    assert sum(s["seconds"] for s in route["carTimeSections"]) == pytest.approx(90)
    assert route["carTimeSections"][0]["seconds"] == pytest.approx(45)


@pytest.mark.parametrize("kind", ["MOTORWAY", "TOLL_ROAD", "FERRY"])
def test_unavoidable_exclusion_is_rejected(kind):
    data = response(); data["routes"][0]["sections"].append(dict(sectionType=kind, startPointIndex=0, endPointIndex=2))
    with pytest.raises(ValueError): parse_route(data, request(), 1000)


@pytest.mark.parametrize('first', [400, 404, 'invalid-data', 'unreachable-stop'])
def test_bad_poi_candidate_does_not_pause_next_route(tmp_path, first):
    async def run():
        calls = []
        def handle(call):
            calls.append(call)
            if len(calls) == 1:
                if isinstance(first, int):
                    return httpx.Response(first, json={'error': 'synthetic-key'})
                data = response()
                if first == 'invalid-data':
                    data['routes'][0]['progress'] = []
                else:
                    data['routes'][0]['legs'][-1]['points'][-1]['latitude'] += 1
                return httpx.Response(200, json=data)
            return httpx.Response(200, json=response())
        storage = Storage('sqlite:///' + str(tmp_path / 'candidate.sqlite'))
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            provider = TomTomCar('synthetic-key', client, storage)
            with pytest.raises(HTTPException):
                await provider.route(request())
            assert provider.next_allowed == 0
            assert (await provider.route(request()))['carSpeedLimits']
        assert len(calls) == 2
        storage.engine.dispose()
    asyncio.run(run())


def test_poi_burst_spacing_shared_across_provider_instances_and_restart(tmp_path):
    import time
    from bikenavi.car import REQUEST_INTERVAL
    async def run():
        starts = []
        def handle(call):
            starts.append(time.monotonic())
            return httpx.Response(200, json=response())
        url = 'sqlite:///' + str(tmp_path / 'spacing.sqlite')
        stores = [Storage(url), Storage(url)]
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            providers = [TomTomCar('synthetic-key', client, s) for s in stores]
            await asyncio.gather(*(providers[i % 2].route(request()) for i in range(6)))
            await TomTomCar('synthetic-key', client, stores[0]).route(request())
        assert len(starts) == 7
        assert all(b - a >= REQUEST_INTERVAL - .02 for a, b in zip(starts, starts[1:]))
        for s in stores: s.engine.dispose()
    asyncio.run(run())


@pytest.mark.parametrize('header,expected', [(None, 2), ('7', 7), ('bad', 2), ('nan', 2),
                                           ('inf', 2), ('-1', 2),
                                           ('Thu, 01 Jan 1970 00:00:09 GMT', 8)])
def test_rate_limit_retry_after_is_parsed_without_five_minute_pause(header, expected):
    from bikenavi.car import retry_delay
    assert retry_delay(header, 1) == expected


def test_rate_limit_keeps_specific_reason_and_recovers(tmp_path, monkeypatch):
    async def run():
        calls = []
        def handle(call):
            calls.append(call)
            return httpx.Response(429, headers={'Retry-After': '7'}) if len(calls) == 1 else httpx.Response(200, json=response())
        storage = Storage('sqlite:///' + str(tmp_path / 'retry.sqlite'))
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            provider = TomTomCar('synthetic-key', client, storage)
            for _ in range(2):
                with pytest.raises(HTTPException) as failure:
                    await provider.route(request())
                assert failure.value.status_code == 429
                assert 'Abfragerate' in failure.value.detail
                assert 1 <= int(failure.value.headers['Retry-After']) <= 7
                assert 'synthetic-key' not in failure.value.detail
            assert len(calls) == 1
            provider.next_allowed = 0
            assert (await provider.route(request()))['carTraffic']
        assert len(calls) == 2
        storage.engine.dispose()
    asyncio.run(run())


@pytest.mark.parametrize("code,value,expected", [
    ("TAKE_EXIT", 0, None), ("TAKE_EXIT", 3, None),
    ("ROUNDABOUT_CROSS", 3, 3), ("ROUNDABOUT_CROSS", 0, None),
    ("ROUNDABOUT_CROSS", -1, None), ("ROUNDABOUT_CROSS", True, None),
    ("ROUNDABOUT_CROSS", "3", None), ("ROUNDABOUT_CROSS", 101, None),
])
def test_roundabout_exit_sentinel_does_not_reject_valid_route(code, value, expected):
    data = response()
    data["routes"][0]["guidance"]["instructions"][1].update(maneuver=code, roundaboutExitNumber=value)
    result = parse_route(data, request(), 1000)
    assert result["maneuvers"][1].get("exitNumber") == expected
    assert result["distance"] == 445
    Route.model_validate(result)
