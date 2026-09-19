"""Check real ORS surface ranges on public Heidelberg sample coordinates."""
import json
from pathlib import Path
import tempfile
from uuid import uuid4

from fastapi.testclient import TestClient
from bikenavi.main import create_app

ROOT = Path(__file__).resolve().parents[1]
settings = dict(line.split("=", 1) for line in (ROOT / ".env").read_text().splitlines()
                if "=" in line and not line.startswith("#"))
settings = {key: value.strip().strip('"').strip("'") for key, value in settings.items()}
with tempfile.TemporaryDirectory() as directory:
    with TestClient(create_app(f"sqlite:///{directory}/check.sqlite", settings["BIKENAVI_TOKEN"], settings["ORS_API_KEY"])) as client:
        response = client.post("/v1/route", headers={"Authorization": "Bearer " + settings["BIKENAVI_TOKEN"]}, json={
            "waypoints": [
                {"id": str(uuid4()), "name": "Beispielstart Heidelberg", "coordinate": {"latitude": 49.41461, "longitude": 8.681495}},
                {"id": str(uuid4()), "name": "Beispielziel Heidelberg", "coordinate": {"latitude": 49.435, "longitude": 8.706}}
            ], "profile": {"bike": "touring", "electric": True, "surface": "any", "gentleHills": False}})
        assert response.status_code == 200, f"Routing-Prüfung: HTTP {response.status_code}"
        route = response.json()
        sections = route["surfaceSections"]
        assert sections and all(0 <= section["startIndex"] < section["endIndex"] < len(route["coordinates"]) for section in sections)
        (ROOT / "tests/fixtures/heidelberg-surface-route.json").write_text(json.dumps(route, ensure_ascii=False, indent=2) + "\n")
        print(f"Echte Route: {route['distance']:.0f} m, {len(sections)} Belagsabschnitte.")
        print("Gelieferte Belagskennungen:", sorted({section['surface'] for section in sections}))
