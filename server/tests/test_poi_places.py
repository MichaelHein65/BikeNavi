import asyncio
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from bikenavi.main import create_app
from bikenavi.models import Coordinate, Profile, Waypoint
from bikenavi.pois import POIService, POISearch, POISourceError, PLACE_CATEGORIES, station
from bikenavi.storage import Storage
from test_pois import Router, point, context


@pytest.mark.parametrize("mode", [None, "cycling", "hiking", "bikeAndHike", "sea"])
@pytest.mark.parametrize("category", ["fuel", *PLACE_CATEGORIES])
def test_noncar_discovery_preserves_places_without_requesting_car_routes(mode, category):
    class NearbyService(POIService):
        async def places(self, search, center, radius):
            return [dict(station("DE", index, "Öffentliches Beispiel", latitude, 8,
                                amount if category == "fuel" else None, opened), fetchedAt=100)
                    for index, (latitude, amount, opened) in enumerate([
                        (49.001, 1.8, True), (49.002, 1.7, None), (49.003, None, None),
                        (49.004, 1.6, True), (49.005, 1.9, True), (49.006, 1.0, False), (50, 0.9, True)])]

        async def country_stations(self, country, center, radius, notices=None):
            return await self.places(None, center, radius) if country == "DE" else []

    async def run():
        service = NearbyService(None, None, "")
        search = POISearch(category=category, center=point(), profile=Profile(travelMode=mode))
        result = await service.search(search)
        expected = ["DE:3", "DE:1", "DE:0"] if category == "fuel" else ["DE:0", "DE:1", "DE:2"]
        assert [item["id"] for item in result["items"]] == expected
        assert [item["id"] for item in result["unpriced"]] == (["DE:2"] if category == "fuel" else [])
        for item in result["items"] + result["unpriced"]:
            assert 100 < item["airDistance"] < 600
            assert item["drivingSeconds"] == item["drivingDistance"] == 0
            assert "arrivalCoordinate" not in item and item["detourSeconds"] is None
        assert result["items"][0]["coordinate"] == point(49.004 if category == "fuel" else 49.001).model_dump()
        assert "Luftlinie" in result["scope"]
        assert any("Anlegestellen" in notice for notice in result["notices"]) == (mode == "sea")
        with pytest.raises(HTTPException) as error:
            await service.search(search.model_copy(update={"context": context()}))
        assert error.value.status_code == 422
        with pytest.raises(HTTPException) as error:
            await service.route_to_stop(search, Waypoint(id=uuid4(), name="Beispiel", coordinate=point(49.001)))
        assert error.value.status_code == 422
    asyncio.run(run())


def feature(category="parking", identifier="example", **updates):
    properties = {"place_id": identifier, "name": "Beispielort", "lat": 49.001, "lon": 8,
                  "categories": [PLACE_CATEGORIES[category]], "country_code": "de", "address_line2": "Beispielstraße"}
    properties.update(updates)
    return {"type": "Feature", "properties": properties}


@pytest.mark.parametrize("category", list(PLACE_CATEGORIES))
def test_geoapify_all_categories_and_cached_search_contract(category):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            assert request.url.host == "api.geoapify.com"
            assert request.url.params["apiKey"] == "private-example"
            assert request.url.params["categories"] == PLACE_CATEGORIES[category]
            assert request.url.params["filter"] == "circle:8.0,49.0,10000"
            assert request.url.params["bias"] == "proximity:8.0,49.0"
            assert request.url.params["limit"] == "20"
            return httpx.Response(200, json={"features": [feature(category)]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, Router(), "https://overpass.invalid", places_key="private-example")
            search = POISearch(category=category, center=point())
            first, second = await asyncio.gather(service.search(search), service.search(search))
            assert len(calls) == 1
            assert len(first["items"]) == 1
            assert first["items"] == second["items"]
            item = first["items"][0]
            assert item["country"] == "DE"
            assert item["isOpen"] is None and item["dieselPrice"] is None
            assert "Geoapify" in item["source"] and "OpenStreetMap" in item["source"]
            assert "private-example" not in str(first)
            assert item["coordinate"] == item["arrivalCoordinate"]
            assert item["placeCoordinate"] == item["coordinate"]
    asyncio.run(run())


def test_geoapify_filters_duplicates_private_platforms_outside_and_malformed():
    async def run():
        data = [feature("station"), feature("station"), feature("station", "duplicate-location"), {},
                feature("station", "private", categories=["public_transport.train", "access_limited.private"]),
                feature("station", "platform", categories=["public_transport.train", "public_transport.platform"]),
                feature("station", "far", lat=50), feature("station", "invalid", lat="broken")]
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json={"features": data}))) as client:
            service = POIService(client, Router(), "", places_key="private-example")
            result = await service.search(POISearch(category="station", center=point()))
            assert [item["id"] for item in result["items"]] == ["Geoapify:example"]
    asyncio.run(run())


