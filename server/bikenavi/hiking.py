"""Conservative OSM walking and a single cycle -> walk transition.

The public ORS API does not offer multimodal routing. Compare reachable cycle
approaches to the final walking leg; never invent a straight-line connection.
"""
import asyncio
from uuid import uuid4

from fastapi import HTTPException

from .models import Coordinate, RouteRequest, Waypoint
from .providers import PAVED, ROUTE_TIMEOUT, _distance_m, parse_route, road_gap_edges

POI_RADIUS = 500

WALKING_WARNING = ("Einfache Wanderwege ohne bekannte Kletterpassagen (höchstens SAC T1). "
                   "Fehlende OSM-Schwierigkeitsangaben sind keine Bestätigung der Sicherheit. "
                   "Beschilderung, Sperrungen und Zustand vor Ort beachten.")


def validate_walking(data, route):
    """Require complete difficulty ranges, accepting only untagged or easy paths."""
    values = data["features"][0]["properties"].get("extras", {}).get("traildifficulty", {}).get("values", [])
    cursor = 0
    for entry in values:
        if (not isinstance(entry, list) or len(entry) != 3 or
                not all(type(v) is int for v in entry)):
            raise HTTPException(502, "Ungültige Wanderschwierigkeiten vom Routingdienst.")
        start, end, difficulty = entry
        if start != cursor or not start < end < len(route["coordinates"]):
            raise HTTPException(502, "Unvollständige Wanderschwierigkeiten vom Routingdienst.")
        if difficulty not in (0, 1):
            raise HTTPException(422, "Diese Strecke enthält anspruchsvolle Berg- oder Kletterwege. Bitte ein anderes Ziel wählen.")
        cursor = end
    if cursor != len(route["coordinates"]) - 1:
        raise HTTPException(502, "Der Routingdienst liefert keine vollständigen Wanderschwierigkeiten. Keine Wanderroute freigegeben.")


# ORS bicycle routing can include dismount/pedestrian paths. In combined mode
# generic paths conservatively belong to the walking leg; cycleways remain bike.
WALK_WAYTYPES = {4, 7, 8}


def waytypes(data, route):
    values = data["features"][0]["properties"].get("extras", {}).get("waytype", {}).get("values", [])
    edges = []
    for entry in values:
        if (not isinstance(entry, list) or len(entry) != 3 or
                not all(type(v) is int for v in entry)):
            raise HTTPException(502, "Ungültige Wegarten vom Routingdienst.")
        start, end, kind = entry
        if start != len(edges) or not start < end < len(route["coordinates"]) or not 0 <= kind <= 10:
            raise HTTPException(502, "Unvollständige Wegarten vom Routingdienst.")
        edges.extend([kind] * (end - start))
    if len(edges) != len(route["coordinates"]) - 1:
        raise HTTPException(502, "Der Routingdienst liefert keine vollständigen Wegarten.")
    return edges


def validate_cycling(data, route):
    if any(kind in WALK_WAYTYPES for kind in waytypes(data, route)):
        raise HTTPException(422, "Allgemeine Pfade, Fußwege und Treppen benötigen einen Wanderanteil.")


async def walking(ors, waypoints, start_radius=POI_RADIUS, with_waytypes=False):
    data = await ors.request("POST", "/v2/directions/foot-walking/geojson", timeout=ROUTE_TIMEOUT, json={
        "coordinates": [[w.coordinate.longitude, w.coordinate.latitude] for w in waypoints],
        "radiuses": [start_radius] + [POI_RADIUS] * (len(waypoints) - 1),
        "elevation": True, "instructions": True, "language": "de",
        "extra_info": ["surface", "waytype", "traildifficulty"],
    })
    route = parse_route(data)
    validate_walking(data, route)
    if (_distance_m(route["coordinates"][0], waypoints[0].coordinate.model_dump()) > start_radius or
            _distance_m(route["coordinates"][-1], waypoints[-1].coordinate.model_dump()) > POI_RADIUS):
        raise HTTPException(422, "Start oder Ziel liegt nicht an einem einfachen Wanderweg. Bitte den Kartenpunkt näher an den Weg setzen.")
    route.update(walkingStartIndex=0, walkingDistance=route["distance"], cyclingDistance=0)
    route["warnings"].append(WALKING_WARNING)
    for label, coordinate, waypoint in [("Start", route["coordinates"][0], waypoints[0]),
                                        ("Ziel", route["coordinates"][-1], waypoints[-1])]:
        offset = _distance_m(coordinate, waypoint.coordinate.model_dump())
        if offset > 20:
            route["warnings"].append(f"Beim {label} fehlen für etwa {round(offset)} m Luftlinie Wegdaten bis zum POI. Dieser Zugang ist nicht berechnet und nicht auf Kletterfreiheit geprüft; Verlauf, Sperrungen und Gelände vor Ort prüfen.")
            if label == "Ziel":
                route["unmappedDestinationDistance"] = offset
    return (route, waytypes(data, route)) if with_waytypes else route


