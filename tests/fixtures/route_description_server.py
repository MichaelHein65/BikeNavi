"""Disposable HTTPS fixture: public routes and live Wikimedia, no Pi or AI keys.

Trust a temporary certificate only in the dedicated test simulator. Documents
are stored in a temporary database. The eight-second analysis delay lets the UI
exercise closing and reopening the view while the detached Pi job runs.
"""
import asyncio
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

from fastapi import HTTPException

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from bikenavi.main import create_app
from bikenavi.route_description import DescriptionGenerator
from bikenavi.models import Route
from bikenavi.blog import distance

for key in ('BLOG_OPENAI_API_KEY', 'BLOG_OPENAI_MODEL'): os.environ.pop(key, None)
directory = TemporaryDirectory(prefix='bikenavi-description-')
app = create_app('sqlite:///' + str(Path(directory.name) / 'example.sqlite'),
                 token='example-description-token-' + 'x' * 40, ors_key='')
original = app.router.lifespan_context


class ExampleGenerator(DescriptionGenerator):
    async def generate(self, request, progress):
        await asyncio.sleep(8)
        return await super().generate(request, progress)


@asynccontextmanager
async def lifespan(app):
    async with original(app):
        app.state.description_jobs.generator = ExampleGenerator(app.state.ors.client)
        async def example_route(body, include_context=True):
            await asyncio.sleep(25)  # Exercise additional selections during routing.
            coords = [point.coordinate.model_dump() for point in body.waypoints]
            for coordinate in coords: coordinate['altitude'] = 100
            metres = sum(distance(a, b) for a, b in zip(coords, coords[1:]))
            return Route.model_validate({'id': str(uuid4()), 'coordinates': coords, 'distance': metres,
                'duration': metres / 4, 'ascent': 0, 'descent': 0, 'calculatedAt': 1,
                'waypointIndices': list(range(len(coords))), 'surfaceSections': [{'startIndex': 0, 'endIndex': len(coords) - 1, 'surface': 3}],
                'intersectionContexts': [], 'provider': 'synthetic-ui-example',
                'warnings': ['Synthetische gerade Verbindungen für den UI-Test; keine echte Straßenroute oder Geländeprüfung.']})
        async def unavailable_tile(*args, **kwargs):
            raise HTTPException(503, 'Das öffentliche UI-Beispiel enthält kein Offline-Wegenetz.')
        app.state.ors.route = example_route
        app.state.offline.tile = unavailable_tile
        yield


app.router.lifespan_context = lifespan
