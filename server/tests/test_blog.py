import base64
import json
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from bikenavi.main import create_app
from bikenavi.blog import project

TOKEN = 'test-blog-token-' + 'a' * 40
AUTH = {'Authorization': 'Bearer ' + TOKEN}


def point(ride_id, **kwargs):
    return {'id': str(uuid4()), 'rideID': ride_id, 'coordinate': {'latitude': 49.41, 'longitude': 8.68},
            'capturedAt': 100, 'title': 'Neckar · Beispieldaten', 'note': 'Eine Pause am Fluss.', **kwargs}


def save_ride(client, state='finished'):
    ride = {'id': str(uuid4()), 'kind': 'ride', 'title': 'Beispieltour Heidelberg', 'createdAt': 1, 'updatedAt': 2,
            'recordingState': state, 'track': [
                {'coordinate': {'latitude': 49.41+i*.001, 'longitude': 8.68+i*.001}, 'timestamp': i+1, 'accuracy': 5, 'speed': 2, 'segment': 0 if i < 2 else 1} for i in range(4)]}
    result = client.post('/v1/mutations', json={'mutationID': str(uuid4()), 'baseRevision': 0, 'document': ride}, headers=AUTH)
    assert result.status_code == 200
    return result.json()


def upstream(request):
    if request.url.host.endswith('wikipedia.org'):
        return httpx.Response(200, json={'query': {'pages': {'1': {'title': 'Neckar', 'extract': 'Der Neckar ist ein Fluss in Deutschland.', 'coordinates': [{'lat': 49.41, 'lon': 8.68}], 'pageprops': {'wikibase_item': 'Q1673'}}}}})
    if request.url.host.endswith('opentopomap.org'):
        # Valid PNG header, renderer only accepts 256x256 PNGs.
        return httpx.Response(200, content=b'\x89PNG\r\n\x1a\n'+b'\x00\x00\x00\rIHDR'+(256).to_bytes(4,'big')*2)
    return httpx.Response(503)


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    monkeypatch.delenv('BLOG_OPENAI_MODEL', raising=False)
    app = create_app(f'sqlite:///{tmp_path}/blog.sqlite', token=TOKEN, transport=httpx.MockTransport(upstream))
    with TestClient(app) as client:
        yield client


def test_auth_and_finished_guard(client):
    ride = save_ride(client, 'recording')['document']['id']
    assert client.post('/v1/blog-points', json=point(ride)).status_code == 401
    assert client.get(f'/v1/rides/{ride}/blog').status_code == 401
    assert client.post(f'/v1/rides/{ride}/blog', headers=AUTH).status_code == 409
    assert client.post('/v1/blog-points', json=point(str(uuid4())), headers=AUTH).status_code == 404


def test_points_are_immutable_retryable_and_paginated(client):
    ride = save_ride(client)['document']['id']
    first = point(ride)
    a = client.post('/v1/blog-points', json=first, headers=AUTH)
    assert a.status_code == 200
    assert client.post('/v1/blog-points', json=first, headers=AUTH).json() == a.json()
    assert client.post('/v1/blog-points', json={**first, 'note': 'anders'}, headers=AUTH).status_code == 409
    for _ in range(5): assert client.post('/v1/blog-points', json=point(ride), headers=AUTH).status_code == 200
    page = client.get(f'/v1/rides/{ride}/blog-points', headers=AUTH).json()
    assert len(page['points']) == 5 and page['hasMore']
    end = client.get(f'/v1/rides/{ride}/blog-points?after={page["cursor"]}', headers=AUTH).json()
    assert len(end['points']) == 1 and not end['hasMore']


@pytest.mark.parametrize('changes', [{'note': ''}, {'photo': '<script>'}, {'photo': base64.b64encode(b'<svg onload=alert(1)>').decode()}, {'coordinate': {'latitude': 91, 'longitude': 1}}])
def test_bad_content_rejected(client, changes):
    ride = save_ride(client)['document']['id']
    assert client.post('/v1/blog-points', json=point(ride, **changes), headers=AUTH).status_code == 422


def test_generation_portable_escape_sources_and_versions(client):
    ride = save_ride(client)['document']['id']
    p = point(ride, title='<script>alert(1)</script>', note='<img src=x onerror=alert(1)>', photo=base64.b64encode(b'\xff\xd8\xfftest\xff\xd9').decode())
    assert client.post('/v1/blog-points', json=p, headers=AUTH).status_code == 200
    response = client.post(f'/v1/rides/{ride}/blog', headers=AUTH)
    assert response.status_code == 200, response.text
    blog = response.json()
    assert blog['mode'] == 'template' and blog['sourceCount'] == 1
    html = blog['html']
    assert '<script>' not in html and '<img src=x' not in html
    assert '&lt;script&gt;' in html and 'data:image/jpeg;base64,' in html and 'data:image/png;base64,' in html
    assert 'https://de.wikipedia.org/wiki/Neckar' in html and 'CC BY-SA 3.0' in html
    assert 'Pausenabschnitte getrennt' in html and html.count('<polyline') == 2
    again = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
    assert again['id'] != blog['id']
    assert client.get(f'/v1/rides/{ride}/blog', headers=AUTH).json()['id'] == again['id']