def merge_routes(bike, walk):
    # A sub-metre join tolerance handles provider rounding, never a free-space leg.
    if _distance_m(bike["coordinates"][-1], walk["coordinates"][0]) > 1:
        raise HTTPException(422, "Rad- und Wanderweg sind an diesem Abstellpunkt nicht verbunden.")
    offset = len(bike["coordinates"]) - 1
    route = dict(bike)
    route["id"] = str(uuid4())
    route["coordinates"] = bike["coordinates"] + walk["coordinates"][1:]
    for key in ("distance", "duration", "ascent", "descent"):
        route[key] = bike[key] + walk[key]
    route["maneuvers"] = [m for m in bike["maneuvers"] if m["type"] != 10]
    route["maneuvers"].append(dict(instruction="Rad abstellen · zu Fuß weiter zum Ziel", distance=0,
                                    coordinateIndex=offset, type=11))
    route["maneuvers"] += [dict(m, coordinateIndex=m["coordinateIndex"] + offset) for m in walk["maneuvers"]]
    route["surfaceSections"] = (bike.get("surfaceSections") or []) + [
        dict(s, startIndex=s["startIndex"] + offset, endIndex=s["endIndex"] + offset)
        for s in walk.get("surfaceSections") or []]
    # Replace the synthetic parking waypoint with the actual tour destination.
    if bike.get("waypointIndices") and walk.get("waypointIndices"):
        route["waypointIndices"] = bike["waypointIndices"][:-1] + [offset + walk["waypointIndices"][-1]]
    else:
        route["waypointIndices"] = None
    totals = {}
    for s in bike["surfaces"] + walk["surfaces"]:
        totals[s["name"]] = totals.get(s["name"], 0) + s["distance"]
    route["surfaces"] = [dict(name=name, distance=distance, percentage=min(100, 100 * distance / max(1, route["distance"])))
                         for name, distance in totals.items()]
    route.update(walkingStartIndex=offset, walkingDistance=walk["distance"], cyclingDistance=bike["distance"])
    if walk.get("unmappedDestinationDistance"):
        route["unmappedDestinationDistance"] = walk["unmappedDestinationDistance"]
    route["warnings"] = list(dict.fromkeys(bike["warnings"] + walk["warnings"] + [
        "Rad-Abstellpunkt ist ein berechneter Übergang am Weg, kein bestätigter Fahrradständer. Abstellen vor Ort prüfen.",
        "Kürzester geprüfter Fußrest: begrenzter Vergleich von bis zu acht Radanschlüssen entlang der letzten 10 km der Wanderannäherung; keine globale Optimalitätsgarantie."]))
    return route


def parking_waypoint(item):
    location = item.get("location") if isinstance(item, dict) else None
    if not isinstance(location, list) or len(location) != 2:
        raise HTTPException(502, "Ungültiger Radanschluss vom Routingdienst.")
    try:
        point = Coordinate(longitude=location[0], latitude=location[1])
    except (ValueError, TypeError) as error:
        raise HTTPException(502, "Ungültige Radanschluss-Koordinate vom Routingdienst.") from error
    return Waypoint(id=uuid4(), name="Rad abstellen", coordinate=point)


