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

from typing import Any

import structlog

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
    Insert one audit_logs row. Never raises — a failed audit write must not
    fail the operation it is describing; it logs via structlog instead so
    the gap is at least visible in the server log.

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

    roles = NOTIFY_ACTIONS.get(action)
    if roles:
        try:
            notification_service.create_for_roles(
                roles=roles,
                type_=action,
                title=_notify_title(action, target_label or target_id or ""),
                body=(metadata or {}).get("notify_body"),
                link=(metadata or {}).get("notify_link"),
                exclude_user_id=str(actor.get("id")) if actor.get("id") else None,
                agency_type=agency_type,
            )
        except Exception:
            log.error("audit_service.notify_failed", action=action, exc_info=True)

    return row


def _notify_title(action: str, label: str) -> str:
    parts = action.split(".", 1)
    noun = parts[0].replace("_", " ")
    verb = parts[1].replace("_", " ") if len(parts) > 1 else ""
    title = f"{noun.capitalize()} {verb}".strip()
    return f"{title}: {label}" if label else title
