"""Mapped nautical hazards are hard exclusions, never route-cost preferences."""
import math

from fastapi import HTTPException
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import polygonize_full, unary_union

# Conservative geometric test margin, not a certified nautical clearance.
HAZARD_MARGIN = 75
ERROR = "Gefahrenstellen sind unvollständig kartiert. Keine Seewegverbindung berechnet."


def is_hazard(tags, draft):
    kind = tags.get("seamark:type")
    if kind in {"rock", "wreck", "obstruction"} or tags.get("natural") in {"reef", "shoal", "rock"}:
        return True
    if tags.get("seamark:sea_area:category") in {"shoal", "reef", "ledge"}:
        return True
    if kind == "seabed_area":
        return (tags.get("seamark:seabed_area:water_level") in {"covers", "awash", "dry"}
                or tags.get("seamark:seabed_area:surface") in {"rocky", "coral"})
    if kind in {"depth_area", "sounding"}:
        key = "seamark:depth_area:minimum_depth" if kind == "depth_area" else "seamark:sounding:depth"
        try:
            depth = float(tags[key])
            return not math.isfinite(depth) or depth <= draft
        except (ValueError, KeyError, TypeError):
            return True
    return False


def exclusions(elements, project, draft):
    def coords(geometry):
        if not isinstance(geometry, list) or len(geometry) < 2:
            raise HTTPException(503, ERROR)
        result = []
        for point in geometry:
            if not isinstance(point, dict) or not (-85 <= point.get("lat", 100) <= 85 and -180 <= point.get("lon", 1000) <= 180):
                raise HTTPException(503, ERROR)
            result.append(project(point["lon"], point["lat"]))
        return result

    blocked = []
    for element in elements:
        if not is_hazard(element.get("tags", {}), draft):
            continue
        kind = element.get("type")
        if kind == "node":
            xy = coords([element, element])[0]
            geometry = Point(xy)
        elif kind == "way":
            points = coords(element.get("geometry"))
            tags = element.get("tags", {})
            area_only = (tags.get("natural") == "shoal" or tags.get("seamark:sea_area:category") in {"shoal", "reef", "ledge"}
                         or tags.get("seamark:type") == "depth_area")
            if area_only and (len(points) < 4 or points[0] != points[-1]):
                raise HTTPException(503, ERROR)
            geometry = Polygon(points) if len(points) >= 4 and points[0] == points[-1] else LineString(points)
        elif kind == "relation":
            # Fill complete outer rings conservatively, including interior holes.
            # Missing/open rings must not silently become passable water.
            outer = [LineString(coords(m.get("geometry"))) for m in element.get("members", [])
                     if m.get("type") == "way" and m.get("role", "") in {"", "outer"}]
            if not outer:
                raise HTTPException(503, ERROR)
            polygons, cuts, dangles, invalid = polygonize_full(unary_union(outer))
            if polygons.is_empty or not cuts.is_empty or not dangles.is_empty or not invalid.is_empty:
                raise HTTPException(503, ERROR)
            geometry = polygons
        else:
            raise HTTPException(503, ERROR)
        if not geometry.is_valid:
            raise HTTPException(503, ERROR)
        blocked.append(geometry.buffer(HAZARD_MARGIN))
    return unary_union(blocked)
