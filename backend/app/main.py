"""FastAPI app entry point."""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import db, worker
from .config import get_settings
from .routes import auth, me, web_push as web_push_routes


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.init_pool()
    await worker.start()
    try:
        yield
    finally:
        await worker.stop()
        await db.close_pool()


settings = get_settings()

app = FastAPI(
    title="duo-sync API",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.is_dev else None,
    redoc_url=None,
)

# CORS — the iOS app doesn't need CORS, but it's handy in dev for a
# browser-based admin UI later. Tighten in prod.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.is_dev else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(me.router)
app.include_router(web_push_routes.router)
