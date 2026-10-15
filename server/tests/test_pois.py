import asyncio
import gzip
import json
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from bikenavi.main import create_app
from bikenavi.models import Coordinate, Profile, Waypoint
from bikenavi.pois import POIService, POISearch, POIRouteContext, RouteCorridor, distance, price


def point(latitude=49.0, longitude=8.0):
    return Coordinate(latitude=latitude, longitude=longitude)


def search(context=None):
    return POISearch(center=point(), context=context)


def context():
    points = [point(48.99), point(), point(49.01), point(49.02)]
    return POIRouteContext(coordinates=points, progress=1111.95,
        pending=[Waypoint(id=uuid4(), name="Beispielziel", coordinate=points[-1])], bearing=0)


def test_prices_reject_boolean_zero_sentinel_and_nonfinite():
    for value in [False, True, None, 0, 0.001, -1, float("nan"), float("inf"), "unknown"]:
        assert price(value) is None
    assert price("1.719") == 1.719


def test_corridor_rejects_behind_far_side_and_stale_progress():
    corridor = RouteCorridor(search(context()))
    assert corridor.ahead(point(49.01))
    assert not corridor.ahead(point(48.995))
    assert not corridor.ahead(point(49.01, 8.1))
    stale = context().model_copy(update={"progress": 10})
    with pytest.raises(HTTPException):
        RouteCorridor(search(stale))


def test_corridor_rejects_uturn_and_reverse_travel_but_allows_short_driveway():
    corridor = RouteCorridor(search(context()))
    forward = {"coordinates": [point().model_dump(), point(49.01).model_dump(), point(49.0099).model_dump(), point(49.02).model_dump()], "maneuvers": []}
    assert corridor.forward(forward)
    assert not corridor.forward(dict(forward, maneuvers=[{"type": 9}]))
    assert not corridor.forward(dict(forward, coordinates=[point().model_dump(), point(49.01).model_dump(), point(49.005).model_dump()]))


def test_corridor_clips_long_routes_using_geodesic_progress():
    points = [point(48 + index * 0.0001, 8 + index * 0.00015) for index in range(15_001)]
    progress = sum(distance(first, second) for first, second in zip(points[:10_000], points[1:10_001]))
    route = POIRouteContext(coordinates=points, progress=progress,
        pending=[Waypoint(id=uuid4(), name="Beispielziel", coordinate=points[-1])])
    corridor = RouteCorridor(POISearch(center=points[10_000], context=route))
    assert progress > 100_000
    assert corridor.line.length <= 50_501
    assert len(corridor.line.coords) < 20
    assert corridor.ahead(points[10_200])
    assert not corridor.ahead(points[9_990])
    assert not corridor.ahead(points[-1])


def test_german_key_missing_and_rate_limit_do_not_leak_key():
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            assert request.url.params["type"] == "diesel"
            assert request.url.params["rad"] == "25"
            return httpx.Response(200, json={"ok": True, "stations": []})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, None, "")
            with pytest.raises(ValueError, match="Schlüssel fehlt"):
                await service.country_stations("DE", point(), 10)
            service.tanker_key = "test-private-key"
            await service.country_stations("DE", point(), 10)
            await service.country_stations("DE", point(), 10)
            assert len(calls) == 1
            await service.country_stations("DE", point(49.1), 10)
            assert len(calls) == 1
            notices = []
            assert await service.country_stations("DE", point(50), 10, notices) == []
            assert any("Minute" in notice for notice in notices)
            assert all("test-private-key" not in notice for notice in notices)
    asyncio.run(run())


def test_austria_missing_price_stays_unknown_and_closed_stays_closed():
    async def run():
        def handle(request):
            assert request.url.params["fuelType"] == "DIE"
            return httpx.Response(200, json=[{"id": 1, "name": "Beispiel", "location": {"latitude": 49, "longitude": 8},
                                             "prices": [{"fuelType": "SUP", "amount": 1.2}], "open": False}])
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            items = await POIService(client, None, "").country_stations("AT", point(), 10)
            assert items[0]["dieselPrice"] is None
            assert items[0]["isOpen"] is False
            assert items[0]["priceTimestamp"] is None
    asyncio.run(run())


