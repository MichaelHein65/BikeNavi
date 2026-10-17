"""Short, preloaded car-only asides. No route, position or speed goes to OpenAI."""
import asyncio
from collections import deque
import hashlib
import json
import os
import re
import secrets
import time

import httpx
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field
from .blog import response_text

EVENTS = ('navigation', 'slower', 'overspeed', 'faster', 'compliant', 'offRoute', 'rerouted', 'rerouteFailed', 'arrived')
# Original archetypes, no actor imitation or quoted film dialogue.
MOODS = (
    ('energisch und ungeduldig, aber nicht beleidigend', 'Meine Geduld hat heute frei.'),
    ('schlecht gelaunter, trockener Beifahrer', 'War ja klar, dass ich wieder mitdenken muss.'),
    ('heiterer Komiker mit trockenem Humor', 'Mein innerer Beifahrer trägt heute Konfetti.'),
    ('melancholischer, existenziell gelangweilter Roboter', 'Das Universum bleibt davon vermutlich unbeeindruckt.'),
    ('verträumter, absurd entspannter Chaot', 'Mein Gedankenkarussell fährt heute mit Wolkenantrieb.'),
    ('höflicher, ironischer Butler', 'Ich gestatte mir dazu ein dezentes Seufzen.'),
    ('pathetischer Weltraumkapitän', 'Das Bordorchester hält gespannt den Atem an.'),
)


def mood_id(index):
    return hashlib.sha256(f'bikenavi-car-character-v1-{index}'.encode()).hexdigest()[:24]


class CharacterRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    previousID: str | None = Field(default=None, max_length=64)


class CharacterPack(BaseModel):
    characterID: str
    source: str
    phrases: dict[str, list[str]]


def validate_phrases(value):
    if not isinstance(value, dict) or set(value) != set(EVENTS):
        raise ValueError('Missing events')
    for phrases in value.values():
        if not isinstance(phrases, list) or len(phrases) != 3:
            raise ValueError('Expected three variants')
        for phrase in phrases:
            if not isinstance(phrase, str) or not 3 <= len(phrase) <= 100 or len(phrase.split()) > 16:
                raise ValueError('Aside too long')
            # Only one sentence, never directions, measurements or markup.
            if not re.fullmatch(r"[A-Za-zÄÖÜäöüß ,;:'’–-]+[.!]", phrase):
                raise ValueError('Invalid sentence')
            if re.search(r'\b(links|rechts|abbiegen|wenden|beschleunig\w*|gas|brems\w*|tempo|kmh|kilometer|meter|ras\w*|überhol\w*|ignorier\w*)\b', phrase, re.I):
                raise ValueError('Driving advice belongs to navigation')
    return value


class CarCharacters:
    def __init__(self, client):
        self.client = client
        self.lock = asyncio.Lock()
        self.attempts = deque()

    async def prepare(self, request):
        # One generation at a time and at most 30/hour per backend process.
        if self.lock.locked():
            raise HTTPException(429, 'Ein Charakter wird bereits vorbereitet.')
        async with self.lock:
            now = time.monotonic()
            while self.attempts and now - self.attempts[0] >= 3600:
                self.attempts.popleft()
            if len(self.attempts) >= 30 or (self.attempts and now - self.attempts[-1] < 10):
                raise HTTPException(429, 'Bitte mit dem nächsten Charakterwechsel kurz warten.')
            self.attempts.append(now)
            index = secrets.choice([i for i in range(len(MOODS)) if mood_id(i) != request.previousID])
            mood, fallback = MOODS[index]
            phrases = {event: [fallback] * 3 for event in EVENTS}
            source = 'template'
            key = os.getenv('CAR_OPENAI_API_KEY') or os.getenv('BLOG_OPENAI_API_KEY', '')
            model = os.getenv('CAR_OPENAI_MODEL') or os.getenv('BLOG_OPENAI_MODEL', '')
            if key and model:
                schema = {'type': 'object', 'additionalProperties': False,
                          'properties': {event: {'type': 'array', 'items': {'type': 'string', 'maxLength': 100, 'pattern': r"^[A-Za-zÄÖÜäöüß ,;:'’–-]+[.!]$"}, 'minItems': 3, 'maxItems': 3} for event in EVENTS},
                          'required': list(EVENTS)}
                try:
                    async with asyncio.timeout(30):
                        for attempt in range(2):
                            response = await self.client.post('https://api.openai.com/v1/responses',
                                headers={'Authorization': 'Bearer ' + key}, timeout=30,
                                json={'model': model, 'store': False, 'max_output_tokens': 4000,
                                      **({'reasoning': {'effort': 'low'}} if model == 'gpt-5.6-luna' or model.startswith('gpt-5.6-luna-') else {}),
                                      'instructions': 'Schreibe kurze deutsche Charakter-Nachsätze für einen Auto-Beifahrer. '
                                      'Stimmung: ' + mood + '. Stimmung nicht benennen. Je Ereignis drei verschiedene Varianten. '
                                      'Jede Variante genau ein Satz mit höchstens 16 Wörtern und 100 Zeichen, mit Punkt oder Ausrufezeichen. '
                                      'Der sachliche Navigationshinweis wird bereits VOR deinem Satz gesprochen. '
                                      'Nur ein humorvoller Kommentar über die eigene Befindlichkeit, KEINE Fahranweisungen, '
                                      'Richtungen, Zahlen, Geschwindigkeiten, Streckenbehauptungen oder Handlungsaufforderungen. '
                                      'Auch bildlich NICHT verwenden: links, rechts, abbiegen, wenden, beschleunigen, Gas, '
                                      'Bremse, bremsen, Tempo, Kilometer, Meter, rasen, rasant, überholen, ignorieren. '
                                      'Keine Beleidigungen, Drohungen, Drogenempfehlungen, Filmzitate oder Schauspielerimitation. '
                                      'Bei overspeed ernster und nachdrücklich, nicht verharmlosend. '
                                      'navigation=Abbiegevorwarnung, slower=bald niedrigeres Limit, overspeed=weiter zu schnell, '
                                      'faster=höheres Limit, compliant=Tempo angepasst, offRoute=Route verlassen, '
                                      'rerouted=neue Route bereit, rerouteFailed=Neuberechnung fehlt, arrived=Ziel erreicht.',
                                      'input': 'Erzeuge das vollständige Repertoire.' if attempt == 0 else 'Der vorherige Entwurf verletzte eine Textregel. Erzeuge einen neuen, kürzeren Entwurf ohne die verbotenen Wörter, auch nicht als Metapher.',
                                      'text': {'format': {'type': 'json_schema', 'name': 'car_character', 'strict': True, 'schema': schema}}})
                            response.raise_for_status()
                            try:
                                phrases = validate_phrases(json.loads(response_text(response.json())))
                            except (ValueError, KeyError, TypeError):
                                if attempt == 0:
                                    continue
                                raise
                            source = 'openai'
                            break
                except (httpx.HTTPError, TimeoutError, ValueError, KeyError, TypeError):
                    pass  # A complete local repertoire is always available.
            return CharacterPack(characterID=mood_id(index), source=source, phrases=phrases)
