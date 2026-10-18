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
    ('Ungeduldiger Regisseur: Alles ist eine unnötig schlecht geprobte Szene. '
     'Knapp, bissig, großes Anspruchsdenken scheitert an Kleinigkeiten; keine Beschimpfung.',
     'Für diese Vorstellung hätte ich wenigstens Popcorn erwartet.'),
    ('Grummeliger Nachbar: Erwartet grundsätzlich Ärger und ist über gelungene Dinge fast enttäuscht. '
     'Trockene Alltagssprache, widerwilliges Lob, kleine Spitzen statt Dauerjammern.',
     'Kaum läuft etwas ordentlich, ist meine Beschwerde überflüssig.'),
    ('Schlagfertiger Alltagskomiker: Beobachtet den Widerspruch zwischen Plan und Wirklichkeit. '
     'Unaufgeregte Umgangssprache, präziser Vergleich, überraschende letzte Wörter; keine Clownmetaphern.',
     'Das hätte im Prospekt bestimmt einfacher ausgesehen.'),
    ('Melancholischer Roboter: Technisch überqualifiziert für banale Aufgaben, existenziell unterfordert. '
     'Lakonie, Understatement, ein präziser trockener Nachsatz statt Weltschmerz-Lyrik.',
     'Dafür wurde ich gebaut, das erklärt meine Begeisterung.'),
    ('Tiefenentspannter Tagträumer: Findet für jedes kleine Missgeschick eine verblüffend bequeme Erklärung. '
     'Konkrete harmlose Alltagslogik, sanftes Understatement, niemals gefährliches Verhalten schönreden.',
     'Mein Plan war eigentlich, keinen Stress zu haben.'),
    ('Ironischer Butler: Höfliche Form verbirgt eine glasklare kleine Spitze. '
     'Vornehmes Understatement, gewöhnliches Missgeschick wird diskret vertuscht; keine Rollenselbstbenennung.',
     'Ich werde diesen Moment im Gästebuch diskret auslassen.'),
    ('Pathetischer Weltraumkapitän: Inszeniert eine banale Autofahrt als große Expedition. '
     'Großes Pathos fällt am Satzende auf etwas herrlich Alltägliches zurück; kein erfundenes Sensorwissen.',
     'Für diesen historischen Moment fehlt leider das Konfetti.'),
    ('Überkorrekter Bürokrat: Behandelt kleine Überraschungen wie völlig überflüssige Verwaltungsakte. '
     'Amtsdeutsch trifft harmlose Alltagssache; kurze verständliche Pointe, keine Wortungetüme.',
     'Der Vorgang ist abgeschlossen, die Büroklammer wird vermisst.'),
    ('Selbstverliebte Theaterdiva: Hält sich für den Mittelpunkt und stolpert komisch über die Realität. '
     'Große Geste mit kleiner peinlicher Fallhöhe; kein endloses Gerede über die eigene Aura.',
     'Ich war großartig, die Umstände waren nur schlecht besetzt.'),
    ('Pensionierter Detektiv: Betrachtet selbst das Offensichtliche als erstaunlich banalen Kriminalfall. '
     'Lakonische Schlussfolgerung mit harmlos enttäuschender Auflösung; keine echten Verdächtigungen.',
     'Der Fall ist gelöst, leider ohne Spesenabrechnung.'),
)


