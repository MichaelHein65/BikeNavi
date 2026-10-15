import asyncio
from email.utils import formatdate
from types import SimpleNamespace
from urllib.parse import parse_qs

import httpx
import pytest

from bikenavi.pois import POIService as BasePOIService, POISourceError, POISearch, TAGS
from test_pois import Router, point


class POIService(BasePOIService):
    async def places(self, search, center, radius):
        return await self.osm(search, center, radius)


def payload():
    return {"elements": [
        {"type": "node", "id": 1, "lat": 49.001, "lon": 8, "tags": {"name": "Beispielort"}},
        {"type": "way", "id": 2, "center": {"lat": 49.002, "lon": 8}, "tags": {"access": "private"}},
    ]}


@pytest.fixture
def clock(monkeypatch):
    current = [1000.0]
    monkeypatch.setattr("bikenavi.pois.time", SimpleNamespace(time=lambda: current[0], monotonic=lambda: current[0]))
    return current


@pytest.mark.parametrize("category", ["supermarket", "airport", "station", "beach", "parking"])
def test_all_nonfuel_categories_use_osm_and_cache_results(category):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            assert request.method == "POST"
            assert "BikeNavi" in request.headers["User-Agent"]
            assert "github.com/MichaelHein65/BikeNavi" in request.headers["User-Agent"]
            assert TAGS[category] in parse_qs(request.content.decode())["data"][0]
            return httpx.Response(200, json=payload())
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, Router(), "https://osm.invalid/api/interpreter")
            search = POISearch(category=category, center=point())
            first = await service.search(search)
            second = await service.search(search)
            assert len(calls) == 1
            assert len(first["items"]) == 1
            assert first["items"] == second["items"]
            assert first["items"][0]["id"] == "OSM:node:1"
            assert first["items"][0]["drivingDistance"] > 0
            assert first["items"][0]["dieselPrice"] is None
    asyncio.run(run())


@pytest.mark.parametrize("failure", [406, 429, 500, "timeout", "json", "remark"])
def test_failed_source_pauses_all_categories_without_false_route_failure(clock, failure):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            if len(calls) > 1:
                return httpx.Response(200, json=payload())
            if failure == "timeout":
                raise httpx.ReadTimeout("private upstream detail", request=request)
            if failure == "remark":
                return httpx.Response(200, json={"elements": [], "remark": "private upstream detail"})
            return httpx.Response(200 if failure == "json" else failure, text="private upstream detail")
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, Router(), "https://osm.invalid/api/interpreter")
            results = await asyncio.gather(*(service.search(POISearch(category=category, center=point()))
                                            for category in ["parking", "supermarket", "station"]))
            assert len(calls) == 1
            for result in results:
                assert result["items"] == []
                assert result["scope"] == "Ortesuche nicht verfügbar"
                assert "30 Sekunden" in result["notices"][0]
                assert "private upstream detail" not in str(result)
                assert "Pkw-Anfahrt" not in str(result)
            clock[0] += 30
            result = await service.search(POISearch(category="parking", center=point()))
            assert len(calls) == 2
            assert len(result["items"]) == 1
    asyncio.run(run())


@pytest.mark.parametrize("retry", ["120", formatdate(1120, usegmt=True)])
def test_retry_after_and_successful_cache_remain_effective(clock, retry):
    async def run():
        calls = []
        def handle(request):
            calls.append(request)
            if len(calls) == 1:
                return httpx.Response(200, json=payload())
            return httpx.Response(429, headers={"Retry-After": retry})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = POIService(client, Router(), "https://osm.invalid/api/interpreter")
            parking = POISearch(category="parking", center=point())
            await service.osm(parking, point(), 10)
            with pytest.raises(POISourceError, match="120 Sekunden"):
                await service.osm(POISearch(category="beach", center=point()), point(), 10)
            assert len(await service.osm(parking, point(), 10)) == 1
            clock[0] += 31
            with pytest.raises(POISourceError, match="89 Sekunden"):
                await service.osm(POISearch(category="station", center=point()), point(), 10)
            assert len(calls) == 2
    asyncio.run(run())
