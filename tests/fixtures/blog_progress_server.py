"""Disposable local HTTPS fixture for BlogProgressUITests.

Uses labelled Heidelberg records uploaded by the dedicated documentation simulator.
No Pi access, keys, internet research or real AI calls. Supply a temporary TLS
certificate to uvicorn and trust it only in that test simulator.
"""
import asyncio
import os
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
example_directory = TemporaryDirectory(prefix='bikenavi-blog-progress-')
import httpx
from contextlib import asynccontextmanager
from bikenavi.main import create_app
from bikenavi.blog import BlogGenerator

for key in ('BLOG_OPENAI_API_KEY', 'BLOG_OPENAI_MODEL', 'BLOG_WEB_SEARCH'):
    os.environ.pop(key, None)
app = create_app('sqlite:///' + str(Path(example_directory.name) / 'example.sqlite'), token='example-progress-token-' + 'x' * 40,
                 ors_key='', transport=httpx.MockTransport(lambda request: httpx.Response(503)))
original = app.router.lifespan_context

class ExampleGenerator(BlogGenerator):
    async def location_hints(self, *args):
        await asyncio.sleep(10)
        return {}
    async def terrain_map(self, *args): return None
    async def topo(self, *args): return None
    async def nearby_sources(self, *args):
        await asyncio.sleep(30)
        return []
    async def web_research(self, *args): return []
    async def story(self, *args):
        await asyncio.sleep(20)
        return await super().story(*args)

@asynccontextmanager
async def lifespan(app):
    async with original(app):
        generator = ExampleGenerator(app.state.ors.client, app.state.blogs)
        app.state.blog_generator = generator
        app.state.blog_jobs.generator = generator
        yield
app.router.lifespan_context = lifespan
