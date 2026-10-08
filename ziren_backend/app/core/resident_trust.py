"""
What "verified" means for a resident, defined once.

`users.is_verified` is NOT it. That column is set False at sign-up and then
used as an ACCOUNT-ACTIVE switch - by update_agency_admin ("is_verified
doubles as active flag") and by the Provincial Admin's resident status toggle -
so on a resident it says whether the account is switched on, not whether an
administrator has checked their ID. The ID check has lived in
`verification_level` since migration 012: decide_verification writes 2 on
approval. Since 2026-10-08 a resident reports during their first week
(GRACE_DAYS) without it, and after that only once level 2 is reached.

Five places read `is_verified` as if it were the ID check (Week 10): the
dashboard's reporter card and accept dialog, the incident history, the
responder app's reporter badge, and the Operational Area's verified-resident
counts. One place (users.py, the provincial dashboard KPI) had already been
corrected with a comment - the knowledge stayed in that one file. Every reader
now comes here instead (Week 9 plan item 3: one shared definition, so a
change is made in one place).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Mapping

#: decide_verification writes this on approval; below it, not verified.
VERIFIED_LEVEL = 2

#: The reporter as a dispatcher's list and card show them: name, how far we
#: trust the identity, and their false-SOS record. Embedded through the
#: reporter foreign key (incidents has three keys to users).
REPORTER_COLUMNS = "full_name, verification_level, sos_warning_count, created_at"
REPORTER_EMBED = "users!incidents_reporter_id_fkey(" + REPORTER_COLUMNS + ")"
#: The same, plus what the full incident card shows: the number to call
#: back, the suspension, and the emergency contact.
REPORTER_DETAIL_EMBED = (
    "users!incidents_reporter_id_fkey("
    "id, phone_number, sos_suspended_until, emergency_contact_name, emergency_contact_number, "
    + REPORTER_COLUMNS + ")"
)


def id_verified(row: Mapping[str, Any] | None) -> bool:
    """An administrator has approved this resident's ID."""
    if not row:
        return False
    try:
        return int(row.get("verification_level") or 0) >= VERIFIED_LEVEL
    except (TypeError, ValueError):
        return False


# ── The first week ───────────────────────────────────────────

#: A new resident may report for this many days before an administrator has
#: verified them (user request 2026-10-08). After that only an approval lets
#: them report again; a submission still waiting for an admin does not.
GRACE_DAYS = 7


def _as_datetime(value: Any) -> datetime | None:
    """A timestamp from a row, or None when there is no readable one."""
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str) and value:
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def grace_ends_at(role: Any, verification_level: Any, created_at: Any) -> datetime | None:
    """When an unverified resident's first week ends.

    None when the rule does not apply: staff, an already verified resident, or
    a row without a readable sign-up time (the same fail-open rule as every
    reporting check - a bad row must not refuse an emergency).
    """
    if role != "resident":
        return None
    if id_verified({"verification_level": verification_level}):
        return None
    joined = _as_datetime(created_at)
    if joined is None:
        return None
    return joined + timedelta(days=GRACE_DAYS)


def grace_expired(role: Any, verification_level: Any, created_at: Any,
                  now: datetime | None = None) -> bool:
    """An unverified resident whose first week is over: they may not report."""
    if not isinstance(verification_level, int):
        return False
    ends = grace_ends_at(role, verification_level, created_at)
    if ends is None:
        return False
    return (now or datetime.now(timezone.utc)) >= ends