@pytest.mark.parametrize("failure", [401, 403, 429, 500, "timeout", "invalid"])
def test_geoapify_errors_do_not_leak_key_or_rotate_to_overpass(monkeypatch, failure):
    clock = [1000.0]
    monkeypatch.setattr("bikenavi.pois.time", SimpleNamespace(time=lambda: clock[0], monotonic=lambda: clock[0]))
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            assert request.url.host == "api.geoapify.com"
            if failure == "timeout":
                raise httpx.ReadTimeout("secret-key", request=request)
            return httpx.Response(200 if failure == "invalid" else failure, text="secret-key", headers={"Retry-After": "60"})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, Router(), "https://overpass.invalid", places_key="secret-key")
            first = await service.search(POISearch(category="parking", center=point()))
            clock[0] += 1
            second = await service.search(POISearch(category="beach", center=point()))
            assert len(calls) == 1
            assert first["items"] == second["items"] == []
            assert first["scope"] == second["scope"] == "Ortesuche nicht verfügbar"
            assert "secret-key" not in str(first) + str(second)
    asyncio.run(run())


def test_geoapify_missing_key_and_empty_results_are_distinct():
    async def run():
        service = POIService(None, Router(), "")
        result = await service.search(POISearch(category="parking", center=point()))
        assert "Schlüssel" in result["notices"][0]
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json={"features": []}))) as client:
            result = await POIService(client, Router(), "", places_key="fake").search(POISearch(category="parking", center=point()))
            assert result["scope"] == "Umkreis 10 km"
            assert result["items"] == []
    asyncio.run(run())


def test_geoapify_shared_budget_survives_service_restart(tmp_path):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            return httpx.Response(200, json={"features": [feature()]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            store = Storage(f"sqlite:///{tmp_path}/budget.sqlite")
            first = POIService(client, Router(), "", storage=store, places_key="fake")
            second = POIService(client, Router(), "", storage=store, places_key="fake")
            search = POISearch(category="parking", center=point())
            await first.places(search, point(), 10)
            with pytest.raises(POISourceError, match="Sekunde"):
                await second.places(search, point(), 25)
            assert len(calls) == 1
    asyncio.run(run())


class AccessRouter(Router):
    def __init__(self, gap=0.001):
        self.gap = gap
        self.requests = []

    async def car_route(self, request):
        self.requests.append(request)
        result = await super().car_route(request)
        if request.waypoints[-1].name == "Beispielort":
            result["coordinates"][-1]["longitude"] += self.gap
        return result


def test_building_or_beach_uses_drivable_point_but_fuel_stays_strict():
    async def run():
        router = AccessRouter()
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json={"features": [feature("beach")]}))) as client:
            service = POIService(client, router, "", places_key="fake")
            result = await service.search(POISearch(category="beach", center=point()))
            item = result["items"][0]
            assert item["coordinate"]["longitude"] == 8.001
            assert item["placeCoordinate"]["longitude"] == 8
            assert 70 < item["accessDistance"] < 80
            assert "Fußweg" in item["address"]
            assert any("Luftlinie" in notice for notice in result["notices"])
            stop = Waypoint(id=uuid4(), name="Beispielort", coordinate=point(49.001))
            with pytest.raises(HTTPException):
                await service.route_to_stop(POISearch(category="fuel", center=point()), stop)
            router.gap = 0.01
            with pytest.raises(HTTPException):
                await service.route_to_stop(POISearch(category="beach", center=point()), stop)
    asyncio.run(run())


def test_nonfuel_route_uses_arrival_as_intermediate_and_preserves_pending():
    async def run():
        router = AccessRouter()
        service = POIService(None, router, "")
        search = POISearch(category="station", center=point(), context=context())
        stop = Waypoint(id=uuid4(), name="Beispielort", coordinate=point(49.01))
        result = await service.route_to_stop(search, stop)
        via = router.requests[1].waypoints
        assert via[1].coordinate.longitude == 8.001
        assert via[2:] == search.context.pending
        assert result["detourSeconds"] == 100
        assert result["accessDistance"] > 70
    asyncio.run(run())


def test_main_wires_private_geoapify_key_without_changing_diesel(tmp_path, monkeypatch):
    monkeypatch.setenv("GEOAPIFY_API_KEY", "fake-places")
    monkeypatch.setenv("TANKERKOENIG_API_KEY", "fake-diesel")
    with TestClient(create_app(f"sqlite:///{tmp_path}/test.sqlite", token="a" * 40, ors_key="")) as client:
        assert client.app.state.pois.places_key == "fake-places"
        assert client.app.state.pois.tanker_key == "fake-diesel"


def test_filtered_empty_geoapify_result_is_cached():
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            return httpx.Response(200, json={"features": [feature(categories=["parking", "access_limited.private"])]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, Router(), "", places_key="fake")
            search = POISearch(category="parking", center=point())
            for _ in range(2):
                result = await service.search(search)
                assert result["items"] == []
                assert "Keine Orte" in result["notices"][-1]
            assert len(calls) == 1
    asyncio.run(run())


def test_nonfuel_arrival_behind_route_is_rejected():
    class BehindRouter(Router):
        async def car_route(self, request):
            result = await super().car_route(request)
            result["coordinates"][-1] = point(48.9995).model_dump()
            return result
    async def run():
        service = POIService(None, BehindRouter(), "")
        search = POISearch(category="station", center=point(), context=context())
        stop = Waypoint(id=uuid4(), name="Beispielort", coordinate=point(49.001))
        with pytest.raises(HTTPException, match="voraus"):
            await service.route_to_stop(search, stop)
    asyncio.run(run())
