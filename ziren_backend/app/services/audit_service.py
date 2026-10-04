"""
audit_service — the single write-path for administrative audit trail rows.

Every mutation a Provincial Admin or Agency Admin makes to a managed
resource (station, account, rubric config, system config, announcement)
calls record() here, in addition to whatever structlog line already exists
at that call site. This is what the Audit Logs module and System
Governance's Configuration History read, and it is also how Notifications
get most of their content: a NOTIFY_ACTIONS entry fans a row out to the
given roles' inboxes via notification_service.

agency_type on both the row and the notify fan-out: pass the agency_type
the action belongs to (e.g. the station's, the reassigned responder's) for
anything agency-owned, so only that one Provincial Admin sees/is notified
of it, not all three. Leave it unset (None) for genuinely platform-wide
actions (system_config.updated) — see migration 034's Type A/B split.
"""

from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterator

import structlog
from fastapi import HTTPException, status

from app.db.supabase_client import get_supabase
from app.services import notification_service

log = structlog.get_logger()

# action -> roles to notify. Absent action = audit-only, no notification.
NOTIFY_ACTIONS: dict[str, tuple[str, ...]] = {
    "station.created":        ("provincial_admin",),
    "station.activated":      ("provincial_admin",),
    "station.deactivated":    ("provincial_admin",),
    "agency_admin.created":   ("provincial_admin",),
    "agency_admin.assigned":  ("provincial_admin",),
    "responder.reassigned":   ("provincial_admin",),
    "account.suspended":      ("provincial_admin",),
    "account.deactivated":    ("provincial_admin",),
    "account.reactivated":    ("provincial_admin",),
    "verification.approved":  ("provincial_admin",),
    "verification.rejected":  ("provincial_admin",),
    "rubric.activated":       ("provincial_admin",),
    "system_config.updated":  ("provincial_admin",),
    # announcement.published is deliberately ABSENT here: it already fans
    # out a precisely-targeted notification from inside
    # announcement_service.publish() itself (to whichever audience the
    # announcement actually targets — a specific role, a specific agency, or
    # everyone), and this audit call runs right alongside that. Mapping it
    # here too would double-notify and, worse, notify the WRONG audience
    # (this map has no way to express "whoever the announcement targeted").
}


def record(
    *,
    actor: dict,
    action: str,
    target_type: str,
    target_id: str | None = None,
    target_label: str | None = None,
    previous: dict | None = None,
    new: dict | None = None,
    metadata: dict[str, Any] | None = None,
    agency_type: str | None = None,
) -> dict:
    """
    Insert one audit_logs row for an EVENT that changed nothing (a sign-in, a
    security event). Never raises. Anything that changes state uses action()
    below, which refuses the change when it cannot be recorded (finding #6).

    agency_type: which agency_type (PNP/BFP/MDRRMO) this action belongs to,
    if any. Stored on the row so a Provincial Admin's Audit Logs view can be
    filtered to "mine + platform-wide", and used below to target the
    notification fan-out to that one Provincial Admin instead of all three.
    """
    db = get_supabase()
    payload = {
        "actor_id":       str(actor.get("id")) if actor.get("id") else None,
        "actor_role":     actor.get("role"),
        "actor_name":     actor.get("full_name"),
        "action":         action,
        "target_type":    target_type,
        "target_id":      str(target_id) if target_id is not None else None,
        "target_label":   target_label,
        "previous_value": previous,
        "new_value":      new,
        "metadata":       metadata,
        "agency_type":    agency_type,
    }
    try:
        result = db.table("audit_logs").insert(payload).execute()
        row = (result.data or [payload])[0]
    except Exception:
        log.error(
            "audit_service.write_failed",
            action=action,
            target_type=target_type,
            target_id=target_id,
            exc_info=True,
        )
        return payload

    _notify(action, target_label or target_id, metadata, actor, agency_type)
    return row


# =============================================================================
# Audited actions — the action and its record succeed or fail together
# =============================================================================
#
# Evaluator finding #6 (2026-10-05): record() above runs AFTER the change it
# describes and never raises, so an account could be approved, a station
# deactivated or a setting changed with no row saying who did it. For
# anything that changes state, use action() instead:
#
#     with audit_service.action(actor=..., action="station.deactivated",
#                               target_type="station", target_id=sid) as entry:
#         db.table("stations").update(...).execute()
#         entry.new = {"is_active": False}
#
# The row is written FIRST, as 'pending'. If it cannot be written the action
# is refused (503) and nothing changes. The block then runs; on success the row
# becomes 'succeeded', on an exception 'failed' (and the exception carries on).
# If even that final update cannot be written the row stays 'pending' — the
# attempt and its author are still on record. record() remains for events that
# change nothing (a sign-in), where refusing the event would help no one.
#
# Before migration 044 the table has no outcome column: the row is then written
# without one, still before the action, still mandatory.


