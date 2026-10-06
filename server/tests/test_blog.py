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
        return httpx.Response(200, json={'query': {'pages': {'1': {'title': 'Neckar', 'extract': 'Der Neckar ist ein Fluss in Deutschland.', 'coordinates': [{'lat': 49.41, 'lon': 8.68}]}}}})
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


def test_ai_research_and_story_are_source_backed_without_photo_upload(tmp_path, monkeypatch):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    requests = []
    def ai_upstream(request):
        if request.url.host != 'api.openai.com': return upstream(request)
        body = json.loads(request.content); requests.append(body)
        assert body['store'] is False and 'photo' not in body['input']
        if 'tools' in body:
            text = 'Heidelberg liegt am Neckar. Belegte Landschaft. [Quelle]'
            start = text.index('[Quelle]')
            return httpx.Response(200, json={'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': text, 'annotations': [{'type': 'url_citation', 'title': 'Stadt Heidelberg', 'url': 'https://www.heidelberg.de/', 'start_index': start, 'end_index': len(text)}]}]}]})
        story = {'title': 'Mit Neugier am Neckar', 'introduction': 'Ein Weg am Fluss [2].', 'stops': ['Kleine Pause, weiter Blick [1].'], 'closing': 'Die nächste Folge wartet!'}
        return httpx.Response(200, json={'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps(story)}]}]})
    app = create_app(f'sqlite:///{tmp_path}/ai.sqlite', token=TOKEN, transport=httpx.MockTransport(ai_upstream))
    with TestClient(app) as client:
        ride = save_ride(client)['document']['id']
        client.post('/v1/blog-points', json=point(ride, photo=base64.b64encode(b'\xff\xd8\xfftest\xff\xd9').decode()), headers=AUTH)
        result = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
        assert result['mode'] == 'openai' and result['sourceCount'] == 2
        assert 'href="#source-2"' in result['html'] and 'https://www.heidelberg.de/' in result['html']
        assert len(requests) == 2
        assert requests[0]['max_tool_calls'] == 3
        assert requests[1]['text']['format']['strict'] is True


def test_ai_failure_preserves_complete_template(tmp_path, monkeypatch):
    monkeypatch.setenv('BLOG_OPENAI_API_KEY', 'test-secret')
    monkeypatch.setenv('BLOG_OPENAI_MODEL', 'test-model')
    app = create_app(f'sqlite:///{tmp_path}/bad-ai.sqlite', token=TOKEN, transport=httpx.MockTransport(upstream))
    with TestClient(app) as client:
        ride = save_ride(client)['document']['id']
        client.post('/v1/blog-points', json=point(ride), headers=AUTH)
        result = client.post(f'/v1/rides/{ride}/blog', headers=AUTH).json()
        assert result['mode'] == 'template'
        assert any('KI-Text' in w for w in result['warnings'])
        assert any('KI-Webrecherche' in w for w in result['warnings'])
        assert 'Eine Pause am Fluss.' in result['html']


def test_unsafe_web_citations_are_rejected():
    from bikenavi.blog import safe_source, prose
    assert not safe_source('javascript:alert(1)')
    assert not safe_source('https://user:pass@example.com/')
    assert prose('<script>[1]</script>', [{'url': 'https://example.org/'}]) == '&lt;script&gt;<a href="#source-1" aria-label="Quelle 1">[1]</a>&lt;/script&gt;'
