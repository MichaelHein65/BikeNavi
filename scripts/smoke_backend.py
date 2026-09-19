"""Exercise the real provider through BikeNavi, using public Heidelberg test points."""
import tempfile
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient
from bikenavi.main import create_app

root = Path(__file__).resolve().parents[1]
settings = {}
for line in (root / ".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        settings[k.strip()] = v.strip().strip("\"").strip("'")
headers = {"Authorization": "Bearer " + settings["BIKENAVI_TOKEN"]}
with tempfile.TemporaryDirectory() as directory:
    with TestClient(create_app(f"sqlite:///{directory}/smoke.sqlite", settings["BIKENAVI_TOKEN"], settings["ORS_API_KEY"])) as client:
        for surface in ["any", "preferPaved", "pavedOnly"]:
            request = {"waypoints": [
                {"id": str(uuid4()), "name": "Beispiel A", "coordinate": {"longitude": 8.681495, "latitude": 49.41461}},
                {"id": str(uuid4()), "name": "Beispiel B", "coordinate": {"longitude": 8.686507, "latitude": 49.41943}}],
                "profile": {"bike": "touring", "electric": True, "surface": surface, "gentleHills": True}}
            response = client.post("/v1/route", json=request, headers=headers)
            print(f"BikeNavi routing {surface}: HTTP {response.status_code}")
            if response.status_code == 200:
                route = response.json()
                print(f"  {route['distance']:.0f} m; {len(route['coordinates'])} Punkte; {len(route['surfaces'])} Belagstypen")
                fixture = root / "tests/fixtures/heidelberg-route.json"
                fixture.parent.mkdir(parents=True, exist_ok=True)
                if surface == "any":
                    import json
                    fixture.write_text(json.dumps(route, ensure_ascii=False, indent=2) + "\n")
            elif surface == "pavedOnly" and response.status_code == 422:
                print("  Strikte Belagsvorgabe korrekt ohne Aufweichen abgelehnt.")
            else:
                raise SystemExit("Routing-Integration fehlgeschlagen; es wurden keine Zugangsdaten ausgegeben.")
        response = client.get("/v1/search", params={"q": "Schloss Heidelberg"}, headers=headers)
        print(f"BikeNavi Ortssuche: HTTP {response.status_code}")
        if response.status_code != 200:
            raise SystemExit("Ortssuche muss überprüft werden.")
        print(f"  {len(response.json())} Treffer")