def test_delete_removes_journal_and_drafts(client):
    saved = save_ride(client); ride = saved['document']['id']
    client.post('/v1/blog-points', json=point(ride), headers=AUTH)
    assert client.post(f'/v1/rides/{ride}/blog', headers=AUTH).status_code == 200
    assert client.post('/v1/mutations', json={'mutationID': str(uuid4()), 'baseRevision': 1, 'deleted': True, 'document': saved['document']}, headers=AUTH).status_code == 200
    assert client.get(f'/v1/rides/{ride}/blog', headers=AUTH).status_code == 404
    from bikenavi.blog_store import JournalPoint, BlogDraft
    from sqlalchemy import select
    with client.app.state.storage.sessions() as session:
        assert session.scalars(select(JournalPoint)).all() == []
        assert session.scalars(select(BlogDraft)).all() == []


def test_research_failure_is_explicit_and_no_fake_facts(tmp_path, monkeypatch):
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    app = create_app(f'sqlite:///{tmp_path}/down.sqlite', token=TOKEN, transport=httpx.MockTransport(lambda r: httpx.Response(503)))
    with TestClient(app) as client:
        ride = save_ride(client)['document']['id']
        result = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
        assert result['sourceCount'] == 0
        assert any('Keine Ortsquellen' in w for w in result['warnings'])
        assert 'Streckenübersicht' in result['html']


def test_topographic_projection_poles_are_finite():
    import math
    assert all(math.isfinite(v) for v in project({'latitude': 90, 'longitude': 180}, 13))


def test_changed_ride_cannot_persist_stale_blog(client):
    saved = save_ride(client); ride = saved['document']['id']
    repo = client.app.state.blogs
    _, points, revision = repo.snapshot(ride)
    client.post('/v1/blog-points', json=point(ride), headers=AUTH)
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as error:
        repo.save(ride, revision, [], str(uuid4()), 'old', {'createdAt': 1})
    assert error.value.status_code == 409


