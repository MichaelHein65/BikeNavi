import asyncio
import json

import httpx
import pytest
from fastapi.testclient import TestClient
from fastapi import HTTPException
from bikenavi.car_character import CarCharacters, CharacterRequest, EVENTS, MOODS, mood_id, validate_phrases
from bikenavi.main import create_app


def test_offline_pack_changes_secret_character_and_is_complete(monkeypatch):
    monkeypatch.delenv('CAR_OPENAI_API_KEY', raising=False)
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    async def check():
        async with httpx.AsyncClient() as client:
            service = CarCharacters(client)
            pack = await service.prepare(CharacterRequest(previousID=mood_id(0)))
            assert pack.characterID != mood_id(0)
            assert pack.source == 'template'
            validate_phrases(pack.phrases)
            assert set(pack.model_dump()) == {'characterID', 'source', 'phrases'}
            with pytest.raises(HTTPException) as error:
                await service.prepare(CharacterRequest())
            assert error.value.status_code == 429
    asyncio.run(check())
    for _, phrase in MOODS:
        validate_phrases({event: [phrase] * 3 for event in EVENTS})


@pytest.mark.parametrize('bad', ['Jetzt rechts abbiegen.', 'Gib Gas!', 'Es gilt 80.', 'Ein Satz. Noch einer.', 'a' * 101, 'Tempo ist egal.'])
def test_invalid_generated_asides_are_rejected(bad):
    with pytest.raises(ValueError):
        validate_phrases({event: [bad] * 3 for event in EVENTS})


@pytest.mark.parametrize('result', ['valid', 'invalid', 'refused', 'failure'])
def test_openai_request_is_private_bounded_and_falls_back(monkeypatch, result):
    monkeypatch.setenv('CAR_OPENAI_API_KEY', 'synthetic-test-secret')
    monkeypatch.setenv('CAR_OPENAI_MODEL', 'configured-model')
    def handle(request):
        body = json.loads(request.content)
        assert request.url == 'https://api.openai.com/v1/responses'
        assert body['model'] == 'configured-model'
        assert body['store'] is False
        assert body['text']['format']['strict'] is True
        assert not any(word in body for word in ('route', 'position', 'speed', 'coordinates'))
        if result == 'failure': return httpx.Response(503)
        phrase = 'Meine Schaltkreise seufzen leise.' if result == 'valid' else 'Jetzt rechts abbiegen.'
        payload = {'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': json.dumps({event: [phrase] * 3 for event in EVENTS})}]}]}
        if result == 'refused': payload['status'] = 'incomplete'
        return httpx.Response(200, json=payload)
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            pack = await CarCharacters(client).prepare(CharacterRequest())
            assert pack.source == ('openai' if result == 'valid' else 'template')
            validate_phrases(pack.phrases)
    asyncio.run(check())


def test_endpoint_requires_auth_and_rejects_extra_trip_data(tmp_path, monkeypatch):
    monkeypatch.delenv('CAR_OPENAI_API_KEY', raising=False)
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    token = 'test-' * 10
    app = create_app(database_url=f'sqlite:///{tmp_path}/test.db', token=token)
    with TestClient(app) as client:
        assert client.post('/v1/car/character', json={}).status_code == 401
        headers = {'Authorization': f'Bearer {token}'}
        assert client.post('/v1/car/character', json={'coordinates': []}, headers=headers).status_code == 422
        response = client.post('/v1/car/character', json={}, headers=headers)
        assert response.status_code == 200
        assert response.json()['source'] == 'template'


def test_invalid_metaphor_gets_one_bounded_repair(monkeypatch):
    monkeypatch.setenv('CAR_OPENAI_API_KEY', 'synthetic-test-secret')
    monkeypatch.setenv('CAR_OPENAI_MODEL', 'configured-model')
    calls = []
    def handle(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body['text']['format']['schema']['properties']['navigation']['items']['maxLength'] == 100
        phrase = 'Mein inneres Tempo ist heute verwirrt.' if len(calls) == 1 else 'Meine Schaltkreise seufzen leise.'
        return httpx.Response(200, json={'status': 'completed', 'output': [{'content': [
            {'type': 'output_text', 'text': json.dumps({event: [phrase] * 3 for event in EVENTS})}]}]})
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            pack = await CarCharacters(client).prepare(CharacterRequest())
            assert pack.source == 'openai'
            assert len(calls) == 2
            assert 'kürzeren Entwurf' in calls[1]['input']
    asyncio.run(check())


def test_repeated_invalid_text_never_retries_without_bound(monkeypatch):
    monkeypatch.setenv('CAR_OPENAI_API_KEY', 'synthetic-test-secret')
    monkeypatch.setenv('CAR_OPENAI_MODEL', 'configured-model')
    calls = []
    def handle(request):
        calls.append(request)
        return httpx.Response(200, json={'status': 'completed', 'output': [{'content': [
            {'type': 'output_text', 'text': json.dumps({event: ['Gib Gas!'] * 3 for event in EVENTS})}]}]})
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            pack = await CarCharacters(client).prepare(CharacterRequest())
            assert pack.source == 'template'
            assert len(calls) == 2
    asyncio.run(check())
