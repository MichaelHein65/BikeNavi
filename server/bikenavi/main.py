import os
import secrets
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request

from .models import Mutation, Route, RouteRequest, Waypoint
from .providers import ORS
from .storage import Storage


def create_app(database_url: str | None = None, token: str | None = None,
               ors_key: str | None = None, transport=None,
               overpass_url: str | None = None) -> FastAPI:
    db_url = database_url or os.getenv("DATABASE_URL", "sqlite:///./bikenavi.sqlite")
    access_token = token if token is not None else os.getenv("BIKENAVI_TOKEN", "")
    key = ors_key if ors_key is not None else os.getenv("ORS_API_KEY", "")
    context_url = overpass_url if overpass_url is not None else os.getenv("OVERPASS_URL", "")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if len(access_token) < 32:
            raise RuntimeError("BIKENAVI_TOKEN muss mindestens 32 Zeichen lang sein.")
        app.state.storage = Storage(db_url)
        async with httpx.AsyncClient(timeout=35, transport=transport) as client:
            app.state.ors = ORS(key, client, context_url)
            yield
        app.state.storage.engine.dispose()

    app = FastAPI(title="BikeNavi", version="0.1.0", lifespan=lifespan,
                  docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def limit_body(request: Request, call_next):
        # Count streamed bytes as well as Content-Length to handle chunked uploads.
        if request.method in ("POST", "PUT", "PATCH"):
            from starlette.responses import JSONResponse
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > 16 * 1024 * 1024:
                    return JSONResponse({"detail": "Die Übertragung ist zu groß."}, status_code=413)
            request._body = bytes(body)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    def authenticate(authorization: str = Header(default="")):
        if not secrets.compare_digest(authorization, f"Bearer {access_token}"):
            raise HTTPException(401, "Bitte Serveradresse und Zugangsschlüssel prüfen.")

    @app.get("/health")
    def health():
        return {"status": "ok", "version": "0.1.0"}

    @app.get("/v1/status", dependencies=[Depends(authenticate)])
    def status():
        return {"routingAvailable": bool(key), "version": "0.1.0"}

    @app.get("/v1/changes", dependencies=[Depends(authenticate)])
    def changes(after: int = Query(default=0, ge=0)):
        return app.state.storage.changes(after)

    @app.post("/v1/mutations", dependencies=[Depends(authenticate)])
    def mutate(mutation: Mutation):
        return app.state.storage.apply(mutation)

    @app.post("/v1/route", response_model=Route, dependencies=[Depends(authenticate)])
    async def route(body: RouteRequest):
        return await app.state.ors.route(body)

    @app.get("/v1/search", response_model=list[Waypoint], dependencies=[Depends(authenticate)])
    async def search(q: str = Query(min_length=3, max_length=200),
                     lat: float | None = Query(default=None, ge=-90, le=90),
                     lon: float | None = Query(default=None, ge=-180, le=180)):
        return await app.state.ors.search(q, lat, lon)

    @app.get("/v1/place-name", dependencies=[Depends(authenticate)])
    async def place_name(lat: float = Query(ge=-90, le=90),
                         lon: float = Query(ge=-180, le=180)):
        return {"name": await app.state.ors.place_name(lat, lon)}

    return app


app = create_app()
