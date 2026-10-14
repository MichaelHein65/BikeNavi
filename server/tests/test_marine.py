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
        from urllib.parse import parse_qs
        assert req.method == "POST"
        assert "coastline" in parse_qs(req.content.decode())["data"][0]
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
    assert route["marineRoutingRevision"] == 2
    assert route["ascent"] == route["descent"] == 0
    assert route["provider"] == "Seeweg · OSM-Wasserwege"


def test_sea_plan_and_next_waypoint_survive_idempotent_sync(client):
    req = request()
    route = WaterArea(coast(), (-.02,-.02,.02,.04)).route(req)
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


@pytest.mark.parametrize("first", [httpx.Response(503), httpx.Response(200, json={"remark": "runtime error: out of memory", "elements": []}), httpx.Response(200, json={"version": 0.6})])
def test_coast_download_retries_provider_errors_and_rejects_partial_results(first):
    import asyncio
    from urllib.parse import parse_qs
    from bikenavi.marine import MarineRouter
    from bikenavi.offline import DEFAULT_OVERPASS, FALLBACK_OVERPASS
    async def run():
        calls = []
        def upstream(req):
            calls.append(str(req.url))
            assert req.method == "POST"
            query = parse_qs(req.content.decode())["data"][0]
            assert "[maxsize:67108864]" in query  # Server working memory, not response bytes.
            assert '"ferry"' not in query
            assert "coastline" in query and "fairway" in query
            assert req.headers["User-Agent"].startswith("BikeNavi/")
            return first if len(calls) == 1 else httpx.Response(200, json=coast())
        async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as client:
            data = await MarineRouter(client, "").coast_data((-.02,-.02,.02,.04))
            assert data == coast()
            assert calls == [DEFAULT_OVERPASS, FALLBACK_OVERPASS]
    asyncio.run(run())


def test_unavailable_custom_coast_provider_never_uses_another_host_or_partial_coast():
    import asyncio
    from bikenavi.marine import MarineRouter
    async def run():
        calls = []
        def upstream(req):
            calls.append(str(req.url))
            raise httpx.ReadTimeout("unavailable", request=req)
        async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as client:
            with pytest.raises(HTTPException) as error:
                await MarineRouter(client, "https://maps.example/api").coast_data((-.02,-.02,.02,.04))
            assert error.value.status_code == 503
            assert calls == ["https://maps.example/api"]
    asyncio.run(run())


def test_dateline_passage_is_rejected_before_querying_the_wrong_side_of_the_globe():
    import asyncio
    from bikenavi.marine import MarineRouter
    async def run():
        def upstream(req):
            pytest.fail("Unsupported dateline passage must not query a 265-degree land rectangle")
        async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as client:
            with pytest.raises(HTTPException) as error:
                await MarineRouter(client, "").route(request(((141,35),(-124,37))))
            assert error.value.status_code == 422
            assert "Datumsgrenze" in error.value.detail
    asyncio.run(run())


def test_missing_depth_outside_dataset_footprint_is_reported_as_coverage_not_outage():
    import asyncio
    from bikenavi.bathymetry import DepthTiles
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req:httpx.Response(404))) as client:
            with pytest.raises(HTTPException) as error:
                await DepthTiles(client).tile((400,-740))
            assert error.value.status_code == 422
            assert "Tiefenabdeckung" in error.value.detail
            with pytest.raises(HTTPException) as coastal_error:
                await DepthTiles(client).tile((437,157))
            assert coastal_error.value.status_code == 503
    asyncio.run(run())


def test_ropotnica_shoal_polygon_and_rocks_are_land_for_search_and_simplification():
    data = json.loads((Path(__file__).resolve().parents[2]/"tests/fixtures/ropotnica-marine-osm.json").read_text())
    area = WaterArea(data, (43.765,15.345,43.79,15.375))
    req = request(((15.355,43.779),(15.365,43.7755)))
    direct = LineString([area.project(p.coordinate.longitude,p.coordinate.latitude) for p in req.waypoints])
    assert direct.intersects(area.obstacles)
    route = area.route(req)
    line = LineString([area.project(c['longitude'],c['latitude']) for c in route['coordinates']])
    assert area.prepared.covers(line)
    assert not line.intersects(area.obstacles)
    assert len(route['coordinates']) > 2
    with pytest.raises(HTTPException) as error:
        area.route(request(((15.3595,43.7775),(15.365,43.7755))))
    assert error.value.status_code == 422


def test_point_and_polygon_hazards_cannot_be_crossed_even_on_a_fairway():
    from bikenavi.marine_obstacles import exclusions
    data = coast()
    data['elements'].extend([
        {'type':'node','lat':0,'lon':.015,'tags':{'seamark:type':'rock'}},
        way([(.021,-.001),(.023,-.001),(.023,.001),(.021,.001),(.021,-.001)], **{'seamark:sea_area:category':'shoal'}),
        way([(0,0),(.03,0)], **{'seamark:type':'recommended_track'})])
    area = WaterArea(data,(-.02,-.02,.02,.04))
    route = area.route(request())
    line = LineString([area.project(c['longitude'],c['latitude']) for c in route['coordinates']])
    assert not line.intersects(area.obstacles)
    assert area.prepared.covers(line)
    # Joined multipolygon outer fragments must exclude their interior as well.
    relation = {'type':'relation','tags':{'natural':'reef'},'members':[
        {'type':'way','role':'outer','geometry':[{'lon':x,'lat':y} for x,y in [(0,0),(.01,0),(.01,.01)]]},
        {'type':'way','role':'outer','geometry':[{'lon':x,'lat':y} for x,y in [(.01,.01),(0,.01),(0,0)]]}]}
    blocked = exclusions([relation], area.project, 2)
    assert blocked.covers(Point(area.project(.005,.005)))
    relation['members'].pop()
    with pytest.raises(HTTPException): exclusions([relation],area.project,2)


def test_depth_area_and_sounding_block_at_or_below_draft():
    from bikenavi.marine_obstacles import is_hazard
    assert is_hazard({'seamark:type':'sounding','seamark:sounding:depth':'2'},2)
    assert not is_hazard({'seamark:type':'sounding','seamark:sounding:depth':'3'},2)
    assert is_hazard({'seamark:type':'depth_area'},2)
    assert is_hazard({'seamark:type':'depth_area','seamark:depth_area:minimum_depth':'2.4'},2.5)


def test_drying_emodnet_maximum_is_not_overridden_by_negative_mean():
    import asyncio
    from bikenavi.bathymetry import DepthTiles
    async def run():
        def upstream(req):
            return httpx.Response(200,json={'table':{'columnNames':['latitude','longitude','elevation_max','elevation'],
                'rows':[[43.700520833,15.700520833,0,-8],[43.700520833,15.7015625,1,-9]]}})
        async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as client:
            cells = await DepthTiles(client).tile((437,157))
            assert list(cells[:,2]) == [0,-1]
    asyncio.run(run())
