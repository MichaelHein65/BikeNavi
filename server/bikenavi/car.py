"""TomTom Maps v1 car routing; key stays on the Pi, no paid fallback.

API reference: https://docs.tomtom.com/routing-api/documentation/tomtom-maps/v1/guidance-instructions
"""
import asyncio
import logging
import math
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from uuid import uuid4

import httpx
from fastapi import HTTPException

from .models import Route, RouteRequest
from .car_environment import provider_environments
from .providers import _distance_m

# Below the documented free 20,000/month. Use a dedicated, unbilled key.
FREE_MONTHLY_LIMIT = 19_000
# TomTom Routing defaults to 5 QPS. Share spacing across POI/route calls,
# processes and restarts; leave headroom for rolling one-second windows.
REQUEST_INTERVAL = 0.3
logger = logging.getLogger(__name__)


def retry_delay(value, now):
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        try:
            seconds = parsedate_to_datetime(value).timestamp() - now
        except (TypeError, ValueError, OverflowError):
            seconds = 2
    return max(2, seconds) if math.isfinite(seconds) else 2


DIRECTIONS = {"STRAIGHT", "SLIGHT_RIGHT", "RIGHT", "SHARP_RIGHT", "RIGHT_U_TURN",
              "SLIGHT_LEFT", "LEFT", "SHARP_LEFT", "LEFT_U_TURN"}
MANEUVERS = {"DEPART": 11, "TURN_LEFT": 0, "TURN_RIGHT": 1, "SHARP_LEFT": 2,
             "SHARP_RIGHT": 3, "BEAR_LEFT": 4, "BEAR_RIGHT": 5, "KEEP_LEFT": 12,
             "KEEP_RIGHT": 13, "MOTORWAY_EXIT_LEFT": 12, "MOTORWAY_EXIT_RIGHT": 13,
             "MAKE_UTURN": 9, "TRY_MAKE_UTURN": 9}


def number(value, minimum=0):
    if type(value) not in (int, float) or not math.isfinite(value) or value < minimum:
        raise ValueError("Invalid numeric route data")
    return value


def index(value, count):
    if type(value) is not int or not 0 <= value < count:
        raise ValueError("Invalid route index")
    return value


