import json
import math
from pathlib import Path
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from shapely.geometry import LineString, Point

from bikenavi.main import create_app
from bikenavi.marine import WaterArea
from bikenavi.models import RouteRequest

AUTH = {"Authorization": "Bearer " + "marine-test-" + "a" * 40}


def way(coords, **tags):
    return {"type": "way", "id": 1, "tags": tags, "geometry": [{"lon": x, "lat": y} for x, y in coords]}


def coast(island=False):
    ways = [way([(-.1,.01),(.1,.01)], natural="coastline")]
    if island:
        ways.append(way([(.011,-.004),(.019,-.004),(.019,.004),(.011,.004),(.011,-.004)], natural="coastline"))
    return {"elements": ways}


def request(coords=((0,0),(.03,0))):
    return RouteRequest.model_validate({"profile":{"travelMode":"sea"},"waypoints":[{"id":str(uuid4()),"name":"Öffentlicher Beispielpunkt","coordinate":{"latitude":lat,"longitude":lon}} for lon,lat in coords]})


@pytest.fixture
def client(tmp_path):
    def upstream(req):
        if req.url.host == "erddap.emodnet.eu":
            import re
            from urllib.parse import unquote
            from bikenavi.bathymetry import STEP
            ranges = re.findall(r"\[\(([-.0-9]+)\):1:\(([-.0-9]+)\)\]", unquote(req.url.query.decode()))
            south, west = float(ranges[0][0]), float(ranges[1][0])
            rows = [[south+y*STEP, west+x*STEP, -20, -20] for y in range(96) for x in range(96)]
            return httpx.Response(200, json={"table":{"columnNames":["latitude","longitude","elevation_max","elevation"],"rows":rows}})
        assert "coastline" in req.url.params.get("data", "")
        return httpx.Response(200, json=coast())
    with TestClient(create_app(f"sqlite:///{tmp_path/'marine.sqlite'}", token=AUTH["Authorization"][7:], ors_key="", transport=httpx.MockTransport(upstream))) as c:
        yield c


def test_water_route_does_not_need_ors_and_preserves_all_requested_points(client):
    req = request(((0,0),(math.degrees(1852/6_371_000),0),(math.degrees(3704/6_371_000),0)))
    result = client.post("/v1/route", headers=AUTH, json=req.model_dump(mode="json"))
    assert result.status_code == 200
    route = result.json()
    assert [route["coordinates"][i] for i in route["waypointIndices"]] == [{**p.coordinate.model_dump(),"altitude":None} for p in req.waypoints]
    assert route["distance"] == pytest.approx(3704, abs=10)
    assert route["duration"] == pytest.approx(route["distance"] / (4 * 1852 / 3600))
    assert route["marineDraft"] == 2
    assert route["ascent"] == route["descent"] == 0
    assert route["provider"] == "Seeweg · OSM-Wasserwege"


def test_sea_plan_and_next_waypoint_survive_idempotent_sync(client):
    req = request()
    route = client.post("/v1/route",headers=AUTH,json=req.model_dump(mode="json")).json()
    document = {"id":str(uuid4()),"kind":"ride","title":"Öffentliches Seeweg-Testbeispiel","createdAt":1,"updatedAt":2,
                "profile":{"travelMode":"sea"},"waypoints":[p.model_dump(mode="json") for p in req.waypoints],"route":route,
                "recordingState":"paused","localNavigation":{"marineNextWaypointIndex":1}}
    mutation = {"mutationID":str(uuid4()),"baseRevision":0,"document":document}
    first = client.post("/v1/mutations",headers=AUTH,json=mutation)
    assert first.status_code == 200
    assert client.post("/v1/mutations",headers=AUTH,json=mutation).json() == first.json()
    saved = first.json()["document"]
    assert saved["profile"]["travelMode"] == "sea"
    assert saved["localNavigation"]["marineNextWaypointIndex"] == 1


def test_land_waypoints_and_incomplete_coastlines_fail_closed():
    area = WaterArea(coast(),(-.02,-.02,.02,.04))
    with pytest.raises(HTTPException) as error:
        area.route(request(((0,.015),(.03,0))))
    assert error.value.status_code == 422
    incomplete = {"elements":[way([(-.1,.01),(0,.01)],natural="coastline")]}
    with pytest.raises(HTTPException) as error:
        WaterArea(incomplete,(-.02,-.02,.02,.04))
    assert error.value.status_code == 503
    with pytest.raises(HTTPException):
        WaterArea({"elements":[],"remark":"timeout"},(-.02,-.02,.02,.04))


def test_route_goes_around_island_and_every_segment_stays_in_water():
    area = WaterArea(coast(island=True),(-.02,-.02,.02,.04))
    req = request()
    direct = LineString([area.project(0,0),area.project(.03,0)])
    assert not area.prepared.covers(direct)
    route = area.route(req)
    line = LineString([area.project(c["longitude"],c["latitude"]) for c in route["coordinates"]])
    assert area.prepared.covers(line)
    assert line.length > direct.length
    assert any(abs(c["latitude"])>.004 for c in route["coordinates"])


def test_mapped_fairway_is_preferred_to_open_water_shortcut():
    data = coast()
    data["elements"].append(way([(0,0),(.005,-.002),(.025,-.002),(.03,0)], **{"seamark:type":"recommended_track"}))
    area = WaterArea(data,(-.02,-.02,.02,.04))
    route = area.route(request())
    line = LineString([area.project(c["longitude"],c["latitude"]) for c in route["coordinates"]])
    assert line.intersection(area.corridors).length/line.length > .5
    assert area.prepared.covers(line)


