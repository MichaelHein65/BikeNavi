"""Read bounded OSM tiles from an operator-installed, verified country index."""
from datetime import datetime
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import time

from shapely.geometry import box, shape

MAX_OBJECTS = 200_000
MAX_AGE = 30 * 86400


def poi(tags):
    return tags.get('amenity') in {'drinking_water', 'bench', 'shelter'} or tags.get('tourism') in {
        'picnic_site', 'attraction', 'viewpoint', 'museum', 'information'}


def extract_elements(path, bounds):
    west, south, east, north = bounds
    query = 'minlon <= ? AND maxlon >= ? AND minlat <= ? AND maxlat >= ?'
    params = (east, west, north, south)
    connection = sqlite3.connect(Path(path).as_uri() + '?mode=ro', uri=True)
    try:
        ways = []
        needed = set()
        for payload, in connection.execute(
                f'SELECT payload FROM ways JOIN way_bounds USING(id) WHERE highway=1 AND {query}', params):
            way = json.loads(payload)
            ways.append(way); needed.update(way['nodes'])
            if len(ways) > MAX_OBJECTS or len(needed) > MAX_OBJECTS:
                raise ValueError('OSM extract tile exceeds object limit')
        nodes = {}
        refs = sorted(needed)
        for offset in range(0, len(refs), 500):
            chunk = refs[offset:offset+500]
            for id, lon, lat, version, tags in connection.execute(
                    f'SELECT * FROM nodes WHERE id IN ({",".join("?" for _ in chunk)})', chunk):
                nodes[id] = {'type': 'node', 'id': id, 'lon': lon, 'lat': lat, 'version': version, 'tags': json.loads(tags)}
        if needed - nodes.keys():
            raise ValueError('OSM extract contains incomplete road geometry')
        # Match Overpass bbox semantics: at least one way node lies inside the tile.
        ways = [w for w in ways if any(west <= nodes[n]['lon'] <= east and south <= nodes[n]['lat'] <= north for n in w['nodes'])]
        used = {n for w in ways for n in w['nodes']}
        relations = {}
        for way in ways:
            for id, payload in connection.execute(
                    'SELECT relations.id, payload FROM relations JOIN relation_ways ON relations.id=relation_ways.relation_id WHERE way_id=?', (way['id'],)):
                relations[id] = json.loads(payload)
                if len(relations) > MAX_OBJECTS:
                    raise ValueError('OSM extract restriction limit')
        places = []
        for payload, in connection.execute(f'SELECT payload FROM places JOIN place_bounds USING(id) WHERE {query}', params):
            item = json.loads(payload)
            # Match Overpass "out center tags": POI geometries must never add
            # roads outside the selection without their turn restrictions.
            item.pop('nodes', None)
            places.append(item)
            if len(places) > 20_000:
                raise ValueError('OSM extract POI limit')
        # Full nodes last preserve version and access tags when also selected as POI.
        return places + ways + list(relations.values()) + [nodes[n] for n in sorted(used)]
    finally:
        connection.close()


class LocalExtracts:
    def __init__(self, directory, manifest_pattern="*.json"):
        self.directory = Path(directory) if directory else None
        self.verified = {}
        self.manifest_pattern = manifest_pattern

    def candidates(self, x, y):
        if self.directory is None or not self.directory.is_dir():
            return None
        bounds = (x*.05-180, y*.05-90, (x+1)*.05-180, (y+1)*.05-90)
        footprint = box(*bounds).buffer(.001)
        manifests = []
        for path in self.directory.glob(self.manifest_pattern):
            try:
                manifests.append(json.loads(path.read_text()))
            except FileNotFoundError:
                continue  # Retention may remove an obsolete manifest during enumeration.
        for metadata in sorted(manifests, key=lambda m: m.get('sourceDate', ''), reverse=True):
            if metadata.get('schema') != 1:
                raise ValueError('Unknown OSM extract manifest')
            coverage = shape(metadata['coverage'])
            if not coverage.is_valid or not coverage.covers(footprint):
                continue
            stamp = datetime.fromisoformat(metadata['sourceDate'].replace('Z', '+00:00')).timestamp()
            if not 0 <= time.time() - stamp <= MAX_AGE:
                continue
            yield metadata, stamp

    def source_date(self, x, y):
        return next((stamp for _, stamp in self.candidates(x, y)), None)

    def tile(self, x, y):
        bounds = (x*.05-180, y*.05-90, (x+1)*.05-180, (y+1)*.05-90)
        for metadata, stamp in self.candidates(x, y):
            path = (self.directory / metadata['file']).resolve()
            if path.parent != self.directory.resolve() or not path.name.endswith('.sqlite'):
                raise ValueError('Invalid OSM extract path')
            stat = path.stat()
            fingerprint = (stat.st_mtime_ns, stat.st_size, metadata['sha256'])
            if self.verified.get(path) != fingerprint:
                with path.open('rb') as source:
                    if hashlib.file_digest(source, 'sha256').hexdigest() != metadata['sha256']:
                        raise ValueError('OSM extract checksum mismatch')
                with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as conn:
                    source = json.loads(conn.execute('SELECT payload FROM metadata').fetchone()[0])
                    if source['sourceDate'] != metadata['sourceDate'] or source['coverage'] != metadata['coverage']:
                        raise ValueError('OSM extract provenance mismatch')
                self.verified[path] = fingerprint
            return extract_elements(path, bounds), stamp
        return None
