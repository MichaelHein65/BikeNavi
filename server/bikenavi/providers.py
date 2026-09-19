import time
from uuid import uuid4

import httpx
from fastapi import HTTPException

from .models import RouteRequest

SURFACES = {0: "Unbekannt", 1: "Befestigt", 2: "Unbefestigt", 3: "Asphalt", 4: "Beton",
            5: "Kopfsteinpflaster", 6: "Metall", 7: "Holz", 8: "Fester Schotter",
            9: "Feiner Schotter", 10: "Schotter", 11: "Erde", 12: "Naturboden",
            13: "Eis / Schnee", 14: "Pflaster", 15: "Sand", 16: "Holzschnitzel",
            17: "Gras", 18: "Rasengitter"}
PAVED = {1, 3, 4, 5, 6, 14}


def parse_route(body: dict) -> dict:
    try:
        feature = body["features"][0]
        props = feature["properties"]
        coordinates = feature["geometry"]["coordinates"]
        summary = props["summary"]
        maneuvers = [{"instruction": step["instruction"], "distance": step["distance"],
                      "coordinateIndex": step["way_points"][0], "type": step["type"]}
                     for segment in props.get("segments", []) for step in segment.get("steps", [])]
        surface = props.get("extras", {}).get("surface", {}).get("summary", [])
        sections = []
        previous_end = 0
        for start, end, code in props.get("extras", {}).get("surface", {}).get("values", []):
            if not all(type(v) is int for v in (start, end, code)) or not previous_end <= start < end < len(coordinates) or code < 0:
                raise ValueError("Invalid surface geometry indices")
            sections.append({"startIndex": start, "endIndex": end, "surface": code})
            previous_end = end
        return {"id": str(uuid4()), "coordinates": [
                    {"longitude": c[0], "latitude": c[1], "altitude": c[2] if len(c) > 2 else None}
                    for c in coordinates],
                "distance": summary["distance"], "duration": summary["duration"],
                "ascent": props.get("ascent", 0), "descent": props.get("descent", 0),
                "maneuvers": maneuvers,
                "surfaces": [{"name": SURFACES.get(s["value"], "Unbekannt"),
                              "distance": s["distance"], "percentage": s["amount"]} for s in surface],
                "surfaceSections": sections,
                "warnings": [], "provider": "openrouteservice", "calculatedAt": time.time()}
    except (KeyError, IndexError, TypeError, ValueError) as error:
        raise HTTPException(502, "Der Routingdienst hat eine unvollständige Route geliefert.") from error


class ORS:
    def __init__(self, api_key: str, client: httpx.AsyncClient):
        self.key = api_key
        self.client = client

    async def request(self, method: str, path: str, **kwargs) -> dict:
        if not self.key:
            raise HTTPException(503, "Auf dem Pi fehlt noch der openrouteservice-API-Schlüssel. Kartenpunkte und Planungen kannst du bereits speichern.")
        try:
            response = await self.client.request(method, "https://api.openrouteservice.org" + path,
                                                 headers={"Authorization": self.key}, **kwargs)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as error:
            status = error.response.status_code
            if status == 429:
                raise HTTPException(429, "Das Routing-Kontingent ist gerade ausgeschöpft. Bitte später erneut versuchen.") from error
            if status in (401, 403):
                raise HTTPException(503, "Der Routing-Zugang ist nicht freigeschaltet oder sein Kontingent ist erschöpft.") from error
            if status in (400, 404):
                raise HTTPException(422, "Für diese Punkte konnte keine passende Route gefunden werden. Bitte Punkte näher an einen befahrbaren Weg setzen.") from error
            raise HTTPException(502, "Der Routingdienst ist vorübergehend nicht verfügbar.") from error
        except (httpx.RequestError, ValueError) as error:
            raise HTTPException(502, "Der Kartendienst ist gerade nicht erreichbar.") from error

    async def route(self, request: RouteRequest) -> dict:
        profile = request.profile
        bike = {"touring": "cycling-regular", "gravel": "cycling-regular",
                "mountain": "cycling-mountain", "road": "cycling-road"}[profile.bike]
        if profile.electric and profile.bike == "touring":
            bike = "cycling-electric"
        # The public ORS service does not support custom surface weightings. We
        # compare actual candidates and validate strict policies after routing.
        candidates = [bike]
        if profile.surface != "any" and bike != "cycling-road":
            candidates.append("cycling-road")
        results = []
        for candidate in candidates:
            options = {"avoid_features": ["steps"]}
            if profile.gentleHills:
                options["profile_params"] = {"weightings": {"steepness_difficulty": 0}}
            try:
                data = await self.request("POST", f"/v2/directions/{candidate}/geojson", json={
                    "coordinates": [[w.coordinate.longitude, w.coordinate.latitude] for w in request.waypoints],
                    "elevation": True, "instructions": True, "language": "de",
                    "extra_info": ["surface", "waytype", "steepness"], "options": options})
            except HTTPException as error:
                if error.status_code == 422:
                    continue
                raise
            route = parse_route(data)
            surface = data["features"][0]["properties"].get("extras", {}).get("surface", {}).get("summary", [])
            known_paved = sum(s["distance"] for s in surface if s["value"] in PAVED)
            undesirable = max(0, route["distance"] - known_paved)
            if profile.surface == "pavedOnly" and (not surface or undesirable > 1 or
                    any(s["value"] not in PAVED and s["distance"] > 0 for s in surface)):
                continue
            results.append((route["distance"] + (undesirable * 8 if profile.surface != "any" else 0), route))
        if not results:
            raise HTTPException(422, "Keine durchgehend als befestigt bekannte Route gefunden. Die Vorgabe wurde nicht gelockert. Du kannst Zwischenziele ändern oder unbekannte / unbefestigte Abschnitte erlauben.")
        route = min(results, key=lambda pair: pair[0])[1]
        if profile.surface == "preferPaved":
            route["warnings"].append("Befestigte Wege bevorzugt: Vergleich der verfügbaren Fahrrad- und Rennradrouten. Schotter oder unbekannte Abschnitte können enthalten sein.")
        if profile.bike == "gravel":
            route["warnings"].append("Gravel verwendet zunächst das Tourenradprofil. Die Beläge siehst du in der Streckenübersicht.")
        if not route["surfaces"]:
            route["warnings"].append("Für diese Route fehlen Angaben zur Wegbeschaffenheit.")
        return route

    async def search(self, text: str, lat: float | None, lon: float | None) -> list[dict]:
        params = {"text": text, "size": 8, "lang": "de"}
        if lat is not None and lon is not None:
            params.update({"focus.point.lat": lat, "focus.point.lon": lon})
        data = await self.request("GET", "/geocode/search", params=params)
        return [{"id": str(uuid4()), "name": f["properties"].get("label", "Ort"),
                 "coordinate": {"longitude": f["geometry"]["coordinates"][0],
                                "latitude": f["geometry"]["coordinates"][1]}}
                for f in data.get("features", [])]

    async def place_name(self, lat: float, lon: float) -> str | None:
        data = await self.request("GET", "/geocode/reverse", params={
            "point.lat": lat, "point.lon": lon, "size": 1, "lang": "de"})
        features = data.get("features", [])
        if not features:
            return None
        properties = features[0].get("properties", {})
        # A nearby feature supplies a human-readable label, never new routing coordinates.
        name = properties.get("label") or properties.get("name")
        return name.strip()[:300] if isinstance(name, str) and name.strip() else None
