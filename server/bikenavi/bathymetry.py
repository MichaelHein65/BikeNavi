"""EMODnet raster constraints for experimental planning, never navigational clearance."""
import asyncio
import json
import math
import time
from collections import OrderedDict

import httpx
import numpy as np
from fastapi import HTTPException
from shapely import set_precision
from shapely.geometry import LineString, box
from shapely.ops import unary_union
from shapely.prepared import prep

URL = 'https://erddap.emodnet.eu/erddap/griddap/bathymetry_dtm_2024.json'
STEP = 1 / 960  # Native 1/16 arc minute cells, centres offset by half a cell.
WARNING = 'EMODnet DTM 2024 · nicht zur Navigation geeignet. Grobe Rastertiefen bezogen auf LAT; teils Zellmittelwerte statt geringster Tiefe. Keine Prüfung von Wasserstand, Hindernissen oder aktueller Befahrbarkeit.'
ERROR = 'EMODnet-Tiefendaten fehlen oder sind nicht erreichbar. Keine Planung mit ungeprüfter Wassertiefe möglich.'


class DepthTiles:
    def __init__(self, client):
        self.client = client
        self.cache = OrderedDict()
        self.semaphore = asyncio.Semaphore(3)

    async def tile(self, key):
        cached = self.cache.get(key)
        if cached and time.monotonic() - cached[0] < 86400:
            self.cache.move_to_end(key)
            return cached[1]
        # 96x96 native cells per 0.1 degree tile; no resampling over shoals.
        y, x = key
        south, west = y / 10, x / 10
        query = ','.join(f'{field}[({south+STEP/2:.9f}):1:({south+.1-STEP/2:.9f})][({west+STEP/2:.9f}):1:({west+.1-STEP/2:.9f})]' for field in ('elevation_max', 'elevation'))
        async with self.semaphore:
            try:
                async with self.client.stream('GET', URL + '?' + query, timeout=30) as response:
                    # Fixed DTM 2024 coordinate footprint from its official ERDDAP metadata.
                    # Distinguish outside-coverage 404s from a temporary provider outage.
                    if response.status_code == 404 and not (15 <= south < 90 and -36 <= west < 43):
                        raise HTTPException(422, 'Diese Passage liegt außerhalb der verfügbaren EMODnet-Tiefenabdeckung. Eine weltweite Seewegplanung ist mit dieser Datenquelle noch nicht möglich.')
                    response.raise_for_status()
                    body = bytearray()
                    async for chunk in response.aiter_bytes():
                        body.extend(chunk)
                        if len(body) > 2 * 1024 * 1024:
                            raise ValueError('Oversized depth tile')
                table = json.loads(body)['table']
                columns = table['columnNames']
                rows = table['rows']
                if not 1 <= len(rows) <= 10000:
                    raise ValueError('Invalid depth tile')
                indices = [columns.index(n) for n in ('latitude', 'longitude', 'elevation_max', 'elevation')]
                values = []
                for row in rows:
                    lat, lon, high, mean = [row[i] for i in indices]
                    if not (math.isfinite(lat) and math.isfinite(lon) and south-STEP/10 <= lat <= south+.1+STEP/10 and west-STEP/10 <= lon <= west+.1+STEP/10):
                        raise ValueError('Depth tile coordinate mismatch')
                    # Highest elevation is the shallowest known cell value; mean is explicitly a fallback.
                    candidates = [v for v in (high, mean) if isinstance(v, (int, float)) and math.isfinite(v)]
                    # Zero/positive maxima represent drying/land cells. A negative
                    # mean must never override a known shallowest elevation.
                    elevation = max(candidates) if candidates else math.nan
                    lat = (round(lat / STEP - .5) + .5) * STEP
                    lon = (round(lon / STEP - .5) + .5) * STEP
                    values.append((lat, lon, -elevation))
                result = np.asarray(values, dtype=float)
            except (ValueError, KeyError, TypeError, IndexError, httpx.HTTPError) as error:
                raise HTTPException(503, ERROR) from error
        self.cache[key] = (time.monotonic(), result)
        self.cache.move_to_end(key)
        while len(self.cache) > 128:
            self.cache.popitem(last=False)
        return result

    async def area(self, area, provisional, draft):
        # Only a corridor of native tiles is loaded, so long passages do not need a rectangular sea-wide download.
        line = LineString([(c['longitude'], c['latitude']) for c in provisional['coordinates']])
        corridor = line.buffer(.025)  # ~2 km either side in European seas; one tile neighbour on the boundary.
        candidates = set()
        coords = list(line.coords)
        for a, b in zip(coords, coords[1:]):
            steps = max(1, math.ceil(max(abs(a[0]-b[0]), abs(a[1]-b[1])) / .04))
            for i in range(steps+1):
                x = math.floor((a[0]+(b[0]-a[0])*i/steps)*10)
                y = math.floor((a[1]+(b[1]-a[1])*i/steps)*10)
                candidates.update((y+dy, x+dx) for dy in (-1,0,1) for dx in (-1,0,1))
        keys = sorted((y,x) for y,x in candidates if corridor.intersects(box(x/10, y/10, (x+1)/10, (y+1)/10)))
        # Work in batches instead of allocating a task for every tile of a long voyage.
        tiles = []
        for i in range(0, len(keys), 3):
            tiles.extend(await asyncio.gather(*(self.tile(k) for k in keys[i:i+3])))
        known = await asyncio.to_thread(self.water, area, tiles, draft, False)
        allowed = await asyncio.to_thread(self.water, area, tiles, draft, True)
        return allowed, known

    @staticmethod
    def water(area, tiles, draft, include_unknown=False):
        rectangles = []
        for values in tiles:
            # Merge contiguous cells by latitude; gaps and NaNs never become navigable by interpolation.
            for latitude in np.unique(values[:, 0]):
                row = values[values[:, 0] == latitude]
                row = row[np.argsort(row[:, 1])]
                start = previous = None
                def append(end):
                    if start is not None:
                        rectangles.append(set_precision(box(*area.project(start-STEP/2, latitude-STEP/2), *area.project(end+STEP/2, latitude+STEP/2)), .001))
                for _, longitude, depth in row:
                    if (math.isfinite(depth) and depth > draft) or (include_unknown and not math.isfinite(depth)):
                        if start is None or longitude-previous > STEP*1.1:
                            append(previous)
                            start = longitude
                        previous = longitude
                    else:
                        append(previous)
                        start = previous = None
                append(previous)
        if not rectangles:
            if include_unknown: return box(0, 0, 0, 0)
            raise HTTPException(422, 'Keine EMODnet-Rasterzellen tiefer als der eingestellte Tiefgang vorhanden. Keine Navigationsfreigabe.')
        return unary_union(rectangles)
