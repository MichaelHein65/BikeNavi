"""Water-only routing from directed OSM coastlines and mapped sea corridors."""
import asyncio
import copy
import heapq
import json
import math
import time
from collections import OrderedDict
from uuid import uuid4

import httpx
import numpy as np
from fastapi import HTTPException
from shapely import contains_xy
from shapely.geometry import LineString, Point, box
from shapely.ops import polygonize_full, unary_union
from shapely.prepared import prep
from shapely.strtree import STRtree

from .offline import DEFAULT_OVERPASS, FALLBACK_OVERPASS
from .bathymetry import DepthTiles, WARNING as DEPTH_WARNING
from .marine_obstacles import exclusions

WARNING = "Wasserweg anhand erfasster OSM-Küsten; erfasste Fahrwasser und empfohlene Kurse werden leicht bevorzugt. Fährlinien erhalten keinen Vorteil. Strömung, Sperrungen und nautische Eignung werden nicht geprüft. Amtliche Seekarten und aktuelle Hinweise prüfen."
DATA_ERROR = "Küsten- und Seewegdaten sind unvollständig. Es wird keine ungeprüfte Verbindung berechnet."


class WaterArea:
    def __init__(self, data, bounds, draft=2.0):
        south, west, north, east = bounds
        self.scale = math.cos(math.radians((south + north) / 2))
        self.bounds = bounds
        self.region = box(*self.project(west, south), *self.project(east, north))
        coast, directed, corridors = [], [], []
        incoming, outgoing = {}, {}
        if data.get("remark") or not isinstance(data.get("elements"), list):
            raise HTTPException(503, DATA_ERROR)
        if len(data["elements"]) > 20_000:
            raise HTTPException(503, DATA_ERROR)
        geometry_count = 0
        for way in data["elements"]:
            if way.get("type") != "way":
                continue
            geometry = way.get("geometry", [])
            geometry_count += len(geometry)
            if geometry_count > 200_000:
                raise HTTPException(503, DATA_ERROR)
            if len(geometry) < 2 or any(not isinstance(p, dict) or not (-85 <= p.get("lat", 100) <= 85 and -180 <= p.get("lon", 1000) <= 180) for p in geometry):
                raise HTTPException(503, DATA_ERROR)
            coords = [self.project(p["lon"], p["lat"]) for p in geometry]
            line = LineString(coords)
            tags = way.get("tags", {})
            if tags.get("natural") != "coastline":
                if tags.get("waterway") == "fairway" or tags.get("seamark:type") in {"fairway", "navigation_line", "recommended_track"}:
                    corridors.append(line)
                continue
            clipped = line.intersection(self.region)
            parts = list(clipped.geoms) if clipped.geom_type == "MultiLineString" else [clipped]
            for part in parts:
                if part.geom_type != "LineString" or part.length == 0:
                    continue
                coast.append(part)
                a, b = tuple(part.coords[0]), tuple(part.coords[-1])
                outgoing[a] = outgoing.get(a, 0) + 1
                incoming[b] = incoming.get(b, 0) + 1
                directed.extend((a, b) for a, b in zip(part.coords, list(part.coords)[1:]) if a != b)
        if not coast:
            raise HTTPException(503, DATA_ERROR)
        for endpoint in set(incoming) | set(outgoing):
            if self.region.boundary.distance(Point(endpoint)) > 0.05 and (incoming.get(endpoint) != 1 or outgoing.get(endpoint) != 1):
                raise HTTPException(503, DATA_ERROR)
        polygons, cuts, dangles, invalid = polygonize_full(unary_union(coast + [self.region.boundary]))
        if not cuts.is_empty or not dangles.is_empty or not invalid.is_empty:
            raise HTTPException(503, DATA_ERROR)
        segments = [LineString([a, b]) for a, b in directed]
        tree = STRtree(segments)
        water = []
        for polygon in polygons.geoms:
            point = polygon.representative_point()
            index = int(tree.nearest(point))
            a, b = directed[index]
            side = (b[0]-a[0])*(point.y-a[1]) - (b[1]-a[1])*(point.x-a[0])
            if side < 0:  # OSM coastline direction: land left, sea right.
                water.append(polygon)
        if not water:
            raise HTTPException(503, DATA_ERROR)
        # A small geometric margin prevents grazing shores. It is not a depth/safety clearance.
        self.obstacles = exclusions(data["elements"], self.project, draft)
        self.water = unary_union(water).buffer(-10).difference(self.obstacles)
        self.prepared = prep(self.water)
        self.corridors = unary_union(corridors).buffer(80).intersection(self.water) if corridors else None
        self.preferred = prep(self.corridors) if self.corridors is not None else None

    def project(self, lon, lat):
        factor = 6_371_000 * self.scale
        return factor * math.radians(lon), factor * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))

    def coordinate(self, xy):
        factor = 6_371_000 * self.scale
        return {"longitude": math.degrees(xy[0] / factor), "latitude": math.degrees(2 * math.atan(math.exp(xy[1] / factor)) - math.pi / 2)}

    def route(self, request, deadline=None):
        deadline = deadline or time.monotonic() + 25
        left, bottom, right, top = self.region.bounds
        step = max(35, math.sqrt((right-left)*(top-bottom) / 120_000))
        width, height = math.floor((right-left)/step)+1, math.floor((top-bottom)/step)+1
        xs = left + np.tile(np.arange(width), height) * step
        ys = bottom + np.repeat(np.arange(height), width) * step
        wet = contains_xy(self.water, xs, ys)
        preferred = contains_xy(self.corridors, xs, ys) if self.corridors is not None else np.zeros(len(xs), dtype=bool)
        edges = {}

        def coordinate(node):
            return (float(xs[node]), float(ys[node]))

        def connects(a, b):
            return self.prepared.covers(LineString([a, b]))

        def attach(point):
            if not self.prepared.contains(Point(point)):
                raise HTTPException(422, "Ein Wegpunkt liegt an Land, zu nah an der Küste oder in einer kartierten Gefahrenstelle. Wähle einen anderen Wasserpunkt.")
            cx, cy = int(round((point[0]-left)/step)), int(round((point[1]-bottom)/step))
            nodes = []
            for x in range(max(0, cx-3), min(width, cx+4)):
                for y in range(max(0, cy-3), min(height, cy+4)):
                    node = y*width+x
                    if wet[node] and connects(point, coordinate(node)):
                        nodes.append((math.dist(point, coordinate(node)), node))
            if not nodes:
                raise HTTPException(422, "Der Wegpunkt hat keinen erreichbaren Wasseranschluss. Es wird keine Landverbindung verwendet.")
            return sorted(nodes)[:12]

        def search(start, goal):
            starts, goals = attach(start), dict((node, distance) for distance, node in attach(goal))
            distances, parents, queue = {}, {}, []
            for distance, node in starts:
                cost = distance * (1 if preferred[node] else 1.05)
                distances[node] = cost
                parents[node] = None
                heapq.heappush(queue, (cost + math.dist(coordinate(node), goal), cost, node))
            expanded = 0
            best_goal, best_cost = None, math.inf
            while queue:
                estimate, cost, node = heapq.heappop(queue)
                if estimate >= best_cost:
                    break
                if cost != distances.get(node):
                    continue
                expanded += 1
                if expanded % 256 == 0 and time.monotonic() > deadline:
                    raise HTTPException(503, "Die Wasserwegsuche hat ihr Zeitlimit erreicht. Setze zusätzliche Wegpunkte.")
                if node in goals:
                    total = cost + goals[node] * (1 if preferred[node] else 1.05)
                    if total < best_cost:
                        best_goal, best_cost = node, total
                x, y = node % width, node // width
                for dx, dy in ((-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)):
                    nx, ny = x+dx, y+dy
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue
                    neighbor = ny*width+nx
                    if not wet[neighbor]:
                        continue
                    key = tuple(sorted((node, neighbor)))
                    if key not in edges:
                        edges[key] = connects(coordinate(node), coordinate(neighbor))
                    if not edges[key]:
                        continue
                    length = step * (math.sqrt(2) if dx and dy else 1)
                    candidate = cost + length * (1 if preferred[node] and preferred[neighbor] else 1.05)
                    if candidate < distances.get(neighbor, math.inf):
                        distances[neighbor], parents[neighbor] = candidate, node
                        heapq.heappush(queue, (candidate + math.dist(coordinate(neighbor), goal), candidate, neighbor))
            if best_goal is None:
                raise HTTPException(422, "Keine durchgehende Wasserverbindung im erfassten Gebiet gefunden. Es wird nicht über Land geroutet.")
            path = []
            node = best_goal
            while node is not None:
                path.append(coordinate(node))
                node = parents[node]
            path = [start] + path[::-1] + [goal]
            # Remove raster zigzags only when the entire simplified line is still in water.
            def cost(a, b):
                distance = math.dist(a, b)
                count = max(2, math.ceil(distance / step))
                fraction = sum(self.preferred.contains(Point(a[0]+(b[0]-a[0])*i/count, a[1]+(b[1]-a[1])*i/count)) for i in range(count+1))/(count+1) if self.preferred else 0
                return distance*(1.05-0.05*fraction)
            costs = [0.0]
            for a, b in zip(path, path[1:]): costs.append(costs[-1] + cost(a,b))
            reduced, i = [path[0]], 0
            while i < len(path)-1:
                if time.monotonic() > deadline:
                    raise HTTPException(503, "Die Wasserwegsuche hat ihr Zeitlimit erreicht. Setze zusätzliche Wegpunkte.")
                best = i+1
                for j in range(len(path)-1, i, -1):
                    if j % 128 == 0 and time.monotonic() > deadline:
                        raise HTTPException(503, "Die Wasserwegsuche hat ihr Zeitlimit erreicht. Versuche einen zusätzlichen Wegpunkt.")
                    if connects(path[i],path[j]) and cost(path[i],path[j]) <= (costs[j]-costs[i])*1.001:
                        best = j
                        break
                if math.dist(reduced[-1],path[best])>0.01:
                    reduced.append(path[best])
                i = best
            path = reduced
            if not self.prepared.covers(LineString(path)):
                raise HTTPException(503, DATA_ERROR)
            return path

        positions = [self.project(p.coordinate.longitude, p.coordinate.latitude) for p in request.waypoints]
        coordinates, waypoint_indices = [request.waypoints[0].coordinate.model_dump(exclude_none=True)], [0]
        for ordinal, (start, goal) in enumerate(zip(positions, positions[1:]), 1):
            if math.dist(start, goal) < 1:
                raise HTTPException(422, "Wegpunkte müssen mindestens einen Meter auseinanderliegen.")
            path = search(start, goal)
            coordinates.extend(self.coordinate(p) for p in path[1:-1])
            coordinates.append(request.waypoints[ordinal].coordinate.model_dump(exclude_none=True))
            waypoint_indices.append(len(coordinates)-1)
        if len(coordinates) > 10_000:
            raise HTTPException(422, "Zu viele Kurswechsel. Teile den Seeweg in kürzere Etappen.")
        maneuvers = []
        for index, (a, b) in enumerate(zip(coordinates, coordinates[1:])):
            p1, p2 = map(math.radians, (a["latitude"], b["latitude"]))
            dp, dl = p2-p1, math.radians(b["longitude"]-a["longitude"])
            psi = math.log(math.tan(math.pi/4+p2/2)/math.tan(math.pi/4+p1/2))
            q = dp/psi if abs(psi)>1e-12 else math.cos(p1)
            distance = 6_371_000*math.hypot(dp,q*dl)
            course = math.degrees(math.atan2(dl,psi))%360
            maneuvers.append({"instruction":f"Kurs {int(math.floor(course+0.5))%360:03}° · Kurswechsel {index+2}","distance":distance,"coordinateIndex":index,"type":11})
        return {"id":str(uuid4()),"coordinates":coordinates,"distance":sum(m["distance"] for m in maneuvers),
                "duration":0,"ascent":0,"descent":0,"maneuvers":maneuvers,"surfaces":[],"warnings":[WARNING],
                "provider":"Seeweg · OSM-Wasserwege","calculatedAt":time.time(),"waypointIndices":waypoint_indices}


