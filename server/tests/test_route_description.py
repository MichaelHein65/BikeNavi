import asyncio
import json
from copy import deepcopy
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from bikenavi.main import create_app
from bikenavi.route_description import (DescriptionGenerator, DescriptionJobs, DescriptionRequest,
                                        DescriptionStory, analyse, locate, render_description, trusted_url)

TOKEN = 'route-test-' + 'a' * 40
AUTH = {'Authorization': 'Bearer ' + TOKEN}


def request():
    coords = [{'latitude': 49 + i * .001, 'longitude': 8} for i in range(5)]
    return DescriptionRequest.model_validate({'planID': str(uuid4()), 'title': 'Öffentliche synthetische Beispieltour',
        'waypoints': [{'id': str(uuid4()), 'name': name, 'coordinate': coords[i]} for name, i in [('Start', 0), ('Zwischenziel', 2), ('Ziel', 4)]],
        'profile': {'bike': 'touring', 'electric': True}, 'route': {
            'id': str(uuid4()), 'coordinates': coords, 'distance': 400, 'duration': 100, 'ascent': 20, 'descent': 20,
            'calculatedAt': 1, 'waypointIndices': [0, 2, 4],
            'surfaceSections': [{'startIndex': 0, 'endIndex': 1, 'surface': 3}, {'startIndex': 1, 'endIndex': 2, 'surface': 15},
                                {'startIndex': 3, 'endIndex': 4, 'surface': 10}],
            'elevationProfile': [{'distance': i * 50, 'altitude': 100 + (i * 5 if i <= 4 else (8 - i) * 5)} for i in range(9)]}})


def test_analysis_all_legs_surface_gaps_and_steep_climbs_and_descents():
    sections, notes, _ = analyse(request())
    assert [s['title'] for s in sections] == ['Start → Zwischenziel', 'Zwischenziel → Ziel']
    assert sections[0]['surfaces'] == {'Asphalt': 100, 'Sand': 100}
    assert sections[1]['surfaces'] == {'Schotter': 100, 'Unbekannt': 100}
    assert any('Anstieg' in w['text'] and w['fromKM'] == 0 for w in sections[0]['warnings'])
    assert any('Abfahrt' in w['text'] for w in sections[1]['warnings'])
    assert any('Belag nicht erfasst' in w['text'] for w in sections[1]['warnings'])
    sand = next(w for w in sections[0]['warnings'] if 'Sand' in w['text'])
    assert (sand['fromKM'], sand['toKM']) == (.1, .2)
    assert any('keine Prüfung aktueller Sperrungen' in note for note in notes)


def test_no_elevation_does_not_claim_flat_route_and_aggregate_surfaces_cannot_locate_bad_ground():
    r = request()
    r.route.elevationProfile = None
    r.route.surfaceSections = None
    sections, notes, _ = analyse(r)
    assert all(s['surfaces'] == {'Unbekannt': 200} for s in sections)
    assert not any(w['kind'] == 'grade' for s in sections for w in s['warnings'])
    assert any('Keine vollständigen Höhendaten' in n for n in notes)
    html = render_description(r, sections, [], DescriptionStory(introduction='Beispiel', sections=['A', 'B'], closing='Beispiel'), notes, 'template')
    assert 'Anstieg nicht erfasst' in html


def test_short_dem_spike_does_not_create_steepness_and_coarse_data_is_reported():
    r = request()
    from bikenavi.models import ElevationSample
    r.route.elevationProfile = [ElevationSample(distance=0, altitude=100), ElevationSample(distance=400, altitude=100)]
    from bikenavi.models import Route
    r.route = Route.model_validate(r.route.model_dump())
    sections, notes, _ = analyse(r)
    assert not any(w['kind'] == 'grade' for s in sections for w in s['warnings'])
    assert any('Grobe Höhenabstände' in n for n in notes)


def test_missing_waypoint_indices_preserve_forward_leg_order_and_endpoint_gaps():
    r = request()
    r.route.waypointIndices = None
    r.route.unmappedDestinationDistance = 100
    sections, notes, _ = analyse(r)
    assert len(sections) == 2 and sections[0]['toKM'] == sections[1]['fromKM']
    assert any('angenähert' in n for n in notes)
    assert any('nicht analysiert' in n for n in notes)


