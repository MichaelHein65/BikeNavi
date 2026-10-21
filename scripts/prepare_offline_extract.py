"""Index a Geofabrik PBF with its matching .poly for fast, offline Pi downloads.

Usage: .venv/bin/python scripts/prepare_offline_extract.py FILE.osm.pbf FILE.poly OUTPUT.sqlite
Install OUTPUT.sqlite and OUTPUT.json together in server/data/osm on the Pi.
Requires osmium==4.3.2 (operator tool only); never downloads files automatically.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import osmium
from shapely.geometry import Polygon, MultiPolygon, mapping

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from bikenavi.osm_extract import poi


def boundary(path):
    lines = iter(Path(path).read_text().splitlines()[1:])
    outers, holes = [], []
    for name in lines:
        if name.strip() == 'END':
            break
        points = []
        for line in lines:
            if line.strip() == 'END':
                break
            points.append(tuple(map(float, line.split())))
        (holes if name.strip().startswith('!') else outers).append(Polygon(points))
    geometry = MultiPolygon(outers)
    for hole in holes:
        geometry = geometry.difference(hole)
    if geometry.is_empty or not geometry.is_valid:
        raise ValueError('Invalid extract boundary')
    return json.loads(json.dumps(mapping(geometry)))


def prepare(pbf, poly, output):
    pbf, output = Path(pbf), Path(output)
    if output.exists() or output.with_suffix('.json').exists():
        raise ValueError('Use a new versioned output filename; existing extracts remain intact')
    with osmium.io.Reader(str(pbf)) as reader:
        stamp = reader.header().get('osmosis_replication_timestamp')
    if not stamp:
        raise ValueError('PBF must contain an OSM source timestamp')
    source = {'sourceDate': stamp, 'coverage': boundary(poly), 'source': 'Geofabrik / OpenStreetMap', 'license': 'ODbL-1.0'}
    staging = output.with_suffix('.partial')
    if staging.exists():
        raise ValueError('A staging file already exists; inspect before retrying')
    conn = sqlite3.connect(staging)
    conn.executescript('''
        PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA cache_size=-32768;
        CREATE TABLE metadata(payload TEXT);
        CREATE TABLE nodes(id INTEGER PRIMARY KEY, lon REAL, lat REAL, version INTEGER, tags TEXT);
        CREATE TABLE ways(id INTEGER PRIMARY KEY, highway INTEGER, payload TEXT);
        CREATE VIRTUAL TABLE way_bounds USING rtree(id,minlon,maxlon,minlat,maxlat);
        CREATE TABLE relations(id INTEGER PRIMARY KEY,payload TEXT);
        CREATE TABLE relation_ways(way_id INTEGER,relation_id INTEGER);
        CREATE TABLE places(id INTEGER PRIMARY KEY,payload TEXT);
        CREATE VIRTUAL TABLE place_bounds USING rtree(id,minlon,maxlon,minlat,maxlat);
    ''')
    conn.execute('INSERT INTO metadata VALUES(?)', (json.dumps(source),))
    def place(item, bounds):
        item = {key: value for key, value in item.items() if key != 'nodes'}
        west, east, south, north = bounds
        if item['type'] != 'node':
            item['center'] = {'lon': (west+east)/2, 'lat': (south+north)/2}
        id = conn.execute('INSERT INTO places(payload) VALUES(?)', (json.dumps(item),)).lastrowid
        conn.execute('INSERT INTO place_bounds VALUES(?,?,?,?,?)', (id,west,east,south,north))
    def node_rows(refs):
        result = []
        for offset in range(0,len(refs),500):
            chunk = refs[offset:offset+500]
            result.extend(conn.execute(f'SELECT lon,lat FROM nodes WHERE id IN ({",".join("?" for _ in chunk)})',chunk))
        return result
    class Index(osmium.SimpleHandler):
        def __init__(self):
            super().__init__(); self.batch=[]; self.node_count=0; self.way_count=0; self.missing=0
        def flush(self):
            conn.executemany('INSERT INTO nodes VALUES(?,?,?,?,?)',self.batch); self.batch=[]
        def node(self,n):
            self.batch.append((n.id,n.lon,n.lat,n.version,json.dumps(dict(n.tags),separators=(',',':')) if len(n.tags) else '{}'))
            self.node_count+=1
            if len(self.batch)>=10000:self.flush()
            if poi(n.tags):place({'type':'node','id':n.id,'lon':n.lon,'lat':n.lat,'tags':dict(n.tags)},(n.lon,n.lon,n.lat,n.lat))
        def way(self,w):
            if self.batch:self.flush()
            refs=[n.ref for n in w.nodes]
            coords=node_rows(list(set(refs)))
            if len(coords)!=len(set(refs)) or not coords:
                self.missing+=1
                if 'highway' in w.tags:raise ValueError('PBF has an incomplete highway; use a complete-way extract')
                return
            bounds=(min(c[0] for c in coords),max(c[0] for c in coords),min(c[1] for c in coords),max(c[1] for c in coords))
            item={'type':'way','id':w.id,'nodes':refs,'tags':dict(w.tags)}
            conn.execute('INSERT INTO ways VALUES(?,?,?)',(w.id,int('highway' in w.tags),json.dumps(item,separators=(',',':'))))
            conn.execute('INSERT INTO way_bounds VALUES(?,?,?,?,?)',(w.id,*bounds))
            if poi(w.tags):place(item,bounds)
            self.way_count+=1
        def relation(self,r):
            if self.batch:self.flush()
            if r.tags.get('type')=='restriction':
                item={'type':'relation','id':r.id,'tags':dict(r.tags),'members':[
                    {'type':{'n':'node','w':'way','r':'relation'}[m.type],'ref':m.ref,'role':m.role} for m in r.members]}
                conn.execute('INSERT INTO relations VALUES(?,?)',(r.id,json.dumps(item)))
                conn.executemany('INSERT INTO relation_ways VALUES(?,?)',[(m.ref,r.id) for m in r.members if m.type=='w'])
            elif poi(r.tags) and not any(m.type=='r' for m in r.members):
                bounds=[]
                for m in r.members:
                    row=(conn.execute('SELECT minlon,maxlon,minlat,maxlat FROM way_bounds WHERE id=?',(m.ref,)).fetchone() if m.type=='w' else
                         conn.execute('SELECT lon,lon,lat,lat FROM nodes WHERE id=?',(m.ref,)).fetchone())
                    if row is None:return
                    bounds.append(row)
                if bounds:place({'type':'relation','id':r.id,'tags':dict(r.tags)},(
                    min(b[0] for b in bounds),max(b[1] for b in bounds),min(b[2] for b in bounds),max(b[3] for b in bounds)))
    try:
        index=Index(); index.apply_file(str(pbf)); index.flush()
        conn.execute('CREATE INDEX restriction_way ON relation_ways(way_id)'); conn.commit()
        if conn.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('OSM index integrity check failed')
        conn.close()
        staging.rename(output)
        with output.open('rb') as handle:digest=hashlib.file_digest(handle,'sha256').hexdigest()
        metadata={'schema':1,'file':output.name,'sha256':digest,**source}
        manifest = output.with_suffix('.json.partial')
        manifest.write_text(json.dumps(metadata,ensure_ascii=False))
        manifest.rename(output.with_suffix('.json'))
        print(f'Index: {output}; OSM: {stamp}; nodes={index.node_count}, ways={index.way_count}, incomplete non-road ways skipped={index.missing}',flush=True)
    except BaseException:
        conn.close()
        staging.unlink(missing_ok=True)
        raise


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pbf',type=Path);parser.add_argument('poly',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();prepare(args.pbf,args.poly,args.output)


if __name__=='__main__':main()
