import asyncio

import httpx
import pytest
from fastapi import HTTPException

from bikenavi.providers import ORS


def test_current_endpoint_and_repeated_geometry_cached_without_mutable_sharing(monkeypatch):
    calls=[]
    clock=[1000.0]
    monkeypatch.setattr('bikenavi.providers.time.monotonic',lambda:clock[0])
    def handler(request):
        assert request.url.host=='api.heigit.org'
        assert request.url.path=='/openrouteservice/v2/directions/cycling-regular/geojson'
        calls.append(request)
        return httpx.Response(200,json={'features':[{'geometry':{'coordinates':[[8.68,49.41],[8.69,49.42]]}}]})
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            ors=ORS('test-key',client)
            path='/v2/directions/cycling-regular/geojson'
            payload={'coordinates':[[8.68,49.41],[8.69,49.42]]}
            first=await ors.request('POST',path,json=payload)
            first['features'].clear()
            second=await ors.request('POST',path,json=payload)
            assert second['features'] and len(calls)==1
            await ors.request('POST',path,json=dict(payload,extra_info=['surface']))
            assert len(calls)==2
            clock[0]+=301
            await ors.request('POST',path,json=payload)
            assert len(calls)==3
    asyncio.run(run())


@pytest.mark.parametrize('error,code,text', [('Quota exceeded',429,'Tageskontingent'),
                                          ('Access denied',503,'Routing-Zugang')])
def test_quota_distinct_from_access_denied_and_errors_not_cached(error,code,text):
    calls=[]
    def handler(request):
        calls.append(request)
        return httpx.Response(403,json={'error':error})
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            ors=ORS('test-key',client)
            for _ in range(2):
                with pytest.raises(HTTPException) as caught:
                    await ors.request('POST','/v2/directions/cycling-regular/geojson',json={})
                assert caught.value.status_code==code and text in caught.value.detail
            assert len(calls)==2
    asyncio.run(run())
