"""Show a labelled real Heidelberg sample in the already installed simulator app."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
DEVICE = "CDFCED4D-5B0D-4C35-A4B0-8A3A1E1C11CB"
BUNDLE = "de.michaelhein.BikeNavi"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--local-only", action="store_true", help="Keep the visual test fixture entirely in the simulator")
parser.add_argument("--surfaces", action="store_true", help="Preview the real route with surface ranges")
args = parser.parse_args()
subprocess.run(["xcrun", "simctl", "terminate", DEVICE, BUNDLE], capture_output=True)
container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", DEVICE, BUNDLE, "data"], text=True).strip())
db_path = container / "Library/Application Support/BikeNavi/tours.sqlite"
if not db_path.exists():
    raise SystemExit("App zuerst einmal starten, damit der lokale Speicher angelegt ist.")
fixture = "heidelberg-surface-route.json" if args.surfaces else "heidelberg-route.json"
route = json.loads((ROOT / "tests/fixtures" / fixture).read_text())
sample_id = "123C7446-B126-41E7-82E3-64D572AFA78B" if args.surfaces else "5C75E6A4-B0A4-4D85-A449-5E0BEFA46FE6"
document = {
    "id": sample_id, "kind": "plan", "title": "Heidelberg · Belagsbeispiel" if args.surfaces else "Heidelberg · Beispieltour",
    "createdAt": time.time(), "updatedAt": time.time(),
    "waypoints": [{"id": str(uuid4()), "name": "Beispielstart Heidelberg" if args.surfaces else "Start am Neckar", "coordinate": route["coordinates"][0]},
                  {"id": str(uuid4()), "name": "Beispielziel Heidelberg" if args.surfaces else "Ziel in Neuenheim", "coordinate": route["coordinates"][-1]}],
    "profile": {"bike": "touring", "electric": True, "surface": "any", "gentleHills": True},
    "route": route, "track": [], "movingDuration": 0, "recordingState": "none",
}
with sqlite3.connect(db_path) as db:
    if not db.execute("SELECT 1 FROM documents WHERE id=?", (sample_id,)).fetchone():
        record = {"document": document, "revision": 0, "dirty": True, "deleted": False, "mutationID": str(uuid4())}
        db.execute("INSERT INTO documents(id,payload) VALUES(?,?)", (sample_id, json.dumps(record).encode()))
settings = dict(line.split("=", 1) for line in (ROOT / ".env").read_text().splitlines()
                if "=" in line and not line.startswith("#"))
environment = dict(os.environ)
environment["SIMCTL_CHILD_BIKENAVI_SERVER"] = settings.get("BIKENAVI_SERVER_URL", "")
environment["SIMCTL_CHILD_BIKENAVI_TOKEN"] = "" if args.local_only else settings["BIKENAVI_TOKEN"].strip().strip('"').strip("'")
environment["SIMCTL_CHILD_BIKENAVI_PLAN_ID"] = sample_id
subprocess.run(["xcrun", "simctl", "launch", DEVICE, BUNDLE], env=environment, check=True)
print("Die gekennzeichnete Heidelberger Beispielplanung ist im Simulator geöffnet.")
