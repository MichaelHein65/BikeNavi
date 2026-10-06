import asyncio
import copy
import json
import math
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
PAVED_ONLY_TOLERANCE_M = 100
# Keep the provider phase below the app's 90-second request timeout, even
# when comparing two profiles. Other services retain the shared 35 s timeout.
ROUTE_DEADLINE_SECONDS = 80
ROUTE_TIMEOUT = httpx.Timeout(75, connect=10)


def _distance_m(a: dict, b: dict) -> float:
    radians = math.pi / 180
    latitude = (a["latitude"] + b["latitude"]) * radians / 2
    x = (b["longitude"] - a["longitude"]) * radians * math.cos(latitude)
    y = (b["latitude"] - a["latitude"]) * radians
    return math.hypot(x, y) * 6_371_000


def _road_kind(highway: str) -> int:
    if highway in {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link"}:
        return 2
    if highway in {"tertiary", "tertiary_link", "residential", "unclassified", "living_street", "service", "road"}:
        return 1
    return 0


def parse_intersection_contexts(route: dict, elements: list[dict]) -> list[dict]:
    ways = []
    for element in elements:
        geometry = element.get("geometry")
        highway = element.get("tags", {}).get("highway")
        if element.get("type") != "way" or not isinstance(highway, str) or not isinstance(geometry, list):
            continue
        points = [{"latitude": point.get("lat"), "longitude": point.get("lon"), "altitude": None}
                  for point in geometry if isinstance(point, dict)]
        if len(points) >= 2 and all(isinstance(point["latitude"], (int, float)) and
                                    isinstance(point["longitude"], (int, float)) for point in points):
            ways.append((element.get("id"), _road_kind(highway), points))

    contexts = []
    seen_indices = set()
    for maneuver in route.get("maneuvers", []):
        index = maneuver.get("coordinateIndex")
        if maneuver.get("type") not in range(0, 10) or not isinstance(index, int) or index in seen_indices:
            continue
        if not 0 <= index < len(route["coordinates"]):
            continue
        seen_indices.add(index)
        center = route["coordinates"][index]
        candidates = []
        used = set()
        for way_id, kind, points in ways:
            nearest, distance = min(enumerate(points), key=lambda item: _distance_m(center, item[1]))
            meters = _distance_m(center, distance)
            if meters > 55:
                continue
            start, end = max(0, nearest - 4), min(len(points), nearest + 5)
            line = points[start:end]
            if len(line) < 2:
                continue
            key = way_id if way_id is not None else tuple((round(p["latitude"], 7), round(p["longitude"], 7)) for p in line)
            if key in used:
                continue
            used.add(key)
            candidates.append((meters, {"coordinates": line[:12], "kind": kind}))
        candidates.sort(key=lambda item: (item[0], -item[1]["kind"]))
        roads = [road for _, road in candidates[:10]]
        if roads:
            contexts.append({"coordinateIndex": index, "roads": roads})
    return contexts


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
                "waypointIndices": props.get("way_points"),
                "warnings": [], "provider": "openrouteservice", "calculatedAt": time.time()}
    except (KeyError, IndexError, TypeError, ValueError) as error:
        raise HTTPException(502, "Der Routingdienst hat eine unvollständige Route geliefert.") from error


ROAD_GAP_MAX_M = 250
ROAD_GAP_TOTAL_M = 500


def road_gap_edges(route, kinds):
    """Bounded missing surface tags between paved ordinary road sections.

    Keep original unknown surfaces in the response. This is a routing tolerance,
    never a claim that the missing pavement has been surveyed.
    """
    count = len(route["coordinates"]) - 1
    if kinds is None or len(kinds) != count:
        return set()
    surfaces = [-1] * count
    for section in route.get("surfaceSections") or []:
        for edge in range(section["startIndex"], section["endIndex"]):
            surfaces[edge] = section["surface"]
    allowed = set()
    total = 0.0
    start = 0
    while start < count:
        if surfaces[start] != 0:
            start += 1
            continue
        end = start + 1
        while end < count and surfaces[end] == 0:
            end += 1
        length = sum(_distance_m(a,b) for a,b in zip(route["coordinates"][start:end], route["coordinates"][start+1:end+1]))
        if (start > 0 and end < count and surfaces[start-1] in PAVED and surfaces[end] in PAVED
                and all(kind in (2,3) for kind in kinds[start-1:end+1]) and length <= ROAD_GAP_MAX_M):
            allowed.update(range(start,end))
            total += length
        start = end
    return allowed if total <= ROAD_GAP_TOTAL_M else set()


