"""Height lookup only: never changes or reroutes the supplied geometry."""
import math

from fastapi import HTTPException
import httpx

from .models import Coordinate, Model
from pydantic import Field


class ElevationRequest(Model):
    coordinates: list[Coordinate] = Field(min_length=2, max_length=2000)


class ElevationResponse(Model):
    altitudes: list[float] = Field(min_length=2, max_length=2000)
    source: str


async def elevations(client, key, body: ElevationRequest):
    if not key:
        raise HTTPException(503, "Der Höhendienst ist auf dem Pi nicht eingerichtet.")
    geometry = [[c.longitude, c.latitude] for c in body.coordinates]
    try:
        response = await client.post("https://api.heigit.org/openelevationservice/v0/line",
            headers={"Authorization": key},
            json={"format_in": "polyline", "format_out": "polyline", "geometry": geometry}, timeout=25)
        response.raise_for_status()
        values = response.json()["geometry"]
        altitudes, interpolated = align_heights(geometry, values)
        source = "openrouteservice · SRTM"
        if interpolated:
            noun = "Höhenpunkt" if interpolated == 1 else "Höhenpunkte"
            source += f"; {interpolated} fehlende {noun} interpoliert" if interpolated != 1 else "; 1 fehlender Höhenpunkt interpoliert"
        return ElevationResponse(altitudes=altitudes, source=source)
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        # Never expose upstream errors, credentials or coordinates in error messages.
        raise HTTPException(503, "Höhendaten sind gerade nicht verfügbar. Die Route bleibt nutzbar; versuche es später erneut.") from None


def _distance(a, b):
    lat1, lat2 = math.radians(a[1]), math.radians(b[1])
    dlat, dlon = lat2-lat1, math.radians(b[0]-a[0])
    value = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return 12_742_000 * math.asin(min(1, math.sqrt(value)))


def align_heights(geometry, values):
    """Match the returned subsequence by position, never by shifted array index.

    ORS can omit individual SRTM voids (notably coastal pixels). Interpolate
    only small interior holes, bounded by actual heights on both sides.
    """
    if not isinstance(values, list) or not 2 <= len(values) <= len(geometry):
        raise ValueError("Incomplete elevation geometry")
    heights = [None] * len(geometry)
    cursor = 0
    for actual in values:
        if (not isinstance(actual, list) or len(actual) != 3
                or any(type(v) not in (int, float) or not math.isfinite(v) for v in actual)
                or not -500 <= actual[2] <= 9000):
            raise ValueError("Invalid elevation sample")
        while cursor < len(geometry) and (abs(actual[0]-geometry[cursor][0]) > 0.00001
                                         or abs(actual[1]-geometry[cursor][1]) > 0.00001):
            cursor += 1
        if cursor == len(geometry):
            raise ValueError("Reordered or displaced elevation geometry")
        heights[cursor] = actual[2]
        cursor += 1
    missing = sum(h is None for h in heights)
    if heights[0] is None or heights[-1] is None or missing > 8:
        raise ValueError("Elevation coverage too sparse")
    index = 1
    while index < len(heights)-1:
        if heights[index] is not None:
            index += 1
            continue
        start = index-1
        while heights[index] is None:
            index += 1
        end = index
        distances = [0.0]
        for a, b in zip(geometry[start:end], geometry[start+1:end+1]):
            distances.append(distances[-1] + _distance(a, b))
        if end-start-1 > 2 or distances[-1] > 100:
            raise ValueError("Elevation hole too long")
        for i in range(start+1, end):
            t = distances[i-start]/distances[-1] if distances[-1] else 0.5
            heights[i] = heights[start] + (heights[end]-heights[start])*t
    return heights, missing
