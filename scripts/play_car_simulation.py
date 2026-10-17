"""Build a synthetic trip with an existing Pi repertoire and speak it on macOS.

Run smoke_car_character.py first for fresh AI text. This script makes no network
requests and stores generated audio and traces only in ignored directories.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "build/car-character-live.json")
    parser.add_argument("--voice", default="Anna (Premium)")
    parser.add_argument("--no-play", action="store_true", help="Audio erzeugen, ohne es abzuspielen")
    args = parser.parse_args()
    if not args.input.is_file():
        parser.error("Repertoire fehlt. Zuerst scripts/smoke_car_character.py ausführen.")
    required = ["swiftc", "say", "ffmpeg"] + ([] if args.no_play else ["afplay"])
    for tool in required:
        if not shutil.which(tool):
            parser.error(f"Benötigtes Programm fehlt: {tool}")
    build = ROOT / "build"
    artifacts = ROOT / "artifacts"
    build.mkdir(exist_ok=True)
    artifacts.mkdir(exist_ok=True)
    executable = build / "simulate-car-trip"
    subprocess.run(["swiftc", "-parse-as-library",
                    *map(str, sorted((ROOT / "ios/BikeNavi/Core").glob("*.swift"))),
                    str(ROOT / "scripts/simulate_car_trip.swift"), "-lsqlite3", "-o", str(executable)], check=True)
    trace = build / "car-character-simulation.json"
    subprocess.run([str(executable), str(args.input.resolve()), str(trace)], check=True)
    moments = json.loads(trace.read_text())
    lines = ["Dies ist eine simulierte Autofahrt mit erfundenen Tempolimits. "
             "Die kurzen Charaktertexte wurden auf dem Pi mit OpenAI erzeugt. [[slnc 900]]"]
    lines.extend(moment["speech"] + " [[slnc 1100]]" for moment in moments if moment.get("speech"))
    lines.append("Die Simulation ist beendet.")
    speech = build / "car-character-simulation-speech.txt"
    speech.write_text("\n".join(lines))
    aiff = build / "car-character-simulation.aiff"
    output = artifacts / "car-character-simulation.mp3"
    subprocess.run(["say", "-v", args.voice, "-r", "185", "-f", str(speech), "-o", str(aiff)], check=True)
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(aiff),
                    "-codec:a", "libmp3lame", "-q:a", "3", str(output)], check=True)
    print(f"Hörsimulation erstellt: {output}", flush=True)
    if not args.no_play:
        subprocess.run(["afplay", str(output)], check=True)
        print("Wiedergabe beendet.")


if __name__ == "__main__":
    main()
