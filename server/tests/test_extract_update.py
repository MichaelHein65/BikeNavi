"""Real miniature PBF imports, failed updates and generation-aware cache checks."""
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
from types import SimpleNamespace

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import update_offline_extract as updater
from bikenavi.main import create_app
from test_osm_extract import make_extract
from test_offline import AUTH, TOKEN


@pytest.fixture
def source(tmp_path, monkeypatch):
    folder = tmp_path / 'source'; folder.mkdir()
    make_extract(folder)
    monkeypatch.setattr(updater, 'MIN_COUNTS', {'nodes': 1, 'ways': 1})
    monkeypatch.setattr(updater.shutil, 'disk_usage', lambda _: SimpleNamespace(free=20 * 1024**3))
    return folder


def client_for(source, calls=None, failure=None):
    pbf = (source / 'source.osm.pbf').read_bytes()
    digest = hashlib.md5(pbf).hexdigest()
    def respond(request):
        if calls is not None: calls.append(request.url.path)
        if failure == 'http': return httpx.Response(503)
        if request.url.path.endswith('.md5'):
            return httpx.Response(200, text=('0'*32 if failure == 'checksum' else digest) + '  croatia-latest.osm.pbf\n')
        if request.url.path.endswith('.pbf'): return httpx.Response(200, content=pbf)
        return httpx.Response(200, content=(source/'coverage.poly').read_bytes())
    return httpx.Client(transport=httpx.MockTransport(respond))


def test_atomic_publication_and_no_download_when_unchanged(tmp_path, source, monkeypatch):
    target = tmp_path / 'maps'
    real_prepare = updater.prepare
    def checked_prepare(*args):
        real_prepare(*args)
        assert not list(target.glob('*.json'))  # only staging visible during preparation
    monkeypatch.setattr(updater, 'prepare', checked_prepare)
    calls = []
    with client_for(source, calls) as client:
        updater.update(target, client)
        manifest = next(target.glob('*.json'))
        data = json.loads(manifest.read_text())
        assert data['counts'] == {'nodes': 5, 'ways': 2}
        assert (target/data['file']).is_file()
        assert not (target/'.updates/staging').exists()
        calls.clear()
        updater.update(target, client)
    assert calls == ['/europe/croatia-latest.osm.pbf.md5']
    assert json.loads((target/'.updates/status.json').read_text())['result'] == 'unchanged'
    assert list(target.glob('*.json')) == [manifest]


@pytest.mark.parametrize('failure', ['http', 'checksum', 'import', 'validation', 'space', 'small'])
def test_failed_update_preserves_previous_generation(tmp_path, source, monkeypatch, failure):
    target = tmp_path / 'maps'; target.mkdir()
    make_extract(target, age=2)
    before = {p.name: p.read_bytes() for p in target.glob('example.*')}
    def fail(*_): raise ValueError('Injected import/validation failure')
    if failure == 'import': monkeypatch.setattr(updater, 'prepare', fail)
    if failure == 'validation': monkeypatch.setattr(updater, 'validate', fail)
    if failure == 'space': monkeypatch.setattr(updater.shutil, 'disk_usage', lambda _: SimpleNamespace(free=0))
    if failure == 'small': monkeypatch.setattr(updater, 'MIN_COUNTS', {'nodes': 10_000_000, 'ways': 1_000_000})
    with client_for(source, failure=failure) as client, pytest.raises((ValueError, httpx.HTTPError)):
        updater.update(target, client)
    assert {p.name: p.read_bytes() for p in target.glob('example.*')} == before
    assert not list(target.glob('croatia-auto-*'))
    assert json.loads((target/'.updates/status.json').read_text())['result'] == 'failed'
    assert not (target/'.updates/staging').exists()


@pytest.mark.parametrize('age', [8, -1])
def test_stale_or_future_source_rejected(tmp_path, monkeypatch, age):
    monkeypatch.setattr(updater.shutil, 'disk_usage', lambda _: SimpleNamespace(free=20 * 1024**3))
    source = tmp_path/'source'; source.mkdir(); make_extract(source, age=age)
    target = tmp_path/'maps'
    with client_for(source) as client, pytest.raises(ValueError, match='old or from the future'):
        updater.update(target, client)
    assert not list(target.glob('*.json'))


def test_timestamp_cannot_regress_against_manual_country(tmp_path, source):
    target = tmp_path/'maps'; target.mkdir(); make_extract(target, age=0.5)
    data = json.loads((target/'example.json').read_text())
    data['file'] = 'croatia-manual.sqlite'
    (target/'example.sqlite').rename(target/data['file'])
    (target/'example.json').write_text(json.dumps(data))
    with client_for(source) as client, pytest.raises(ValueError, match='regression'):
        updater.update(target, client)
    assert not list(target.glob('croatia-auto-*'))