def parse_route(data, request, fetched_at):
    raw = data["routes"][0]
    summary = raw["summary"]
    coordinates, waypoints = [], [0]
    legs = raw["legs"]
    if len(legs) != len(request.waypoints) - 1:
        raise ValueError("Missing requested stops")
    for leg in legs:
        points = [{"latitude": p["latitude"], "longitude": p["longitude"]} for p in leg["points"]]
        if len(points) < 2:
            raise ValueError("Empty leg")
        if coordinates and coordinates[-1] != points[0]:
            raise ValueError("Disconnected legs")
        # TomTom indices include both copies of a shared leg endpoint. Keep them
        # to preserve the provider's indices for maneuvers, progress and sections.
        coordinates.extend(points)
        waypoints.append(len(coordinates) - 1)
    count = len(coordinates)
    duration = number(summary["travelTimeInSeconds"])
    progress = raw["progress"]
    times = [(index(p["pointIndex"], count), number(p["travelTimeInSeconds"])) for p in progress]
    if not times or times[0] != (0, 0) or times[-1][0] != count - 1 or abs(times[-1][1] - duration) > 1:
        raise ValueError("Incomplete time profile")
    time_sections = []
    for (start, before), (end, after) in zip(times, times[1:]):
        if end <= start or after < before:
            raise ValueError("Unordered time profile")
        # POI arrival estimates consume complete sections up to a waypoint. Preserve
        # that contract even when the provider's sparse time profile crosses a stop.
        cuts = [start] + [w for w in waypoints if start < w < end] + [end]
        lengths = [sum(_distance_m(a, b) for a, b in zip(coordinates[left:right], coordinates[left + 1:right + 1]))
                   for left, right in zip(cuts, cuts[1:])]
        total = sum(lengths)
        if total <= 0 and after > before:
            raise ValueError("Travel time without geometry")
        for left, right, length in zip(cuts, cuts[1:], lengths):
            time_sections.append(dict(startIndex=left, endIndex=right, seconds=(after - before) * length / total if total else 0))
    maneuvers = []
    for instruction in raw.get("guidance", {}).get("instructions", []):
        code = instruction["maneuver"]
        kind = 10 if code.startswith("ARRIVE") else 7 if code.startswith("ROUNDABOUT") else MANEUVERS.get(code, 6)
        # TomTom may send zero for a motorway exit. This field describes only
        # numbered roundabout exits; absent/inapplicable values are not errors.
        exit_number = instruction.get("roundaboutExitNumber")
        if kind != 7 or type(exit_number) is not int or not 1 <= exit_number <= 100:
            exit_number = None
        maneuvers.append(dict(instruction=instruction["message"], distance=0,
                              coordinateIndex=index(instruction["pointIndex"], count), type=kind,
                              roadName=instruction.get("street"), exitNumber=exit_number))
    if not maneuvers or any(a["coordinateIndex"] > b["coordinateIndex"] for a, b in zip(maneuvers, maneuvers[1:])):
        raise ValueError("Missing or unordered instructions")
    options = request.profile.carOptions
    forbidden = {name for enabled, name in ((options.avoidHighways, "MOTORWAY"),
        (options.avoidTolls, "TOLL_ROAD"), (options.avoidFerries, "FERRY")) if enabled} if options else set()
    limits, lanes, traffic = [], [], []
    for section in raw.get("sections", []):
        kind = section["sectionType"]
        if kind in forbidden:
            raise ValueError("Provider could not respect selected avoidance")
        if kind not in {"SPEED_LIMIT", "LANES", "TRAFFIC"}:
            continue
        start, end = index(section["startPointIndex"], count), index(section["endPointIndex"], count)
        if start >= end:
            continue
        span = dict(startIndex=start, endIndex=end)
        if kind == "SPEED_LIMIT":
            # Unknown/unlimited/conditional values must not become a numerical legal limit.
            value = section.get("maxSpeedLimitInKmh")
            if type(value) in (int, float) and math.isfinite(value) and 0 < value <= 300:
                limits.append(dict(**span, kilometersPerHour=value))
        elif kind == "LANES":
            items = section.get("lanes", [])
            if not 1 <= len(items) <= 12:
                continue
            if any(not l.get("directions") or not set(l["directions"]).issubset(DIRECTIONS)
                   or (l.get("follow") is not None and l["follow"] not in l["directions"]) for l in items):
                continue
            if any(l.get("follow") for l in items):
                lanes.append(dict(**span, lanes=[dict(directions=l["directions"], follow=l.get("follow")) for l in items]))
        else:
            category = section.get("simpleCategory", "OTHER")
            traffic.append(dict(**span, delaySeconds=number(section.get("delayInSeconds", 0)),
                                category=category if category in {"JAM", "ROAD_WORK", "ROAD_CLOSURE"} else "OTHER"))
    limits.sort(key=lambda s: s["startIndex"])
    lanes.sort(key=lambda s: s["startIndex"])
    traffic.sort(key=lambda s: s["startIndex"])
    warnings = []
    if not lanes:
        warnings.append("Für diese Route wurden keine Spurhinweise geliefert.")
    if not limits:
        warnings.append("Für diese Route wurden keine Tempolimits geliefert.")
    route = dict(id=str(uuid4()), coordinates=coordinates, distance=number(summary["lengthInMeters"]),
                 duration=duration, ascent=0, descent=0, maneuvers=maneuvers, surfaces=[], warnings=warnings,
                 provider="TomTom · Pkw", calculatedAt=fetched_at, waypointIndices=waypoints,
                 carTimeSections=time_sections, carSpeedLimits=limits, carLaneSections=lanes,
                 carRoadSections=provider_environments(count, raw.get("sections", [])),
                 carTraffic=dict(fetchedAt=fetched_at, delaySeconds=number(summary["trafficDelayInSeconds"]), sections=traffic))
    for ordinal, waypoint in enumerate(request.waypoints):
        gap = _distance_m(waypoint.coordinate.model_dump(), coordinates[waypoints[ordinal]])
        if gap > (350 if ordinal == len(request.waypoints) - 1 else 50):
            raise ValueError("Requested stop not reachable by car")
        if ordinal == len(request.waypoints) - 1 and gap > 20:
            route["destinationAccessDistance"] = gap
            warnings.append(f"Pkw-Route endet an der Straße: etwa {math.ceil(gap)} m Luftlinie zum Ziel. Restweg und Restzeit nicht berechnet.")
    return Route.model_validate(route).model_dump(mode="json", exclude_none=True)


