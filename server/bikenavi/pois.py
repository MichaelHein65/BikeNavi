import asyncio
import gzip
import json
import math
import time
from bisect import bisect_left
from email.utils import parsedate_to_datetime
from typing import Literal
from uuid import uuid4

import httpx
from fastapi import HTTPException
from pydantic import Field
from shapely.geometry import LineString, Point
from shapely.ops import substring

from .models import Coordinate, Model, Profile, RouteRequest, Waypoint


class POIRouteContext(Model):
    coordinates: list[Coordinate] = Field(min_length=2, max_length=100_000)
    progress: float = Field(ge=0)
    pending: list[Waypoint] = Field(min_length=1, max_length=47)
    bearing: float | None = Field(default=None, ge=0, lt=360)


class POISearch(Model):
    category: Literal["fuel", "supermarket", "airport", "station", "beach", "parking"] = "fuel"
    center: Coordinate
    radius: Literal[10, 25] = 10
    profile: Profile = Field(default_factory=lambda: Profile(travelMode="car"))
    context: POIRouteContext | None = None


class POIStopRequest(Model):
    search: POISearch
    stop: Waypoint


SOURCES = {
    "DE": ("Tankerkönig · MTS-K · CC BY 4.0", "https://creativecommons.tankerkoenig.de/"),
    "AT": ("E-Control · Spritpreisrechner", "https://www.spritpreisrechner.at/"),
    "SI": ("goriva.si · öffentliches Preisportal", "https://goriva.si/"),
    "HR": ("Min2Go · öffentliches Preisportal", "https://www.mzoe-gor.hr/"),
}
BOUNDS = {"DE": (47.2, 55.1, 5.8, 15.1), "AT": (46.3, 49.1, 9.5, 17.2),
          "SI": (45.4, 46.9, 13.3, 16.6), "HR": (42.3, 46.6, 13.4, 19.5)}
TAGS = {"fuel": '"amenity"="fuel"', "supermarket": '"shop"="supermarket"',
        "airport": '"aeroway"="aerodrome"', "station": '"railway"="station"',
        "beach": '"natural"="beach"', "parking": '"amenity"="parking"'}
PLACE_CATEGORIES = {"supermarket": "commercial.supermarket", "airport": "airport.terminal",
                    "station": "public_transport.train", "beach": "beach", "parking": "parking"}
PLACE_NAMES = {"supermarket": "Supermarkt", "airport": "Flughafenterminal", "station": "Bahnhof",
               "beach": "Strand", "parking": "Parkplatz"}


class POISourceError(Exception):
    pass


def distance(first, second):
    latitude = math.radians(second.latitude - first.latitude)
    longitude = math.radians(second.longitude - first.longitude)
    square = math.sin(latitude / 2) ** 2 + math.cos(math.radians(first.latitude)) * math.cos(math.radians(second.latitude)) * math.sin(longitude / 2) ** 2
    return 6_371_000 * 2 * math.atan2(math.sqrt(min(1, square)), math.sqrt(max(0, 1 - square)))


def price(value):
    if isinstance(value, bool):
        return None
    try:
        amount = float(value)
        return amount if math.isfinite(amount) and 0.1 <= amount <= 10 else None
    except (TypeError, ValueError):
        return None


def station(country, identifier, name, latitude, longitude, amount=None, opened=None, address="", hours=None):
    source, url = SOURCES[country]
    return {"id": country + ":" + str(identifier), "name": str(name or "Tankstelle")[:300],
            "coordinate": Coordinate(latitude=latitude, longitude=longitude).model_dump(),
            "country": country, "dieselPrice": price(amount), "isOpen": opened if isinstance(opened, bool) else None,
            "address": address, "openingHours": hours, "source": source, "sourceURL": url,
            "priceTimestamp": None}


