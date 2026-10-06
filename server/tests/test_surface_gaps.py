import json
from uuid import uuid4
import httpx
import pytest
from fastapi.testclient import TestClient
from bikenavi.main import create_app
from bikenavi.providers import road_gap_edges, parse_route

TOKEN='test-token-long-enough-123456789012345'


def example(lengths, surfaces, kinds):
    # Synthetic equatorial metric geometry, no personal location.
    points=[[0,0]]
    for length in lengths:
        points.append([points[-1][0]+length/111194.92664455874,0])
    totals={}
    for length, surface in zip(lengths,surfaces):
        totals[surface]=totals.get(surface,0)+length
    return {'features':[{'geometry':{'coordinates':points},'properties':{
        'summary':{'distance':sum(lengths),'duration':sum(lengths)},'way_points':[0,len(lengths)],
        'extras':{'surface':{'values':[[i,i+1,s] for i,s in enumerate(surfaces)],
                            'summary':[{'value':s,'distance':d,'amount':100*d/sum(lengths)} for s,d in totals.items()]},
                  'waytype':{'values':[[i,i+1,k] for i,k in enumerate(kinds)]}}}}]}


@pytest.mark.parametrize('length,surface,kind,allowed',[(223,0,3,True),(249.9,0,2,True),
    (250.1,0,3,False),(223,15,3,False),(223,10,3,False),(223,0,5,False),(223,0,4,False)])
def test_only_short_missing_tags_on_roads_between_paved_sections_get_extra_budget(tmp_path,length,surface,kind,allowed):
    raw=example([100,length,100],[3,surface,3],[3,kind,2])
    points=raw['features'][0]['geometry']['coordinates']
    body={'profile':{'surface':'pavedOnly'},'waypoints':[
        {'id':str(uuid4()),'name':'Synthetic example','coordinate':{'longitude':p[0],'latitude':p[1]}}
        for p in [points[0],points[-1]]]}
    with TestClient(create_app(f'sqlite:///{tmp_path}/gaps.sqlite',TOKEN,'test-key',
                    httpx.MockTransport(lambda req:httpx.Response(200,json=raw)))) as client:
        response=client.post('/v1/route?include_context=false',headers={'Authorization':'Bearer '+TOKEN},json=body)
        assert response.status_code==(200 if allowed else 422),response.text
        if allowed:
            route=response.json()
            assert any('Belagslücken toleriert' in w for w in route['warnings'])
            assert any(s['name']=='Unbekannt' for s in route['surfaces'])
            assert route['surfaceSections'][1]['surface']==0


def test_gap_budget_is_bounded_over_whole_route_and_cannot_consume_real_dirt_budget():
    raw=example([50,240,50,240,50],[3,0,3,0,3],[3]*5)
    assert road_gap_edges(parse_route(raw),[3]*5)=={1,3}
    raw=example([50,180,50,180,50,180,50],[3,0,3,0,3,0,3],[3]*7)
    assert not road_gap_edges(parse_route(raw),[3]*7)


@pytest.mark.parametrize('surfaces',[[0,3,3],[3,3,0],[3,-1,3]])
def test_unbounded_or_unreported_surface_is_not_a_bridge(surfaces):
    raw=example([120,120,120],[3,0,3],[3]*3)
    route=parse_route(raw)
    route['surfaceSections']=[dict(startIndex=i,endIndex=i+1,surface=s) for i,s in enumerate(surfaces) if s>=0]
    assert not road_gap_edges(route,[3]*3)


@pytest.mark.parametrize('dirt,expected',[(100,200),(101,422)])
def test_bridged_street_gap_keeps_separate_100m_budget_for_real_unpaved_sections(tmp_path,dirt,expected):
    raw=example([100,223,100,dirt],[3,0,3,15],[3,3,3,5])
    points=raw['features'][0]['geometry']['coordinates']
    body={'profile':{'surface':'pavedOnly'},'waypoints':[
        {'id':str(uuid4()),'name':'Synthetic example','coordinate':{'longitude':p[0],'latitude':p[1]}}
        for p in [points[0],points[-1]]]}
    with TestClient(create_app(f'sqlite:///{tmp_path}/dirt.sqlite',TOKEN,'test-key',
                    httpx.MockTransport(lambda req:httpx.Response(200,json=raw)))) as client:
        response=client.post('/v1/route?include_context=false',headers={'Authorization':'Bearer '+TOKEN},json=body)
        assert response.status_code==expected,response.text
