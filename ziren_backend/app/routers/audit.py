"""
/audit-logs — Provincial Admin's administrative audit trail.

Read-only. Rows are written exclusively by app.services.audit_service.record()
from wherever a mutation happens; nothing here ever inserts.
"""

import structlog
from fastapi import APIRouter, Depends, Query

from app.core.dependencies import require_provincial_admin
from app.db.supabase_client import get_supabase

log = structlog.get_logger()
router = APIRouter()


def _inclusive_end(date_to: str | None) -> str | None:
    """
    Same fix as analytics_service.py's and report_service.py's own copies of
    this helper — see either doc comment for the full explanation.

    Without it, a bare 'YYYY-MM-DD' compared with `.lte` means "created_at <=
    midnight at the START of that day", which excludes almost the entire day
    an admin picked "To" to mean. list_audit_logs was still doing the plain
    comparison; a caller picking "To: today" would see none of today's
    entries until after midnight.
    """
    if date_to and "T" not in date_to:
        return f"{date_to}T23:59:59.999999"
    return date_to


@router.get("/")
def list_audit_logs(
    actor_id: str | None = Query(None),
    target_type: str | None = Query(None),
    action: str | None = Query(None),
    date_from: str | None = Query(None, description="ISO date/datetime, inclusive"),
    date_to: str | None = Query(None, description="ISO date/datetime, inclusive"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(require_provincial_admin),
):
    """
    One page of the audit trail, newest first.

    Scoped to the caller's own agency_type PLUS platform-wide rows
    (agency_type IS NULL — e.g. system_config.updated) — mirrors the RLS
    policy "audit_logs: provincial_admin reads own scope" from migration
    034 exactly, so the FastAPI-layer result matches what RLS would allow
    even though the service-role client bypasses RLS.

    Returns {items, total} — total is the match count before paging, so the
    dashboard can render pagination controls without a second request.
    """
    db = get_supabase()
    query = (
        db.table("audit_logs")
        .select("*", count="exact")
        .order("created_at", desc=True)
    )
    own_agency_type = current_user.get("agency_type")
    if own_agency_type:
        # PostgREST "or" filter syntax: agency_type.is.null,agency_type.eq.<mine>
        query = query.or_(f"agency_type.is.null,agency_type.eq.{own_agency_type}")
    if actor_id:
        query = query.eq("actor_id", actor_id)
    if target_type:
        query = query.eq("target_type", target_type)
    if action:
        query = query.eq("action", action)
    if date_from:
        query = query.gte("created_at", date_from)
    if date_to:
        query = query.lte("created_at", _inclusive_end(date_to))

    result = query.range(offset, offset + limit - 1).execute()
    return {"items": result.data or [], "total": result.count or 0}
