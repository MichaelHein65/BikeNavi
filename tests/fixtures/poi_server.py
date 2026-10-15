"""Local synthetic public POI examples for UI tests; no upstream or private data."""
import json
import time
from pathlib import Path
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request

app = FastAPI()
ROUTE = json.loads((Path(__file__).resolve().parents[2] / "ios/BikeNavi/PreviewData/heidelberg-car-route.json").read_text())


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/pois/search")
async def search(request: Request):
    body = await request.json()
    if request.headers.get("Authorization") != "Bearer public-poi-example-token":
        raise HTTPException(401)
    fuel = body["category"] == "fuel"
    items = [{"id": f"example-{index}", "name": f"Beispiel · {'Tankstelle' if fuel else 'Ort'} {index + 1}",
              "coordinate": ROUTE["coordinates"][min(len(ROUTE["coordinates"]) - 1, 8 + index * 3)], "country": "DE",
              "dieselPrice": 1.699 + index * 0.02 if fuel else None, "isOpen": True,
              "address": "Heidelberg · synthetisches Beispiel", "openingHours": "Nur Demonstrationsdaten",
              "source": "Synthetische öffentliche Beispieldaten", "sourceURL": "https://example.org/",
              "priceTimestamp": None, "fetchedAt": time.time(), "drivingDistance": 1200 + index * 500,
              "drivingSeconds": 180 + index * 60, "detourSeconds": 120 + index * 60 if body.get("context") else None}
             for index in range(3)]
    if not fuel:
        title = {"supermarket": "Supermarkt", "airport": "Terminal", "station": "Bahnhof", "beach": "Strand", "parking": "Parkplatz"}[body["category"]]
        for item in items:
            item["name"] = "Beispiel · " + title
            item["isOpen"] = None
            item["placeCoordinate"] = dict(item["coordinate"], latitude=item["coordinate"]["latitude"] + 0.00112)
            item["arrivalCoordinate"] = item["coordinate"]
            item["accessDistance"] = 125
            item["address"] += " · Pkw-Zielpunkt etwa 125 m Luftlinie vom kartierten Ort. Zugang vor Ort prüfen; Fußweg und Restzeit nicht berechnet."
            item["source"] = "Geoapify · OSM · synthetisches UI-Beispiel"
    if body.get("profile", {}).get("travelMode") != "car":
        if body.get("context"):
            raise HTTPException(422, "Non-car searches must not send a car corridor")
        for item in items:
            item["coordinate"] = item.pop("placeCoordinate", item["coordinate"])
            item.pop("arrivalCoordinate", None)
            item.pop("accessDistance", None)
            item["address"] = "Heidelberg · synthetisches Beispiel"
            item["airDistance"] = 750
            item["drivingDistance"] = 0
            item["drivingSeconds"] = 0
    return {"items": items, "unpriced": [], "scope": "Beispiel · entlang der Route" if body.get("context") else "Beispiel · Umkreis 10 km",
            "notices": ["BEISPIELDATEN · Keine echten Angebote oder bestätigten Zufahrten."], "searchedAt": time.time()}


@app.post("/v1/route")
async def route(request: Request):
    body = await request.json()
    points = [waypoint["coordinate"] for waypoint in body["waypoints"]]
    return {**ROUTE, "id": str(uuid4()), "coordinates": points, "waypointIndices": list(range(len(points))),
            "maneuvers": [], "surfaceSections": [], "carTimeSections": [{"startIndex": 0, "endIndex": len(points) - 1, "seconds": 180}],
            "provider": "Synthetisches POI-Beispiel", "warnings": ["Keine echte Straßenroute"], "elevationProfile": None}
