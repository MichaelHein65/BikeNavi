"""Route-bound road context. No inference from legal limits or GPS deviation."""
import asyncio
import math

import httpx
from shapely.geometry import LineString
from shapely.strtree import STRtree


def sections_from_edges(environments):
    sections = []
    for edge, environment in enumerate(environments):
        if sections and sections[-1]["environment"] == environment:
            sections[-1]["endIndex"] = edge + 1
        else:
            sections.append(dict(startIndex=edge, endIndex=edge + 1, environment=environment))
    return sections


def provider_environments(count, sections):
    # Both URBAN and MOTORWAY are explicitly requested for the complete route.
    edges = ["rural"] * (count - 1)
    for kind, environment in (("URBAN", "urban"), ("MOTORWAY", "divided")):
        for section in sections:
            if section["sectionType"] != kind:
                continue
            start, end = section["startPointIndex"], section["endPointIndex"]
            if type(start) is not int or type(end) is not int or not 0 <= start <= end < count:
                raise ValueError("Invalid road environment indices")
            edges[start:end] = [environment] * (end - start)
    return sections_from_edges(edges)


def osm_environments(route, elements):
    points = route["coordinates"]
    lon_scale = 111195 * math.cos(math.radians(points[0]["latitude"]))
    def xy(lat, lon):
        return ((lon - points[0]["longitude"]) * lon_scale, (lat - points[0]["latitude"]) * 111195)
    roads, kinds = [], []
    divided_members = {member["ref"] for element in elements
        if element.get("type") == "relation" and element.get("tags", {}).get("type") == "dual_carriageway"
        for member in element.get("members", []) if member.get("type") == "way"}
    for element in elements:
        tags = element.get("tags", {})
        if element.get("type") != "way" or not tags.get("highway"):
            continue
        geometry = element.get("geometry", [])
        if len(geometry) < 2:
            continue
        coords = [(p.get("lat"), p.get("lon")) for p in geometry]
        if any(type(lat) not in (int, float) or type(lon) not in (int, float)
               or not math.isfinite(lat) or not math.isfinite(lon) or abs(lat) > 90 or abs(lon) > 180 for lat, lon in coords):
            continue
        kind = None
        if tags["highway"] in {"track", "path"}:
            kind = "offRoad"
        elif tags["highway"] == "motorway" or tags.get("dual_carriageway") == "yes" or element.get("id") in divided_members:
            kind = "divided"
        # Ordinary roads participate too: do not snap to a nearby field track.
        roads.append(LineString([xy(lat, lon) for lat, lon in coords])); kinds.append(kind)
    if not roads:
        return route["carRoadSections"]
    tree = STRtree(roads)
    edges = [None] * (len(points) - 1)
    for section in route["carRoadSections"]:
        edges[section["startIndex"]:section["endIndex"]] = [section["environment"]] * (section["endIndex"] - section["startIndex"])
    for i, (a, b) in enumerate(zip(points, points[1:])):
        if edges[i] == "divided":  # Explicit motorway data wins over adjacent OSM roads.
            continue
        edge = LineString([xy(a["latitude"], a["longitude"]), xy(b["latitude"], b["longitude"])])
        if edge.length < 1 or edge.length > 250:
            continue
        samples = [edge.interpolate(f, normalized=True) for f in (0, .25, .5, .75, 1)]
        candidates = sorted((max(roads[j].distance(p) for p in samples), int(j)) for j in tree.query(edge.buffer(12)))
        if not candidates or candidates[0][0] > 12:
            continue
        gap, best = candidates[0]
        if kinds[best] is None or any(kinds[j] != kinds[best] and distance <= gap + 5 for distance, j in candidates[1:]):
            continue
        edges[i] = kinds[best]
    return sections_from_edges(edges)


async def enrich_environments(route, client, overpass_url):
    if not overpass_url:
        route["warnings"].append("OSM-Straßenmerkmale fehlen: weitere getrennte Fahrbahnen und Off-Road sind nicht sicher erkennbar.")
        return route
    points = route["coordinates"]
    # Bound query size/time. Never silently sample away bends in the matching geometry.
    line = LineString([(p["longitude"], p["latitude"]) for p in points]).simplify(.00005)
    if len(line.coords) > 5000 or line.bounds[2] - line.bounds[0] > 180:
        route["warnings"].append("OSM-Umgebungserkennung für diese lange Route nicht verfügbar.")
        return route
    coordinates = ",".join(f"{lat:.7f},{lon:.7f}" for lon, lat in line.coords)
    query = f'[out:json][timeout:8][maxsize:16777216];way[highway](around:40,{coordinates})->.roads;(.roads;rel(bw.roads)[type=dual_carriageway];);out tags geom;'
    try:
        async with asyncio.timeout(12):
            response = await client.post(overpass_url, data={"data": query}, timeout=10,
                                         headers={"User-Agent": "BikeNavi/0.4 personal navigation"})
            response.raise_for_status()
            if len(response.content) > 8 * 1024 * 1024:
                raise ValueError("OSM response too large")
            data = response.json()
            if data.get("remark") or not isinstance(data.get("elements"), list):
                raise ValueError("Incomplete OSM response")
            route["carRoadSections"] = await asyncio.to_thread(osm_environments, route, data["elements"])
    except (httpx.HTTPError, TimeoutError, ValueError, KeyError, TypeError, AttributeError):
        route["warnings"].append("OSM-Straßenmerkmale derzeit nicht verfügbar: weitere getrennte Fahrbahnen und Off-Road eventuell unerkannt.")
    return route
