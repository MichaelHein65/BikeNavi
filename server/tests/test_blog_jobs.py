import asyncio

import pytest
from fastapi import HTTPException

from bikenavi.blog_jobs import BlogJobs


class Repository:
    def snapshot(self, ride_id):
        if ride_id == 'missing':
            raise HTTPException(404, 'Fahrt fehlt')
        return {}, [], 1


class Generator:
    def __init__(self):
        self.repository = Repository()
        self.lock = asyncio.Lock()
        self.gate = asyncio.Event()
        self.calls = 0
        self.error = None

    async def generate(self, ride_id, progress):
        self.calls += 1
        async with self.lock:
            progress('researching')
            await self.gate.wait()
            if self.error:
                raise self.error
            progress('writing')
            await asyncio.sleep(0)
            progress('saving')
            return {'id': 'draft-' + ride_id}


def test_job_survives_start_response_and_is_idempotent_with_real_progress():
    async def scenario():
        generator = Generator()
        jobs = BlogJobs(generator)
        first = jobs.start('ride', 'attempt')
        assert first['phase'] == 'analysing'
        await asyncio.sleep(0)
        assert jobs.get('ride', 'attempt')['phase'] == 'researching'
        assert jobs.start('ride', 'attempt')['generationID'] == 'attempt'
        with pytest.raises(HTTPException) as error:
            jobs.start('ride', 'second')
        assert error.value.status_code == 409
        with pytest.raises(HTTPException):
            jobs.get('other', 'attempt')
        generator.gate.set()
        await jobs.task
        final = jobs.get('ride', 'attempt')
        assert final['phase'] == 'completed' and final['draftID'] == 'draft-ride'
        assert final['updatedAt'] >= final['startedAt']
        jobs.start('ride', 'attempt')
        assert generator.calls == 1
        assert jobs.current('ride') == final
        assert jobs.current('other') is None
    asyncio.run(scenario())


@pytest.mark.parametrize('failure, message', [(HTTPException(409, 'Fahrt geändert'), 'Fahrt geändert'),
                                             (RuntimeError('PRIVATE DATA'), 'Der Pi konnte den Blog nicht fertigstellen.')])
def test_failure_is_reported_and_new_attempt_is_allowed(failure, message):
    async def scenario():
        generator = Generator()
        generator.error = failure
        generator.gate.set()
        jobs = BlogJobs(generator)
        jobs.start('ride', 'attempt')
        await jobs.task
        status = jobs.get('ride', 'attempt')
        assert status['phase'] == 'failed' and status['message'].startswith(message)
        assert 'PRIVATE DATA' not in status['message']
        generator.error = None
        jobs.start('ride', 'retry')
        await jobs.task
        assert jobs.get('ride', 'retry')['phase'] == 'completed'
    asyncio.run(scenario())


def test_shutdown_cancels_job_and_history_is_bounded():
    async def scenario():
        generator = Generator()
        jobs = BlogJobs(generator)
        with pytest.raises(HTTPException):
            jobs.start('missing', 'attempt')
        assert jobs.active_id is None and not jobs.jobs
        jobs.start('ride', 'attempt')
        await asyncio.sleep(0)
        await jobs.close()
        assert jobs.get('ride', 'attempt')['phase'] == 'failed'
        generator.gate.set()
        for index in range(40):
            jobs.start('ride', str(index))
            await jobs.task
        assert len(jobs.jobs) == 32
        assert jobs.current('ride')['generationID'] == '39'
        with pytest.raises(HTTPException):
            jobs.get('ride', 'attempt')
    asyncio.run(scenario())