class MarineRouter:
    def __init__(self, client, url):
        self.client, self.url = client, url or DEFAULT_OVERPASS
        self.lock = asyncio.Lock()
        self.cache = OrderedDict()
        self.depths = DepthTiles(client)

    async def coast_data(self, bounds):
        bbox = ",".join(f"{p:.5f}" for p in bounds)
        # Overpass working memory is separate from our streamed response limit.
        # Large Adriatic coast queries need more than 16 MiB even for small replies.
        query = (f'[out:json][timeout:20][maxsize:67108864];('
                 f'way["natural"="coastline"]({bbox});'
                 f'way["seamark:type"~"^(fairway|navigation_line|recommended_track)$"]({bbox});'
                 f'way["waterway"="fairway"]({bbox});'
                 f'nwr["seamark:type"~"^(rock|wreck|obstruction|depth_area|sounding|seabed_area)$"]({bbox});'
                 f'nwr["seamark:sea_area:category"~"^(shoal|reef|ledge)$"]({bbox});'
                 f'nwr["natural"~"^(reef|shoal|rock)$"]({bbox}););out geom;' )
        urls = [self.url] + ([FALLBACK_OVERPASS] if self.url == DEFAULT_OVERPASS else [])
        for url in urls:
            try:
                async with self.client.stream("POST", url, data={"data": query},
                        headers={"User-Agent": "BikeNavi/0.4.0 marine routing"}, timeout=25) as response:
                    response.raise_for_status()
                    body = bytearray()
                    async for chunk in response.aiter_bytes():
                        body.extend(chunk)
                        if len(body) > 16 * 1024 * 1024:
                            raise HTTPException(503, DATA_ERROR)
                data = json.loads(body)
                if not isinstance(data, dict) or data.get("remark") or not isinstance(data.get("elements"), list):
                    raise ValueError("Incomplete Overpass response")
                return data
            except (httpx.HTTPError, ValueError):
                continue
        raise HTTPException(503, "Küsten- und Seewegdaten gerade nicht erreichbar. Es wird keine ungeprüfte Verbindung berechnet.")

    async def route(self, request):
        try:
            async with asyncio.timeout(80):
                return await self._route(request)
        except TimeoutError as error:
            raise HTTPException(503,"Die Wasserwegsuche hat ihr Zeitlimit erreicht. Es wird keine ungeprüfte Verbindung verwendet.") from error

    async def _route(self, request):
        points = request.waypoints
        if any(abs(p.coordinate.latitude)>85 for p in points):
            raise HTTPException(422,"Seeweg nur zwischen 85° Süd und 85° Nord.")
        south,north = min(p.coordinate.latitude for p in points),max(p.coordinate.latitude for p in points)
        west,east = min(p.coordinate.longitude for p in points),max(p.coordinate.longitude for p in points)
        if east - west > 180:
            raise HTTPException(422, "Seewege über die Datumsgrenze werden derzeit nicht unterstützt. Die aktuelle Seewegplanung kann diese Ozeanpassage nicht berechnen.")
        scale = math.cos(math.radians((south+north)/2))
        margin = 1500/111_195
        bounds = (math.floor((south-margin)/.02)*.02,math.floor((west-margin/scale)/.02)*.02,
                  math.ceil((north+margin)/.02)*.02,math.ceil((east+margin/scale)/.02)*.02)
        if bounds[0]<-85 or bounds[2]>85 or bounds[1]<-180 or bounds[3]>180:
            raise HTTPException(422,"Für diese Randlage fehlen geeignete Küstendaten; setze die Wegpunkte innerhalb von 85° Süd/Nord und außerhalb des Datumswechsels.")
        draft = request.profile.boatDraft or 2.0
        cache_key = (bounds, draft)
        async with self.lock:
            cached = self.cache.get(cache_key)
            if cached and time.monotonic()-cached[0]<3600:
                area = cached[1]
                self.cache.move_to_end(cache_key)
            else:
                data = await self.coast_data(bounds)
                area = await asyncio.to_thread(WaterArea,data,bounds,draft)
                self.cache[cache_key] = (time.monotonic(),area)
                while len(self.cache)>4:
                    self.cache.popitem(last=False)
            provisional = await asyncio.to_thread(area.route, request)
            draft = request.profile.boatDraft or 2.0
            depth_water, known_depth_water = await self.depths.area(area, provisional, draft)
            constrained = copy.copy(area)
            constrained.water = area.water.intersection(depth_water)
            constrained.prepared = prep(constrained.water)
            constrained.corridors = area.corridors.intersection(constrained.water) if area.corridors is not None else None
            constrained.preferred = prep(constrained.corridors) if constrained.corridors is not None else None
            try:
                result = await asyncio.to_thread(constrained.route, request)
            except HTTPException as error:
                if error.status_code == 422:
                    raise HTTPException(422, 'Mit diesem Tiefgang wurde keine durchgehend tiefere EMODnet-Rasterverbindung gefunden. Bekannte flache Rasterzellen werden gemieden; keine Navigationsfreigabe.') from error
                raise
            line = LineString([area.project(c['longitude'],c['latitude']) for c in result['coordinates']])
            result['marineDepthUncertain'] = not known_depth_water.covers(line)
            if result['marineDepthUncertain']:
                result['warnings'].append('Tiefen entlang dieser Planung sind teilweise unbekannt: EMODnet löst enge Küstenbereiche nicht ausreichend auf. Diese Abschnitte sind nicht auf ausreichende Tiefe geprüft.')
            result['warnings'].append('Kartierte Untiefen, Felsen und Hindernisse werden mit 75 m geometrischem Abstand ausgeschlossen. Kartierung und Abstand sind keine vollständige nautische Sicherheitsprüfung.')
            result['marineRoutingRevision'] = 2
            result['marineDraft'] = draft
            result['marineDepthSource'] = 'EMODnet DTM 2024 · LAT'
            result['duration'] = result['distance'] / ((request.profile.boatSpeedKnots or 4.0) * 1852 / 3600)
            result['warnings'].append(DEPTH_WARNING)
            return result