def test_real_tribunj_to_sibenik_follows_water_and_mapped_seaways():
    data = json.loads((Path(__file__).resolve().parents[2]/"tests/fixtures/tribunj-sibenik-marine-osm.json").read_text())
    area = WaterArea(data,(43.72,15.72,43.78,15.92))
    req = request(((15.7458,43.7508),(15.8835,43.737)))
    direct = LineString([area.project(p.coordinate.longitude,p.coordinate.latitude) for p in req.waypoints])
    assert not area.prepared.covers(direct)  # The direct connection cuts through mainland/islands.
    route = area.route(req)
    line = LineString([area.project(c["longitude"],c["latitude"]) for c in route["coordinates"]])
    assert area.prepared.covers(line)
    assert 6 < route["distance"]/1852 < 10
    assert any(43.72<c["latitude"]<43.73 and 15.85<c["longitude"]<15.88 for c in route["coordinates"])  # Sv. Ante channel.
    assert area.corridors is None  # Ferry lines alone must never pull a leisure route into a dogleg.


def test_depth_cells_exclude_shoals_and_unknown_values_without_cutting_corners():
    import copy
    import numpy as np
    from bikenavi.bathymetry import DepthTiles, STEP
    from shapely.prepared import prep
    base = WaterArea(coast(), (-.02, -.02, .02, .04))
    values = np.array([[(y+.5)*STEP, (x+.5)*STEP, 1 if (x,y)==(1,0) else 10] for y in range(-2,4) for x in range(-2,6)])
    wet = DepthTiles.water(base, [values], 2)
    area = copy.copy(base)
    area.water = base.water.intersection(wet)
    area.prepared = prep(area.water)
    req = request(((.5*STEP,.5*STEP),(3.5*STEP,.5*STEP)))
    line = LineString([area.project(p.coordinate.longitude,p.coordinate.latitude) for p in req.waypoints])
    assert not area.prepared.covers(line)
    result = area.route(req)
    detour = LineString([area.project(c['longitude'],c['latitude']) for c in result['coordinates']])
    assert area.prepared.covers(detour)
    values[:,2] = float('nan')
    with pytest.raises(HTTPException): DepthTiles.water(base, [values], 2)
    with pytest.raises(HTTPException): DepthTiles.water(base, [np.array([[.5*STEP,.5*STEP,1]])], 2)


def test_depth_tile_uses_shallowest_value_and_marks_missing_data_unusable():
    import asyncio
    from bikenavi.bathymetry import DepthTiles
    async def run():
        def respond(req):
            return httpx.Response(200,json={'table':{'columnNames':['latitude','longitude','elevation_max','elevation'],'rows':[
                [43.700520833,15.700520833,-1,-8], [43.700520833,15.7015625,None,-5], [43.700520833,15.702604167,None,None]]}})
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
            tiles=DepthTiles(http)
            cells=await tiles.tile((437,157))
            assert cells[0,2]==1 and cells[1,2]==5
            assert math.isnan(cells[2,2])
            assert await tiles.tile((437,157)) is cells
    asyncio.run(run())


def test_missing_depth_provider_never_falls_back_to_coast_only_route():
    import asyncio
    from bikenavi.bathymetry import DepthTiles
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req:httpx.Response(503))) as http:
            with pytest.raises(HTTPException) as error: await DepthTiles(http).tile((437,157))
            assert error.value.status_code==503
    asyncio.run(run())


def test_ferry_only_detour_is_removed_across_the_whole_visible_water_leg():
    data = coast()
    data['elements'].append(way([(0,0),(.015,-.008),(.016,-.003),(.03,0)],route='ferry'))
    area=WaterArea(data,(-.02,-.02,.02,.04))
    assert area.corridors is None
    route=area.route(request())
    assert len(route['coordinates'])==2
    assert route['distance']==pytest.approx(3335.85,abs=1)


def test_long_passage_has_no_arbitrary_distance_cutoff():
    import asyncio
    from unittest.mock import AsyncMock
    from bikenavi.marine import MarineRouter
    async def run():
        data={'elements':[way([(-3,.01),(3,.01)],natural='coastline')]}
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req:httpx.Response(200,json=data))) as client:
            router=MarineRouter(client,'')
            router.depths.area=AsyncMock(side_effect=lambda area,route,draft:(area.water,area.water))
            result=await router.route(request(((0,0),(1.2,0))))
            assert result['distance']>130000
            assert len(result['coordinates'])==2
    asyncio.run(run())


def test_unresolved_coastal_cells_are_explicitly_uncertain_but_known_shoals_stay_blocked():
    import numpy as np
    from bikenavi.bathymetry import DepthTiles, STEP
    base=WaterArea(coast(),(-.02,-.02,.02,.04))
    cells=np.array([[.5*STEP,.5*STEP,10],[.5*STEP,1.5*STEP,float('nan')],[.5*STEP,2.5*STEP,1]])
    known=DepthTiles.water(base,[cells],2)
    allowed=DepthTiles.water(base,[cells],2,True)
    unknown=Point(base.project(1.5*STEP,.5*STEP))
    shallow=Point(base.project(2.5*STEP,.5*STEP))
    assert allowed.covers(unknown) and not known.covers(unknown)
    assert not allowed.covers(shallow)
