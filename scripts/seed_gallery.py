"""Seed public example data for README screenshots in an installed simulator app.

Only use on a dedicated documentation simulator. No .env, credentials or Pi access.
Ride times, GPS samples and bike values are synthetic; the route is the public ORS fixture.
"""
import argparse
import copy
import json
from pathlib import Path
import sqlite3
import subprocess
from uuid import UUID, uuid5

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "de.michaelhein.BikeNavi"
PLAN = "123C7446-B126-41E7-82E3-64D572AFA78B"
RIDE = "79151CF4-6C4D-43EF-8A83-B364134FABCE"
STAMP = 1790146800  # Fixed example date, never a real recorded ride.


def identifier(name):
    return str(uuid5(UUID(PLAN), name)).upper()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Dedicated iOS simulator UUID")
    args = parser.parse_args()
    subprocess.run(["xcrun", "simctl", "terminate", args.device, BUNDLE], capture_output=True)
    container = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", args.device, BUNDLE, "data"], text=True).strip())
    database = container / "Library/Application Support/BikeNavi/tours.sqlite"
    database.parent.mkdir(parents=True, exist_ok=True)
    route = json.loads((ROOT / "tests/fixtures/heidelberg-surface-route.json").read_text())
    plan = dict(id=PLAN, kind="plan", title="Heidelberg · Beispieltour", usesAutomaticTitle=False,
                createdAt=STAMP, updatedAt=STAMP,
                waypoints=[dict(id=identifier("start"), name="Start am Neckar", coordinate=route["coordinates"][0]),
                           dict(id=identifier("end"), name="Ziel der Beispieltour", coordinate=route["coordinates"][-1])],
                profile=dict(bike="touring", electric=True, surface="any", gentleHills=True),
                route=route, track=[], movingDuration=0, recordingState="none")
    ride = copy.deepcopy(plan)
    ride.update(id=RIDE, sourcePlanID=PLAN, kind="ride", title="Heidelberg · Beispielaufzeichnung",
                recordingState="finished", startedAt=STAMP, endedAt=STAMP+1350, movingDuration=1350)
    ride["track"] = [dict(coordinate=c, timestamp=STAMP+i*10, accuracy=5, speed=4, segment=0)
                     for i, c in enumerate(route["coordinates"])]
    with sqlite3.connect(database) as db:
        db.execute("CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        db.execute("CREATE TABLE IF NOT EXISTS places (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        db.execute("CREATE TABLE IF NOT EXISTS bike_samples (id TEXT PRIMARY KEY, ride_id TEXT NOT NULL, payload BLOB NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0)")
        # Remove only earlier generated live rides belonging to this fixed example plan.
        for record_id, payload in db.execute("SELECT id, payload FROM documents").fetchall():
            previous = json.loads(payload)["document"]
            if previous.get("sourcePlanID") == PLAN and record_id != RIDE:
                db.execute("DELETE FROM bike_samples WHERE ride_id=?", (record_id,))
                db.execute("DELETE FROM documents WHERE id=?", (record_id,))
        for document in [plan, ride]:
            record = dict(document=document, revision=0, dirty=True, deleted=False, mutationID=identifier(document["id"]))
            db.execute("INSERT OR REPLACE INTO documents VALUES (?, ?)", (document["id"], json.dumps(record).encode()))
        for i, name in enumerate(["Neckarufer · Beispiel", "Pause am Fluss · Beispiel", "Tourziel · Beispiel"]):
            place = dict(id=identifier(name), name=name, coordinate=route["coordinates"][[0, 65, -1][i]], createdAt=STAMP)
            db.execute("INSERT OR REPLACE INTO places VALUES (?, ?)", (place["id"], json.dumps(place).encode()))
        for i, position in enumerate(ride["track"]):
            sample = dict(id=identifier(f"sample-{i}"), rideID=RIDE, sourcePlanID=PLAN, segment=0, position=position,
                          measurement=dict(bikeID=identifier("synthetic-bike"), timestamp=position["timestamp"],
                                           batteryPercent=90-i//10, riderPowerWatts=110+(i%20)*4,
                                           motorPowerWatts=180+(i%25)*6, assistMode=1+(i//34)%4))
            db.execute("INSERT OR REPLACE INTO bike_samples VALUES (?, ?, ?, 0)",
                       (sample["id"], RIDE, json.dumps(sample).encode()))
    print("Public Heidelberg route and labelled synthetic example ride prepared in simulator.")


if __name__ == "__main__":
    main()