def test_ai_image_hints_research_and_story_keep_photos_in_analysis_only(tmp_path, monkeypatch):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    requests = []
    def ai_upstream(request):
        if request.url.host != 'api.openai.com': return upstream(request)
        body = json.loads(request.content); requests.append(body)
        assert body['store'] is False
        if isinstance(body['input'], list):
            content = body['input'][0]['content']
            location = json.loads(content[0]['text'])
            assert content[1]['type'] == 'input_image' and content[1]['image_url'].startswith('data:image/jpeg;base64,')
            assert location['coordinate'] == {'latitude': 49.41, 'longitude': 8.68}
            hints = {'locations': [{'locationID': location['locationID'], 'searchTopics': ['Neckar: Flussgeschichte'], 'localLanguageCodes': ['de'], 'uncertainty': ''}]}
            return ai_text(hints)
        assert 'data:image/' not in body['input'] and 'photo' not in body['input']
        if 'tools' in body:
            text = 'Heidelberg liegt am Neckar. Belegte Landschaft. [Quelle]'
            start = text.index('[Quelle]')
            return httpx.Response(200, json={'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': text, 'annotations': [{'type': 'url_citation', 'title': 'Stadt Heidelberg', 'url': 'https://www.heidelberg.de/', 'start_index': start, 'end_index': len(text)}]}]}]})
        story = {'title': 'Mit Neugier am Neckar', 'introduction': 'Ein Weg am Fluss [2].', 'stops': ['Kleine Pause, weiter Blick [1].'], 'closing': 'Die nächste Folge wartet!', 'backgrounds': [{'heading':'Brücken mit Gedächtnis','text':'Ein Hintergrund zum Neckar [2].\n\nNoch ein belegtes Detail [1].'}]}
        return httpx.Response(200, json={'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps(story)}]}]})
    app = create_app(f'sqlite:///{tmp_path}/ai.sqlite', token=TOKEN, transport=httpx.MockTransport(ai_upstream))
    with TestClient(app) as client:
        ride = save_ride(client)['document']['id']
        client.post('/v1/blog-points', json=point(ride, photo=base64.b64encode(b'\xff\xd8\xfftest\xff\xd9').decode()), headers=AUTH)
        result = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
        assert result['mode'] == 'openai' and result['sourceCount'] == 2
        assert 'href="#source-2"' in result['html'] and 'https://www.heidelberg.de/' in result['html']
        assert len(requests) == 3
        assert requests[1]['max_tool_calls'] == 3
        assert requests[2]['text']['format']['strict'] is True
        context=json.loads(requests[2]['input'])
        assert [f['sourceNumber'] for f in context['nearbySources']]==[1,2]
        assert context['stops'][0]['researchHints']['searchTopics'] == ['Neckar: Flussgeschichte']


def ai_text(value):
    return httpx.Response(200, json={'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps(value)}]}]})


@pytest.mark.parametrize('partial', [False, True])
def test_web_dossier_keeps_multiple_cited_details_and_bounded_partial_output(monkeypatch, partial):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    monkeypatch.setenv('BLOG_WEB_SEARCH', 'true')
    paragraphs = ['Der See entstand in einer Karstsenke. [A]', 'Die Ufer bieten Lebensraum für Zugvögel. [B]', 'Unbelegtes abgeschnittenes Ende']
    text = '\n\n'.join(paragraphs)
    annotations = [{'type': 'url_citation', 'title': 'Lokaler Naturpark', 'url': 'https://example.org/lake', 'start_index': text.index(marker), 'end_index': text.index(marker)+3} for marker in ('[A]', '[B]')]
    # Invalid/truncated citation and unsafe URLs never become usable sources.
    annotations += [{'type': 'url_citation', 'url': 'https://example.org/incomplete', 'start_index': len(text)-2, 'end_index': len(text)+10},
                    {'type': 'url_citation', 'url': 'javascript:bad()', 'start_index': 0, 'end_index': 2}]
    if partial:
        annotations += [{'type': 'url_citation', 'url': 'https://example.org/lake', 'start_index': len(text)-4, 'end_index': len(text)-1}]
    def upstream(request):
        assert json.loads(request.content)['max_output_tokens'] == 6000
        return httpx.Response(200, json={'status': 'incomplete' if partial else 'completed', 'incomplete_details': {'reason': 'max_output_tokens'} if partial else None,
            'output': [{'content': [{'type': 'output_text', 'text': text, 'annotations': annotations}]}]})
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as client:
            warnings = []
            sources = await BlogGenerator(client, None).web_research({'title': 'Öffentliches Beispiel', 'track': []}, [], [], warnings)
            assert len(sources) == 1
            assert 'Karstsenke' in sources[0]['text'] and 'Zugvögel' in sources[0]['text']
            assert 'abgeschnittenes Ende' not in sources[0]['text']
            assert bool(warnings) is partial
    asyncio.run(run())


def test_lake_image_and_coordinates_drive_local_language_sources(tmp_path, monkeypatch):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    requests, wikipedia_languages = [], []
    lake = {'latitude': 43.89, 'longitude': 15.57}  # Public Croatian example, not a recorded visit.
    lake_source = 'https://www.pp-vransko-jezero.hr/'
    def lake_upstream(request):
        if request.url.host.endswith('wikipedia.org'):
            lang = request.url.host.split('.')[0]; wikipedia_languages.append(lang)
            if lang not in ('hr', 'de'): return httpx.Response(200, json={})
            return httpx.Response(200, json={'query': {'pages': {'1': {
                'title': 'Vransko jezero' if lang == 'hr' else 'Vrana-See',
                'extract': 'Jezero je stanište ptica.', 'coordinates': [{'lat': lake['latitude'], 'lon': lake['longitude']}],
                'pageprops': {'wikibase_item': 'Q-test-lake'}}}}})
        if request.url.host != 'api.openai.com': return upstream(request)
        body = json.loads(request.content); requests.append(body)
        if isinstance(body['input'], list):
            content = body['input'][0]['content']
            inputs = [json.loads(c['text']) for c in content if c['type'] == 'input_text']
            assert [c['type'] for c in content] == ['input_text', 'input_image', 'input_text']
            assert inputs[0]['coordinate'] == lake
            return ai_text({'locations': [
                {'locationID': p['locationID'], 'searchTopics': ['Vransko jezero: Entstehung und Vogelschutz'],
                 'localLanguageCodes': ['hr'], 'uncertainty': 'Gewässername anhand des Standorts und lokaler Quellen prüfen.'} for p in inputs]})
        context = json.loads(body['input'])
        assert 'data:image/' not in body['input']
        if 'tools' in body:
            assert len(context['locations']) == 2
            assert context['locations'][0]['coordinate'] == lake
            assert context['locations'][0]['researchHints']['localLanguageCodes'] == ['hr']
            assert 'Vransko jezero' in context['locations'][0]['researchHints']['searchTopics'][0]
            text = 'Vransko jezero: Der Naturpark schützt Lebensräume für Vögel. [Quelle]'
            return httpx.Response(200, json={'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': text, 'annotations': [
                {'type': 'url_citation', 'title': 'Park prirode Vransko jezero', 'url': lake_source, 'start_index': text.index('[Quelle]'), 'end_index': len(text)}]}]}]})
        assert [p['researchHints']['locationID'] for p in context['stops']] == [p['locationID'] for p in context['stops']]
        assert context['stops'][0]['coordinate'] == lake
        assert context['nearbySources'][0]['language'] == 'hr'
        assert context['nearbySources'][0]['coordinate'] == lake and context['nearbySources'][0]['searchCoordinate'] == lake
        return ai_text({'title': 'Ein See als Rastplatz für Zugvögel', 'introduction': 'Eine Etappe am Naturpark.',
                        'stops': ['Der Naturpark schützt Lebensräume für Vögel [2].', 'Der Vogelschutz verbindet Wasser und Ufer [2].'],
                        'closing': 'Bis zur nächsten Etappe.', 'backgrounds': [{'heading': 'Ein Rastplatz auf langen Reisen', 'text': 'Der Vogelschutz prägt den Naturpark [2].'}]})
    app = create_app(f'sqlite:///{tmp_path}/lake.sqlite', token=TOKEN, transport=httpx.MockTransport(lake_upstream))
    with TestClient(app) as client:
        saved = save_ride(client)
        ride = saved['document']; ride['track'] = []
        client.post('/v1/mutations', json={'mutationID': str(uuid4()), 'baseRevision': 1, 'document': ride}, headers=AUTH)
        photo = base64.b64encode(b'\xff\xd8\xffsynthetic-test\xff\xd9').decode()
        for p in [point(ride['id'], title='Öffentliches kroatisches Beispiel', coordinate=lake, photo=photo, sortOrder=0),
                  point(ride['id'], title='Notiz ohne Foto', coordinate=lake, sortOrder=1)]:
            assert client.post('/v1/blog-points', json=p, headers=AUTH).status_code == 200
        result = client.post(f'/v1/rides/{ride["id"]}/blog', headers=AUTH).json()
        assert result['mode'] == 'openai' and result['sourceCount'] == 2
        assert result['generationDetails'] == {'analysedLocations': 2, 'analysedPhotos': 1, 'sourceLanguages': ['hr']}
        assert wikipedia_languages == ['hr', 'de', 'en']  # German articles did not suppress Croatian research.
        assert lake_source in result['html'] and 'href="#source-2"' in result['html']
        assert 'researchHints' not in result['html'] and 'searchTopics' not in result
        assert len(requests) == 3