class AuditUnavailable(HTTPException):
    def __init__(self) -> None:
        super().__init__(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "This change was not made because it could not be recorded in "
                "the audit log. Try again in a moment."
            ),
        )


@dataclass
class AuditEntry:
    """What the block may fill in before the row is completed."""
    id: str | None
    action: str
    target_label: str | None
    new: dict | None = None
    metadata: dict[str, Any] | None = None
    notify: bool = True
    _fields: dict = field(default_factory=dict)


def _missing_outcome_column(exc: Exception) -> bool:
    text = str(exc)
    return "outcome" in text and ("42703" in text or "PGRST204" in text or "does not exist" in text
                                  or "Could not find" in text)


@contextmanager
def action(
    *,
    actor: dict,
    action: str,
    target_type: str,
    target_id: str | None = None,
    target_label: str | None = None,
    previous: dict | None = None,
    new: dict | None = None,
    metadata: dict[str, Any] | None = None,
    agency_type: str | None = None,
) -> Iterator[AuditEntry]:
    db = get_supabase()
    payload = {
        "actor_id":       str(actor.get("id")) if actor.get("id") else None,
        "actor_role":     actor.get("role"),
        "actor_name":     actor.get("full_name"),
        "action":         action,
        "target_type":    target_type,
        "target_id":      str(target_id) if target_id is not None else None,
        "target_label":   target_label,
        "previous_value": previous,
        "new_value":      new,
        "metadata":       metadata,
        "agency_type":    agency_type,
    }

    with_outcome = True
    try:
        result = db.table("audit_logs").insert({**payload, "outcome": "pending"}).execute()
    except Exception as exc:
        if not _missing_outcome_column(exc):
            log.error("audit_service.pending_write_failed", action=action, exc_info=True)
            raise AuditUnavailable() from exc
        # Pre-044 database: no outcome to track, but the row still comes first.
        with_outcome = False
        try:
            result = db.table("audit_logs").insert(payload).execute()
        except Exception as exc2:
            log.error("audit_service.pending_write_failed", action=action, exc_info=True)
            raise AuditUnavailable() from exc2

    rows = getattr(result, "data", None) or []
    if not rows:
        # An insert that returned nothing did not demonstrably write anything.
        log.error("audit_service.pending_write_empty", action=action)
        raise AuditUnavailable()

    row_id = rows[0].get("id")
    entry = AuditEntry(id=row_id, action=action, target_label=target_label, new=new, metadata=metadata)

    try:
        yield entry
    except BaseException as exc:
        if with_outcome and row_id:
            _complete(db, row_id, {
                "outcome": "failed",
                "completed_at": datetime.now(timezone.utc).isoformat(),
                "error": _short_error(exc),
            })
        raise

    if with_outcome and row_id:
        done: dict[str, Any] = {
            "outcome": "succeeded",
            "completed_at": datetime.now(timezone.utc).isoformat(),
        }
        if entry.new is not None and entry.new != new:
            done["new_value"] = entry.new
        if entry.metadata is not None and entry.metadata != metadata:
            done["metadata"] = entry.metadata
        _complete(db, row_id, done)

    if entry.notify:
        _notify(action, entry.target_label or target_label or target_id, entry.metadata or metadata,
                actor, agency_type)


def _complete(db, row_id: str, values: dict) -> None:
    """Best effort: a row left 'pending' still names who attempted what."""
    try:
        db.table("audit_logs").update(values).eq("id", row_id).execute()
    except Exception:
        log.error("audit_service.complete_failed", audit_id=row_id, outcome=values.get("outcome"),
                  exc_info=True)


def _short_error(exc: BaseException) -> str:
    detail = getattr(exc, "detail", None)
    text = detail if isinstance(detail, str) else (str(exc) or type(exc).__name__)
    return text[:500]


def _notify(action: str, label: Any, metadata: dict | None, actor: dict, agency_type: str | None) -> None:
    roles = NOTIFY_ACTIONS.get(action)
    if not roles:
        return
    try:
        notification_service.create_for_roles(
            roles=roles,
            type_=action,
            title=_notify_title(action, str(label or "")),
            body=(metadata or {}).get("notify_body"),
            link=(metadata or {}).get("notify_link"),
            exclude_user_id=str(actor.get("id")) if actor.get("id") else None,
            agency_type=agency_type,
        )
    except Exception:
        log.error("audit_service.notify_failed", action=action, exc_info=True)


def _notify_title(action: str, label: str) -> str:
    parts = action.split(".", 1)
    noun = parts[0].replace("_", " ")
    verb = parts[1].replace("_", " ") if len(parts) > 1 else ""
    title = f"{noun.capitalize()} {verb}".strip()
    return f"{title}: {label}" if label else title