def test_highlights_project_to_edges_rather_than_nearest_vertex():
    coords = [{'latitude': 49, 'longitude': 8}, {'latitude': 49.02, 'longitude': 8}]
    gap, position = locate({'latitude': 49.01, 'longitude': 8.001}, coords, [0, 2000])
    assert 60 < gap < 80 and position == pytest.approx(1000)


@pytest.mark.parametrize('url', ['https://upload.wikimedia.org.evil.example/x', 'http://upload.wikimedia.org/x',
                               'https://user@upload.wikimedia.org/x', 'https://upload.wikimedia.org:8443/x'])
def test_only_fixed_image_hosts_without_credentials_or_custom_ports(url):
    assert not trusted_url(url, 'upload.wikimedia.org')


def transport(license_name='CC BY-SA 4.0', writer=None, image_host='upload.wikimedia.org', license_scheme='https', on_writer=None, terrain_available=True, source_language='de'):
    def respond(req):
        if req.url.host == 'a.tile.opentopomap.org':
            if not terrain_available: return httpx.Response(503)
            return httpx.Response(200, content=b'\x89PNG\r\n\x1a\n' + bytes(8) + (256).to_bytes(4, 'big') * 2)
        if req.url.host == 'api.openai.com':
            body = json.loads(req.content)
            if on_writer: on_writer(body)
            assert body['store'] is False and 'track' not in json.loads(body['input'])
            story = writer or {'introduction': 'Vorfreude auf die geplante Strecke [1].', 'sections': ['Start bis Zwischenziel [1].', 'Weiter zum Ziel.'], 'closing': 'Viel Freude unterwegs.'}
            story = {**story, 'language': story.get('language', 'de'),
                     'highlights': story.get('highlights', [{'sourceNumber': 1, 'title': 'Beispielort', 'text': 'Ein kurzer deutscher Hintergrund für deine Tour.'}])}
            return httpx.Response(200, json={'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': json.dumps(story)}]}]})
        if req.url.host in ('upload.wikimedia.org', 'thumb.wikimedia.org'):
            return httpx.Response(200, content=b'\xff\xd8\xff' + b'synthetic')
        if req.url.host == 'commons.wikimedia.org':
            return httpx.Response(200, json={'query': {'pages': {'1': {'imageinfo': [{
                'thumburl': f'https://{image_host}/example.jpg', 'descriptionurl': 'https://commons.wikimedia.org/wiki/File:Example.jpg',
                'extmetadata': {'Artist': {'value': '<a href="https://example.org">Beispielautor</a>'},
                    'LicenseShortName': {'value': license_name}, 'LicenseUrl': {'value': f'{license_scheme}://creativecommons.org/licenses/by-sa/4.0/'}}}]}}}})
        if req.url.params.get('prop') == 'pageimages':
            return httpx.Response(200, json={'query': {'pages': {'1': {'pageimage': 'Example.jpg'}}}})
        if source_language == 'en' and req.url.host == 'de.wikipedia.org':
            return httpx.Response(200, json={'query': {'pages': {}}})
        title, text = ('The Example Castle', 'The Example Castle is a medieval castle. It was built in 1200.') if source_language == 'en' else ('Beispielort', 'Ein ausdrücklich synthetischer Hintergrund für die Prüfung.')
        return httpx.Response(200, json={'query': {'pages': {'1': {'title': title, 'extract': text,
            'coordinates': [{'lat': 49.001, 'lon': 8}], 'pageprops': {'wikibase_item': 'Q-test'}}}}})
    return httpx.MockTransport(respond)