@pytest.mark.parametrize('failure', ['unavailable', 'incomplete', 'missing', 'wrong_id', 'duplicate', 'bad_language', 'long_topic'])
def test_invalid_image_analysis_is_discarded_without_losing_blog(tmp_path, monkeypatch, failure):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    monkeypatch.setenv('BLOG_WEB_SEARCH', 'false')
    def failing_analysis(request):
        if request.url.host != 'api.openai.com': return upstream(request)
        body = json.loads(request.content)
        if isinstance(body['input'], list):
            if failure == 'unavailable': return httpx.Response(503)
            if failure == 'incomplete': return httpx.Response(200, json={'status': 'incomplete', 'output': []})
            location = json.loads(body['input'][0]['content'][0]['text'])
            hint = {'locationID': location['locationID'], 'searchTopics': ['Unbestätigter See'], 'localLanguageCodes': ['hr'], 'uncertainty': ''}
            if failure == 'wrong_id': hint['locationID'] = str(uuid4())
            if failure == 'bad_language': hint['localLanguageCodes'] = ['hr.example.org/path']
            if failure == 'long_topic': hint['searchTopics'] = ['x' * 201]
            return ai_text({'locations': [] if failure == 'missing' else [hint, hint] if failure == 'duplicate' else [hint]})
        context = json.loads(body['input'])
        assert context['stops'][0]['researchHints'] is None
        assert 'Unbestätigter See' not in body['input'] and 'data:image/' not in body['input']
        return ai_text({'title': 'Am Neckar', 'introduction': 'Flussgeschichte [1].', 'stops': ['Hintergrund [1].'], 'closing': 'Weiter geht es.',
                        'backgrounds': [{'heading': 'Flussgeschichte', 'text': 'Der Neckar liegt in Deutschland [1].'}]})
    app = create_app(f'sqlite:///{tmp_path}/image-failure.sqlite', token=TOKEN, transport=httpx.MockTransport(failing_analysis))
    with TestClient(app) as client:
        ride = save_ride(client)['document']['id']
        client.post('/v1/blog-points', json=point(ride, photo=base64.b64encode(b'\xff\xd8\xfftest\xff\xd9').decode()), headers=AUTH)
        result = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
        assert result['mode'] == 'openai' and 'data:image/jpeg;base64,' in result['html']
        assert result['generationDetails']['analysedPhotos'] == 0
        assert any('Fotos wurden nicht ausgewertet' in w for w in result['warnings'])


def test_analysis_keeps_all_fifty_stations_and_photo_associations(monkeypatch):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    points = [point('unused', title=f'Synthetische Station {i}', photo=base64.b64encode(b'\xff\xd8\xff'+bytes([i])+b'\xff\xd9').decode()) for i in range(50)]
    def analysis(request):
        body = json.loads(request.content)
        content = body['input'][0]['content']
        assert len(content) == 100 and body['store'] is False
        results = []
        for i, p in enumerate(points):
            location = json.loads(content[i*2]['text'])
            assert location['locationID'] == p['id']
            assert content[i*2+1]['image_url'] == 'data:image/jpeg;base64,' + p['photo']
            results.append({'locationID': p['id'], 'searchTopics': [p['title']], 'localLanguageCodes': ['de'], 'uncertainty': ''})
        return ai_text({'locations': results})
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(analysis)) as client:
            warnings = []
            hints = await BlogGenerator(client, None).location_hints({'track': []}, points, warnings)
            assert list(hints) == [p['id'] for p in points] and not warnings
            assert all(hints[p['id']]['searchTopics'] == [p['title']] for p in points)
    asyncio.run(run())


def test_no_photo_route_uses_planned_coordinates_for_local_language_hints(monkeypatch):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    coordinates = [{'latitude': 59.32+i*.01, 'longitude': 18.06} for i in range(10)]
    def analysis(request):
        content = json.loads(request.content)['input'][0]['content']
        assert len(content) == 4 and all(p['type'] == 'input_text' for p in content)
        locations = [json.loads(p['text']) for p in content]
        assert locations[0]['coordinate'] == coordinates[0] and locations[-1]['coordinate'] == coordinates[-1]
        return ai_text({'locations': [{'locationID': p['locationID'], 'searchTopics': [], 'localLanguageCodes': ['sv'], 'uncertainty': ''} for p in locations]})
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(analysis)) as client:
            hints = await BlogGenerator(client, None).location_hints({'track': [], 'route': {'coordinates': coordinates}}, [], [])
            assert len(hints) == 4 and all(h['localLanguageCodes'] == ['sv'] for h in hints.values())
    asyncio.run(run())


def test_cancelled_later_language_keeps_already_found_local_sources():
    import asyncio
    from bikenavi.blog import BlogGenerator
    async def run():
        later_language_started = asyncio.Event()
        async def source(request):
            if request.url.host == 'hr.wikipedia.org': return upstream(request)
            later_language_started.set()
            await asyncio.Event().wait()
        async with httpx.AsyncClient(transport=httpx.MockTransport(source)) as client:
            found = {}
            task = asyncio.create_task(BlogGenerator(client, None).research({'latitude': 49.41, 'longitude': 8.68}, ['hr'], found=found))
            await asyncio.wait_for(later_language_started.wait(), timeout=1)
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
            assert len(found) == 1 and next(iter(found.values()))['language'] == 'hr'
    asyncio.run(run())


