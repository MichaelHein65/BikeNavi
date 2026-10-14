"""Disposable local HTTPS API using the production water router and public OSM data.

No Pi access or private tours. Overpass geometry is a dated public fixture, not
a mocked route. Start with uvicorn and a temporary test certificate on port 18445.
"""
import gzip
import re
from urllib.parse import unquote
import json
import tempfile
from pathlib import Path

import httpx

from bikenavi.main import create_app

DATA = json.loads(Path(__file__).with_name("tribunj-sibenik-marine-osm.json").read_text())
DEPTHS = json.loads(gzip.decompress(Path(__file__).with_name("emodnet-tribunj-2024.json.gz").read_bytes()))["tiles"]
TOKEN = "marine-qa-" + "a" * 40  # Public, disposable local-test credential only.
DIRECTORY = tempfile.TemporaryDirectory(prefix="bikenavi-marine-qa-")


def upstream(request):
    if request.url.host == "erddap.emodnet.eu":
        matches = re.findall(r"\[\(([-.0-9]+)\):1:\(([-.0-9]+)\)\]", unquote(request.url.query.decode()))
        if matches:
            key = f"{round(float(matches[0][0])*10)},{round(float(matches[1][0])*10)}"
            if key in DEPTHS: return httpx.Response(200,json=DEPTHS[key])
        return httpx.Response(404)
    if request.method == "GET" and "coastline" in request.url.params.get("data", ""):
        return httpx.Response(200, json=DATA)
    return httpx.Response(503, json={"detail": "No external services in the public example server."})


app = create_app(f"sqlite:///{DIRECTORY.name}/example.sqlite", token=TOKEN, ors_key="",
                 transport=httpx.MockTransport(upstream))
