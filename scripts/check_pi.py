"""Smoke test the private server; create and tombstone a clearly labelled test plan."""
from pathlib import Path
import time
from uuid import uuid4

import httpx

ROOT = Path(__file__).resolve().parents[1]
settings = dict(line.split("=", 1) for line in (ROOT / ".env").read_text().splitlines()
                if "=" in line and not line.startswith("#"))
token = settings["BIKENAVI_TOKEN"].strip().strip("\"").strip("'")
url = settings.get("BIKENAVI_SERVER_URL", "").strip().strip("\"").strip("'")
if not url.startswith("https://"):
    raise SystemExit("In .env fehlt eine gültige BIKENAVI_SERVER_URL mit https://.")

with httpx.Client(base_url=url, timeout=90) as client:
    health = client.get("/health")
    health.raise_for_status()
    print("Pi: HTTPS und Healthcheck erfolgreich.")
    assert client.get("/v1/changes").status_code == 401
    client.headers["Authorization"] = "Bearer " + token
    status = client.get("/v1/status")
    status.raise_for_status()
    assert status.json()["routingAvailable"]
    print("Pi: Zugangsschutz und Routing-Konfiguration erfolgreich.")
    place = client.get("/v1/place-name", params={"lat": 49.41461, "lon": 8.681495})
    place.raise_for_status()
    assert place.json().get("name")
    print("Pi: Ortsname für einen öffentlichen Beispielpunkt erfolgreich ermittelt.")
    waypoints = [
        {"id": str(uuid4()), "name": "Beispiel A", "coordinate": {"longitude": 8.681495, "latitude": 49.41461}},
        {"id": str(uuid4()), "name": "Beispiel B", "coordinate": {"longitude": 8.686507, "latitude": 49.41943}},
    ]
    profile = {"bike": "touring", "electric": True, "surface": "any", "gentleHills": False}
    response = client.post("/v1/route", json={"waypoints": waypoints, "profile": profile})
    response.raise_for_status()
    route = response.json()
    assert route["surfaceSections"]
    assert all(0 <= s["startIndex"] < s["endIndex"] < len(route["coordinates"]) for s in route["surfaceSections"])
    print(f"Pi: E-Bike-Route mit {route['distance']:.0f} Metern berechnet.")
    document = {"id": str(uuid4()), "kind": "plan", "title": "Technischer Verbindungstest · Heidelberg",
                "usesAutomaticTitle": False,
                "createdAt": time.time(), "updatedAt": time.time(), "waypoints": waypoints,
                "profile": profile, "route": route}
    mutation = {"mutationID": str(uuid4()), "baseRevision": 0, "deleted": False, "document": document}
    saved = None
    try:
        result = client.post("/v1/mutations", json=mutation)
        result.raise_for_status()
        saved = result.json()
        assert saved["revision"] == 1
        assert saved["document"]["usesAutomaticTitle"] is False
        assert saved["document"]["route"]["surfaceSections"] == route["surfaceSections"]
        retry = client.post("/v1/mutations", json=mutation)
        retry.raise_for_status()
        assert retry.json() == saved
        cursor = 0
        found = False
        while True:
            page = client.get("/v1/changes", params={"after": cursor})
            page.raise_for_status()
            body = page.json()
            found |= any(r["document"]["id"] == document["id"] for r in body["records"])
            cursor = body["cursor"]
            if not body["hasMore"]:
                break
        assert found
        print("Pi: Planung in PostgreSQL gespeichert und über Synchronisation wieder geladen.")
        print("Pi: Wiederholter Upload erzeugt keine Dublette.")
    finally:
        if saved:
            deletion = {**mutation, "mutationID": str(uuid4()), "baseRevision": saved["revision"], "deleted": True}
            cleanup = client.post("/v1/mutations", json=deletion)
            cleanup.raise_for_status()
            print("Technischen Testeintrag wieder aus dem Tourenarchiv entfernt.")