class RouteCorridor:
    def __init__(self, search):
        self.search = search
        self.scale = 111_195 * math.cos(math.radians(search.center.latitude))
        coordinates = search.context.coordinates
        cumulative = [0.0]
        for first, second in zip(coordinates, coordinates[1:]):
            cumulative.append(cumulative[-1] + distance(first, second))
        start = search.context.progress
        lower = max(0, bisect_left(cumulative, max(0, start - 500)) - 1)
        upper = min(len(coordinates) - 1, bisect_left(cumulative, start + 50_000))
        if upper <= lower or abs(search.center.latitude) > 85:
            raise HTTPException(409, "Kein geeigneter Routenabschnitt voraus.")
        line = LineString([self.xy(point) for point in coordinates[lower:upper + 1]])
        current = Point(self.xy(search.center))
        actual = line.project(current)
        if abs(actual - (start - cumulative[lower])) > 250 or line.distance(current) > 50:
            raise HTTPException(409, "Standort passt nicht mehr zur Route. Bitte erneut suchen.")
        self.line = substring(line, max(0, actual - 500), min(line.length, actual + 50_000)).simplify(3)
        if not isinstance(self.line, LineString) or self.line.length < 50:
            raise HTTPException(409, "Kein geeigneter Routenabschnitt voraus.")
        self.start = self.line.project(current)
        self.end = self.line.length

    def xy(self, point):
        return point.longitude * self.scale, point.latitude * 111_195

    def center(self):
        point = self.line.interpolate((self.start + self.end) / 2)
        return Coordinate(latitude=point.y / 111_195, longitude=point.x / self.scale)

    def ahead(self, coordinate):
        point = Point(self.xy(coordinate))
        progress = self.line.project(point)
        return self.start + 50 < progress <= self.end and self.line.distance(point) <= 3_000

    def forward(self, route):
        if any(step["type"] == 9 for step in route["maneuvers"]):
            return False
        maximum = self.start
        west, south, east, north = self.line.bounds
        for coordinate in route["coordinates"]:
            point = Point(self.xy(Coordinate.model_validate(coordinate)))
            if not west - 60 <= point.x <= east + 60 or not south - 60 <= point.y <= north + 60:
                continue
            if self.line.distance(point) > 60:
                continue
            progress = self.line.project(point)
            if progress < maximum - 60:
                return False
            maximum = max(maximum, progress)
        return True


