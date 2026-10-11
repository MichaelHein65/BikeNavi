"""Generate a labelled public pre-tour example locally, without Pi or private data."""
import asyncio
import json
import os
import re
import sys
from pathlib import Path
from uuid import UUID, uuid5

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'server'))
from bikenavi.route_description import DescriptionGenerator, DescriptionRequest


def example_request():
    route = json.loads((ROOT / 'tests/fixtures/heidelberg-elevation-route.json').read_text())
    identity = UUID('123C7446-B126-41E7-82E3-64D572AFA78B')
    indices = [0, len(route['coordinates']) // 2, len(route['coordinates']) - 1]
    route['waypointIndices'] = indices
    return DescriptionRequest.model_validate({'planID': str(identity), 'title': 'Heidelberg · Routenbeispiel',
        'waypoints': [{'id': str(uuid5(identity, f'description-{i}')), 'name': name, 'coordinate': route['coordinates'][index]}
            for i, (name, index) in enumerate(zip(['Start am Neckar · Beispiel', 'Zwischenziel · Beispiel', 'Tourziel · Beispiel'], indices))],
        'profile': {'bike': 'touring', 'electric': True, 'surface': 'any', 'gentleHills': True}, 'route': route})


async def main():
    # Intentionally no private .env, credentials or billable AI requests.
    for key in ('BLOG_OPENAI_API_KEY', 'BLOG_OPENAI_MODEL'): os.environ.pop(key, None)
    async with httpx.AsyncClient(timeout=8) as client:
        report = await DescriptionGenerator(client).generate(example_request(), lambda phase: print(phase, flush=True))
    output = ROOT / 'build/route-description-public.json'
    output.write_text(json.dumps(report, ensure_ascii=False))
    (ROOT / 'docs/examples/heidelberg-routenbeschreibung.html').write_text(re.sub(r"<a class='add-highlight' href='bikenavi-highlight://insert/[0-9a-fA-F-]+'>[^<]*</a>", '', report['html']))
    print(json.dumps({k: v for k, v in report.items() if k not in {'html', 'planID', 'routeID', 'highlights'}}, ensure_ascii=False))


if __name__ == '__main__': asyncio.run(main())