def test_wikipedia_and_web_research_overlap_before_writing():
    import asyncio
    from bikenavi.blog import BlogGenerator, Story
    async def run():
        wikipedia_started, web_started = asyncio.Event(), asyncio.Event()
        class Repository:
            def snapshot(self, ride_id): return {'title': 'Öffentliches Beispiel', 'track': [], 'createdAt': 1}, [], 1
            def research_sources(self, ride_id): return []
            def save(self, ride_id, revision, versions, draft_id, html, metadata): return metadata
        class Generator(BlogGenerator):
            async def location_hints(self, *args): return {}
            async def terrain_map(self, *args): return None
            async def nearby_sources(self, *args):
                wikipedia_started.set()
                await web_started.wait()
                return [{'title': 'Wiki', 'url': 'https://example.org/wiki', 'text': 'Lokaler Hintergrund', 'language': 'hr', 'distance': 100}]
            async def web_research(self, *args):
                web_started.set()
                await wikipedia_started.wait()
                return [{'title': 'Park', 'url': 'https://example.org/park', 'text': 'Naturgeschichte', 'language': 'web', 'distance': None}]
            async def story(self, ride, points, facts, warnings, hints):
                assert len(facts) == 2
                return Story(title='Titel', introduction='Einleitung', stops=[], closing='Schluss'), 'openai'
        # Serial network phases would deadlock and exhaust the app's time budget.
        metadata = await asyncio.wait_for(Generator(None, Repository()).generate('example'), timeout=1)
        assert metadata['sourceCount'] == 2
    asyncio.run(run())


@pytest.mark.parametrize('failure', ['http', 'incomplete', 'invalid', 'timeout'])
def test_ai_failure_does_not_replace_existing_blog(tmp_path, monkeypatch, failure):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    def failed(request):
        if request.url.host != 'api.openai.com': return upstream(request)
        body = json.loads(request.content)
        if isinstance(body['input'], list) or 'tools' in body or failure == 'http': return httpx.Response(503)
        if failure == 'incomplete': return httpx.Response(200, json={'status': 'incomplete', 'incomplete_details': {'reason': 'max_output_tokens'}})
        if failure == 'timeout': raise httpx.ReadTimeout('provider-specific private message', request=request)
        return ai_text({'incorrect': 'schema'})
    app = create_app(f'sqlite:///{tmp_path}/bad-ai.sqlite', token=TOKEN, transport=httpx.MockTransport(failed))
    with TestClient(app) as client:
        ride = save_ride(client)['document']['id']
        client.post('/v1/blog-points', json=point(ride), headers=AUTH)
        from bikenavi.blog_store import BlogDraft
        previous_id = str(uuid4())
        with client.app.state.storage.sessions.begin() as session:
            session.add(BlogDraft(id=previous_id, ride_id=ride, html='<html>Vorhandener guter Blog</html>', metadata_json={'mode': 'openai', 'createdAt': 1, 'sourceCount': 0}))
        result = client.post(f'/v1/rides/{ride}/blog', headers=AUTH)
        assert result.status_code == 502
        reason = {'http': 'HTTP 503', 'incomplete': 'Ausgabelimit erreicht', 'invalid': 'Textformat', 'timeout': 'Zeitlimit erreicht'}[failure]
        assert reason in result.json()['detail'] and 'keine neue Blogfassung' in result.json()['detail']
        assert 'private message' not in result.text
        current = client.get(f'/v1/rides/{ride}/blog', headers=AUTH).json()
        assert current['id'] == previous_id and current['html'] == '<html>Vorhandener guter Blog</html>'


def test_unsafe_web_citations_are_rejected():
    from bikenavi.blog import safe_source, prose
    assert not safe_source('javascript:alert(1)')
    assert not safe_source('https://user:pass@example.com/')
    assert prose('<script>[1]</script>', [{'url': 'https://example.org/'}]) == '&lt;script&gt;<a href="#source-1" aria-label="Quelle 1">[1]</a>&lt;/script&gt;'



def test_topographic_overview_projects_stops_and_limits_requests(client):
    import asyncio
    from bikenavi.blog import route_map, project
    ride=save_ride(client)['document']; p=point(ride['id'])
    terrain=asyncio.run(client.app.state.blog_generator.terrain_map(ride,[p]))
    assert terrain is not None and len(terrain['tiles'])<=12
    for c in [t['coordinate'] for t in ride['track']]+[p['coordinate']]:
        x,y=project(c,terrain['zoom'])
        assert 29<=x-terrain['originX']<=691 and 29<=y-terrain['originY']<=391
    html=route_map(ride,[p],terrain)
    assert 'Topografische Streckenübersicht' in html and 'data:image/png;base64,' in html
    assert 'schematische' not in html and html.count('<polyline')==2


def test_elevation_has_numeric_metres_and_kilometres_axes():
    from bikenavi.blog import elevation
    html=elevation({'route':{'elevationProfile':[{'distance':0,'altitude':114},{'distance':2500,'altitude':363},{'distance':5200,'altitude':220}], 'elevationSource':'Beispieldaten'}})
    assert 'Höhe (m)' in html and 'Strecke (km)' in html
    assert '>100</text>' in html and '>400</text>' in html and '>0</text>' in html and '>5,2</text>' in html
    assert 'Geplantes Höhenprofil' in html
    flat=elevation({'route':{'elevationProfile':[{'distance':0,'altitude':-5},{'distance':1000,'altitude':-5}]}})
    assert 'nan' not in flat and 'inf' not in flat and '<polyline' in flat


