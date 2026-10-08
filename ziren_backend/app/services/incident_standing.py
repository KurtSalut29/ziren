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
from app.core.resident_trust import grace_expired
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


# Shown to a resident whose first week is over and whom an administrator has
# not verified yet.
UNVERIFIED_MESSAGE = (
    "Your 7 days to verify your account are over. Only residents verified by "
    "an administrator can send reports now. Add your valid ID, selfie and 2x2 "
    "ID photo from your profile. In an emergency, call a hotline now."
)


def refuse_if_unverified(role, verification_level, created_at=None) -> None:
    """Raise 403 for a resident past their first week and not yet verified.

    History: migration 012 said verification must never gate reporting. On
    2026-10-07 the user reversed that (false reports from throwaway accounts
    sent crews out) and a resident reported only at level 2. On 2026-10-08 it
    was softened: a new resident may report for GRACE_DAYS after signing up,
    so nobody is refused on day one, and after that only an administrator's
    approval lets them report again. The rule itself lives in
    app/core/resident_trust.py.

    Only a real resident row with a real level and sign-up time counts. Staff
    accounts, and a row the lookup could not read (a test double, a missing
    column), are not refused: the same fail-open rule as the suspension check.
    """
    if grace_expired(role, verification_level, created_at):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=UNVERIFIED_MESSAGE,
        )


def ensure_reporting_allowed(db: Client, reporter_id: str) -> None:
    """Refuse a report from a resident whose account is suspended, or whose
    first week is over without an administrator verifying them.

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
            .select("sos_suspended_until, role, verification_level, created_at")
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
        refuse_if_unverified(row.get("role"), row.get("verification_level"), row.get("created_at"))


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
