"""Versioned bicycle graph tiles. Preparation only; the phone performs all routing.

Conservative OSM subset: unsupported conditional/via-way restrictions close the
affected ways instead of being silently ignored. No invented links at crossings.
"""
import asyncio
import math
import logging
import time

import httpx
from fastapi import HTTPException

logger = logging.getLogger(__name__)
DEFAULT_OVERPASS = "https://overpass-api.de/api/interpreter"
FALLBACK_OVERPASS = "https://overpass.private.coffee/api/interpreter"

VERSION = 1
TILE_DEGREES = 0.05
ALLOWED = {"yes", "designated", "official", "permissive"}
ROAD_DEFAULTS = {"cycleway", "residential", "living_street", "unclassified", "service",
                 "tertiary", "tertiary_link", "secondary", "secondary_link", "primary", "primary_link", "track"}
SURFACE = {"paved": 1, "asphalt": 3, "concrete": 4, "concrete:plates": 4, "concrete:lanes": 4,
           "paving_stones": 14, "sett": 5, "cobblestone": 5, "metal": 6, "wood": 7,
           "compacted": 8, "fine_gravel": 9, "gravel": 10, "pebblestone": 10,
           "dirt": 11, "earth": 11, "ground": 12, "sand": 15, "grass": 17, "unpaved": 2}


def access(tags, direction=None):
    for key in ("bicycle", "vehicle", "access"):
        directional = tags.get(f"{key}:{direction}") if direction else None
        value = directional if directional is not None else tags.get(key)
        if value is not None:
            return value in ALLOWED
    return True


def conditional(tags):
    return any("conditional" in k and k.split(":")[0] in {"bicycle", "vehicle", "access", "oneway", "restriction"} for k in tags)


def compile_tile(elements, x, y, generated_at=None):
    nodes = {e["id"]: e for e in elements if e.get("type") == "node" and "lat" in e and "lon" in e}
    ways = {e["id"]: e for e in elements if e.get("type") == "way" and "nodes" in e}
    blocked_nodes = set()
    blocked_ways = set()
    restrictions = []
    for id, node in nodes.items():
        tags = node.get("tags", {})
        if (not access(tags) or conditional(tags) or tags.get("locked") == "yes"
                or (tags.get("barrier") not in (None, "no", "bollard", "entrance")
                    and tags.get("bicycle") not in ALLOWED)):
            blocked_nodes.add(id)
    for relation in elements:
        if relation.get("type") != "relation":
            continue
        tags = relation.get("tags", {})
        if tags.get("type") != "restriction":
            continue
        if "bicycle" in tags.get("except", "").split(";") and "restriction:bicycle" not in tags:
            continue
        restriction = tags.get("restriction:bicycle", tags.get("restriction"))
        if restriction is None and not conditional(tags):
            continue  # A motor-vehicle-only restriction does not apply to bicycles.
        members = relation.get("members", [])
        from_ways = [m["ref"] for m in members if m.get("role") == "from" and m.get("type") == "way"]
        to_ways = [m["ref"] for m in members if m.get("role") == "to" and m.get("type") == "way"]
        via = [m for m in members if m.get("role") == "via"]
        if (conditional(tags) or len(via) != 1 or via[0].get("type") != "node"
                or not from_ways or not to_ways or not restriction
                or not restriction.startswith(("no_", "only_"))):
            blocked_ways.update(from_ways)
            blocked_ways.update(m["ref"] for m in via if m.get("type") == "way")
            continue
        for from_way in from_ways:
            restrictions.append({"via": via[0]["ref"], "fromWay": from_way, "toWays": to_ways,
                                 "only": restriction.startswith("only_"), "uTurn": restriction in {"no_u_turn", "only_u_turn"}})
    edges = []
    used = set()
    for id, way in ways.items():
        tags = way.get("tags", {})
        highway = tags.get("highway")
        if (id in blocked_ways or highway in {None, "motorway", "motorway_link", "trunk", "trunk_link", "steps", "construction", "proposed", "raceway"}
                or conditional(tags) or not access(tags) or tags.get("smoothness") in {"impassable", "very_horrible", "horrible"}
                or tags.get("ford") == "yes" or tags.get("motorroad") == "yes"
                or (highway not in ROAD_DEFAULTS and tags.get("bicycle") not in ALLOWED)):
            continue
        one = tags.get("oneway:bicycle", tags.get("oneway", "yes" if tags.get("junction") == "roundabout" else "no"))
        if one not in {"yes", "1", "true", "no", "0", "false", "-1"}:
            continue
        surface = SURFACE.get(tags.get("surface"), 0)
        try:
            grade = max(-40, min(40, float(tags.get("incline", "0").rstrip("%"))))
        except ValueError:
            grade = 0
        for a, b in zip(way["nodes"], way["nodes"][1:]):
            if a == b or a not in nodes or b not in nodes or a in blocked_nodes or b in blocked_nodes:
                continue
            used.update((a, b))
            base = {"way": id, "surface": surface, "name": str(tags.get("name", ""))[:120]}
            if one != "-1" and access(tags, "forward"):
                edges.append({**base, "from": a, "to": b, "incline": grade})
            if one not in {"yes", "1", "true"} and access(tags, "backward"):
                edges.append({**base, "from": b, "to": a, "incline": -grade})
    if len(used) > 150_000 or len(edges) > 350_000:
        raise HTTPException(422, "Dieser Kartenbereich ist für die lokale Rückführung zu groß.")
    excluded = blocked_ways | (set(ways) - {e["way"] for e in edges})
    return {"excludedWays": sorted(excluded), "blockedNodes": sorted(blocked_nodes), "version": VERSION, "x": x, "y": y, "generatedAt": generated_at or time.time(),
            "nodes": [{"id": id, "coordinate": {"latitude": nodes[id]["lat"], "longitude": nodes[id]["lon"]}} for id in sorted(used)],
            "edges": edges, "restrictions": restrictions}