def test_background_chapters_render_without_photo_stops_and_preserve_paragraphs():
    from bikenavi.blog import render, Story, BackgroundChapter
    ride={'title':'Öffentliches Beispiel','createdAt':1,'track':[],'route':None}
    story=Story(title='Mehr als Kilometer',introduction='Ein Einstieg.',stops=[],closing='Ein Ausblick.',backgrounds=[BackgroundChapter(heading='Ein Ort mit Geschichte',text='Ein konkreter Hintergrund [1].\n\nEin Vergleich mit Augenzwinkern <script>.')])
    html=render(ride,[],[{'title':'Beispielquelle','url':'https://example.org/','text':'Belegte Information.','language':'web','distance':None}],{},story,{'warnings':[],'mode':'openai','createdAt':1})
    assert '<h2>Ein Ort mit Geschichte</h2>' in html and 'href="#source-1"' in html and '<script>' not in html
    assert '</p><p>Ein Vergleich' in html
    assert html.index('Ein Ort mit Geschichte')<html.index('Geschichten am Wegesrand')


def test_source_rich_previous_draft_is_reused_during_search_failure(client):
    from bikenavi.blog_store import BlogDraft
    ride=save_ride(client)['document']['id']
    rich=[dict(title='Quelle '+str(i),url='https://example.org/'+str(i),text='Belegtes regionales Detail '+str(i),language='web',distance=None) for i in range(3)]
    with client.app.state.storage.sessions.begin() as session:
        session.add(BlogDraft(id=str(uuid4()),ride_id=ride,html='<html>old</html>',metadata_json={'createdAt':1,'sourceCount':3,'researchSources':rich}))
        session.add(BlogDraft(id=str(uuid4()),ride_id=ride,html='<html>new but sparse</html>',metadata_json={'createdAt':2,'sourceCount':0}))
    assert client.app.state.blogs.research_sources(ride)==rich
    draft=client.post(f'/v1/rides/{ride}/blog',headers=AUTH).json()
    assert draft['sourceCount']>=3 and any('früheren Blogfassung' in w for w in draft['warnings'])
    assert any(f['url']=='https://example.org/0' for f in draft['researchSources'])


def test_legacy_source_appendix_recovery_excludes_personal_notes():
    from bikenavi.blog_store import ArchivedSources
    parser=ArchivedSources()
    parser.feed('<p>Private Notiz</p><li id="source-1"><a href="https://example.org/">[1] Quelle</a><p>Belegter Hintergrund.</p><small>Kontext</small></li><li id="source-2"><a href="javascript:alert(1)">Bad</a><p>Untrusted</p></li>')
    assert len(parser.sources)==1 and parser.sources[0]['title']=='Quelle'
    assert parser.sources[0]['text']=='Belegter Hintergrund.' and '_context' not in parser.sources[0]



def test_existing_route_heights_make_profile_without_optional_samples():
    from bikenavi.blog import elevation
    route={'coordinates':[{'latitude':49.41,'longitude':8.68,'altitude':120},{'latitude':49.42,'longitude':8.69,'altitude':180}], 'distance':2000,'provider':'Beispieldaten'}
    html=elevation({'route':route})
    assert 'Höhen aus Routenpunkten' in html and 'Strecke (km)' in html and '>2</text>' in html
    assert '<polyline' in html and 'Geplantes Höhenprofil' in html
    route['coordinates'][1]['altitude']=None
    assert elevation({'route':route})==''


def test_edit_retry_cursor_order_and_stale_conflict(client):
    ride = save_ride(client)['document']['id']
    first, second = point(ride, sortOrder=0), point(ride, sortOrder=1)
    for p in (first, second):
        assert client.put(f'/v1/blog-points/{p["id"]}', json=p, headers=AUTH).status_code == 200
    cursor = client.get(f'/v1/rides/{ride}/blog-points', headers=AUTH).json()['cursor']
    edited = {**second, 'title': 'Korrigierter Ort', 'note': 'Korrigierte Notiz', 'sortOrder': -1, 'revision': 0}
    url = f'/v1/blog-points/{second["id"]}'
    response = client.put(url, json=edited, headers=AUTH)
    assert response.status_code == 200 and response.json()['revision'] == 1
    assert client.put(url, json=edited, headers=AUTH).json() == response.json()
    page = client.get(f'/v1/rides/{ride}/blog-points?after={cursor}', headers=AUTH).json()
    assert len(page['points']) == 1 and page['points'][0]['title'] == 'Korrigierter Ort'
    assert page['cursor'] > cursor
    assert client.put(url, json={**edited, 'note': 'Veraltete Änderung'}, headers=AUTH).status_code == 409
    _, points, _ = client.app.state.blogs.snapshot(ride)
    assert [p['id'] for p in points] == [second['id'], first['id']]
    draft = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
    assert draft['html'].index('Korrigierter Ort') < draft['html'].index('Neckar · Beispieldaten')


def test_edit_during_generation_rejects_stale_draft(client):
    from fastapi import HTTPException
    ride = save_ride(client)['document']['id']
    p = point(ride)
    client.post('/v1/blog-points', json=p, headers=AUTH)
    repo = client.app.state.blogs
    _, points, revision = repo.snapshot(ride)
    client.put(f'/v1/blog-points/{p["id"]}', json={**p, 'note': 'Nachträglich geändert'}, headers=AUTH)
    with pytest.raises(HTTPException) as error:
        repo.save(ride, revision, [(p['id'], p.get('revision', 0)) for p in points], str(uuid4()), 'old', {'createdAt': 1})
    assert error.value.status_code == 409


