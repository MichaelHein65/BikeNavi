"""Bounded, checksummed regional building blocks. OSM data remains ODbL."""
import base64
import hashlib
import json


def tile_package(tile):
    data = json.dumps(tile, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False).encode()
    return {"schema": 1, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "data": base64.b64encode(data).decode()}


def extract_pois(elements):
    result = []
    seen = set()
    for item in elements:
        tags = item.get("tags", {})
        category = ("water" if tags.get("amenity") == "drinking_water" else
                    "rest" if tags.get("amenity") in {"bench", "shelter"} or tags.get("tourism") == "picnic_site" else
                    "tourism" if tags.get("tourism") in {"attraction", "viewpoint", "museum", "information"} else None)
        center = item if item.get("type") == "node" else item.get("center", {})
        lat, lon = center.get("lat"), center.get("lon")
        if category is None or not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
            continue
        if not -90 <= lat <= 90 or not -180 <= lon <= 180 or tags.get("access") in {"private", "no"}:
            continue
        if category == "water" and tags.get("drinking_water") == "no":
            continue
        identity = (item['type'], item['id'])
        if identity in seen:
            continue
        seen.add(identity)
        result.append({"id": f'{item["type"]}/{item["id"]}', "name": str(tags.get("name", ""))[:300],
                       "category": category, "coordinate": {"latitude": lat, "longitude": lon},
                       "source": "OpenStreetMap", "openingHours": str(tags.get("opening_hours", ""))[:500] or None})
        if len(result) >= 20000:
            break
    return result