def optional_waytypes(data, route):
    # Normal cycling must retain existing behavior when extra-info is absent.
    from .hiking import waytypes
    try:
        return waytypes(data, route)
    except HTTPException:
        return None


class ORS:
    def __init__(self, api_key: str, client: httpx.AsyncClient, overpass_url: str = ""):
        self.key = api_key
        self.client = client
        self.overpass_url = overpass_url
        self.route_cache = {}

    async def request(self, method: str, path: str, **kwargs) -> dict:
        if not self.key:
            raise HTTPException(503, "Auf dem Pi fehlt noch der openrouteservice-API-Schlüssel. Kartenpunkte und Planungen kannst du bereits speichern.")
        cacheable = method == "POST" and path.startswith(("/v2/directions/", "/v2/snap/"))
        cache_key = (path, json.dumps(kwargs.get("json"), sort_keys=True))
        now = time.monotonic()
        self.route_cache = {k: v for k, v in self.route_cache.items() if now-v[0] < 300}
        if cacheable and cache_key in self.route_cache:
            return copy.deepcopy(self.route_cache[cache_key][1])
        url = ("https://api.heigit.org/pelias/v1" + path.removeprefix("/geocode")
               if path.startswith("/geocode/") else "https://api.heigit.org/openrouteservice" + path)
        try:
            response = await self.client.request(method, url,
                                                 headers={"Authorization": self.key}, **kwargs)
            response.raise_for_status()
            data = response.json()
            if cacheable:
                if len(self.route_cache) >= 128:
                    self.route_cache.pop(next(iter(self.route_cache)))
                self.route_cache[cache_key] = (time.monotonic(), copy.deepcopy(data))
            return data
        except httpx.HTTPStatusError as error:
            status = error.response.status_code
            quota_exceeded = False
            if status == 403:
                try:
                    quota_exceeded = error.response.json().get("error") == "Quota exceeded"
                except (ValueError, AttributeError):
                    pass
            if quota_exceeded:
                raise HTTPException(429, "Das Routing-Tageskontingent ist ausgeschöpft. Neue Berechnungen sind erst nach der Rücksetzung durch den Anbieter möglich.") from error
            if status == 429:
                raise HTTPException(429, "Das Routing-Kontingent ist gerade ausgeschöpft. Bitte später erneut versuchen.") from error
            if status in (401, 403):
                raise HTTPException(503, "Der Routing-Zugang ist nicht freigeschaltet oder sein Kontingent ist erschöpft.") from error
            if status in (400, 404):
                raise HTTPException(422, "Für diese Punkte konnte keine passende Route gefunden werden. Bitte Punkte näher an einen befahrbaren Weg setzen.") from error
            raise HTTPException(502, "Der Routingdienst ist vorübergehend nicht verfügbar.") from error
        except (httpx.RequestError, ValueError) as error:
            raise HTTPException(502, "Der Kartendienst ist gerade nicht erreichbar.") from error

    async def route(self, request: RouteRequest, include_context: bool = True, route_validator=None) -> dict:
        if request.profile.travelMode in {"hiking", "bikeAndHike"}:
            from .hiking import route_with_walking
            try:
                async with asyncio.timeout(ROUTE_DEADLINE_SECONDS):
                    route = await route_with_walking(self, request)
            except TimeoutError as error:
                raise HTTPException(502, "Die Rad-/Wandersuche hat ihr Zeitlimit erreicht. Bitte später erneut versuchen.") from error
            route["intersectionContexts"] = await self.intersection_contexts(route) if include_context else []
            return route
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
        async def fetch(candidate):
            options = {"avoid_features": ["steps"]}
            if profile.gentleHills:
                options["profile_params"] = {"weightings": {"steepness_difficulty": 0}}
            return await self.request("POST", f"/v2/directions/{candidate}/geojson", timeout=ROUTE_TIMEOUT, json={
                    "coordinates": [[w.coordinate.longitude, w.coordinate.latitude] for w in request.waypoints],
                    "elevation": True, "instructions": True, "language": "de",
                    "extra_info": ["surface", "waytype", "steepness"], "options": options})

        try:
            async with asyncio.timeout(ROUTE_DEADLINE_SECONDS):
                responses = await asyncio.gather(*(fetch(candidate) for candidate in candidates),
                                                 return_exceptions=True)
        except TimeoutError as error:
            raise HTTPException(502, "Der Kartendienst ist gerade nicht erreichbar.") from error

        results = []
        for data in responses:
            if isinstance(data, BaseException):
                if isinstance(data, HTTPException) and data.status_code == 422:
                    continue
                raise data
            route = parse_route(data)
            if route_validator is not None:
                try:
                    route_validator(data, route)
                except HTTPException as error:
                    if error.status_code == 422:
                        continue
                    raise
            surface = data["features"][0]["properties"].get("extras", {}).get("surface", {}).get("summary", [])
            known_paved = sum(s["distance"] for s in surface if s["value"] in PAVED)
            # Apply one budget to the whole route, including all legs and any
            # distance not covered by known paved surface information.
            undesirable = max(0, route["distance"] - known_paved,
                              sum(s["distance"] for s in surface if s["value"] not in PAVED))
            gap_edges = road_gap_edges(route, optional_waytypes(data, route)) if profile.surface == "pavedOnly" else set()
            gap_metres = sum(_distance_m(route["coordinates"][i], route["coordinates"][i+1]) for i in gap_edges)
            # Never exempt more than explicitly reported unknown surface metres;
            # omitted surface distances remain charged to the ordinary budget.
            gap_metres = min(gap_metres, sum(s["distance"] for s in surface if s["value"] == 0))
            budget_used = max(0, undesirable-gap_metres)
            if profile.surface == "pavedOnly" and (not surface or budget_used > PAVED_ONLY_TOLERANCE_M):
                continue
            if gap_metres > 0:
                route["warnings"].append(f"Belagslücken toleriert: etwa {math.ceil(gap_metres)} m unbekannter Belag auf Straßen zwischen bekannten befestigten Abschnitten (höchstens 250 m je Lücke und 500 m insgesamt). Der Belag bleibt unbekannt; vor Ort prüfen.")
            if profile.surface == "pavedOnly" and budget_used > 0:
                route["warnings"].append(f"Befestigte Wege mit Toleranz: zusätzlich insgesamt bis zu {math.ceil(budget_used)} m unbefestigte oder unbekannte Abschnitte (maximal 100 m pro Route).")
            results.append((route["distance"] + (undesirable * 8 if profile.surface != "any" else 0), route))
        if not results:
            raise HTTPException(422, "Keine passende Route gefunden. Bei „Nur bekannte befestigte Wege“ sind insgesamt höchstens 100 m unbefestigte oder unbekannte Abschnitte erlaubt; zusätzlich nur Straßen-Belagslücken bis 250 m zwischen befestigten Abschnitten (maximal 500 m insgesamt). Ändere die Zwischenziele oder wähle „Befestigte Wege bevorzugen“.")
        route = min(results, key=lambda pair: pair[0])[1]
        if profile.surface == "preferPaved":
            route["warnings"].append("Befestigte Wege bevorzugt: Vergleich der verfügbaren Fahrrad- und Rennradrouten. Schotter oder unbekannte Abschnitte können enthalten sein.")
        if profile.bike == "gravel":
            route["warnings"].append("Gravel verwendet zunächst das Tourenradprofil. Die Beläge siehst du in der Streckenübersicht.")
        if not route["surfaces"]:
            route["warnings"].append("Für diese Route fehlen Angaben zur Wegbeschaffenheit.")
        route["intersectionContexts"] = await self.intersection_contexts(route) if include_context else []
        return route

    async def intersection_contexts(self, route: dict) -> list[dict]:
        if not self.overpass_url:
            return []
        targets = []
        seen = set()
        for maneuver in route.get("maneuvers", []):
            index = maneuver.get("coordinateIndex")
            if maneuver.get("type") in range(0, 10) and isinstance(index, int) and index not in seen and 0 <= index < len(route["coordinates"]):
                seen.add(index)
                targets.append(route["coordinates"][index])
        if not targets:
            return []
        elements = {}
        for offset in range(0, len(targets), 30):
            clauses = "\n".join(
                f'way(around:45,{point["latitude"]:.7f},{point["longitude"]:.7f})["highway"];'
                for point in targets[offset:offset + 30]
            )
            query = f"[out:json][timeout:20];({clauses});out tags geom;"
            try:
                response = await self.client.post(self.overpass_url, data={"data": query},
                                                  headers={"User-Agent": "BikeNavi/0.1 personal cycling navigation"})
                response.raise_for_status()
                for element in response.json().get("elements", []):
                    if isinstance(element, dict):
                        elements[(element.get("type"), element.get("id"))] = element
            except (httpx.HTTPError, ValueError, TypeError, AttributeError):
                continue
        return parse_intersection_contexts(route, list(elements.values()))

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
