import httpx
from fastapi.testclient import TestClient
from bikenavi.main import create_app
from bikenavi.offline import compile_tile

TOKEN = 'offline-test-' + 'x' * 40
AUTH = {'Authorization': 'Bearer ' + TOKEN}


def elements(tags=None, node_tags=None):
    return [{'type':'node','id':1,'lat':49,'lon':8},
            {'type':'node','id':2,'lat':49,'lon':8.001,'tags':node_tags or {}},
            {'type':'node','id':3,'lat':49,'lon':8.002},
            {'type':'way','id':10,'nodes':[1,2,3],'tags':{'highway':'residential','surface':'asphalt', **(tags or {})}}]


def test_bicycle_access_oneway_and_barriers():
    assert len(compile_tile(elements(),1,1)['edges']) == 4
    assert len(compile_tile(elements({'oneway':'yes'}),1,1)['edges']) == 2
    assert len(compile_tile(elements({'oneway':'yes','oneway:bicycle':'no'}),1,1)['edges']) == 4
    assert len(compile_tile(elements({'oneway':'-1'}),1,1)['edges']) == 2
    for tags in [{'access':'private'}, {'bicycle':'no'}, {'bicycle':'dismount'}, {'highway':'steps'},
                 {'access:conditional':'no @ (Mo-Fr)'}, {'highway':'footway'}, {'highway':'motorway'}]:
        assert compile_tile(elements(tags),1,1)['edges'] == []
    assert len(compile_tile(elements({'highway':'footway','bicycle':'yes'}),1,1)['edges']) == 4
    assert compile_tile(elements(node_tags={'barrier':'gate'}),1,1)['edges'] == []
    assert compile_tile(elements(node_tags={'barrier':'bollard','bicycle':'no'}),1,1)['edges'] == []
    assert len(compile_tile(elements(node_tags={'barrier':'bollard'}),1,1)['edges']) == 4
    assert all(e['surface'] == 0 for e in compile_tile(elements({'surface':'unknown'}),1,1)['edges'])


def restriction(via_type='node', extra=None):
    return {'type':'relation','id':40,'tags':{'type':'restriction','restriction':'no_left_turn',**(extra or {})},
            'members':[{'type':'way','role':'from','ref':10},{'type':via_type,'role':'via','ref':2},
                       {'type':'way','role':'to','ref':20}]}


def test_turn_rules_and_unsupported_rules_are_conservative():
    tile = compile_tile(elements()+[restriction()],1,1)
    assert tile['restrictions'][0] == {'via':2,'fromWay':10,'toWays':[20],'only':False,'uTurn':False}
    assert compile_tile(elements()+[restriction(extra={'except':'bicycle'})],1,1)['restrictions'] == []
    assert compile_tile(elements()+[restriction('way')],1,1)['edges'] == []
    assert compile_tile(elements()+[restriction(extra={'restriction:conditional':'no_left_turn @ (Mo-Fr)'})],1,1)['edges'] == []
    assert compile_tile(elements()+[restriction(extra={'restriction':'only_right_turn'})],1,1)['restrictions'][0]['only']


def test_tiles_auth_cache_and_partial_upstream_failure(tmp_path):
    calls = []
    def upstream(request):
        calls.append(request)
        return httpx.Response(200,json={'elements':elements()})
    app = create_app(f'sqlite:///{tmp_path / "db.sqlite"}',token=TOKEN,transport=httpx.MockTransport(upstream),overpass_url='https://osm.test/api')
    with TestClient(app) as client:
        assert client.get('/v1/offline-tiles/3760/2780').status_code == 401
        a = client.get('/v1/offline-tiles/3760/2780',headers=AUTH)
        assert a.status_code == 200
        assert a.json()['version'] == 1
        assert len(a.json()['edges']) == 4
        assert client.get('/v1/offline-tiles/3760/2780',headers=AUTH).json() == a.json()
        assert len(calls) == 1
        assert client.get('/v1/offline-tiles/-1/2780',headers=AUTH).status_code == 422
    # The cache is durable across backend restarts.
    with TestClient(app) as client:
        assert client.get('/v1/offline-tiles/3760/2780',headers=AUTH).status_code == 200
        assert len(calls) == 1
    failed = create_app(f'sqlite:///{tmp_path / "fail.sqlite"}',token=TOKEN,
        transport=httpx.MockTransport(lambda _: httpx.Response(200,json={'elements':elements(),'remark':'runtime error: timeout'})),
        overpass_url='https://osm.test/api')
    with TestClient(failed) as client:
        assert client.get('/v1/offline-tiles/3760/2780',headers=AUTH).status_code == 503
        assert failed.state.storage.offline_tile('1/2/3760/2780') is None


