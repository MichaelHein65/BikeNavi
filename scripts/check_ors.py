"""Read the local key and test ORS without logging credentials or personal locations."""
import sys
from pathlib import Path

import httpx

root = Path(__file__).resolve().parents[1]
settings = {}
for line in (root / ".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        name, value = line.split("=", 1)
        settings[name.strip()] = value.strip().strip("\"").strip("'")
key = settings.get("ORS_API_KEY", "")
if not key:
    print("ORS_API_KEY ist noch leer.")
    sys.exit(1)
try:
    response = httpx.post(
        "https://api.openrouteservice.org/v2/directions/cycling-regular/geojson",
        headers={"Authorization": key}, timeout=40,
        json={"coordinates": [[8.681495, 49.41461], [8.686507, 49.41943]],
              "elevation": True, "instructions": True, "language": "de",
              "extra_info": ["surface", "waytype", "steepness"]},
    )
    print(f"Routing-Test: HTTP {response.status_code}")
    if response.status_code != 200:
        print("Kein erfolgreicher Routing-Zugriff. Zugang, Freischaltung oder Kontingent prüfen.")
        sys.exit(1)
    feature = response.json()["features"][0]
    props = feature["properties"]
    geometry = feature["geometry"]["coordinates"]
    print("API-Schlüssel funktioniert.")
    print(f"Beispielroute Heidelberg: {props['summary']['distance']:.0f} m")
    print(f"Streckenpunkte: {len(geometry)}")
    print(f"Höhenwerte: {'vorhanden' if all(len(c) >= 3 for c in geometry) else 'unvollständig'}")
    print(f"Wegbeläge: {'vorhanden' if props.get('extras', {}).get('surface') else 'nicht geliefert'}")
    print(f"Abbiegehinweise: {sum(len(s.get('steps', [])) for s in props.get('segments', []))}")
except httpx.RequestError:
    print("Der Routingdienst ist vom Mac aus gerade nicht erreichbar.")
    sys.exit(2)
except (ValueError, KeyError, IndexError, TypeError):
    print("Die Routing-Antwort konnte nicht vollständig ausgewertet werden.")
    sys.exit(3)