def test_edit_guards_and_photo_removal(client):
    ride = save_ride(client)['document']['id']
    p = point(ride, photo=base64.b64encode(b'\xff\xd8\xfftest\xff\xd9').decode())
    url = f'/v1/blog-points/{p["id"]}'
    assert client.put(url, json=p).status_code == 401
    assert client.put(url, json={**p, 'id': str(uuid4())}, headers=AUTH).status_code == 422
    assert client.put(url, json={**p, 'rideID': str(uuid4())}, headers=AUTH).status_code == 404
    assert client.put(url, json=p, headers=AUTH).status_code == 200
    other_ride = save_ride(client)['document']['id']
    assert client.put(url, json={**p, 'rideID': other_ride}, headers=AUTH).status_code == 409
    assert client.put(url, json={**p, 'photo': None, 'note': ''}, headers=AUTH).status_code == 422
    removed = client.put(url, json={**p, 'photo': None}, headers=AUTH)
    assert removed.status_code == 200 and 'photo' not in removed.json()


def test_legacy_payload_edit_and_cursor_after_last_deleted_point(client):
    from sqlalchemy import delete, select
    from bikenavi.blog_store import JournalPoint
    ride = save_ride(client)['document']['id']
    p = point(ride)
    client.post('/v1/blog-points', json=p, headers=AUTH)
    with client.app.state.blogs.sessions.begin() as session:
        entry = session.scalar(select(JournalPoint).where(JournalPoint.id == p['id']))
        entry.payload = p  # Existing 0.4.0 data without the new additive fields.
        entry.sequence = 100000  # A legacy DB may have a sequence above the lock generation.
    result = client.put(f'/v1/blog-points/{p["id"]}', json={**p, 'note': 'Neue Notiz'}, headers=AUTH)
    assert result.status_code == 200 and result.json()['revision'] == 1
    cursor = client.get(f'/v1/rides/{ride}/blog-points', headers=AUTH).json()['cursor']
    with client.app.state.blogs.sessions.begin() as session:
        session.execute(delete(JournalPoint).where(JournalPoint.id == p['id']))
    new = point(ride)
    assert client.post('/v1/blog-points', json=new, headers=AUTH).status_code == 200
    page = client.get(f'/v1/rides/{ride}/blog-points?after={cursor}', headers=AUTH).json()
    assert page['points'][0]['id'] == new['id'] and page['cursor'] > cursor


def test_edit_at_point_limit_does_not_count_the_same_station_twice(client):
    ride = save_ride(client)['document']['id']
    points = [point(ride) for _ in range(50)]
    for p in points:
        assert client.post('/v1/blog-points', json=p, headers=AUTH).status_code == 200
    extra = point(ride)
    assert client.put(f'/v1/blog-points/{extra["id"]}', json=extra, headers=AUTH).status_code == 413
    p = points[0]
    assert client.put(f'/v1/blog-points/{p["id"]}', json={**p, 'note': 'Auch bei 50 Stationen korrigierbar'}, headers=AUTH).status_code == 200


def test_progress_job_api_auth_resume_and_exact_draft(client):
    import time
    ride = save_ride(client)['document']['id']
    generation = str(uuid4())
    path = f'/v1/rides/{ride}/blog-jobs'
    assert client.post(path, params={'generation_id': generation}).status_code == 401
    assert client.get(path).status_code == 401
    assert client.get(path, headers=AUTH).json() is None
    started = client.post(path, params={'generation_id': generation}, headers=AUTH)
    assert started.status_code == 202
    for _ in range(100):
        response = client.get(path + '/' + generation, headers=AUTH)
        assert response.status_code == 200
        status = response.json()
        if status['phase'] in ('completed', 'failed'):
            break
        time.sleep(.01)
    assert status['phase'] == 'completed', status
    assert client.get(path, headers=AUTH).json()['generationID'] == generation
    retried = client.post(path, params={'generation_id': generation}, headers=AUTH)
    assert retried.status_code == 202 and retried.json()['draftID'] == status['draftID']
    # A newer draft must not replace the exact result followed by the phone.
    newer = client.post(f'/v1/rides/{ride}/blog', headers=AUTH)
    assert newer.status_code == 200
    exact = client.get(f'/v1/rides/{ride}/blog', params={'draft_id': status['draftID']}, headers=AUTH)
    assert exact.status_code == 200 and exact.json()['id'] == status['draftID']
    assert exact.json()['id'] != newer.json()['id']
    assert client.get(path + '/' + str(uuid4()), headers=AUTH).status_code == 404
    other = save_ride(client)['document']['id']
    assert client.get(f'/v1/rides/{other}/blog-jobs/{generation}', headers=AUTH).status_code == 404
    assert client.get(f'/v1/rides/{other}/blog', params={'draft_id': status['draftID']}, headers=AUTH).status_code == 404


def test_duplicate_markdown_headings_are_removed_without_losing_body_or_safety():
    from bikenavi.blog import story_paragraphs
    facts = [{'url': 'https://example.org/'}]
    html = story_paragraphs('## Wiederholter Titel\n\n### Noch ein Titel\n\nEin belegter Satz [1].\n\n<script>Persönlicher Text</script>', facts)
    assert 'Wiederholter Titel' not in html and 'Noch ein Titel' not in html and '##' not in html
    assert '<p>Ein belegter Satz <a href="#source-1"' in html
    assert '&lt;script&gt;Persönlicher Text&lt;/script&gt;' in html
    assert html.count('<p>') == 2
    assert 'Ein Titel # im Satz.' in story_paragraphs('Ein Titel # im Satz.', [])