def test_public_provider_failure_uses_mirror_and_caches_complete_tile(tmp_path):
    from bikenavi.offline import DEFAULT_OVERPASS, FALLBACK_OVERPASS
    for failure in ('connection', 'incomplete'):
        calls = []
        def upstream(request):
            calls.append(str(request.url))
            if str(request.url) == DEFAULT_OVERPASS:
                if failure == 'connection':
                    raise httpx.ConnectError('Connection refused', request=request)
                return httpx.Response(200, json={'elements': elements(), 'remark': 'timeout'})
            assert str(request.url) == FALLBACK_OVERPASS
            return httpx.Response(200, json={'elements': elements()})
        app = create_app(f'sqlite:///{tmp_path / (failure + ".sqlite")}', token=TOKEN,
                         transport=httpx.MockTransport(upstream), overpass_url=DEFAULT_OVERPASS)
        with TestClient(app) as client:
            response = client.get('/v1/offline-tiles/3781/2798', headers=AUTH)
            assert response.status_code == 200
            assert len(response.json()['edges']) == 4
            assert client.get('/v1/offline-tiles/3781/2798', headers=AUTH).json() == response.json()
            assert calls == [DEFAULT_OVERPASS, FALLBACK_OVERPASS]


def test_failed_mirrors_preserve_existing_tile_on_refresh(tmp_path):
    from bikenavi.offline import DEFAULT_OVERPASS, FALLBACK_OVERPASS
    calls = []
    failing = False
    def upstream(request):
        calls.append(str(request.url))
        return httpx.Response(503) if failing else httpx.Response(200, json={'elements': elements()})
    app = create_app(f'sqlite:///{tmp_path / "refresh.sqlite"}', token=TOKEN,
                     transport=httpx.MockTransport(upstream), overpass_url=DEFAULT_OVERPASS)
    with TestClient(app) as client:
        original = client.get('/v1/offline-tiles/3781/2798', headers=AUTH).json()
        failing = True
        assert client.get('/v1/offline-tiles/3781/2798?refresh=true', headers=AUTH).status_code == 503
        assert calls == [DEFAULT_OVERPASS, DEFAULT_OVERPASS, FALLBACK_OVERPASS]
        assert app.state.storage.offline_tile('1/2/3781/2798') == original


def test_operable_barriers_use_most_specific_explicit_access():
    for barrier in ('gate', 'lift_gate', 'swing_gate'):
        for permit in ({'access': 'yes'}, {'vehicle': 'yes'}, {'bicycle': 'yes', 'access': 'private'}):
            assert len(compile_tile(elements(node_tags={'barrier': barrier, **permit}), 1, 1)['edges']) == 4
        for deny in ({}, {'access': 'private'}, {'access': 'yes', 'vehicle': 'no'},
                     {'access': 'yes', 'bicycle': 'no'}, {'access': 'yes', 'bicycle': 'dismount'},
                     {'access': 'yes', 'locked': 'yes'},
                     {'access': 'yes', 'access:conditional': 'no @ (Mo-Fr)'}):
            assert compile_tile(elements(node_tags={'barrier': barrier, **deny}), 1, 1)['edges'] == []
    # General permission does not make a physical wall passable.
    assert compile_tile(elements(node_tags={'barrier': 'wall', 'access': 'yes'}), 1, 1)['edges'] == []


def test_tisno_bridge_has_continuous_access_in_both_directions():
    import json
    from pathlib import Path
    source = json.loads((Path(__file__).parent / 'fixtures/tisno_bridge_osm.json').read_text())
    tile = compile_tile(source['elements'], 3912, 2675)
    expected = json.loads((Path(__file__).parent / 'fixtures/tisno_bridge_graph.json').read_text())
    assert compile_tile(source['elements'], 3912, 2675, generated_at=1) == expected
    assert tile['blockedNodes'] == []
    assert tile['excludedWays'] == []
    assert tile['compilerRevision'] == 2
    for start, end in [(272268068, 275001050), (275001050, 272268068)]:
        visited, pending = set(), [start]
        while pending:
            node = pending.pop()
            if node in visited:
                continue
            visited.add(node)
            pending.extend(e['to'] for e in tile['edges'] if e['from'] == node and e['surface'] == 3)
        assert end in visited


def test_old_compiler_cache_is_not_reused(tmp_path):
    calls = []
    def upstream(request):
        calls.append(request)
        return httpx.Response(200, json={'elements': elements(node_tags={'barrier': 'lift_gate', 'access': 'yes'})})
    app = create_app(f'sqlite:///{tmp_path / "migration.sqlite"}', token=TOKEN,
                     transport=httpx.MockTransport(upstream), overpass_url='https://osm.test/api')
    with TestClient(app) as client:
        old = compile_tile(elements(node_tags={'barrier': 'lift_gate'}), 3760, 2780)
        old.pop('compilerRevision')
        app.state.storage.save_offline_tile('1/3760/2780', old)
        response = client.get('/v1/offline-tiles/3760/2780', headers=AUTH)
        assert response.status_code == 200
        assert response.json()['compilerRevision'] == 2
        assert len(response.json()['edges']) == 4
        assert len(calls) == 1
        assert app.state.storage.offline_tile('1/3760/2780') == old