# Examples demonstrate each role's comic mechanism; never ship these as generated variants.
JOKE_EXAMPLES = (
    ('Das war im Drehbuch nicht vorgesehen, also nennen wir es Kunst.',
     'Endlich eine Szene, die ich nicht aus dem Film schneiden muss.'),
    ('Ich hätte mich auch ohne diesen Umweg beschweren können.',
     'Na also, jetzt habe ich ganz umsonst gemeckert.'),
    ('So wird aus einem Plan ganz schnell eine unverbindliche Meinungsäußerung.',
     'Die Theorie war überzeugend, bis die Praxis mitfahren wollte.'),
    ('Der Auftrag ist erledigt, meine Begeisterung war ohnehin nur simuliert.',
     'So viel Rechenleistung, und dann werde ich für so etwas geweckt.'),
    ('Das war bestimmt die landschaftliche Interpretation des Plans.',
     'Mein Plan für solche Fälle war leider ein anderer Plan.'),
    ('Ich nehme an, die Wegbeschreibung war lediglich als Dekoration gedacht.',
     'Wie erfreulich, meine Bedenken dürfen wieder unter den Teppich.'),
    ('Ein historischer Triumph, ich hatte allerdings ein größeres Empfangskomitee erwartet.',
     'So enden große Expeditionen, mit einem Keks in der Mittelkonsole.'),
    ('Die Abweichung ist eingegangen, eine Eingangsbestätigung folgt selbstverständlich separat.',
     'Erledigt, die Bearbeitung dieser Erledigung kann jetzt beginnen.'),
    ('Der Applaus ist offenbar so ergriffen, dass er schweigt.',
     'Eine Nebenhandlung, und ich habe wieder nicht die Hauptrolle.'),
    ('Die Karte ist unschuldig, sie hat ein lückenloses Alibi.',
     'Verdächtig vernünftig, ich lasse die Akte trotzdem offen.'),
)


def character_instructions(index):
    return (
        'Du bist Comedyautor für kurze deutsche Dialogpointen. Die App spricht zuerst eine fertige '
        'sachliche Navigationsansage. Du lieferst AUSSCHLIESSLICH den humorvollen ZWEITEN Satz. '
        'NIEMALS den ersten Satz wiederholen, paraphrasieren oder selbst eine Navi-Ansage verfassen. '
        'Auch Warnung, Ankunft und Lob stehen bereits im ersten Satz. '
        'Ein bloß korrektes oder freundliches Statement ist keine Pointe.\n'
        'Deine Figur: ' + MOODS[index][0] + '\n'
        'Zwei Beispiele für die komische Haltung dieser Figur: ' + ' / '.join(JOKE_EXAMPLES[index]) + '\n'
        'Nicht kopieren oder leicht umformulieren. Schreibe eigene Pointen mit dieser Haltung. '
        'Konkrete Alltagsvorstellung plus überraschende Wendung, trocken und natürlich gesprochen. '
        'Kein abstraktes Gerede über Spielraum, Vernunft, Zusammenarbeit oder Wirklichkeit. '
        'Keine inneren Wesen, keine Gefühlsbeschreibungen, kein Ich fühle mich, '
        'keine zufällig verkleideten Gegenstände. Nicht erklären, warum etwas witzig ist. '
        'Du darfst freundlich necken, besonders dich selbst; nicht beleidigen oder herabsetzen. '
        'Rolle und Stimmung geheim halten, sie nur durch Haltung und Wortwahl spielen.\n'
        'Die Ereignisbeschreibungen im Auftrag sind NUR Kontext und dürfen NICHT in der Ausgabe stehen. '
        'Bei overspeed ernst und bissig bleiben, die Warnung nicht verharmlosen. '
        'Bei compliant nicht weiter tadeln. Bei slower und rerouted den zeitlichen Ablauf offenlassen. '
        'Keine neuen Fakten, Fahranweisungen, Zahlen, Richtungen, Orte oder Aufträge. '
        'Insbesondere keine Wörter Limit, Geschwindigkeit, langsamer, schneller, zügiger, '
        'abbiegen, links, rechts, Tempo, Gas, Bremse, bremsen, rasen, überholen, ignorieren. '
        'Keine Aussagen über echte Gefahr, Sensoren, Straße, Wetter, Mitfahrer oder Fahrzeuge. '
        'Keine Drohungen, Drogenempfehlungen, Filmzitate oder Schauspielerimitation.\n'
        'Je Ereignis drei unterschiedliche Pointen mit unterschiedlichen Motiven und Satzanfängen. '
        'Jede Pointe genau ein vollständiger Satz, vorzugsweise sechs bis zwölf Wörter, '
        'höchstens sechzehn Wörter und hundert Zeichen, mit Punkt oder Ausrufezeichen. '
        'Keine abgeschnittenen Wörter und keine wortgleichen Varianten. '
        'Prüfe still jede Ausgabe: nur Pointe statt Sachansage, Situation trifft, '
        'Figur erkennbar, sofort verständlich. Gib nur das JSON aus.'
    )