def test_slovenia_paginates_with_meters_and_never_follows_foreign_next_url():
    async def run():
        def handle(request):
            assert request.url.host == "goriva.si"
            assert request.url.params["radius"] == "10000"
            page = int(request.url.params["page"])
            return httpx.Response(200, json={"next": "https://untrusted.invalid/" if page == 1 else None,
                "results": [{"pk": page, "name": "Beispiel", "lat": 49, "lng": 8,
                             "prices": {"dizel": 1.7, "dizel-premium": 1.5}, "open_hours": "24 ur"}]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            items = await POIService(client, None, "").country_stations("SI", point(), 10)
            assert len(items) == 2
            assert items[0]["dieselPrice"] == 1.7
            assert items[0]["isOpen"] is None
    asyncio.run(run())


def test_croatia_swapped_fields_and_premium_and_blue_diesel():
    async def run():
        data = {"vrsta_gorivas": [{"id": 8, "vrsta_goriva": "Eurodizel bez aditiva"}, {"id": 11, "vrsta_goriva": "Plavi dizel"}],
                "gorivos": [{"id": 1, "vrsta_goriva_id": 8, "naziv": "Eurodiesel"},
                            {"id": 2, "vrsta_goriva_id": 8, "naziv": "Eurodiesel MaxPower"},
                            {"id": 3, "vrsta_goriva_id": 11, "naziv": "Plavi"},
                            {"id": 5, "vrsta_goriva_id": 8, "naziv": None}],
                "postajas": [{"id": 9, "naziv": None, "long": None, "lat": None, "cjenici": []},
                             {"id": 4, "naziv": "Beispiel Kroatien", "long": "49,0", "lat": "8,0",
                              "cjenici": [{"gorivo_id": 1, "cijena": 1.7}, {"gorivo_id": 2, "cijena": 1.3}, {"gorivo_id": 3, "cijena": 0.8}]}]}
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, content=gzip.compress(json.dumps(data).encode())))) as client:
            items = await POIService(client, None, "").country_stations("HR", point(), 10)
            assert len(items) == 1
            assert items[0]["coordinate"]["latitude"] == 49
            assert items[0]["dieselPrice"] == 1.7
    asyncio.run(run())


class Router:
    async def car_route(self, request):
        points = [item.coordinate.model_dump() for item in request.waypoints]
        return {"coordinates": points, "waypointIndices": list(range(len(points))), "duration": len(points) * 100,
                "maneuvers": [], "carTimeSections": [{"startIndex": 0, "endIndex": 1, "seconds": 100}]}


def test_stop_route_preserves_profile_and_pending_and_rejects_backtracking():
    async def run():
        service = POIService(None, Router(), "")
        stop = Waypoint(id=uuid4(), name="Beispiel", coordinate=point(49.01))
        result = await service.route_to_stop(search(context()), stop)
        assert result["detourSeconds"] == 100
        assert len(result["route"]["coordinates"]) == 3
        with pytest.raises(HTTPException):
            await service.route_to_stop(search(context()), stop.model_copy(update={"coordinate": point(48.995)}))
    asyncio.run(run())


def test_rejects_unconfirmed_driveway_and_large_detour():
    class BadRouter(Router):
        async def car_route(self, request):
            result = await super().car_route(request)
            result["coordinates"][1] = point(49.1).model_dump()
            return result
    async def run():
        service = POIService(None, BadRouter(), "")
        with pytest.raises(HTTPException):
            await service.route_to_stop(search(), Waypoint(id=uuid4(), name="Beispiel", coordinate=point(49.01)))
        service.ors = Router()
        with pytest.raises(HTTPException):
            await service.route_to_stop(search(context()), Waypoint(id=uuid4(), name="Beispiel", coordinate=point(49.01)), {"duration": -1000})
    asyncio.run(run())


def test_endpoints_require_authentication_and_validate_scope(tmp_path):
    with TestClient(create_app(f"sqlite:///{tmp_path}/test.sqlite", token="a" * 40, ors_key="")) as client:
        assert client.post("/v1/pois/search", json=search().model_dump()).status_code == 401
        payload = search().model_dump()
        payload["radius"] = 500
        assert client.post("/v1/pois/search", json=payload, headers={"Authorization": "Bearer " + "a" * 40}).status_code == 422


def test_search_ranks_diesel_and_keeps_unknown_prices_separate():
    from bikenavi.pois import station
    class SearchService(POIService):
        async def country_stations(self, country, center, radius, notices=None):
            return [dict(station("DE", index, "Beispiel", 49.01, 8, amount, opened), fetchedAt=100)
                    for index, (amount, opened) in enumerate([(1.8, True), (1.6, True), (0.8, False), (None, None), (1.7, True)])]
    async def run():
        result = await SearchService(None, Router(), "").search(search())
        assert [item["dieselPrice"] for item in result["items"]] == [1.6, 1.7, 1.8]
        assert all(item["isOpen"] is not False for item in result["items"])
    asyncio.run(run())
