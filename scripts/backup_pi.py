"""Back up only the BikeNavi database to this Mac, then verify by restoring a scratch DB."""
from datetime import datetime, timezone
from pathlib import Path
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
directory = ROOT / "artifacts/backups"
directory.mkdir(parents=True, exist_ok=True)
destination = directory / f"bikenavi-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}.dump"
base = "cd /srv/bikenavi && docker compose exec -T database "


def ssh(command, **kwargs):
    return subprocess.run(["ssh", "-T", "-o", "BatchMode=yes", "pi5", command], check=True, **kwargs)


with destination.open("wb") as output:
    ssh(base + "pg_dump -U bikenavi -d bikenavi -Fc", stdout=output)
destination.chmod(0o600)
scratch = "bikenavi_restore_" + uuid4().hex[:12]
ssh(base + f"createdb -U bikenavi {scratch}")
try:
    with destination.open("rb") as source:
        ssh(base + f"pg_restore -U bikenavi --exit-on-error -d {scratch}", stdin=source)
    result = ssh(base + f"psql -U bikenavi -d {scratch} -Atc 'SELECT count(*) FROM records'", capture_output=True, text=True)
    print("Sicherung auf dem Mac erstellt und in einer separaten temporären Datenbank erfolgreich wiederhergestellt.")
    print(f"Wiederhergestellte Archivdatensätze: {result.stdout.strip()}")
    print(f"Sicherungsdatei: {destination}")
finally:
    ssh(base + f"dropdb -U bikenavi {scratch}")