class TomTomCar:
    def __init__(self, key, client, storage):
        self.key, self.client, self.storage = key, client, storage
        self.lock = asyncio.Lock()
        self.next_allowed = 0.0
        self.failure_status = 503
        self.failure_detail = "TomTom ist vorübergehend nicht erreichbar."

    def check_backoff(self):
        remaining = math.ceil(self.next_allowed - time.time())
        if remaining > 0:
            raise HTTPException(self.failure_status, self.failure_detail + f" Erneut versuchen in {remaining} s.",
                                headers={"Retry-After": str(remaining)})

    def backoff(self, status, detail, seconds):
        self.failure_status, self.failure_detail = status, detail
        self.next_allowed = time.time() + seconds
        self.check_backoff()

    async def route(self, request: RouteRequest):
        self.check_backoff()
        locations = ":".join(f"{w.coordinate.latitude},{w.coordinate.longitude}" for w in request.waypoints)
        params = [("key", self.key), ("travelMode", "car"), ("routeType", "fastest"),
                  ("traffic", "true"), ("departAt", "now"), ("instructionsType", "text"), ("language", "de-DE"),
                  ("routeRepresentation", "polyline"), ("extendedRouteRepresentation", "travelTime"),
                  ("sectionType", "lanes"), ("sectionType", "speedLimit"), ("sectionType", "traffic"),
                  ("sectionType", "urban"), ("sectionType", "motorway")]
        options = request.profile.carOptions
        if options:
            params.extend(("avoid", name) for enabled, name in ((options.avoidHighways, "motorways"),
                (options.avoidTolls, "tollRoads"), (options.avoidFerries, "ferries")) if enabled)
            params.extend(("sectionType", name) for enabled, name in ((options.avoidTolls, "tollRoad"), (options.avoidFerries, "ferry")) if enabled)
        if request.startBearing is not None:
            params.append(("vehicleHeading", str(round(request.startBearing) % 360)))
        async with self.lock:
            self.check_backoff()
            # A lock alone serializes fast replies but does not enforce QPS.
            while True:
                now = time.time()
                allowed_at = self.storage.reserve_provider_request("tomtom-routing-spacing", now, REQUEST_INTERVAL)
                if allowed_at is None:
                    break
                await asyncio.sleep(max(0.01, allowed_at - now))
            month = datetime.fromtimestamp(time.time(), timezone.utc).strftime("%Y-%m")
            # Reserve only actual outbound attempts, including failed calls.
            if not self.storage.reserve_provider_month("tomtom-routing", month, FREE_MONTHLY_LIMIT):
                raise HTTPException(429, "Kostenloses TomTom-Monatsbudget erreicht. Keine weiteren Anbieterabrufe in diesem Monat.")
            try:
                response = await self.client.get("https://api.tomtom.com/routing/1/calculateRoute/" + locations + "/json",
                                                 params=params, timeout=httpx.Timeout(35, connect=10))
            except httpx.RequestError as error:
                logger.warning("TomTom transport failure: %s", type(error).__name__)
                self.backoff(503, "TomTom ist vorübergehend nicht erreichbar.", 60)
            if response.status_code != 200:
                logger.warning("TomTom HTTP status: %s", response.status_code)
                if response.status_code in (401, 403):
                    self.backoff(503, "TomTom-Zugang oder benötigte Routing-Funktionen sind nicht freigeschaltet. Kostenlosen API-Schlüssel prüfen.", 60)
                if response.status_code == 429:
                    self.backoff(429, "TomTom begrenzt gerade die Abfragerate.",
                                 retry_delay(response.headers.get("Retry-After"), time.time()))
                if response.status_code >= 500 or response.status_code == 408:
                    self.backoff(503, "TomTom ist vorübergehend nicht erreichbar.", 60)
                # A rejected candidate must not block unrelated routes/POIs.
                raise HTTPException(422, "TomTom konnte für diese Punkte keine Pkw-Route liefern.")
            try:
                return parse_route(response.json(), request, time.time())
            except (ValueError, KeyError, TypeError, IndexError, AttributeError) as error:
                # Never log provider payloads, URLs, coordinates or credentials.
                logger.warning("TomTom route validation failure: %s", type(error).__name__)
                raise HTTPException(502, "Pkw-Daten für diese Strecke nicht verfügbar oder unvollständig. Gespeicherte Route bleibt erhalten.") from error