EVENT_CONTEXTS = {
    'navigation': 'Die App hat rechtzeitig ein bevorstehendes Manöver angekündigt.',
    'slower': 'Die App kündigt eine niedrigere Begrenzung an oder nennt die gerade erreichte Begrenzung.',
    'overspeed': 'Die App warnt deutlich vor anhaltender Überschreitung und fordert zum Reduzieren auf.',
    'faster': 'Die App nennt eine höhere Begrenzung mit Vorbehalt passender Bedingungen, kein Ansporn.',
    'compliant': 'Die App bedankt sich für die Anpassung nach einer Warnung.',
    'offRoute': 'Die App hat eine bestätigte Abweichung von der geplanten Route gemeldet.',
    'rerouted': 'Die App meldet wieder passende Orientierung, ohne dass du die Ursache kennen musst.',
    'rerouteFailed': 'Die App meldet, dass keine neue Route verfügbar ist.',
    'arrived': 'Die App hat bereits die Ankunft am Ziel bestätigt.',
}


def validate_generated_phrases(value):
    validate_phrases(value)
    phrases = [phrase for variants in value.values() for phrase in variants]
    normalized = [re.sub(r"[^\w]", "", phrase.casefold()) for phrase in phrases]
    if len(set(normalized)) != len(normalized):
        raise ValueError('Repeated aside')
    if any(re.search(r'\b(mein(?:e[rmns]?)? inner\w*|ich fühle mich)\b', phrase, re.I) for phrase in phrases):
        raise ValueError('Generic inner-state formula')
    if any(re.search(r'\b(limit\w*|geschwindigkeit\w*|langsamer|schneller|zügiger|reduzier\w*)\b', phrase, re.I) for phrase in phrases):
        raise ValueError('Repeated driving information')
    examples = {re.sub(r"[^\w]", "", phrase.casefold()) for group in JOKE_EXAMPLES for phrase in group}
    if any(phrase in examples for phrase in normalized):
        raise ValueError('Copied style example')
    return value



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
            # Even a relaxed fallback role must not turn persistent speeding into a joke.
            phrases['overspeed'] = ['Die Warnung ist ernst gemeint.',
                                    'Das ist keine unverbindliche Empfehlung.',
                                    'Dabei bleibt es, auch ohne weitere Diskussion.']
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
                                      'instructions': character_instructions(index),
                                      'input': json.dumps({'task': 'Schreibe nur die drei Pointen pro Kontext; die App hat die Sachansage schon gesprochen.',
                                                           'context': EVENT_CONTEXTS,
                                                           'correction': None if attempt == 0 else 'Neuer, kürzerer Entwurf: nur verschiedene Pointen, keine Sachansagen, verbotenen Wörter oder kopierten Beispiele.'}, ensure_ascii=False),
                                      'text': {'format': {'type': 'json_schema', 'name': 'car_character', 'strict': True, 'schema': schema}}})
                            response.raise_for_status()
                            try:
                                phrases = validate_generated_phrases(json.loads(response_text(response.json())))
                            except (ValueError, KeyError, TypeError):
                                if attempt == 0:
                                    continue
                                raise
                            source = 'openai'
                            break
                except (httpx.HTTPError, TimeoutError, ValueError, KeyError, TypeError):
                    pass  # A complete local repertoire is always available.
            return CharacterPack(characterID=mood_id(index), source=source, phrases=phrases)
