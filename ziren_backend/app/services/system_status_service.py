"""
system_status_service — health of the services System Status monitors
(spec Section 13).

Every check is wrapped individually so one failing component can never hide
the rest — the whole point of this page is "which ONE of these is down",
and a single try/except around the whole list would turn that into "is
anything down at all", which is a worse answer.

Pragmatic cut (stated in the plan's Global Constraints): "Realtime services"
has no cheap synchronous health probe available from a request handler —
Postgres LISTEN/NOTIFY-backed realtime is inherently a persistent-connection
concern, not a point-in-time query. It is approximated here as "reachable
whenever the database is" (same Supabase project, same underlying Postgres),
not a live websocket handshake.
"""

import time
from datetime import datetime, timedelta, timezone
from typing import Callable

from app.db.supabase_client import get_supabase
from app.services import triage_service


def _timed(fn: Callable[[], None]) -> dict:
    start = time.perf_counter()
    try:
        fn()
        return {
            "status": "operational",
            "latency_ms": round((time.perf_counter() - start) * 1000, 1),
            "detail": None,
        }
    except Exception as exc:
        return {
            "status": "down",
            "latency_ms": round((time.perf_counter() - start) * 1000, 1),
            "detail": str(exc)[:200],
        }


def _check_ai_nlp() -> None:
    status = triage_service.status()
    if not status.get("model_loaded"):
        raise RuntimeError(status.get("error") or "Triage model not loaded.")


def _check_audit_trail(db) -> None:
    """Audit-log monitoring (evaluator finding #9).

    Every state change writes its audit row first, as 'pending', and completes
    it afterwards (finding #6). A row still pending after ten minutes is a
    change whose outcome could not be written: worth an administrator's look.
    A query error here usually means migration 044 has not been applied.
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat()
    res = (
        db.table("audit_logs")
        .select("id", count="exact")
        .eq("outcome", "pending")
        .lt("created_at", cutoff)
        .limit(1)
        .execute()
    )
    stuck = getattr(res, "count", None) or 0
    if stuck:
        raise RuntimeError(f"{stuck} audited change(s) were started but never confirmed. See Audit Logs.")


def check_all() -> list[dict]:
    db = get_supabase()

    checks: list[tuple[str, Callable[[], None]]] = [
        ("Authentication",       lambda: db.auth.admin.list_users(page=1, per_page=1)),
        ("Database",             lambda: db.table("users").select("id").limit(1).execute()),
        ("Incident Service",     lambda: db.table("incidents").select("id").limit(1).execute()),
        ("Notification Service", lambda: db.table("notifications").select("id").limit(1).execute()),
        ("Map Service",          lambda: db.table("stations").select("id").limit(1).execute()),
        ("AI/NLP Service",       _check_ai_nlp),
        ("File Storage",         lambda: db.storage.list_buckets()),
        # See module docstring — approximated via the database check.
        ("Realtime Services",    lambda: db.table("incidents").select("id").limit(1).execute()),
        ("Audit Trail",          lambda: _check_audit_trail(db)),
    ]

    return [{"name": name, **_timed(fn)} for name, fn in checks]