async def route_with_walking(ors, request: RouteRequest):
    if request.profile.travelMode == "hiking":
        return await walking(ors, request.waypoints)
    cycle_profile = request.profile.model_copy(update={"travelMode": None})

    initial_cycle = None

    async def cycling(points, remember=False):
        nonlocal initial_cycle
        route = await ors.route(RouteRequest(waypoints=points, profile=cycle_profile), include_context=False, route_validator=validate_cycling)
        # Default ORS snapping can terminate on a different nearby street.
        indices = route.get("waypointIndices")
        if not indices or len(indices) != len(points):
            raise HTTPException(502, "Der Routingdienst liefert keine Rad-Wegpunktpositionen.")
        if remember:
            initial_cycle = route
        if any(not 0 <= i < len(route["coordinates"]) or
               _distance_m(route["coordinates"][i], w.coordinate.model_dump()) > (20 if n == len(points)-1 else POI_RADIUS)
               for n, (i, w) in enumerate(zip(indices, points))):
            raise HTTPException(422, "Ein Wegpunkt ist mit dem Rad nicht direkt erreichbar.")
        return route

    try:
        route = await cycling(request.waypoints, remember=True)
        route["warnings"].append("Das Ziel ist vollständig mit dem Rad erreichbar; kein Fußrest und kein Abstellpunkt erforderlich.")
        return route
    except HTTPException as error:
        if error.status_code != 422:
            raise
    # A POI may lie beyond both networks. Keep the useful cycling approach and
    # explicitly mark the missing final access; never add a fabricated foot edge.
    if initial_cycle is not None:
        goal = request.waypoints[-1].coordinate
        nearest = await ors.request("POST", "/v2/snap/foot-walking/json", timeout=ROUTE_TIMEOUT,
                                    json={"locations": [[goal.longitude, goal.latitude]], "radius": POI_RADIUS})
        locations = nearest.get("locations")
        if isinstance(locations, list) and len(locations) == 1 and locations[0] is not None:
            foot_end = parking_waypoint(locations[0]).coordinate.model_dump()
            end = initial_cycle["coordinates"][-1]
            gap = _distance_m(end, goal.model_dump())
            indices = initial_cycle["waypointIndices"]
            prefix_valid = all(_distance_m(initial_cycle["coordinates"][i], w.coordinate.model_dump()) <= POI_RADIUS
                               for i, w in zip(indices[:-1], request.waypoints[:-1]))
            if prefix_valid and 20 < gap <= POI_RADIUS and _distance_m(end, foot_end) <= 1:
                initial_cycle.update(walkingStartIndex=len(initial_cycle["coordinates"])-1,
                                     walkingDistance=0, cyclingDistance=initial_cycle["distance"],
                                     unmappedDestinationDistance=gap)
                initial_cycle["maneuvers"] = [m for m in initial_cycle["maneuvers"] if m["type"] != 10]
                initial_cycle["maneuvers"].append(dict(instruction="Rad abstellen · Wegdaten zum Ziel fehlen",
                    distance=0, coordinateIndex=len(initial_cycle["coordinates"])-1, type=10))
                initial_cycle["warnings"].append(f"Rad abstellen am Ende des erfassten Weges. Zum Ziel-POI fehlen für etwa {round(gap)} m Luftlinie Wegdaten. Der Fußrest ist nicht berechnet und nicht auf Kletterfreiheit geprüft; Verlauf, Sperrungen und Gelände vor Ort prüfen. Die Zeit enthält nur die erfasste Radanfahrt.")
                return initial_cycle
    # All intermediate stops must remain on the cycling prefix. Walking is final.
    bike_profile = {"touring": "cycling-electric" if cycle_profile.electric else "cycling-regular",
                    "gravel": "cycling-regular", "mountain": "cycling-mountain", "road": "cycling-road"}[cycle_profile.bike]
    approach = request.waypoints[-2]
    goal = request.waypoints[-1]
    if _distance_m(approach.coordinate.model_dump(), goal.coordinate.model_dump()) > 10_000:
        # A long cycling prefix must not require an equally long walking request
        # (public ORS walking limits differ from cycling limits).
        nearest = await ors.request("POST", f"/v2/snap/{bike_profile}/json", timeout=ROUTE_TIMEOUT,
                                    json={"locations": [[goal.coordinate.longitude, goal.coordinate.latitude]], "radius": 5000})
        locations = nearest.get("locations")
        if not isinstance(locations, list) or len(locations) != 1 or locations[0] is None:
            raise HTTPException(422, "Im Zielumfeld wurde kein Radanschluss gefunden. Setze das letzte Zwischenziel näher ans Ziel.")
        approach = parking_waypoint(locations[0])
    final_walk, kinds = await walking(ors, [approach, goal], with_waytypes=True)
    points = final_walk["coordinates"]
    # Use walking-reference surfaces only to prune clearly unsuitable searches.
    # Every chosen bicycle prefix still passes the actual whole-route budget.
    surfaces = [0] * len(kinds)
    for section in final_walk.get("surfaceSections") or []:
        surfaces[section["startIndex"]:section["endIndex"]] = [section["surface"]] * (section["endIndex"]-section["startIndex"])
    gap_edges = road_gap_edges(final_walk, kinds)
    unknown_prefix = [0.0]
    for edge, kind in enumerate(surfaces):
        unknown_prefix.append(unknown_prefix[-1] + (_distance_m(points[edge], points[edge+1]) if kind not in PAVED and edge not in gap_edges else 0))
    def eligible(edge, fraction=1):
        # A small geometry margin keeps estimates from acting as approval.
        estimated = unknown_prefix[edge] + fraction * (unknown_prefix[edge+1]-unknown_prefix[edge])
        return kinds[edge] not in WALK_WAYTYPES and (cycle_profile.surface != "pavedOnly" or estimated <= 125)
    samples = [points[-1]] if eligible(len(kinds)-1) else []
    distance = 0.0
    next_sample = 100.0
    for edge in range(len(points)-2, -1, -1):
        a, b = points[edge+1], points[edge]
        # Include the exact end of every cycling section, especially where a
        # long terminal trail begins. Trail samples must not consume the budget.
        if eligible(edge) and (edge == len(kinds)-1 or kinds[edge+1] in WALK_WAYTYPES) and distance <= 10_000:
            samples.append(a)
        step = _distance_m(a, b)
        upper = min(distance + step, 10_000)
        # Sample by travelled distance, independent of provider vertex density.
        while step > 0 and next_sample <= upper and len(samples) < 100:
            t = (next_sample - distance) / step
            if eligible(edge, 1-t):
                samples.append({"longitude": a["longitude"] + t * (b["longitude"] - a["longitude"]),
                                "latitude": a["latitude"] + t * (b["latitude"] - a["latitude"])})
            next_sample += 100
        distance += step
        if distance >= 10_000 or len(samples) >= 100:
            break
    if not samples:
        if cycle_profile.surface == "pavedOnly" and len(request.waypoints) == 2:
            final_walk["warnings"].append("Unter „Nur bekannte befestigte Wege“ wurde keine passende Radanfahrt gefunden. Diese Route wird vollständig gewandert; Radanteil 0 m. Unbekannte Beläge zählen zum gesamten 100-m-Toleranzbudget.")
            return final_walk
        raise HTTPException(422, "Kein Radanschluss an der einfachen Wanderannäherung gefunden.")
    snapped = await ors.request("POST", f"/v2/snap/{bike_profile}/json", timeout=ROUTE_TIMEOUT,
                                json={"locations": [[p["longitude"], p["latitude"]] for p in samples], "radius": 100})
    locations = snapped.get("locations")
    if not isinstance(locations, list) or len(locations) != len(samples):
        raise HTTPException(502, "Der Routingdienst liefert keine vollständigen Radanschlüsse.")
    candidates = []
    for item in locations:
        if item is None:
            continue
        parking = parking_waypoint(item)
        if not any(_distance_m(parking.coordinate.model_dump(), previous.coordinate.model_dump()) < 10 for previous in candidates):
            candidates.append(parking)
    if len(candidates) > 8:
        # Keep nearby approaches and spread the remaining checks over the full
        # search corridor. Strict paving can force a much earlier transition.
        remaining = candidates[4:]
        candidates = candidates[:4] + [remaining[round(i * (len(remaining)-1) / 3)] for i in range(4)]

    async def compare(parking):
        try:
            bike = await cycling(request.waypoints[:-1] + [parking])
            # Do not spend another foot request on a rejected bicycle prefix.
            walk = await walking(ors, [parking, request.waypoints[-1]], start_radius=1)
            return merge_routes(bike, walk)
        except HTTPException as error:
            if error.status_code == 422:
                return None
            raise
    results = await asyncio.gather(*(compare(p) for p in candidates), return_exceptions=True)
    for result in results:
        if isinstance(result, BaseException):
            raise result
    routes = [route for route in results if route is not None]
    if not routes:
        if candidates and cycle_profile.surface == "pavedOnly" and len(request.waypoints) == 2:
            final_walk["warnings"].append("Unter „Nur bekannte befestigte Wege“ wurde keine passende Radanfahrt gefunden: Unbekannte Beläge zählen zum gesamten 100-m-Toleranzbudget. Diese Route wird vollständig gewandert; Radanteil 0 m.")
            return final_walk
        raise HTTPException(422, "Kein verbundener Rad-/Wanderweg ohne Kletterpassagen gefunden. Zwischenziele müssen mit dem Rad erreichbar sein; setze das letzte Zwischenziel näher ans Ziel.")
    return min(routes, key=lambda r: (r["walkingDistance"], r["distance"]))