def test_generation_independent_of_rides_and_blog_with_embedded_licensed_images(monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    async def scenario():
        async with httpx.AsyncClient(transport=transport()) as client:
            generator = DescriptionGenerator(client)
            phases = []
            r = request()
            report = await generator.generate(r, phases.append)
            assert report['planID'] == str(r.planID) and report['routeID'] == str(r.route.id)
            assert report['mode'] == 'template' and report['imageCount'] == 1 and report['sourceCount'] == 1
            highlight = report['highlights'][0]
            assert highlight['coordinate'] == {'latitude': 49.001, 'longitude': 8}
            assert highlight['startWaypointID'] == str(r.waypoints[0].id)
            assert highlight['endWaypointID'] == str(r.waypoints[1].id)
            assert 90 < highlight['routeDistance'] < 110
            html = report['html']
            assert 'bikenavi-highlight://insert/' + highlight['id'] in html
            assert 'Als Zwischenziel einfügen' in html
            assert 'data:image/jpeg;base64,' in html and 'Beispielautor' in html and 'CC BY-SA 4.0' in html
            assert 'Start → Zwischenziel' in html and 'Steiler Anstieg' in html and 'Steile Abfahrt' in html
            assert 'aufgezeichnet' not in html and '<script' not in html
            assert 'Blog-Orten' not in html and 'keine GPS-Aufzeichnung' not in html
            assert 'Topografische Streckenübersicht mit nummerierten Wegpunkten' in html
            assert 'data:image/png;base64,' in html and 1 <= html.count('<image ') <= 12
            assert 'OpenStreetMap-Mitwirkende' in html and 'SRTM' in html and 'OpenTopoMap' in html
            assert 'https://creativecommons.org/licenses/by-sa/3.0/' in html
            assert 'Topografie nicht verfügbar' not in html
            assert all(f'data-route-icon="{kind}"' in html for kind in ('distance', 'uphill', 'downhill', 'surface', 'unknown'))
            assert 'aria-hidden="true" role="presentation" focusable="false"' in html
            assert phases == ['researching', 'images', 'saving']
    asyncio.run(scenario())


def test_unavailable_terrain_keeps_route_highlights_and_explicit_offline_fallback(monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    async def scenario():
        async with httpx.AsyncClient(transport=transport(terrain_available=False)) as client:
            report = await DescriptionGenerator(client).generate(request(), lambda _: None)
            assert report['sourceCount'] == 1 and report['imageCount'] == 1 and report['highlights']
            assert 'schematische Streckenübersicht (Topografie nicht verfügbar)' in report['html']
            assert '<polyline' in report['html'] and '<image ' not in report['html']
            assert any('Topografische Streckenkarte derzeit nicht verfügbar' in note for note in report['warnings'])
    asyncio.run(scenario())


def test_unusable_image_license_does_not_block_analysis(monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    async def scenario():
        async with httpx.AsyncClient(transport=transport(license_name='All rights reserved')) as client:
            report = await DescriptionGenerator(client).generate(request(), lambda _: None)
            assert report['imageCount'] == 0 and 'data:image/jpeg' not in report['html']
            assert any('Keine geeigneten' in w for w in report['warnings'])
    asyncio.run(scenario())


def test_current_wikimedia_thumbnail_host_and_legacy_http_license_are_supported():
    async def scenario():
        async with httpx.AsyncClient(transport=transport(image_host='thumb.wikimedia.org', license_scheme='http')) as client:
            image = await DescriptionGenerator(client).image({'title': 'Beispielort', 'language': 'de'})
            assert image is not None and image['licenseURL'].startswith('https://creativecommons.org/')
    asyncio.run(scenario())


@pytest.mark.parametrize('writer', [None, {'introduction': 'Text', 'sections': ['Nur ein Abschnitt'], 'closing': 'Text'},
    {'introduction': 'Text [99]', 'sections': ['Abschnitt', 'Abschnitt'], 'closing': 'Text'}])
def test_ai_output_and_source_references_validated(monkeypatch, writer):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-key')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    async def scenario():
        async with httpx.AsyncClient(transport=transport(writer=writer)) as client:
            if writer is None:
                report = await DescriptionGenerator(client).generate(request(), lambda _: None)
                assert report['mode'] == 'openai' and 'Vorfreude' in report['html']
            else:
                with pytest.raises(HTTPException) as error:
                    await DescriptionGenerator(client).generate(request(), lambda _: None)
                assert error.value.status_code == 502
    asyncio.run(scenario())


@pytest.mark.parametrize('leg_count', [1, 2, 3])
def test_ai_response_contract_requires_exact_route_leg_count(monkeypatch, leg_count):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-key')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    r = request()
    indices = {1: [0, 4], 2: [0, 2, 4], 3: [0, 1, 2, 4]}[leg_count]
    from bikenavi.models import Waypoint
    r.waypoints = [Waypoint(id=uuid4(), name=f'Beispielziel {i}', coordinate=r.route.coordinates[index])
                   for i, index in enumerate(indices)]
    r.route.waypointIndices = indices
    captured = []
    story = {'introduction': 'Beispiel [1].', 'sections': ['Abschnitt.' for _ in range(leg_count)], 'closing': 'Beispiel.'}
    async def scenario():
        async with httpx.AsyncClient(transport=transport(writer=story, on_writer=captured.append)) as client:
            report = await DescriptionGenerator(client).generate(r, lambda _: None)
            assert report['mode'] == 'openai'
    asyncio.run(scenario())
    schema = captured[0]['text']['format']['schema']['properties']['sections']
    assert schema['minItems'] == schema['maxItems'] == leg_count
    assert len(json.loads(captured[0]['input'])['sections']) == leg_count


def test_foreign_sources_render_short_german_text_and_title_with_stable_highlight_identity(monkeypatch):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-key')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    writer = {'introduction': 'Freue dich auf die Tour.', 'sections': ['Der erste Abschnitt führt zum Zwischenziel.', 'Danach geht es zum Tourziel.'],
              'closing': 'Viel Freude unterwegs.', 'highlights': [{'sourceNumber': 1, 'title': 'Beispielburg', 'text': 'Die mittelalterliche Beispielburg entstand im Jahr 1200.'}]}
    captured = []
    async def scenario():
        async with httpx.AsyncClient(transport=transport(writer=writer, source_language='en', on_writer=captured.append)) as client:
            report = await DescriptionGenerator(client).generate(request(), lambda _: None)
            assert 'Die mittelalterliche Beispielburg' in report['html']
            assert 'The Example Castle' not in report['html'] and 'It was built' not in report['html']
            assert report['highlights'][0]['title'] == 'Beispielburg'
            assert 'en.wikipedia.org/wiki/The_Example_Castle' in report['html']
    asyncio.run(scenario())
    schema = captured[0]['text']['format']['schema']
    assert set(schema['required']) == set(schema['properties'])
    assert schema['properties']['language']['enum'] == ['de']
    assert schema['properties']['highlights']['minItems'] == schema['properties']['highlights']['maxItems'] == 1
    source = json.loads(captured[0]['input'])['sources'][0]
    assert set(source) == {'sourceNumber', 'title', 'text', 'language', 'url'}


def test_template_without_translator_omits_foreign_excerpts(monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    async def scenario():
        async with httpx.AsyncClient(transport=transport(source_language='en')) as client:
            report = await DescriptionGenerator(client).generate(request(), lambda _: None)
            assert report['sourceCount'] == 0 and report['highlights'] == []
            assert 'The Example Castle' not in report['html'] and 'It was built' not in report['html']
    asyncio.run(scenario())


def test_shortened_german_title_retains_place_name_for_waypoint(monkeypatch):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-key')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    writer = {'introduction': 'Kurze Einleitung.', 'sections': ['Abschnitt eins.', 'Abschnitt zwei.'], 'closing': 'Viel Freude.',
              'highlights': [{'sourceNumber': 1, 'title': 'Dorf am Weg', 'text': 'Beispielort ist ein Dorf.'}]}
    async def scenario():
        async with httpx.AsyncClient(transport=transport(writer=writer)) as client:
            report = await DescriptionGenerator(client).generate(request(), lambda _: None)
            assert report['highlights'][0]['title'] == 'Beispielort · Dorf am Weg'
            assert '<h3>Beispielort · Dorf am Weg [1]</h3>' in report['html']
    asyncio.run(scenario())


@pytest.mark.parametrize('change', [
    {'language': 'en'}, {'highlights': []},
    {'introduction': 'Wort ' * 46}, {'sections': ['Wort ' * 91, 'Abschnitt.']}, {'closing': 'Wort ' * 31},
    {'highlights': [{'sourceNumber': 1, 'title': 'Beispielort', 'text': 'Wort ' * 56}]},
    {'highlights': [{'sourceNumber': 1, 'title': 'Beispielort', 'text': 'The village is a settlement in Croatia.'}]},
    {'highlights': [{'sourceNumber': 2, 'title': 'Beispielort', 'text': 'Kurzer deutscher Text.'}]},
    {'highlights': [{'sourceNumber': 1, 'title': 'Beispielort', 'text': 'Der Recherchepunkt liegt 500 Meter Luftlinie neben der Route.'}]},
])
def test_invalid_language_missing_translations_or_excessive_prose_fail_without_report(monkeypatch, change):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-key')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    writer = {'introduction': 'Kurze Einleitung.', 'sections': ['Abschnitt eins.', 'Abschnitt zwei.'], 'closing': 'Viel Freude.', **change}
    async def scenario():
        async with httpx.AsyncClient(transport=transport(writer=writer)) as client:
            with pytest.raises(HTTPException) as error:
                await DescriptionGenerator(client).generate(request(), lambda _: None)
            assert error.value.status_code == 502
    asyncio.run(scenario())


def test_job_idempotency_rejects_modified_snapshot_and_concurrency_and_handles_restart():
    class Generator:
        async def generate(self, r, progress):
            progress('images')
            await asyncio.Event().wait()
    async def scenario():
        jobs = DescriptionJobs(Generator())
        r = request()
        a = jobs.start('one', r)
        assert jobs.start('one', r) == a
        changed = r.model_copy(update={'title': 'Andere Planung'})
        for id, body in [('one', changed), ('two', r)]:
            with pytest.raises(HTTPException) as error: jobs.start(id, body)
            assert error.value.status_code == 409
        await asyncio.sleep(0)
        assert jobs.get('one')['phase'] == 'images'
        await jobs.close()
        assert jobs.get('one')['phase'] == 'failed'
        with pytest.raises(HTTPException) as error: jobs.get('missing')
        assert error.value.status_code == 404
    asyncio.run(scenario())


def test_api_requires_auth_accepts_unsynced_plan_and_never_changes_blog_storage(tmp_path, monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    app = create_app(f'sqlite:///{tmp_path / "api.sqlite"}', token=TOKEN, transport=transport())
    with TestClient(app) as client:
        generation = str(uuid4())
        body = request().model_dump(mode='json')
        path = f'/v1/route-description-jobs?generation_id={generation}'
        assert client.post(path, json=body).status_code == 401
        assert client.get(f'/v1/route-description-jobs/{generation}').status_code == 401
        assert client.post(path, json=body, headers=AUTH).status_code == 202
        for _ in range(50):
            result = client.get(f'/v1/route-description-jobs/{generation}', headers=AUTH).json()
            if result['phase'] == 'completed': break
        assert result['phase'] == 'completed' and result['report']['imageCount'] == 1
        assert client.get('/v1/changes', headers=AUTH).json()['records'] == []
        wrong = deepcopy(body)
        wrong['route']['surfaceSections'][0]['endIndex'] = 999
        assert client.post(path, json=wrong, headers=AUTH).status_code == 422


def test_escaping_untrusted_names_and_text(monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    async def scenario():
        async with httpx.AsyncClient(transport=transport()) as client:
            r = request()
            r.title = '<script>alert(1)</script>'
            report = await DescriptionGenerator(client).generate(r, lambda _: None)
            assert '<script>' not in report['html'] and '&lt;script&gt;' in report['html']
    asyncio.run(scenario())


@pytest.mark.parametrize('license_name', ['CC0', 'CC0 1.0', 'CC BY 4.0', 'Public domain'])
def test_supported_commons_license_names(license_name):
    async def scenario():
        async with httpx.AsyncClient(transport=transport(license_name=license_name)) as client:
            image = await DescriptionGenerator(client).image({'title': 'Beispielort', 'language': 'de'})
            assert image is not None and image['license'] == license_name
    asyncio.run(scenario())
