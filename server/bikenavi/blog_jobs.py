"""Bounded in-memory progress for detached blog generation on this Pi process."""
import asyncio
import time

from fastapi import HTTPException


class BlogJobs:
    def __init__(self, generator):
        self.generator = generator
        self.jobs = {}
        self.task = None
        self.active_id = None

    def start(self, ride_id, generation_id):
        existing = self.jobs.get(generation_id)
        if existing is not None:
            if existing["rideID"] != ride_id:
                raise HTTPException(409, "Dieser Erstellungsauftrag gehört zu einer anderen Fahrt.")
            return dict(existing)
        if self.active_id is not None or self.generator.lock.locked():
            raise HTTPException(409, "Der Pi erstellt gerade einen Blog. Der laufende Auftrag bleibt erhalten.")
        self.generator.repository.snapshot(ride_id)  # Validate before accepting.
        while len(self.jobs) >= 32:
            del self.jobs[next(iter(self.jobs))]
        stamp = time.time()
        self.jobs[generation_id] = {"generationID": generation_id, "rideID": ride_id,
                                   "phase": "analysing", "startedAt": stamp, "updatedAt": stamp,
                                   "draftID": None, "message": None}
        self.active_id = generation_id
        self.task = asyncio.create_task(self._run(ride_id, generation_id))
        return dict(self.jobs[generation_id])

    def get(self, ride_id, generation_id):
        job = self.jobs.get(generation_id)
        if job is None or job["rideID"] != ride_id:
            raise HTTPException(404, "Dieser Erstellungsauftrag ist nicht mehr bekannt. Möglicherweise wurde der Pi neu gestartet. Vorhandene Blogfassungen bleiben erhalten.")
        return dict(job)

    def current(self, ride_id):
        return next((dict(job) for job in reversed(list(self.jobs.values())) if job["rideID"] == ride_id), None)

    def _update(self, generation_id, **values):
        self.jobs[generation_id].update(updatedAt=time.time(), **values)

    async def _run(self, ride_id, generation_id):
        try:
            draft = await self.generator.generate(ride_id, progress=lambda phase: self._update(generation_id, phase=phase))
            self._update(generation_id, phase="completed", draftID=draft["id"])
        except asyncio.CancelledError:
            self._update(generation_id, phase="failed", message="Die Blogerstellung wurde beim Pi-Neustart unterbrochen. Bitte erneut versuchen.")
            raise
        except HTTPException as error:
            self._update(generation_id, phase="failed", message=str(error.detail))
        except Exception:
            self._update(generation_id, phase="failed", message="Der Pi konnte den Blog nicht fertigstellen. Vorhandene Fassungen bleiben erhalten; bitte erneut versuchen.")
        finally:
            self.active_id = None

    async def close(self):
        if self.task is not None and not self.task.done():
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