def test_corrected_blog_headings_preserve_original_journal_notes():
    from bikenavi.blog import render, Story
    ride = {'title': 'Beispieltour', 'track': [], 'createdAt': 1}
    p = point('unused', title='Der Staat am Haus', note='Originalnotiz bleibt erhalten.')
    story = Story(title='Eine klare Strecke', introduction='Einstieg.', stopTitles=['Start am Haus'],
                  stops=['## Start am Haus\n\nEin kurzer Übergang.'], closing='Ein klarer Schluss.')
    html = render(ride, [p], [], {}, story, {'warnings': [], 'mode': 'openai', 'createdAt': 1})
    assert '<h2>Start am Haus</h2>' in html and '<p>Ein kurzer Übergang.</p>' in html
    assert 'Originalnotiz bleibt erhalten.' in html and '##' not in html
    assert p['title'] == 'Der Staat am Haus'
    story.stopTitles = []  # Older structured stories remain valid.
    assert '<h2>Der Staat am Haus</h2>' in render(ride, [p], [], {}, story, {'warnings': [], 'mode': 'openai', 'createdAt': 1})


def test_editorial_prompt_and_heading_schema_are_sent_to_writer(monkeypatch):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    async def scenario():
        generator = BlogGenerator(None, None)
        async def fake_response(key, timeout, body):
            instructions = body['instructions']
            assert 'auch zwischen Stationen und Hintergrundkapiteln' in instructions
            assert '20–50 Wörter' in instructions and 'höchstens drei bis vier' in instructions
            assert 'stopTitles' in body['text']['format']['schema']['required']
            return {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps({
                'title': 'Klarer Titel', 'introduction': 'Einstieg.', 'stops': ['Ein Übergang.'],
                'stopTitles': ['Start am Haus'], 'closing': 'Schluss.', 'backgrounds': []})}]}]}
        generator.ai_response = fake_response
        story, mode = await generator.story({'title': 'Tour', 'track': []}, [point('unused')], [], [])
        assert mode == 'openai' and story.stopTitles == ['Start am Haus']
    asyncio.run(scenario())


@pytest.mark.parametrize('headings', [[], [''], ['A', 'B'], ['x' * 201]])
def test_invalid_model_headings_do_not_become_a_new_blog(monkeypatch, headings):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    async def scenario():
        generator = BlogGenerator(None, None)
        async def fake_response(*args):
            return {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps({
                'title': 'Titel', 'introduction': 'Einstieg.', 'stops': ['Text.'], 'stopTitles': headings,
                'closing': 'Schluss.', 'backgrounds': []})}]}]}
        generator.ai_response = fake_response
        warnings = []
        _, mode = await generator.story({'title': 'Tour', 'track': []}, [point('unused')], [], warnings)
        assert mode == 'template' and warnings
    asyncio.run(scenario())


def test_editorial_pass_removes_repeated_uncertainty_within_original_budget(monkeypatch):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    async def scenario():
        generator = BlogGenerator(None, None)
        calls = []
        async def fake_response(key, timeout, body):
            calls.append((timeout, body))
            stop = 'Nicht sicher benennbar. Die Lage bleibt offen.' if len(calls) == 1 else 'Danach geht es auf dem steinigen Weg weiter.'
            result = {'title': 'Eine Etappe', 'introduction': 'Einstieg.', 'stops': [stop], 'stopTitles': ['Unterwegs'], 'closing': 'Schluss.', 'backgrounds': []}
            return {'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': json.dumps(result)}]}]}
        generator.ai_response = fake_response
        story, mode = await generator.story({'title': 'Tour', 'track': []}, [point('unused')], [], [])
        assert mode == 'openai' and 'steinigen Weg' in story.stops[0]
        assert len(calls) == 2 and calls[0][0] == 45 and 0 < calls[1][0] <= 25
        context = json.loads(calls[1][1]['input'])
        assert context['originalContext']['stops'][0]['note'] == 'Eine Pause am Fluss.'
        assert 'niemals nur ihre einschränkenden Wörter entfernen' in calls[1][1]['instructions']
    asyncio.run(scenario())


@pytest.mark.parametrize('failure', ['unchanged', 'timeout'])
def test_failed_required_editorial_pass_is_not_saved_as_openai(monkeypatch, failure):
    import asyncio
    from bikenavi.blog import BlogGenerator
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    async def scenario():
        generator = BlogGenerator(None, None)
        calls = 0
        async def fake_response(*args):
            nonlocal calls
            calls += 1
            if calls == 2 and failure == 'timeout': raise asyncio.TimeoutError()
            story = {'title': 'Etappe', 'introduction': 'Nicht sicher benennbar.', 'stops': ['Die Zuordnung bleibt offen.'], 'stopTitles': ['Ort'], 'closing': 'Schluss.', 'backgrounds': []}
            return {'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': json.dumps(story)}]}]}
        generator.ai_response = fake_response
        warnings = []
        _, mode = await generator.story({'title': 'Tour', 'track': []}, [point('unused')], [], warnings)
        assert calls == 2 and mode == 'template' and warnings
    asyncio.run(scenario())


def test_writer_receives_verification_flag_without_uncertainty_prose():
    from bikenavi.blog import writing_hint
    hint = {'locationID': 'example', 'searchTopics': ['Regionalgeschichte'], 'localLanguageCodes': ['hr'],
            'uncertainty': 'Die genaue Zuordnung ist nicht sicher.'}
    written = writing_hint(hint)
    assert written['identificationUnverified'] is True and 'uncertainty' not in written
    assert written['locationID'] == hint['locationID'] and written['searchTopics'] == hint['searchTopics']
    assert hint['uncertainty'] == 'Die genaue Zuordnung ist nicht sicher.'  # Research retains the full constraint.
    assert writing_hint(None) is None


def test_writing_validation_errors_are_precise_but_never_echo_arbitrary_provider_data():
    from bikenavi.blog import failure_reason
    assert failure_reason(ValueError('Unvollständige Stopps')) == 'Unvollständige Stopps'
    assert 'PRIVATE' not in failure_reason(ValueError('PRIVATE DATA'))