class OfflineTiles:
    def __init__(self, client, storage, url):
        self.client, self.storage, self.url = client, storage, url
        self.lock = asyncio.Lock()  # Respect public Overpass resources; one preparation at a time.

    async def tile(self, x, y, refresh=False):
        key = f"{VERSION}/{x}/{y}"
        async with self.lock:
            cached = self.storage.offline_tile(key)
            if cached and not refresh and time.time() - cached["generatedAt"] < 30 * 86400:
                return cached
            if not self.url:
                raise HTTPException(503, "Der Download des lokalen Wegenetzes ist auf dem Pi nicht eingerichtet.")
            south, west = y * TILE_DEGREES - 90, x * TILE_DEGREES - 180
            # Return complete ways and all referencing restrictions, including their via members.
            query = (f'[out:json][timeout:25][maxsize:67108864];'
                     f'way["highway"]({south:.5f},{west:.5f},{south+TILE_DEGREES:.5f},{west+TILE_DEGREES:.5f})->.roads;'
                     'rel(bw.roads)["type"="restriction"]->.rules;(.roads;node(w.roads);.rules;);out body;')
            # Keep custom installations on their configured provider. For the public
            # default, a second OSM mirror can serve tiles when the first is down.
            urls = [self.url]
            if self.url == DEFAULT_OVERPASS:
                urls.append(FALLBACK_OVERPASS)
            last_error = None
            for url in urls:
                try:
                    async with self.client.stream("POST", url, data={"data": query}, headers={"User-Agent": "BikeNavi/0.1 personal cycling navigation"}, timeout=40) as response:
                        response.raise_for_status()
                        data = bytearray()
                        async for chunk in response.aiter_bytes():
                            data.extend(chunk)
                            if len(data) > 32 * 1024 * 1024:
                                raise HTTPException(422, "Dieser Kartenbereich ist für die lokale Rückführung zu groß.")
                    import json
                    payload = json.loads(data)
                    if payload.get("remark") or not isinstance(payload.get("elements"), list):
                        raise ValueError("Incomplete Overpass result")
                    result = compile_tile(payload["elements"], x, y)
                except (httpx.HTTPError, ValueError, KeyError, TypeError) as error:
                    last_error = error
                    logger.warning("Offline tile %s: map download failed (%s)", key, type(error).__name__)
                    continue
                self.storage.save_offline_tile(key, result)
                return result
            raise HTTPException(503, "Neue Wegedaten sind gerade nicht erreichbar. Bereits geladene Bereiche bleiben verfügbar. Bitte die Route später erneut berechnen.") from last_error
