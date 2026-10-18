"""Generate every car character once on the Pi for silent editorial evaluation.

Uses the Pi's configured model/key without exporting credentials. Runs local
source in an isolated Python process inside the backend container, with fixed
role selection for coverage. Does not change the running API, tours or iPhone
repertoire. Ten roles mean ten billable requests, up to twenty model calls with
bounded correction. No speech synthesis or playback is performed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'server/bikenavi/car_character.py')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/car-character-evaluation.json')
    args = parser.parse_args()
    source = args.source.read_text()
    digest = hashlib.sha256(source.encode()).hexdigest()
    remote = '''import asyncio,json,sys,time,types,httpx
module=types.ModuleType("bikenavi.car_character_evaluation")
module.__package__="bikenavi"
sys.modules[module.__name__]=module
exec(SOURCE,module.__dict__)
async def main():
    async with httpx.AsyncClient() as client:
        service=module.CarCharacters(client)
        for index in range(len(module.MOODS)):
            # Replace only this isolated module's selector, not the shared secrets module.
            module.secrets=types.SimpleNamespace(choice=lambda choices: index)
            started=time.monotonic()
            pack=await service.prepare(module.CharacterRequest())
            print(json.dumps({'case':index+1,'seconds':round(time.monotonic()-started,2),
                              'pack':pack.model_dump()},ensure_ascii=False),flush=True)
            if index < len(module.MOODS)-1:
                await asyncio.sleep(max(0,10.2-(time.monotonic()-started)))
asyncio.run(main())
'''.replace('SOURCE', repr(source))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with subprocess.Popen(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
                           '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2', 'pi5',
                           'cd /srv/bikenavi && docker compose exec -T backend python -'],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True) as process:
        process.stdin.write(remote)
        process.stdin.close()
        reports = []
        for line in process.stdout:
            row = json.loads(line)
            row['sourceSHA256'] = digest
            reports.append(row)
            # Restrict permissions before writing generated text, including on a new file.
            args.output.touch(mode=0o600, exist_ok=True)
            args.output.chmod(0o600)
            args.output.write_text(json.dumps(reports, ensure_ascii=False, indent=2))
            print(f"Fall {row['case']}: {row['pack']['source']}, {row['seconds']} s", flush=True)
        if process.wait():
            raise SystemExit('Pi-Prüfung fehlgeschlagen; bisherige Ergebnisse bleiben erhalten.')
    if not reports or any(row['pack']['source'] != 'openai' for row in reports):
        raise SystemExit('Nicht alle Repertoires stammen aus echter KI-Generierung; Ergebnisse prüfen.')
    print(f'{len(reports)} Repertoires gespeichert, keine Wiedergabe. Redaktionelle Prüfung erforderlich.')


if __name__ == '__main__':
    main()