def test_lock_prevents_overlapping_runs(tmp_path, source):
    work = tmp_path/'maps/.updates'; work.mkdir(parents=True)
    calls = []
    with (work/'update.lock').open('a') as lock, client_for(source, calls) as client:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        updater.update(work.parent, client)
    assert calls == []


def test_retention_keeps_two_generations_recent_files_and_manual_data(tmp_path):
    for i in range(5):
        p = tmp_path/f'croatia-auto-{i}.json'
        p.write_text(json.dumps({'sourceDate': f'2026-10-{i+1:02}T00:00:00Z'}))
        p.with_suffix('.sqlite').write_text('example')
        if i != 0:  # even an older source is retained when it was recently installed
            for f in [p, p.with_suffix('.sqlite')]: os.utime(f, (1, 1))
    manual = tmp_path/'croatia-manual.sqlite'; manual.write_text('manual')
    updater.cleanup(tmp_path)
    assert {p.stem for p in tmp_path.glob('croatia-auto-*.json')} == {'croatia-auto-0', 'croatia-auto-3', 'croatia-auto-4'}
    assert len(list(tmp_path.glob('*.sqlite'))) == 4
    assert manual.read_text() == 'manual'


def test_new_source_invalidates_cache_without_refresh_and_failure_keeps_cache(tmp_path, monkeypatch):
    target = tmp_path/'maps'; target.mkdir(); make_extract(target, age=2)
    monkeypatch.setenv('OFFLINE_EXTRACT_DIR', str(target))
    app = create_app(f'sqlite:///{tmp_path/"api.sqlite"}', token=TOKEN, overpass_url='')
    with TestClient(app) as client:
        first = client.get('/v1/region-tiles/3912/2675', headers=AUTH)
        assert first.status_code == 200
        newer = tmp_path/'new'; newer.mkdir(); make_extract(newer, age=1)
        metadata = json.loads((newer/'example.json').read_text()); metadata['file'] = 'new.sqlite'
        shutil.copyfile(newer/'example.sqlite', target/'new.sqlite')
        (target/'new.json').write_text(json.dumps(metadata))
        second = client.get('/v1/region-tiles/3912/2675', headers=AUTH)
        assert second.status_code == 200 and second.json()['sha256'] != first.json()['sha256']
        metadata['sourceDate'] = datetime.now(timezone.utc).isoformat()
        metadata['sha256'] = '0'*64
        (target/'new.json').write_text(json.dumps(metadata))
        third = client.get('/v1/region-tiles/3912/2675', headers=AUTH)
        assert third.json() == second.json()


def test_upstream_change_during_download_is_not_published(tmp_path, source, monkeypatch):
    checksums = iter([hashlib.md5((source/'source.osm.pbf').read_bytes()).hexdigest(), '1'*32])
    monkeypatch.setattr(updater, 'checksum', lambda *_: next(checksums))
    with client_for(source) as client, pytest.raises(ValueError, match='upstream changed'):
        updater.update(tmp_path/'maps', client)
    assert not list((tmp_path/'maps').glob('*.json'))


def test_unchanged_source_is_verified_and_expiry_reported(tmp_path, source, monkeypatch):
    target = tmp_path/'maps'
    with client_for(source) as client:
        updater.update(target, client)
        manifest = next(target.glob('*.json'))
        metadata = json.loads(manifest.read_text())
        with (target/metadata['file']).open('ab') as file: file.write(b'broken')
        with pytest.raises(ValueError, match='checksum'):
            updater.update(target, client)
        assert json.loads((target/'.updates/status.json').read_text())['result'] == 'failed'
        monkeypatch.setattr(updater.time, 'time', lambda: updater.timestamp(metadata['sourceDate']) + 8*86400)
        with pytest.raises(ValueError, match='seven days'):
            updater.update(target, client)


def test_download_is_bounded(tmp_path):
    with httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=b'0123456789'))) as client:
        with pytest.raises(ValueError, match='limit'):
            updater.download(client, 'https://example.test/map', tmp_path/'part', 5)


def test_reader_tolerates_retention_removing_obsolete_manifest(tmp_path, monkeypatch):
    make_extract(tmp_path)
    obsolete = tmp_path/'croatia-auto-obsolete.json'
    obsolete.write_text('{}')
    read = Path.read_text
    def during_cleanup(path, *args, **kwargs):
        if path == obsolete:
            raise FileNotFoundError('Retention removed this entry after directory enumeration')
        return read(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'read_text', during_cleanup)
    assert updater.validate(tmp_path) > 0
