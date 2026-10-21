"""Daily Croatia extract maintenance; run in the dedicated Pi updater container."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import time
import uuid

import httpx
import osmium

from prepare_offline_extract import prepare
from bikenavi.osm_extract import LocalExtracts
from bikenavi.offline import compile_tile

BASE = 'https://download.geofabrik.de/europe/croatia'
MAX_SOURCE_AGE = 7 * 86400
RESERVE = 5 * 1024**3
MIN_COUNTS = {"nodes": 10_000_000, "ways": 1_000_000}


def timestamp(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as handle:
        json.dump(value, handle, ensure_ascii=False)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)
    sync_directory(path.parent)


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def download(client, url, target, limit):
    deadline = time.monotonic() + 900
    size = 0
    with client.stream('GET', url) as response:
        response.raise_for_status()
        with target.open('wb') as handle:
            for chunk in response.iter_bytes():
                size += len(chunk)
                if size > limit or time.monotonic() > deadline:
                    raise ValueError('Download exceeds size/time limit')
                handle.write(chunk)
    if not size:
        raise ValueError('Empty download')


def checksum(client, stage):
    target = stage / 'checksum.txt'
    download(client, BASE + '-latest.osm.pbf.md5', target, 4096)
    value = target.read_text().split()[0]
    if not re.fullmatch('[a-fA-F0-9]{32}', value):
        raise ValueError('Invalid upstream checksum')
    return value.lower()


def validate(directory, pattern="*.json"):
    """Exercise the same verified reader and compiler as the serving backend."""
    result = LocalExtracts(directory, pattern).tile(3912, 2675)
    if result is None:
        raise ValueError('Croatia extract does not cover the Tisno reference tile')
    elements, stamp = result
    tile = compile_tile(elements, 3912, 2675, generated_at=stamp)
    if not tile['nodes'] or not tile['edges']:
        raise ValueError('Croatia reference tile has no routable graph')
    return stamp


def cleanup(directory):
    # Only our generations, keep at least two and every file younger than a week.
    manifests = sorted(directory.glob('croatia-auto-*.json'),
                       key=lambda p: json.loads(p.read_text())['sourceDate'], reverse=True)
    protected = {p.with_suffix('.sqlite') for p in manifests[:2]}
    for path in manifests[2:]:
        if time.time() - path.stat().st_mtime > 7 * 86400:
            path.unlink()
    referenced = {p.with_suffix('.sqlite') for p in directory.glob('croatia-auto-*.json')}
    for path in directory.glob('croatia-auto-*.sqlite'):
        if path not in referenced | protected and time.time() - path.stat().st_mtime > 7 * 86400:
            path.unlink()


def update(directory, client):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    work = directory / '.updates'
    work.mkdir(exist_ok=True)
    with (work / 'update.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('Another extract update is already running', flush=True)
            return
        stage = work / 'staging'
        shutil.rmtree(stage, ignore_errors=True)
        stage.mkdir()
        status = {'checkedAt': datetime.now(timezone.utc).isoformat()}
        try:
            # Remove only obsolete updater-owned files, before the free-space check.
            cleanup(directory)
            md5 = checksum(client, stage)
            manifests = [json.loads(p.read_text()) for p in directory.glob('croatia-auto-*.json')]
            current = max(manifests, key=lambda m: m['sourceDate']) if manifests else None
            if current and current.get('pbfMD5') == md5:
                age = time.time() - timestamp(current['sourceDate'])
                if not 0 <= age <= MAX_SOURCE_AGE:
                    raise ValueError('Upstream extract has not advanced within seven days')
                # Verify active data even on an unchanged upstream; never report false success.
                validate(directory, Path(current['file']).with_suffix('.json').name)
                status.update(result='unchanged', sourceDate=current['sourceDate'], file=current['file'])
            else:
                if shutil.disk_usage(directory).free < RESERVE:
                    raise ValueError('At least 5 GiB free disk space required for a safe update')
                print('Downloading Croatia PBF and boundary', flush=True)
                pbf, poly = stage / 'source.osm.pbf', stage / 'source.poly'
                download(client, BASE + '-latest.osm.pbf', pbf, 1024**3)
                with pbf.open('rb') as handle:
                    actual = hashlib.file_digest(handle, 'md5').hexdigest()
                if actual != md5 or checksum(client, stage) != md5:
                    raise ValueError('PBF checksum mismatch or upstream changed during download')
                download(client, BASE + '.poly', poly, 1024**2)
                with osmium.io.Reader(str(pbf)) as reader:
                    source_date = reader.header().get('osmosis_replication_timestamp')
                age = time.time() - timestamp(source_date)
                if not 0 <= age <= MAX_SOURCE_AGE:
                    raise ValueError('New extract is too old or from the future')
                installed = [json.loads(p.read_text()) for p in directory.glob('*.json')]
                if any(timestamp(source_date) < timestamp(m['sourceDate']) for m in installed
                       if m['file'].startswith('croatia-')):
                    raise ValueError('Refusing source timestamp regression')
                if shutil.disk_usage(directory).free < max(RESERVE, pbf.stat().st_size * 12):
                    raise ValueError('Insufficient space for expanded OSM index')
                name = 'croatia-auto-' + re.sub('[^0-9]', '', source_date) + '-' + uuid.uuid4().hex[:8]
                output = stage / (name + '.sqlite')
                prepare(pbf, poly, output)
                validate(stage)
                with sqlite3.connect(output) as connection:
                    counts = {table: connection.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
                              for table in ('nodes', 'ways')}
                # Reject radically truncated files even when the reference tile survives.
                if any(counts[t] < MIN_COUNTS[t] or counts[t] < (current or {}).get('counts', {}).get(t, 0) * .8
                       for t in counts):
                    raise ValueError('Croatia index unexpectedly small')
                manifest = json.loads(output.with_suffix('.json').read_text())
                manifest.update(pbfMD5=md5, counts=counts)
                output.chmod(0o644)
                with output.open('rb') as handle:
                    os.fsync(handle.fileno())
                output.rename(directory / output.name)
                sync_directory(directory)
                # Publish last: an interrupted import never becomes a serving candidate.
                atomic_json(directory / (name + '.json'), manifest)
                status.update(result='updated', sourceDate=source_date, file=output.name, counts=counts)
            atomic_json(work / 'status.json', status)
            print(json.dumps(status), flush=True)
        except Exception as error:
            status.update(result='failed', error=type(error).__name__ + ': ' + str(error))
            atomic_json(work / 'status.json', status)
            raise
        finally:
            shutil.rmtree(stage, ignore_errors=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    with httpx.Client(follow_redirects=True, timeout=60,
                      headers={'User-Agent': 'BikeNavi country extract updater (daily)'}) as client:
        update(args.directory, client)
