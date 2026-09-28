"""
announcement_service — Provincial Admin's system-wide broadcasts (spec
Section 14).

publish() both inserts the row and fans out a notification to whichever
audience it targets, reusing notification_service's role/agency fan-out
(Task 4) rather than building a third delivery mechanism.
"""

from typing import Any

from app.db.supabase_client import get_supabase
from app.services import audit_service, notification_service

_ALL_ROLES = ("provincial_admin", "agency_admin", "responder", "resident")


def publish(
    actor: dict,
    *,
    title: str,
    body: str,
    category: str,
    target_type: str,
    target_agency_id: str | None = None,
    expires_at: str | None = None,
) -> dict:
    db = get_supabase()

    payload = {
        "title": title,
        "body": body,
        "category": category,
        "target_type": target_type,
        "target_agency_id": target_agency_id,
        "created_by": actor.get("id"),
        "expires_at": expires_at,
    }
    result = db.table("announcements").insert(payload).execute()
    if not result.data:
        raise RuntimeError("Failed to publish announcement.")
    row = result.data[0]

    notify_kwargs: dict[str, Any] = {
        "type_": "announcement.published",
        "title": f"Announcement: {title}",
        "body": body[:200],
        "link": "/announcements",
        "exclude_user_id": actor.get("id"),
    }
    if target_type == "all":
        notification_service.create_for_roles(roles=_ALL_ROLES, **notify_kwargs)
    elif target_type == "agency":
        notification_service.create_for_agency(target_agency_id, **notify_kwargs)
    else:
        notification_service.create_for_roles(roles=(target_type,), **notify_kwargs)

    audit_service.record(
        actor=actor,
        action="announcement.published",
        target_type="announcement",
        target_id=row["id"],
        target_label=title,
    )

    return row


def list_for_user(user: dict) -> list[dict]:
    """
    Announcements that apply to this user: target_type='all', OR matches
    their role, OR (target_type='agency' AND target_agency_id is theirs) —
    active and not expired.
    """
    db = get_supabase()
    result = (
        db.table("announcements")
        .select("*")
        .eq("is_active", True)
        .order("created_at", desc=True)
        .execute()
    )
    rows = result.data or []

    role = user.get("role")
    agency_id = str(user.get("agency_id")) if user.get("agency_id") else None

    def applies(row: dict) -> bool:
        if row["target_type"] == "all":
            return True
        if row["target_type"] == role:
            return True
        if row["target_type"] == "agency":
            return agency_id is not None and str(row.get("target_agency_id")) == agency_id
        return False

    return [row for row in rows if applies(row)]


def list_all(include_inactive: bool = True) -> list[dict]:
    """Provincial Admin's own management list — every announcement, active or not."""
    db = get_supabase()
    query = db.table("announcements").select("*").order("created_at", desc=True)
    if not include_inactive:
        query = query.eq("is_active", True)
    return query.execute().data or []


def deactivate(announcement_id: str, actor: dict) -> dict:
    db = get_supabase()
    check = db.table("announcements").select("id, title").eq("id", announcement_id).single().execute()
    if not check.data:
        raise ValueError("Announcement not found.")

    result = (
        db.table("announcements")
        .update({"is_active": False})
        .eq("id", announcement_id)
        .execute()
    )
    if not result.data:
        raise RuntimeError("Failed to deactivate announcement.")

    audit_service.record(
        actor=actor,
        action="announcement.deactivated",
        target_type="announcement",
        target_id=announcement_id,
        target_label=check.data.get("title"),
    )

    return result.data[0]
