import asyncio
import json

import httpx
import pytest
from fastapi.testclient import TestClient
from fastapi import HTTPException
from bikenavi.car_character import CarCharacters, CharacterRequest, EVENTS, MOODS, mood_id, validate_phrases, validate_generated_phrases, JOKE_EXAMPLES
from bikenavi.main import create_app


def generated_fixture():
    nouns = ('Kalender', 'Notizblock', 'Kaffee', 'Aktenkoffer', 'Sessel', 'Hut', 'Bleistift', 'Wecker', 'Schreibtisch')
    endings = ('hat heute frei', 'wartet auf Feierabend', 'verlangt eine Pause')
    return {event: [f'Mein {noun} {ending}.' for ending in endings] for event, noun in zip(EVENTS, nouns)}


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
        payload = {'status': 'completed', 'output': [{'content': [{'type': 'output_text', 'text': json.dumps(generated_fixture() if result == 'valid' else {event: [phrase] * 3 for event in EVENTS})}]}]}
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
            {'type': 'output_text', 'text': json.dumps(generated_fixture() if len(calls) == 2 else {event: [phrase] * 3 for event in EVENTS})}]}]})
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            pack = await CarCharacters(client).prepare(CharacterRequest())
            assert pack.source == 'openai'
            assert len(calls) == 2
            assert 'kürzerer Entwurf' in calls[1]['input']
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


@pytest.mark.parametrize('phrase', ['Mein innerer Kompass applaudiert.', 'Meine innere Diva singt.', 'Ich fühle mich überraschend ordentlich.'])
def test_generic_inner_state_formulas_trigger_repair(phrase):
    values = generated_fixture()
    values['offRoute'][0] = phrase
    with pytest.raises(ValueError, match='inner-state'):
        validate_generated_phrases(values)


def test_repeated_generated_asides_are_rejected_even_with_other_punctuation():
    values = generated_fixture()
    values['arrived'][2] = values['slower'][0].upper().replace('.', '!')
    with pytest.raises(ValueError, match='Repeated'):
        validate_generated_phrases(values)
    # Existing and fallback packs remain readable; strict diversity is for new AI output.
    validate_phrases(values)


@pytest.mark.parametrize('index', range(10))
def test_all_ten_roles_have_valid_fallback_and_preserve_previous_id_exclusion(monkeypatch, index):
    monkeypatch.delenv('CAR_OPENAI_API_KEY', raising=False)
    monkeypatch.delenv('BLOG_OPENAI_API_KEY', raising=False)
    assert len(MOODS) == 10
    assert len({mood_id(i) for i in range(10)}) == 10
    def choose(candidates):
        assert index not in candidates
        assert len(candidates) == 9
        return candidates[0]
    monkeypatch.setattr('bikenavi.car_character.secrets.choice', choose)
    async def check():
        async with httpx.AsyncClient() as client:
            pack = await CarCharacters(client).prepare(CharacterRequest(previousID=mood_id(index)))
            assert pack.characterID != mood_id(index)
            validate_phrases(pack.phrases)
            assert len(set(pack.phrases['overspeed'])) == 3
            assert MOODS[0 if index != 0 else 1][1] not in pack.phrases['overspeed']
    asyncio.run(check())


def test_style_examples_are_not_returned_as_generated_material():
    values = generated_fixture()
    values['offRoute'][0] = JOKE_EXAMPLES[0][0]
    with pytest.raises(ValueError, match='Copied'):
        validate_generated_phrases(values)


@pytest.mark.parametrize('phrase', ['Bitte langsamer werden.', 'Hier gilt ein niedrigeres Limit.', 'Die Geschwindigkeit bleibt zu hoch.'])
def test_ai_aside_cannot_repeat_speed_instruction(phrase):
    values = generated_fixture()
    values['slower'][0] = phrase
    with pytest.raises(ValueError, match='driving information'):
        validate_generated_phrases(values)
