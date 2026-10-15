import asyncio
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import httpx
import pytest

from bikenavi.models import Coordinate
from bikenavi.pois import POIService
from bikenavi.storage import Storage


@pytest.fixture
def clock(monkeypatch):
    current = [1000.0]
    monkeypatch.setattr("bikenavi.pois.time", SimpleNamespace(time=lambda: current[0], monotonic=lambda: current[0]))
    return current


def point(latitude=49):
    return Coordinate(latitude=latitude, longitude=8)


def answer():
    return {"ok": True, "stations": [{"id": "example", "name": "Beispiel", "lat": 49.01, "lng": 8,
                                       "price": 1.719, "isOpen": True}]}


def test_nearby_concurrent_searches_share_one_area_request(clock):
    async def run():
        calls = []
        async def handle(request):
            calls.append(request)
            await asyncio.sleep(0.01)
            return httpx.Response(200, json=answer())
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, None, "", "fake-key")
            first, second = await asyncio.gather(service.country_stations("DE", point(), 10),
                                                  service.country_stations("DE", point(49.02), 10))
            assert len(calls) == 1
            assert first == second
            assert first[0]["fetchedAt"] == 1000
            clock[0] += 61
            await service.country_stations("DE", point(49.03), 10)
            assert len(calls) == 1
    asyncio.run(run())


def test_changed_area_uses_partial_cache_until_next_request_slot(clock):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            return httpx.Response(200, json=answer())
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, None, "", "fake-key")
            await service.country_stations("DE", point(), 25)
            clock[0] += 60
            notices = []
            items = await service.country_stations("DE", point(49.02), 25, notices)
            assert len(calls) == 1
            assert items[0]["fetchedAt"] == 1000
            assert any("teilweise" in notice for notice in notices)
            assert any("1 Sekunden" in notice for notice in notices)
            clock[0] += 1
            items = await service.country_stations("DE", point(49.02), 25)
            assert len(calls) == 2
            assert items[0]["fetchedAt"] == 1061
    asyncio.run(run())


def test_failed_refresh_counts_and_old_data_expires(clock):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            return httpx.Response(200, json=answer()) if len(calls) == 1 else httpx.Response(429, text="fake-secret-key")
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, None, "", "fake-secret-key")
            await service.country_stations("DE", point(), 10)
            clock[0] += 121
            notices = []
            items = await service.country_stations("DE", point(), 10, notices)
            assert len(calls) == 2
            assert items[0]["fetchedAt"] == 1000
            assert items[0]["isOpen"] is None
            assert all("fake-secret-key" not in notice for notice in notices)
            assert any("fehlgeschlagen" in notice for notice in notices)
            await service.country_stations("DE", point(), 10)
            assert len(calls) == 2
            clock[0] = 1301
            assert await service.country_stations("DE", point(), 10) == []
    asyncio.run(run())


def test_budget_survives_service_and_database_reopening(clock, tmp_path):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            return httpx.Response(200, json=answer())
        url = f"sqlite:///{tmp_path}/budget.sqlite"
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            first = POIService(client, None, "", "fake-key", Storage(url))
            await first.country_stations("DE", point(), 10)
            restarted = POIService(client, None, "", "fake-key", Storage(url))
            notices = []
            assert await restarted.country_stations("DE", point(), 10, notices) == []
            assert len(calls) == 1
            assert any("Minute" in notice for notice in notices)
            clock[0] += 61
            assert await restarted.country_stations("DE", point(), 10)
            assert len(calls) == 2
    asyncio.run(run())


def test_database_budget_reservation_is_atomic(tmp_path):
    storage = Storage(f"sqlite:///{tmp_path}/budget.sqlite")
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda _: storage.reserve_provider_request("tankerkoenig", 1000, 61), range(16)))
    assert results.count(None) == 1
    assert results.count(1061) == 15
    assert storage.reserve_provider_request("tankerkoenig", 1060, 61) == 1061
    assert storage.reserve_provider_request("tankerkoenig", 1061, 61) is None
