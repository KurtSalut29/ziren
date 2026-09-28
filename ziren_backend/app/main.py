"""
Ziren — FastAPI backend entry point.

Start with:
    uvicorn app.main:app --reload
"""

import mimetypes
from contextlib import asynccontextmanager
from pathlib import Path

import structlog
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.config import settings
from app.models.rubric import AgencyType
from app.routers import (
    auth, incidents, dispatch, users, rubric, responder, stations,
    triage as triage_router, map as map_router, audit, notifications,
    geographic, analytics, governance, ai_monitoring, system_status,
    announcements, reports, search, assist_requests,
)
from app.services import (
    asr_engines,
    rubric_service,
    transcription_service,
    triage_service,
)
from app.services.rubric_traceability import (
    check_provenance,
    load_seed_config,
)

log = structlog.get_logger()


# ---------------------------------------------------------------------------
# Startup: rubric provenance check
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Runs once at startup before the server accepts requests.

    Phase 5.2 — provenance check:
      Loads each agency's seed config (or active DB config once 5.3 is wired)
      and warns on any rule still carrying a TODO provenance string.
      This keeps provenance debt visible at every server start — not just at
      development time.

    The check is non-fatal: a TODO provenance does not prevent startup.
    It is a quality gate for the defense, not a hard runtime guard.
    """
    log.info("startup.rubric_provenance_check", message="Checking rubric provenance...")

    startup_configs = []
    for agency in AgencyType:
        # Prefer DB config; fall back to seed for provenance check at startup.
        # rubric_service._load_config() handles the persistent audit write
        # for fallbacks at evaluation time — here we only need the config object
        # to run the provenance check, so load_seed_config() is sufficient.
        db_config = rubric_service.get_active_config(agency)
        cfg = db_config if db_config else load_seed_config(agency)
        startup_configs.append(cfg)
        source = "db" if db_config else "seed (no active DB config)"
        log.info(
            "startup.rubric_config_loaded",
            agency=agency.value,
            version=cfg.version,
            source=source,
        )

    result = check_provenance(startup_configs)

    if not result.clean:
        log.warning(
            "startup.rubric_provenance_incomplete",
            todo_count=len(result.todo_rules),
            message=(
                "Rubric has unfilled TODO provenance. "
                "Fill in field interview references before the defense."
            ),
        )

    # -----------------------------------------------------------------------
    # Phase 4 — load the triage model before the first request
    #
    # Loading here rather than lazily on the first report means the ~570KB
    # artefact and the Waray/Bisaya dictionaries are already in memory when a
    # resident submits, and — more importantly — that a broken or version-
    # skewed model is visible in the startup log instead of surfacing as a
    # degraded triage on a real emergency.
    #
    # Non-fatal by design: the API serves without triage, incidents save with
    # severity NULL, and the dispatcher triages by hand.
    # -----------------------------------------------------------------------
    if triage_service.load():
        log.info("startup.triage_ready", **triage_service.status())
    else:
        log.warning(
            "startup.triage_unavailable",
            message=(
                "Triage model did not load. Incidents will be saved with "
                "severity NULL for manual triage."
            ),
            **triage_service.status(),
        )

    # -----------------------------------------------------------------------
    # Speech-to-text for voice reports.
    #
    # Same contract as triage above: non-fatal, and absent is a valid
    # configuration. With no engine the report still lands and the dispatcher
    # still hears the recording — only the transcript that re-ranks the queue
    # is missing.
    #
    # Loaded here rather than on first use so the cost of pulling model
    # weights lands at startup, in a log line, instead of inside the first
    # emergency report that happens to carry audio.
    # -----------------------------------------------------------------------
    if settings.asr_engine:
        engine = asr_engines.load(settings.asr_engine)
        transcription_service.register_engine(engine)
        if engine is None:
            log.warning(
                "startup.transcription_unavailable",
                requested=settings.asr_engine,
                message=(
                    "ASR_ENGINE is set but the engine could not be built. "
                    "Voice notes will be stored and played back, not "
                    "transcribed."
                ),
            )
        else:
            log.info("startup.transcription_ready", **transcription_service.status())
    else:
        log.info(
            "startup.transcription_disabled",
            message=(
                "No ASR_ENGINE configured. Recordings are stored and playable; "
                "queue ranking uses the typed text only."
            ),
        )

    yield  # server runs here

    # Shutdown logic (none needed for Phase 5)
    log.info("shutdown.rubric", message="Rubric engine shutting down.")


# ---------------------------------------------------------------------------
# App instance
# ---------------------------------------------------------------------------
# Global rate limiter instance — imported from app.core.rate_limit so that the
# routers' @limiter.limit(...) decorators and app.state.limiter are the SAME
# object. Constructing a Limiter here again would recreate the split-storage
# bug described in app/core/rate_limit.py.
from app.core.rate_limit import limiter  # noqa: E402

app = FastAPI(
    title="Ziren API",
    description="Emergency Incident Reporting & Dispatch System — Backend API",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.environment != "production" else None,
    redoc_url="/redoc" if settings.environment != "production" else None,
)

# Attach rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ---------------------------------------------------------------------------
# Unhandled-exception guard
#
# ORDERING IS THE WHOLE POINT — this must be registered BEFORE CORSMiddleware.
# Starlette applies user middleware outermost-first in reverse registration
# order, so registering this first and CORS second puts CORS *outside* it, and
# the 500 produced here travels back out through CORS and gets its headers.
#
# Why it is needed at all: an exception escaping a route is caught by
# Starlette's ServerErrorMiddleware, which sits OUTSIDE the CORS layer. Its
# bare 500 therefore carries no Access-Control-Allow-Origin, the browser
# refuses to expose the response, and fetch() rejects with a TypeError. The
# dashboard's api client can only report that as a transport failure:
#
#     "Could not reach http://localhost:8000/... Check the backend is running
#      and that this origin is allowed in CORS_ORIGINS_RAW."
#
# Every server-side 500 was disguising itself as a down backend or a CORS
# misconfiguration. A real foreign-key violation cost a full debugging detour
# through two subsystems that were both fine. Errors must describe themselves.
#
# NOTE: an @app.exception_handler(Exception) does NOT fix this — FastAPI binds
# the catch-all handler onto ServerErrorMiddleware, which is outside CORS for
# the same reason. It has to be middleware, and it has to be inside.
# ---------------------------------------------------------------------------
@app.middleware("http")
async def catch_unhandled_exceptions(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception:
        log.exception(
            "http.unhandled_exception",
            method=request.method,
            path=request.url.path,
        )
        # Deliberately generic to the client — the traceback goes to the log,
        # not over the wire — but it is a real HTTP response, so CORS headers
        # get attached and the browser surfaces the 500 instead of hiding it.
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error. Check the API logs for the traceback."},
        )


# ---------------------------------------------------------------------------
# CORS — only allow configured origins, never wildcard in production
# Registered AFTER the guard above so that it wraps it. Do not reorder.
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
app.include_router(auth.router,        prefix="/auth",       tags=["auth"])
app.include_router(incidents.router,   prefix="/incidents",  tags=["incidents"])
app.include_router(dispatch.router,    prefix="/dispatch",   tags=["dispatch"])
app.include_router(responder.router,   prefix="/responder",  tags=["responder"])
app.include_router(users.router,       prefix="/users",      tags=["users"])
app.include_router(rubric.router,      prefix="/rubric",     tags=["rubric"])
app.include_router(stations.router,    prefix="/stations",   tags=["stations"])
app.include_router(map_router.router,  prefix="/map",        tags=["map"])
app.include_router(triage_router.router, prefix="/triage",    tags=["triage"])
app.include_router(audit.router,       prefix="/audit-logs", tags=["audit"])
app.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
app.include_router(geographic.router, prefix="/geographic", tags=["geographic"])
app.include_router(analytics.router, prefix="/analytics", tags=["analytics"])
app.include_router(governance.router, prefix="/governance", tags=["governance"])
app.include_router(ai_monitoring.router, prefix="/ai-classification", tags=["ai-classification"])
app.include_router(system_status.router, prefix="/system-status", tags=["system-status"])
app.include_router(announcements.router, prefix="/announcements", tags=["announcements"])
app.include_router(reports.router, prefix="/reports", tags=["reports"])
app.include_router(search.router, prefix="/search", tags=["search"])
app.include_router(assist_requests.router, prefix="/assist-requests", tags=["assist-requests"])


# ── Android app download ─────────────────────────────────────────────────────
# A public page and the APK behind it, at /download/. Served from
# public/downloads/ (git-ignored: it holds a build artefact, not source), and
# mounted only when that folder exists so a fresh checkout is unaffected.
# The .apk type is registered explicitly: Starlette falls back to text/plain for
# a type the OS does not know, and a phone shows that instead of installing it.
mimetypes.add_type("application/vnd.android.package-archive", ".apk")
_DOWNLOADS = Path(__file__).resolve().parent.parent / "public" / "downloads"
if _DOWNLOADS.is_dir():
    app.mount("/download", StaticFiles(directory=_DOWNLOADS, html=True), name="download")


@app.get("/health", tags=["health"])
def health_check():
    """
    Public health probe — returns 200 if the service is up.

    `triage` reports whether the Phase 4 model is loaded and which dataset
    release produced it. It deliberately does NOT affect the status code: the
    API is healthy without triage, it just saves incidents with severity NULL
    for a dispatcher to handle. This is the endpoint the mobile app polls to
    confirm it can reach the backend at all.
    """
    return {
        "status": "ok",
        "service": "ziren-api",
        "triage": triage_service.status(),
        # Same rule as triage: absent is a valid state, not an outage. Reports
        # still land and still carry their audio; they are simply ranked on
        # what the resident typed until a recogniser is chosen.
        "transcription": transcription_service.status(),
    }