class POIService:
    def __init__(self, client, ors, overpass_url, tanker_key="", storage=None, places_key=""):
        self.client = client
        self.ors = ors
        self.overpass_url = overpass_url
        self.tanker_key = tanker_key
        self.storage = storage
        self.places_key = places_key
        self.places_next = 0.0
        self.places_retry_at = 0.0
        self.cache = {}
        self.lock = asyncio.Lock()
        self.tanker_next = 0.0
        self.tanker_lock = asyncio.Lock()
        self.tanker_snapshots = []
        self.osm_retry_at = 0.0
        self.search_slots = asyncio.Semaphore(2)

    async def cached(self, key, loader, seconds=120):
        async with self.lock:
            now = time.monotonic()
            cached = self.cache.get(key)
            if cached and now - cached[0] < seconds:
                return cached[1], cached[2]
            result = await loader()
            stamp = time.time()
            self.cache = {name: entry for name, entry in self.cache.items() if now - entry[0] < 300}
            if len(self.cache) >= 64:
                self.cache.pop(next(iter(self.cache)))
            self.cache[key] = (time.monotonic(), result, stamp)
            return result, stamp

    async def get_json(self, url, params=None):
        response = await self.client.get(url, params=params, timeout=15)
        response.raise_for_status()
        return response.json()

    async def german_stations(self, center, radius, notices):
        if not self.tanker_key:
            raise ValueError("Deutschland: Tankerkönig-Schlüssel fehlt auf dem Pi.")
        async with self.tanker_lock:
            now = time.time()
            self.tanker_snapshots = [snapshot for snapshot in self.tanker_snapshots if 0 <= now - snapshot["stamp"] <= 300]
            covered = [snapshot for snapshot in self.tanker_snapshots
                       if distance(center, snapshot["center"]) + radius * 1000 <= 25_000]
            fresh = [snapshot for snapshot in covered if now - snapshot["stamp"] < 120]
            snapshot = max(fresh, key=lambda entry: entry["stamp"]) if fresh else None
            wait = max(0, self.tanker_next - time.monotonic())
            if snapshot is None:
                if wait <= 0 and self.storage is not None:
                    next_allowed = self.storage.reserve_provider_request("tankerkoenig", now, 61)
                    wait = max(0, next_allowed - now) if next_allowed is not None else 0
                if wait <= 0:
                    self.tanker_next = time.monotonic() + 61
                    try:
                        data = await self.get_json("https://creativecommons.tankerkoenig.de/json/list.php", {
                            "lat": center.latitude, "lng": center.longitude, "rad": 25,
                            "type": "diesel", "sort": "price", "apikey": self.tanker_key})
                        if data.get("ok") is not True:
                            raise ValueError("Preisdienst hat die Anfrage abgelehnt.")
                        items = [station("DE", item["id"], item["name"], item["lat"], item["lng"],
                                         item.get("price"), item.get("isOpen"),
                                         " ".join(str(item.get(key, "")) for key in ["street", "houseNumber", "place"]))
                                 for item in data["stations"]]
                        snapshot = {"center": center, "stamp": time.time(), "items": items}
                        self.tanker_snapshots = (self.tanker_snapshots + [snapshot])[-8:]
                        return [dict(item, fetchedAt=snapshot["stamp"]) for item in items
                                if distance(center, Coordinate.model_validate(item["coordinate"])) <= radius * 1000]
                    except Exception:
                        notices.append("Deutschland: Preisabruf fehlgeschlagen; kein sofortiger Wiederholungsabruf.")
                    now = time.time()
                    wait = max(0, self.tanker_next - time.monotonic())
                self.tanker_snapshots = [entry for entry in self.tanker_snapshots if 0 <= now - entry["stamp"] <= 300]
                relevant = [entry for entry in self.tanker_snapshots
                            if distance(center, entry["center"]) <= 25_000 + radius * 1000]
                snapshot = max(relevant, key=lambda entry: (
                    distance(center, entry["center"]) + radius * 1000 <= 25_000, entry["stamp"])) if relevant else None
                if wait > 0:
                    notices.append(f"Deutschland: höchstens eine Preisabfrage pro Minute. Erneuter Abruf frühestens in {math.ceil(wait)} Sekunden; Details und Routenwahl benötigen keinen Preisabruf.")
            if snapshot is None:
                notices.append("Deutschland: keine verwendbaren Preisdaten für dieses Gebiet im Zwischenspeicher.")
                return []
            age = max(0, int(time.time() - snapshot["stamp"]))
            notices.append(f"Deutschland: gespeicherte Preisdaten, abgerufen vor {age} Sekunden; kein neuer Preisabruf.")
            if distance(center, snapshot["center"]) + radius * 1000 > 25_000:
                notices.append("Deutschland: das neue Suchgebiet ist nur teilweise durch gespeicherte Daten abgedeckt.")
            return [dict(item, fetchedAt=snapshot["stamp"], isOpen=item["isOpen"] if age < 120 else None)
                    for item in snapshot["items"]
                    if distance(center, Coordinate.model_validate(item["coordinate"])) <= radius * 1000]

    async def country_stations(self, country, center, radius, notices=None):
        if country == "DE":
            return await self.german_stations(center, radius, notices if notices is not None else [])
        async def load():
            if country == "AT":
                data = await self.get_json("https://api.e-control.at/sprit/1.0/search/gas-stations/by-address", {
                    "latitude": center.latitude, "longitude": center.longitude, "fuelType": "DIE", "includeClosed": "false"})
                return [station(country, item["id"], item["name"], item["location"]["latitude"], item["location"]["longitude"],
                                next((value.get("amount") for value in item.get("prices", []) if value.get("fuelType") == "DIE"), None),
                                item.get("open"), item["location"].get("address", "")) for item in data]
            if country == "SI":
                items = []
                for page in range(1, 21):
                    data = await self.get_json("https://goriva.si/api/v1/search/", {
                        "position": f"{center.latitude},{center.longitude}", "radius": radius * 1000, "page": page})
                    items.extend(data["results"])
                    if not data.get("next"):
                        break
                else:
                    raise ValueError("Slowenien: Suchgebiet enthält zu viele Ergebnisse. Bitte kleiner suchen.")
                return [station(country, item["pk"], item["name"], item["lat"], item["lng"],
                                item.get("prices", {}).get("dizel"), address=item.get("address", ""),
                                hours=item.get("open_hours")) for item in items]
            response = await self.client.get("https://webservis.mzoe-gor.hr/data.gz", timeout=20)
            response.raise_for_status()
            if len(response.content) > 5_000_000:
                raise ValueError("Kroatien: unerwartete Datengröße.")
            import io
            with gzip.GzipFile(fileobj=io.BytesIO(response.content)) as compressed:
                content = compressed.read(12_000_001)
            if len(content) > 12_000_000:
                raise ValueError("Kroatien: unerwartete Datengröße.")
            data = json.loads(content)
            types = {item["id"] for item in data["vrsta_gorivas"] if (item.get("vrsta_goriva") or "").lower() == "eurodizel bez aditiva"}
            fuels = {item["id"] for item in data["gorivos"] if item["vrsta_goriva_id"] in types
                     and item.get("naziv") and not any(word in item["naziv"].lower() for word in ["premium", "maxpower", "class", "plavi", "test", "nije u portfelju"])}
            result = []
            for item in data["postajas"]:
                try:
                    amounts = [price(value["cijena"]) for value in item["cjenici"] if value["gorivo_id"] in fuels]
                    amounts = [value for value in amounts if value is not None]
                    result.append(station(country, item["id"], item["naziv"], float(str(item.get("long") or "").replace(",", ".")),
                                          float(str(item.get("lat") or "").replace(",", ".")), min(amounts) if amounts else None,
                                          address=(item.get("adresa") or "") + ", " + (item.get("mjesto") or "")))
                except (ValueError, TypeError):
                    continue
            return result

        key = (country,) if country == "HR" else (country, round(center.latitude, 5), round(center.longitude, 5), radius)
        items, stamp = await self.cached(key, load)
        return [dict(item, fetchedAt=stamp) for item in items
                if distance(center, Coordinate.model_validate(item["coordinate"])) <= radius * 1000]

    async def osm(self, search, center, radius):
        if not self.overpass_url:
            raise POISourceError("Der OSM-Ortedienst ist auf dem Pi nicht eingerichtet.")
        async def load():
            wait = self.osm_retry_at - time.monotonic()
            if wait > 0:
                raise POISourceError(f"Der OSM-Ortedienst pausiert nach einem Fehler. Bitte frühestens in {math.ceil(wait)} Sekunden erneut suchen; Tankerkönig ist davon unabhängig.")
            query = f'[out:json][timeout:18];nwr(around:{radius * 1000},{center.latitude},{center.longitude})[{TAGS[search.category]}];out center 150;'
            try:
                response = await self.client.post(self.overpass_url, data={"data": query}, timeout=22,
                    headers={"User-Agent": "BikeNavi/0.4 (+https://github.com/MichaelHein65/BikeNavi)",
                             "Accept": "application/json"})
                response.raise_for_status()
                data = response.json()
                if not isinstance(data, dict) or data.get("remark") or not isinstance(data.get("elements"), list):
                    raise ValueError("Incomplete OSM response")
            except (httpx.HTTPError, ValueError) as error:
                pause = 30
                if isinstance(error, httpx.HTTPStatusError):
                    retry = error.response.headers.get("Retry-After", "")
                    try:
                        pause = max(pause, int(retry) if retry.isdigit() else parsedate_to_datetime(retry).timestamp() - time.time())
                    except (ValueError, TypeError, OverflowError):
                        pass
                self.osm_retry_at = time.monotonic() + pause
                raise POISourceError(f"Der OSM-Ortedienst antwortet derzeit nicht zuverlässig. Bitte frühestens in {math.ceil(pause)} Sekunden erneut suchen. Tankerkönig und die bisherige Route bleiben davon unabhängig.") from None
            result = []
            for item in data["elements"]:
                tags = item.get("tags", {})
                if tags.get("access") in ["private", "no"] or tags.get("disused") == "yes":
                    continue
                coordinate = item.get("center", item)
                result.append({"id": f'OSM:{item["type"]}:{item["id"]}', "name": tags.get("name", tags.get("brand", "Ort ohne Namen")),
                               "coordinate": Coordinate(latitude=coordinate["lat"], longitude=coordinate["lon"]).model_dump(),
                               "country": "", "dieselPrice": None, "isOpen": None, "address": tags.get("addr:street", ""),
                               "openingHours": tags.get("opening_hours"), "priceTimestamp": None,
                               "source": "© OpenStreetMap-Mitwirkende · ODbL", "sourceURL": "https://www.openstreetmap.org/copyright"})
            return result
        items, stamp = await self.cached((search.category, round(center.latitude, 5), round(center.longitude, 5), radius), load)
        return [dict(item, fetchedAt=stamp) for item in items]

    async def places(self, search, center, radius):
        if not self.places_key:
            raise POISourceError("Für Supermarkt, Flughafen, Bahnhof, Strand und Parkplatz fehlt noch der Geoapify-Schlüssel auf dem Pi.")
        async def load():
            wait = self.places_retry_at - time.monotonic()
            if wait > 0:
                raise POISourceError(f"Geoapify pausiert nach einem Fehler. Bitte in {math.ceil(wait)} Sekunden erneut suchen.")
            await asyncio.sleep(max(0, self.places_next - time.monotonic()))
            if self.storage is not None:
                next_allowed = self.storage.reserve_provider_request("geoapify", time.time(), 1)
                if next_allowed is not None:
                    raise POISourceError("Die Ortesuche wird gerade verwendet. Bitte in einer Sekunde erneut versuchen.")
            self.places_next = time.monotonic() + 1
            try:
                response = await self.client.get("https://api.geoapify.com/v2/places", params={
                    "apiKey": self.places_key, "categories": PLACE_CATEGORIES[search.category],
                    "filter": f"circle:{center.longitude},{center.latitude},{radius * 1000}",
                    "bias": f"proximity:{search.center.longitude},{search.center.latitude}",
                    "limit": 20, "lang": "de"}, timeout=30,
                    headers={"User-Agent": "BikeNavi/0.4 (+https://github.com/MichaelHein65/BikeNavi)"})
                response.raise_for_status()
                data = response.json()
                if not isinstance(data, dict) or not isinstance(data.get("features"), list):
                    raise ValueError("Invalid places response")
            except (httpx.HTTPError, ValueError) as error:
                pause = 30
                message = "Geoapify ist vorübergehend nicht erreichbar."
                if isinstance(error, httpx.HTTPStatusError):
                    status = error.response.status_code
                    if status in (401, 403):
                        message = "Geoapify-Zugang oder Kontingent ist nicht freigegeben. Bitte den Schlüssel und Tarif prüfen."
                        pause = 300
                    elif status == 429:
                        message = "Das Geoapify-Kontingent ist vorübergehend ausgeschöpft."
                    retry = error.response.headers.get("Retry-After", "")
                    try:
                        pause = max(pause, int(retry) if retry.isdigit() else parsedate_to_datetime(retry).timestamp() - time.time())
                    except (ValueError, TypeError, OverflowError):
                        pass
                self.places_retry_at = time.monotonic() + pause
                raise POISourceError(f"{message} Erneuter Abruf frühestens in {math.ceil(pause)} Sekunden; die bisherige Route bleibt erhalten.") from None
            result, seen, locations, valid_features = [], set(), set(), 0
            for feature in data["features"][:20]:
                try:
                    properties = feature["properties"]
                    identifier = properties["place_id"]
                    categories = properties.get("categories", [])
                    if not isinstance(identifier, str) or identifier in seen or not isinstance(categories, list):
                        continue
                    coordinate = Coordinate(latitude=properties["lat"], longitude=properties["lon"])
                    valid_features += 1
                    if PLACE_CATEGORIES[search.category] not in categories:
                        continue
                    if any(value in categories for value in ["no_access", "access_limited.private", "access_limited.with_permit", "access_limited.services", "airport.military", "airport.private", "public_transport.platform"]):
                        continue
                    raw = properties.get("datasource", {}).get("raw", {})
                    if raw.get("access") in ("no", "private") or raw.get("public_transport") in ("platform", "stop_position"):
                        continue
                    if distance(center, coordinate) > radius * 1000:
                        continue
                    name = properties.get("name") or PLACE_NAMES[search.category]
                    address = properties.get("address_line2") or properties.get("formatted") or ""
                    if not isinstance(name, str) or not isinstance(address, str):
                        continue
                    location = (name.casefold(), round(coordinate.latitude, 5), round(coordinate.longitude, 5))
                    if location in locations:
                        continue
                    locations.add(location)
                    seen.add(identifier)
                    result.append({"id": "Geoapify:" + identifier, "name": name[:300], "coordinate": coordinate.model_dump(),
                                   "country": str(properties.get("country_code") or "").upper()[:2],
                                   "dieselPrice": None, "isOpen": None, "address": address[:1000], "openingHours": None,
                                   "priceTimestamp": None, "source": "Geoapify · © OpenStreetMap-Mitwirkende · ODbL",
                                   "sourceURL": "https://www.geoapify.com/places-api/"})
                except (KeyError, TypeError, ValueError, AttributeError):
                    continue
            if data["features"] and not valid_features:
                self.places_retry_at = time.monotonic() + 30
                raise POISourceError("Geoapify lieferte unlesbare Ortsdaten. Bitte frühestens in 30 Sekunden erneut versuchen.")
            return result
        key = ("geoapify", search.category, round(center.latitude, 5), round(center.longitude, 5), radius,
               round(search.center.latitude, 5), round(search.center.longitude, 5))
        items, stamp = await self.cached(key, load, seconds=300)
        return [dict(item, fetchedAt=stamp) for item in items]

    async def route_to_stop(self, search, stop, baseline=None):
        if search.profile.travelMode != "car":
            raise HTTPException(422, "Die POI-Anfahrt benötigt das Auto-Profil.")
        context = search.context
        corridor = RouteCorridor(search) if context else None
        if corridor and not corridor.ahead(stop.coordinate):
            raise HTTPException(409, "Dieser Ort liegt nicht mehr im Suchabschnitt voraus.")
        origin = Waypoint(id=uuid4(), name="Aktueller Standort", coordinate=search.center)
        arrival = stop
        if search.category != "fuel" and context:
            approach = await self.ors.car_route(RouteRequest(waypoints=[origin, stop], profile=search.profile,
                                                           startBearing=context.bearing))
            arrival = stop.model_copy(update={"coordinate": Coordinate.model_validate(approach["coordinates"][-1])})
            if distance(stop.coordinate, arrival.coordinate) > 350 or not corridor.ahead(arrival.coordinate):
                raise HTTPException(422, "Kein geeigneter Pkw-Zielpunkt voraus bestätigt.")
        route = await self.ors.car_route(RouteRequest(waypoints=[origin, arrival] + (context.pending if context else []),
                                                      profile=search.profile, startBearing=context.bearing if context else None))
        index = route["waypointIndices"][1]
        arrival_coordinate = Coordinate.model_validate(route["coordinates"][index])
        access_distance = distance(stop.coordinate, arrival_coordinate)
        if access_distance > (25 if search.category == "fuel" else 350):
            raise HTTPException(422, "Eine ausreichend genaue Pkw-Zufahrt ist nicht bestätigt.")
        if corridor and not corridor.ahead(arrival_coordinate):
            raise HTTPException(422, "Der Pkw-Zielpunkt liegt nicht mehr voraus.")
        seconds = sum(part["seconds"] for part in route["carTimeSections"] if part["endIndex"] <= index)
        extra = None
        if corridor:
            if baseline is None:
                baseline = await self.ors.car_route(RouteRequest(waypoints=[origin] + context.pending, profile=search.profile,
                                                               startBearing=context.bearing))
            extra = max(0, route["duration"] - baseline["duration"])
            if extra > 600 or not corridor.forward(route):
                raise HTTPException(422, "Anfahrt erfordert Rückfahrt, Wendemanöver oder mehr als zehn Minuten Umweg.")
        approach = route["coordinates"][:index + 1]
        meters = sum(distance(Coordinate.model_validate(first), Coordinate.model_validate(second)) for first, second in zip(approach, approach[1:]))
        return {"route": route, "drivingDistance": meters, "drivingSeconds": seconds, "detourSeconds": extra,
                "arrivalCoordinate": arrival_coordinate.model_dump(), "accessDistance": access_distance}

    async def search(self, search):
        async with self.search_slots:
            try:
                async with asyncio.timeout(85):
                    return await self._search(search)
            except TimeoutError:
                raise HTTPException(504, "Ortesuche dauert zu lange. Die bisherige Route bleibt erhalten.") from None

    async def _search(self, search):
        if search.profile.travelMode != "car" and search.context:
            raise HTTPException(422, "Routenkorridore sind nur für das Auto verfügbar. Andere Profile verwenden die Umkreissuche.")
        corridor = RouteCorridor(search) if search.context else None
        center, radius = (corridor.center(), 25) if corridor else (search.center, search.radius)
        notices, items = [], []
        if search.category == "fuel":
            countries = [country for country, (south, north, west, east) in BOUNDS.items()
                         if south - radius / 111 <= center.latitude <= north + radius / 111
                         and west - radius / 70 <= center.longitude <= east + radius / 70]
            for country in countries:
                try:
                    items.extend(await self.country_stations(country, center, radius, notices))
                except ValueError as error:
                    notices.append(str(error) if str(error).startswith(("Deutschland:", "Slowenien:", "Kroatien:")) else f"{country}: Preisdaten nicht lesbar.")
                except Exception:
                    notices.append(f"{country}: Preisdienst derzeit nicht erreichbar.")
            notices.append("Diesel · günstigste geprüfte Treffer der gelieferten Auswahl, keine vollständige Marktübersicht. Preisstand unbekannt; Abrufzeit ist kein Preiszeitpunkt.")
            if any(item["country"] in ["SI", "HR"] for item in items):
                notices.append("Slowenien/Kroatien: experimentelle Portalanbindung; Öffnungsstatus unbekannt.")
            if not items:
                try:
                    items = await self.osm(search, center, radius)
                    notices.append("Nur Tankstellenstandorte · Dieselangebot und Preise nicht bestätigt.")
                except Exception:
                    notices.append("Auch die Tankstellenstandorte sind derzeit nicht verfügbar.")
        else:
            try:
                items = await self.places(search, center, radius)
            except POISourceError as error:
                return {"items": [], "unpriced": [], "notices": [str(error)],
                        "scope": "Ortesuche nicht verfügbar", "searchedAt": time.time()}
            except Exception:
                return {"items": [], "unpriced": [], "notices": ["Ortedaten konnten nicht verarbeitet werden. Bitte später erneut versuchen."],
                        "scope": "Ortesuche nicht verfügbar", "searchedAt": time.time()}
            notices.append("Orte von Geoapify · © OpenStreetMap-Mitwirkende · ODbL (openstreetmap.org/copyright). Begrenzte Auswahl von bis zu 20 Treffern, keine vollständige Übersicht.")
            if search.category == "airport":
                notices.append("Suche nach kartierten Flughafenterminals, nicht nach Startbahnen oder Flugplatzmittelpunkten. Terminal und Zugang vor Ort prüfen.")
        items = [item for item in items if item["isOpen"] is not False
                 and (not corridor or corridor.ahead(Coordinate.model_validate(item["coordinate"])))]
        items.sort(key=lambda item: (item["dieselPrice"] is None, item["dieselPrice"] or 0,
                                    distance(search.center, Coordinate.model_validate(item["coordinate"]))))
        if search.profile.travelMode != "car":
            nearby = [dict(item, airDistance=distance(search.center, Coordinate.model_validate(item["coordinate"])),
                           drivingDistance=0, drivingSeconds=0, detourSeconds=None)
                      for item in items
                      if distance(search.center, Coordinate.model_validate(item["coordinate"])) <= radius * 1000]
            found = [item for item in nearby if search.category != "fuel" or item["dieselPrice"] is not None][:3]
            unpriced = [item for item in nearby if search.category == "fuel" and item["dieselPrice"] is None][:3]
            notices.append("Entfernungen sind Luftlinien zum kartierten Ort, keine bestätigten Wege oder Reisezeiten. Suche im Umkreis, nicht entlang der Route.")
            if search.profile.travelMode == "sea":
                notices.append("Landorte für den Landgang: keine bestätigten Anlegestellen oder Bootstankstellen. Nicht automatisch als Wasserwegpunkt verwenden.")
            else:
                notices.append("Die Route zum gewählten Ort wird erst in der Planung mit deinem Fortbewegungsprofil geprüft.")
            if not found and not unpriced:
                notices.append("Keine Orte dieser Kategorie im Suchgebiet geliefert. Suchgebiet erweitern.")
            return {"items": found, "unpriced": unpriced, "notices": notices,
                    "scope": f"Umkreis {radius} km · Luftlinie", "searchedAt": time.time()}
        baseline = None
        if corridor:
            origin = Waypoint(id=uuid4(), name="Aktueller Standort", coordinate=search.center)
            baseline = await self.ors.car_route(RouteRequest(waypoints=[origin] + search.context.pending,
                profile=search.profile, startBearing=search.context.bearing))
        found, unpriced = [], []
        for item in items[:18]:
            if len(found) >= 3 and (search.category != "fuel" or item["dieselPrice"] is None
                                    or item["dieselPrice"] > found[-1]["dieselPrice"]):
                break
            stop = Waypoint(id=uuid4(), name=item["name"], coordinate=Coordinate.model_validate(item["coordinate"]))
            try:
                checked = await self.route_to_stop(search, stop, baseline)
            except HTTPException as error:
                if error.status_code in [401, 403, 429, 503]:
                    notices.append(str(error.detail))
                    break
                continue
            except Exception:
                continue
            result = dict(item, **{key: value for key, value in checked.items() if key != "route"})
            if search.category != "fuel":
                result["placeCoordinate"] = item["coordinate"]
                result["coordinate"] = checked["arrivalCoordinate"]
                if checked["accessDistance"] > 20:
                    result["address"] += f" · Pkw-Zielpunkt etwa {math.ceil(checked['accessDistance'])} m Luftlinie vom kartierten Ort. Zugang vor Ort prüfen; Fußweg und Restzeit nicht berechnet."
            if search.category == "fuel" and item["dieselPrice"] is None:
                unpriced.append(result)
            else:
                found.append(result)
                found.sort(key=lambda entry: (entry["dieselPrice"] or 0, entry["drivingSeconds"], entry["id"]))
                found = found[:3]
            if len(unpriced) == 3:
                break
        if len(items) > 18:
            notices.append("Routenprüfung auf die ersten 18 Kandidaten begrenzt.")
        if search.category != "fuel" and found:
            notices.append("Karte und Übernahme verwenden den gerouteten Pkw-Zielpunkt, nicht einen Gebäude-/Flächenmittelpunkt. Keine bestätigte Fußverbindung oder freie Parkplätze.")
            for item in found:
                if item["accessDistance"] > 20:
                    notices.append(f"{item['name']}: etwa {math.ceil(item['accessDistance'])} m Luftlinie zwischen Pkw-Zielpunkt und kartiertem Ort; Zugang vor Ort prüfen, Fußweg und Restzeit nicht berechnet.")
        if not found and not unpriced:
            notices.append("Keine Orte dieser Kategorie im Suchgebiet geliefert. Suchgebiet erweitern." if not items and search.category != "fuel"
                           else "Keine passende Pkw-Anfahrt bestätigt. Suchgebiet erweitern oder später erneut versuchen.")
        return {"items": found, "unpriced": unpriced, "notices": notices,
                "scope": "Bis 50 km voraus · maximal +10 min · ohne erkannte Rückfahrt" if corridor else f"Umkreis {radius} km",
                "searchedAt": time.time()}
