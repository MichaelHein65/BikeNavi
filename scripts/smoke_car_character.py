"""Test two genuine AI repertoires via the private Pi API without revealing the roles.

Uses the app connection from .env, never exports the Pi's OpenAI key and does not
read or mutate tours. Makes two billable generation requests (up to four model
calls including bounded corrections). Full diagnostic
responses are saved only under ignored build/ for local inspection.
"""
import json
from pathlib import Path
import sys
import time

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from bikenavi.car_character import CharacterPack, validate_phrases


def main():
    settings = {key.strip(): value.strip().strip('"').strip("'")
                for line in (ROOT / '.env').read_text().splitlines()
                if '=' in line and not line.lstrip().startswith('#')
                for key, value in [line.split('=', 1)]}
    url, token = settings.get('BIKENAVI_SERVER_URL', ''), settings.get('BIKENAVI_TOKEN', '')
    if not url.startswith('https://') or len(token) < 32:
        raise SystemExit('HTTPS-App-Zugang in .env fehlt.')
    reports = []
    previous = None
    with httpx.Client(base_url=url, timeout=40) as client:
        if client.get('/health').status_code != 200:
            raise SystemExit('Pi-Healthcheck fehlgeschlagen.')
        if client.post('/v1/car/character', json={}).status_code != 401:
            raise SystemExit('Zugangsschutz fehlgeschlagen.')
        client.headers['Authorization'] = 'Bearer ' + token
        for attempt in range(2):
            start = time.monotonic()
            response = client.post('/v1/car/character', json={'previousID': previous})
            elapsed = time.monotonic() - start
            if response.status_code != 200:
                raise SystemExit(f'Charakter-API: HTTP {response.status_code}.')
            pack = CharacterPack.model_validate(response.json())
            validate_phrases(pack.phrases)
            reports.append({'seconds': round(elapsed, 2), 'pack': pack.model_dump()})
            output = ROOT / 'build/car-character-live.json'
            output.parent.mkdir(exist_ok=True)
            output.write_text(json.dumps(reports, ensure_ascii=False, indent=2))
            output.chmod(0o600)
            if pack.source != 'openai':
                raise SystemExit('Nur Ersatztexte erhalten; echte KI-Generierung noch nicht bestätigt.')
            if previous == pack.characterID:
                raise SystemExit('Charakterwechsel hat dieselbe Rolle zurückgegeben.')
            print(f'KI-Prüfung {attempt + 1}: source=openai, {len(pack.phrases)} Situationen, '
                  f'{sum(map(len, pack.phrases.values()))} Varianten, {elapsed:.1f} s.', flush=True)
            previous = pack.characterID
            if attempt == 0:
                time.sleep(max(0, 11 - elapsed))
    print('HTTPS, Zugangsschutz, echte KI-Texte und anderer geheimer Charakter bestätigt.')


if __name__ == '__main__':
    try:
        main()
    except httpx.HTTPError as error:
        # URLs, request headers and credentials do not belong in diagnostic output.
        raise SystemExit('Verbindung zum Pi fehlgeschlagen: ' + type(error).__name__) from None
