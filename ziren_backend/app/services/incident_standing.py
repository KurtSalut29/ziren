"""
incident_standing — whether a resident may report right now: suspensions, the
SOS cooldown and the false-SOS thresholds.

Split out of incident_service (evaluator finding #23, 2026-10-05). Each
function takes the caller's database client rather than creating one.
incident_service re-exports every name, so existing imports keep working.
"""

import structlog
from datetime import datetime, timezone
from fastapi import HTTPException, status
from supabase import Client
from app.services.incident_rows import _parse_dt

log = structlog.get_logger()


# ── SOS anti-abuse constants ──────────────────────────────────────────────────
# Server-side cooldown: minimum minutes between SOS submissions per account.
SOS_COOLDOWN_MINUTES = 30


# Warning threshold: sos_warning_count >= this value flags the report
# for the dispatcher as "account has prior false SOS history".
SOS_TRUST_FLAG_THRESHOLD = 1


# Suspension threshold: sos_warning_count >= this triggers automatic
# SOS access suspension (sos_suspended_until set to +30 days).
SOS_SUSPEND_THRESHOLD = 3


SOS_SUSPENSION_DAYS = 30


def _refuse_if_suspended(suspended_until) -> None:
    """Raise 403 when this date is a suspension still in force.

    Only a real timestamp string counts. Anything else - None, or whatever a
    test double hands back - is not a suspension, because the cost of getting
    this wrong in the other direction is refusing somebody's emergency report.
    """
    if not isinstance(suspended_until, str) or not suspended_until:
        return
    try:
        until = _parse_dt(suspended_until)
    except (ValueError, TypeError):
        return
    if until > datetime.now(timezone.utc):
        from app.services.resident_account_service import suspension_message
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=suspension_message(until),
        )


def ensure_reporting_allowed(db: Client, reporter_id: str) -> None:
    """Refuse a report from a resident whose account is suspended.

    Suspension used to stop only the SOS button, so an account suspended for
    false reports could go on sending ordinary ones. It now stops every report.

    FAILS OPEN. If the lookup itself fails - the database is slow, the row is
    missing - the report goes through. A suspension check that can block a real
    emergency because of an outage is worse than one a suspended account slips
    past once.
    """
    try:
        result = (
            db.table("users")
            .select("sos_suspended_until")
            .eq("id", reporter_id)
            .maybe_single()
            .execute()
        )
        row = None if result is None else result.data
    except Exception:
        log.warning("incident.suspension_check_failed", reporter_id=reporter_id, exc_info=True)
        return
    if isinstance(row, dict):
        _refuse_if_suspended(row.get("sos_suspended_until"))


def _update_sos_timestamp(db: Client, reporter_id: str) -> None:
    """Record the time of this SOS submission for cooldown enforcement."""
    try:
        db.table("users") \
          .update({"sos_last_submitted_at": datetime.now(timezone.utc).isoformat()}) \
          .eq("id", reporter_id) \
          .execute()
    except Exception as e:
        # Non-fatal — cooldown enforcement degrades gracefully if this fails
        log.warning("sos.timestamp_update_failed", reporter_id=reporter_id, error=str(e))
