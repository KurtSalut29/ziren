"""
resident_account_service - a resident's standing: warnings, suspension, history.

WHAT THIS IS FOR

Verification answers "is this person who they say they are". It says nothing
about how they behave afterwards. A verified resident who sends a prank report
ties up a fire crew exactly as an anonymous one does, and until now the only
thing an agency could do about it was flag a false SOS - nothing for a false
ordinary report, abusive messages or a borrowed identity, and nothing the
resident was ever told about.

This module is the rest of that: an admin can WARN a resident for any
violation, SUSPEND them from reporting for a number of days or until further
notice, and REINSTATE them. Every one of those is

  1. written to the resident's row,
  2. written to the audit trail (which is also the history shown on screen),
  3. told to the resident on their phone as a notification of its own type.

NO NEW TABLE, NO NEW COLUMN

It runs on what migrations 012 and 025 already created:

  users.sos_warning_count    how many warnings are on record. It was only ever
                             raised by a false SOS; a warning is a warning, so
                             every violation counts on the same number.
  users.sos_suspended_until  when the suspension ends. It used to block only the
                             SOS button; it now blocks every kind of report -
                             see incident_service.ensure_reporting_allowed.
  audit_logs                 one row per warning, suspension and reinstatement,
                             carrying the violation and the admin's note. That
                             is the history; nothing else stores it.

A SUSPENDED RESIDENT CANNOT REPORT - AND IS TOLD WHO TO CALL

The refusal message always carries the emergency hotline. Taking the app away
from someone must never leave them with nothing to do in a real emergency.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.db.supabase_client import get_supabase
from app.services import audit_service, notification_service

log = structlog.get_logger()

# The violations an admin can cite. The key is stored; the label is what the
# resident reads, so it is written to be read by them.
VIOLATIONS: dict[str, str] = {
    "false_report":     "Sending a false or prank report",
    "false_sos":        "Misusing the SOS button",
    "spam":             "Sending repeated or duplicate reports",
    "abusive_language": "Abusive or threatening messages",
    "fake_identity":    "Using a false or borrowed identity",
    "other":            "Another violation of the reporting rules",
}

WARNED = "resident.warned"
SUSPENDED = "resident.suspended"
REINSTATED = "resident.reinstated"
HISTORY_ACTIONS = (WARNED, SUSPENDED, REINSTATED)

# The same escalation the false-SOS path has always had: the third warning
# suspends by itself.
AUTO_SUSPEND_AT = 3
AUTO_SUSPEND_DAYS = 30
MAX_SUSPEND_DAYS = 365

# "Until further notice" is stored as a date far enough away to never arrive.
# A real column for it would need a migration; this needs none and reads
# correctly to every piece of code that only asks "is it in the future".
INDEFINITE = datetime(9999, 12, 31, tzinfo=timezone.utc)

# How many residents one listing reads. The whole resident table of a province
# this size, in one bounded read, filtered and counted here - so the counts on
# the filter chips and the rows under them can never disagree.
_SCAN_MAX = 3000

_LIST_SELECT = (
    "id, email, full_name, phone_number, created_at, "
    "municipality_address, purok_sitio, street_address, "
    "verification_level, verification_method, verified_at, valid_id_type, "
    "is_verified, sos_warning_count, sos_suspended_until, "
    "barangays(name, municipality)"
)

_DETAIL_SELECT = (
    "id, email, full_name, first_name, middle_name, last_name, name_suffix, "
    "date_of_birth, sex, phone_number, role, created_at, "
    "municipality_address, purok_sitio, street_address, "
    "verification_level, verification_method, verified_at, "
    "valid_id_type, valid_id_number, is_pwd, is_verified, "
    "emergency_contact_name, emergency_contact_number, "
    "sos_warning_count, sos_suspended_until, "
    "barangays(name, municipality)"
)


# ── Reading a row ────────────────────────────────────────────────────────────

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse(value) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def suspension_of(row: dict, now: datetime | None = None) -> dict:
    """Whether this resident is suspended right now, and until when.

    A date in the past is NOT a suspension. The column is never cleared when a
    suspension runs out, so the date is compared every time it is read.
    """
    until = _parse(row.get("sos_suspended_until")) if isinstance(row, dict) else None
    active = until is not None and until > (now or _now())
    indefinite = active and until.year >= 9000
    return {
        "active": active,
        "indefinite": indefinite,
        "until": until.isoformat() if active and not indefinite else None,
    }


def standing_of(row: dict, now: datetime | None = None) -> str:
    """'suspended', 'warned' or 'good' - the one word the list shows."""
    if suspension_of(row, now)["active"]:
        return "suspended"
    return "warned" if int(row.get("sos_warning_count") or 0) > 0 else "good"


def suspension_message(until: datetime) -> str:
    """What a suspended resident is told when a report is refused."""
    when = (
        "until further notice"
        if until.year >= 9000
        else f"until {until.strftime('%B %d, %Y')}"
    )
    return (
        f"Your account is suspended from sending reports {when} because of a "
        "violation of the reporting rules. If this is a real emergency, call "
        "911 or your local emergency hotline now. To appeal, contact your "
        "municipal MDRRMO office."
    )


def _shape(row: dict, now: datetime) -> dict:
    barangay = row.pop("barangays", None)
    row["barangay"] = barangay.get("name") if isinstance(barangay, dict) else None
    row["warning_count"] = int(row.pop("sos_warning_count", 0) or 0)
    row["suspension"] = suspension_of(row, now)
    row.pop("sos_suspended_until", None)
    row["standing"] = (
        "suspended" if row["suspension"]["active"]
        else "warned" if row["warning_count"] > 0 else "good"
    )
    row["verified"] = int(row.get("verification_level") or 0) >= 2
    return row


# ── Who may act on whom ──────────────────────────────────────────────────────

def _own_municipality(current_user: dict | None) -> str | None:
    if not current_user or current_user.get("role") != "agency_admin":
        return None
    from app.services.geographic_service import agency_municipality
    return agency_municipality(str(current_user.get("agency_id") or ""))


def _assert_scope(db: Client, row: dict, current_user: dict | None) -> None:
    """An Agency Admin may act on the people their station serves.

    That is the residents of their own municipality, and anyone from elsewhere
    who has filed a report to their agency - a prank call does not stop being
    their problem because the caller lives in the next town. A Provincial Admin
    has no such limit.
    """
    own = _own_municipality(current_user)
    if own is None:
        return
    if (row.get("municipality_address") or None) == own:
        return
    agency_id = str((current_user or {}).get("agency_id") or "")
    if agency_id:
        try:
            hit = (
                db.table("incidents")
                .select("id")
                .eq("reporter_id", str(row["id"]))
                .eq("assigned_agency_id", agency_id)
                .limit(1)
                .execute()
                .data
            )
            if hit:
                return
        except Exception:
            log.warning("resident_account.scope_lookup_failed", exc_info=True)
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="This resident is outside your municipality and has not reported to your agency.",
    )


def _resident(db: Client, user_id: str, select: str) -> dict:
    result = db.table("users").select(select).eq("id", user_id).maybe_single().execute()
    row = None if result is None else result.data
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Resident not found.")
    if row.get("role", "resident") != "resident":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only resident accounts can be warned or suspended here.",
        )
    return row


# ── Listing ──────────────────────────────────────────────────────────────────

def list_residents(
    *,
    standing: str = "verified",
    q: str | None = None,
    limit: int = 50,
    offset: int = 0,
    current_user: dict | None = None,
) -> dict:
    """Resident accounts, with how each one stands.

    `standing`: verified (the default - where a resident goes once their ID is
    approved), unverified, warned, suspended, or all. The counts returned cover
    every bucket at once, whatever is being shown, so a chip can say how many it
    would reveal.
    """
    db: Client = get_supabase()
    now = _now()

    query = db.table("users").select(_LIST_SELECT).eq("role", "resident")
    own = _own_municipality(current_user)
    if own is not None:
        query = query.eq("municipality_address", own)
    rows = query.order("created_at", desc=True).limit(_SCAN_MAX).execute().data or []
    rows = [_shape(r, now) for r in rows]

    counts = {
        "all": len(rows),
        "verified": sum(1 for r in rows if r["verified"]),
        "unverified": sum(1 for r in rows if not r["verified"]),
        "warned": sum(1 for r in rows if r["warning_count"] > 0),
        "suspended": sum(1 for r in rows if r["standing"] == "suspended"),
    }

    keep = {
        "verified": lambda r: r["verified"],
        "unverified": lambda r: not r["verified"],
        "warned": lambda r: r["warning_count"] > 0,
        "suspended": lambda r: r["standing"] == "suspended",
        "all": lambda r: True,
    }.get(standing)
    if keep is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="standing must be one of: verified, unverified, warned, suspended, all.",
        )
    rows = [r for r in rows if keep(r)]

    words = [w for w in (q or "").lower().split() if w]
    if words:
        def hay(r: dict) -> str:
            return " ".join(str(r.get(k) or "") for k in (
                "full_name", "email", "phone_number", "barangay", "municipality_address",
            )).lower()
        rows = [r for r in rows if all(w in hay(r) for w in words)]

    # Suspended first, then the most warned, then the most recently verified:
    # the accounts somebody may need to act on are never below the fold.
    rank = {"suspended": 0, "warned": 1, "good": 2}
    rows.sort(key=lambda r: (
        rank[r["standing"]], -r["warning_count"],
        -(_parse(r.get("verified_at") or r.get("created_at")) or now).timestamp(),
    ))

    total = len(rows)
    page = rows[offset:offset + limit]
    _attach_report_counts(db, page)
    return {"items": page, "total": total, "counts": counts, "truncated": counts["all"] >= _SCAN_MAX}


def _attach_report_counts(db: Client, rows: list[dict]) -> None:
    """How many reports each resident on this page has filed. Bounded by the page."""
    for r in rows:
        r["report_count"] = 0
    ids = [str(r["id"]) for r in rows]
    if not ids:
        return
    try:
        inc = db.table("incidents").select("reporter_id").in_("reporter_id", ids).execute().data or []
    except Exception:
        log.warning("resident_account.report_count_failed", exc_info=True)
        return
    tally: dict[str, int] = {}
    for row in inc:
        rid = str(row.get("reporter_id") or "")
        tally[rid] = tally.get(rid, 0) + 1
    for r in rows:
        r["report_count"] = tally.get(str(r["id"]), 0)


# ── One resident ─────────────────────────────────────────────────────────────

def get_resident(user_id: str, *, current_user: dict | None = None) -> dict:
    """One resident: who they are, what they have reported, and their history."""
    db: Client = get_supabase()
    row = _resident(db, user_id, _DETAIL_SELECT)
    _assert_scope(db, row, current_user)
    row.pop("role", None)
    row = _shape(row, _now())

    reports: list[dict] = []
    try:
        reports = (
            db.table("incidents")
            .select("id, record_number, report_text, status, review_status, incident_category, submitted_via, created_at")
            .eq("reporter_id", user_id)
            .order("created_at", desc=True)
            .limit(200)
            .execute()
            .data
            or []
        )
    except Exception:
        log.warning("resident_account.reports_failed", user_id=user_id, exc_info=True)
    row["report_count"] = len(reports)
    row["rejected_report_count"] = sum(1 for r in reports if r.get("review_status") == "rejected")
    row["recent_reports"] = reports[:6]
    row["history"] = history(user_id, db=db)
    row["violations"] = [{"key": k, "label": v} for k, v in VIOLATIONS.items()]
    return row


def history(user_id: str, *, db: Client | None = None, limit: int = 50) -> list[dict]:
    """Every warning, suspension and reinstatement, newest first."""
    db = db or get_supabase()
    try:
        rows = (
            db.table("audit_logs")
            .select("id, action, actor_name, actor_role, new_value, created_at")
            .eq("target_type", "user")
            .eq("target_id", str(user_id))
            .in_("action", list(HISTORY_ACTIONS))
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
            .data
            or []
        )
    except Exception:
        # The history is a convenience; the standing on the row is the fact.
        log.warning("resident_account.history_failed", user_id=user_id, exc_info=True)
        return []
    out = []
    for r in rows:
        value = r.get("new_value") if isinstance(r.get("new_value"), dict) else {}
        out.append({
            "id": r.get("id"),
            "kind": {WARNED: "warned", SUSPENDED: "suspended", REINSTATED: "reinstated"}.get(r.get("action"), "warned"),
            "violation": value.get("violation"),
            "violation_label": VIOLATIONS.get(value.get("violation") or "", None),
            "note": value.get("note"),
            "incident_id": value.get("incident_id"),
            "suspended_until": value.get("suspended_until"),
            "indefinite": bool(value.get("indefinite")),
            "automatic": bool(value.get("automatic")),
            "by": r.get("actor_name"),
            "by_role": r.get("actor_role"),
            "at": r.get("created_at"),
        })
    return out


# ── Acting ───────────────────────────────────────────────────────────────────

def _violation(key: str | None) -> str:
    if key not in VIOLATIONS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"violation must be one of: {', '.join(VIOLATIONS)}.",
        )
    return key


def _note(note: str | None, *, required: bool) -> str | None:
    text = (note or "").strip()
    if required and len(text) < 5:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Say what happened, in at least a few words. The resident will read it.",
        )
    return text[:500] or None


def _tell(user_id: str, *, type_: str, title: str, body: str, meta: dict) -> None:
    """Notify the resident. Never raises: the action is already recorded."""
    try:
        notification_service.create_for_user(
            str(user_id), type_=type_, title=title, body=body[:240],
            link=None, is_important=True, metadata=meta,
        )
    except Exception:
        log.error("resident_account.notify_failed", user_id=user_id, type=type_, exc_info=True)


def _suspend_row(
    db: Client, row: dict, *, until: datetime, violation: str, note: str | None,
    actor: dict, automatic: bool, incident_id: str | None = None,
) -> dict:
    indefinite = until.year >= 9000
    db.table("users").update({"sos_suspended_until": until.isoformat()}).eq("id", str(row["id"])).execute()
    at = _now().isoformat()
    audit_service.record(
        actor=actor, action=SUSPENDED, target_type="user", target_id=str(row["id"]),
        target_label=row.get("full_name"),
        previous={"sos_suspended_until": row.get("sos_suspended_until")},
        new={
            "violation": violation, "note": note, "incident_id": incident_id,
            "suspended_until": None if indefinite else until.isoformat(),
            "indefinite": indefinite, "automatic": automatic,
        },
    )
    when = "until further notice" if indefinite else f"until {until.strftime('%B %d, %Y')}"
    _tell(
        str(row["id"]),
        type_="account.suspended",
        title="Your account is suspended from reporting",
        body=f"{VIOLATIONS[violation]}. You cannot send reports {when}."
             + (f" {note}" if note else ""),
        meta={
            "at": at, "violation": violation, "violation_label": VIOLATIONS[violation],
            "note": note, "suspended_until": None if indefinite else until.isoformat(),
            "indefinite": indefinite, "automatic": automatic,
        },
    )
    log.warning(
        "resident_account.suspended", user_id=str(row["id"]), violation=violation,
        until=until.isoformat(), automatic=automatic, actor_id=str(actor.get("id")),
    )
    return {"active": True, "indefinite": indefinite, "until": None if indefinite else until.isoformat()}


def warn(
    user_id: str, *, violation: str, note: str | None, incident_id: str | None = None,
    actor: dict, check_scope: bool = True,
) -> dict:
    """Put one warning on a resident's record and tell them.

    The third warning suspends the account for thirty days by itself - the same
    rule the false-SOS flag has always applied, now for every violation.
    """
    db: Client = get_supabase()
    violation = _violation(violation)
    note = _note(note, required=True)
    row = _resident(db, user_id, "id, role, full_name, municipality_address, sos_warning_count, sos_suspended_until")
    if check_scope:
        _assert_scope(db, row, actor)

    count = int(row.get("sos_warning_count") or 0) + 1
    db.table("users").update({"sos_warning_count": count}).eq("id", user_id).execute()
    at = _now().isoformat()
    audit_service.record(
        actor=actor, action=WARNED, target_type="user", target_id=user_id,
        target_label=row.get("full_name"),
        previous={"sos_warning_count": count - 1},
        new={"violation": violation, "note": note, "incident_id": incident_id, "warning_count": count},
    )
    left = AUTO_SUSPEND_AT - count
    _tell(
        user_id,
        type_="account.warned",
        title="You received a warning",
        body=f"{VIOLATIONS[violation]}." + (f" {note}" if note else ""),
        meta={
            "at": at, "violation": violation, "violation_label": VIOLATIONS[violation],
            "note": note, "warning_count": count, "warnings_left": max(left, 0),
            **({"incident_id": str(incident_id)} if incident_id else {}),
        },
    )
    log.info("resident_account.warned", user_id=user_id, violation=violation, count=count, actor_id=str(actor.get("id")))

    suspension = suspension_of(row)
    if count >= AUTO_SUSPEND_AT and not suspension["active"]:
        suspension = _suspend_row(
            db, row, until=_now() + timedelta(days=AUTO_SUSPEND_DAYS), violation=violation,
            note=f"Automatic: {count} warnings on record.", actor=actor, automatic=True,
            incident_id=incident_id,
        )
    return {
        "id": user_id, "warning_count": count, "suspension": suspension,
        "standing": "suspended" if suspension["active"] else "warned",
    }


def suspend(
    user_id: str, *, violation: str, note: str | None, days: int | None, actor: dict,
) -> dict:
    """Stop a resident from reporting for `days`, or until further notice (None)."""
    db: Client = get_supabase()
    violation = _violation(violation)
    note = _note(note, required=True)
    if days is not None and not (1 <= days <= MAX_SUSPEND_DAYS):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"days must be between 1 and {MAX_SUSPEND_DAYS}, or left out for 'until further notice'.",
        )
    row = _resident(db, user_id, "id, role, full_name, municipality_address, sos_warning_count, sos_suspended_until")
    _assert_scope(db, row, actor)
    until = INDEFINITE if days is None else _now() + timedelta(days=days)
    suspension = _suspend_row(db, row, until=until, violation=violation, note=note, actor=actor, automatic=False)
    return {
        "id": user_id, "warning_count": int(row.get("sos_warning_count") or 0),
        "suspension": suspension, "standing": "suspended",
    }


def reinstate(user_id: str, *, note: str | None, clear_warnings: bool, actor: dict) -> dict:
    """Lift a suspension, and optionally wipe the warnings that led to it."""
    db: Client = get_supabase()
    note = _note(note, required=False)
    row = _resident(db, user_id, "id, role, full_name, municipality_address, sos_warning_count, sos_suspended_until")
    _assert_scope(db, row, actor)
    was = suspension_of(row)
    count = int(row.get("sos_warning_count") or 0)
    if not was["active"] and not (clear_warnings and count > 0):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This resident is not suspended.",
        )

    payload: dict = {"sos_suspended_until": None}
    if clear_warnings:
        payload["sos_warning_count"] = 0
    db.table("users").update(payload).eq("id", user_id).execute()
    new_count = 0 if clear_warnings else count
    audit_service.record(
        actor=actor, action=REINSTATED, target_type="user", target_id=user_id,
        target_label=row.get("full_name"),
        previous={"sos_suspended_until": row.get("sos_suspended_until"), "sos_warning_count": count},
        new={"note": note, "warning_count": new_count, "cleared_warnings": clear_warnings},
    )
    _tell(
        user_id,
        type_="account.reinstated",
        title="You can send reports again",
        body=("Your suspension was lifted." if was["active"] else "Your warnings were cleared.")
             + (f" {note}" if note else ""),
        meta={"at": _now().isoformat(), "note": note, "warning_count": new_count, "was_suspended": was["active"]},
    )
    log.info("resident_account.reinstated", user_id=user_id, cleared=clear_warnings, actor_id=str(actor.get("id")))
    return {
        "id": user_id, "warning_count": new_count,
        "suspension": {"active": False, "indefinite": False, "until": None},
        "standing": "warned" if new_count > 0 else "good",
    }


def announce_false_sos(reporter_id: str, *, incident_id: str, result: dict, actor: dict) -> None:
    """The false-SOS flag already raised the count; record it and tell the resident.

    incident_service.record_false_sos has always changed the row silently: no
    audit entry, and the resident learned of it only when the SOS button stopped
    working. Never raises - the flag itself has been applied.
    """
    try:
        count = int(result.get("warning_count") or 0)
        audit_service.record(
            actor=actor, action=WARNED, target_type="user", target_id=str(reporter_id),
            previous={"sos_warning_count": max(count - 1, 0)},
            new={"violation": "false_sos", "note": "An SOS was confirmed as a false alarm.",
                 "incident_id": str(incident_id), "warning_count": count},
        )
        at = _now().isoformat()
        _tell(
            str(reporter_id), type_="account.warned", title="You received a warning",
            body=f"{VIOLATIONS['false_sos']}. An SOS you sent was confirmed as a false alarm.",
            meta={"at": at, "violation": "false_sos", "violation_label": VIOLATIONS["false_sos"],
                  "note": "An SOS you sent was confirmed as a false alarm.", "warning_count": count,
                  "warnings_left": max(AUTO_SUSPEND_AT - count, 0), "incident_id": str(incident_id)},
        )
        until = _parse(result.get("suspended_until"))
        if until is not None:
            audit_service.record(
                actor=actor, action=SUSPENDED, target_type="user", target_id=str(reporter_id),
                new={"violation": "false_sos", "note": f"Automatic: {count} warnings on record.",
                     "incident_id": str(incident_id), "suspended_until": until.isoformat(),
                     "indefinite": False, "automatic": True},
            )
            _tell(
                str(reporter_id), type_="account.suspended",
                title="Your account is suspended from reporting",
                body=f"{VIOLATIONS['false_sos']}. You cannot send reports until {until.strftime('%B %d, %Y')}.",
                meta={"at": at, "violation": "false_sos", "violation_label": VIOLATIONS["false_sos"],
                      "note": f"Automatic: {count} warnings on record.",
                      "suspended_until": until.isoformat(), "indefinite": False, "automatic": True},
            )
    except Exception:
        log.error("resident_account.false_sos_announce_failed", reporter_id=reporter_id, exc_info=True)
