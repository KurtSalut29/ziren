"""
notification_service — per-user notification feed.

Backs the notification bell/center. Rows are fanned out to recipients by
role (create_for_roles) or by agency (create_for_agency) — mostly called
from audit_service.record() via its NOTIFY_ACTIONS map, and directly by
announcement_service.publish().
"""

from typing import Iterable

import structlog

from app.db.supabase_client import get_supabase
from app.services import push_service

log = structlog.get_logger()


def _insert_for_recipients(
    recipient_ids: list[str],
    *,
    type_: str,
    title: str,
    body: str | None,
    link: str | None,
    is_important: bool,
    metadata: dict | None = None,
) -> None:
    if not recipient_ids:
        return
    db = get_supabase()
    rows = [
        {
            "recipient_id": rid,
            "type": type_,
            "title": title,
            "body": body,
            "link": link,
            "is_important": is_important,
            **({"metadata": metadata} if metadata else {}),
        }
        for rid in recipient_ids
    ]
    db.table("notifications").insert(rows).execute()

    # The same notice to the phone, even when the app is closed (evaluator
    # findings #11 / #12). A no-op until push is configured; never raises.
    push_service.send_to_users(
        recipient_ids,
        title=title,
        body=body,
        data={"type": type_, "link": link, **(metadata or {})},
        important=is_important,
    )


def create_for_roles(
    *,
    roles: Iterable[str],
    type_: str,
    title: str,
    body: str | None = None,
    link: str | None = None,
    is_important: bool = False,
    exclude_user_id: str | None = None,
    agency_type: str | None = None,
) -> None:
    """
    Notify every user whose role is in `roles`.

    exclude_user_id keeps an actor from being notified of their own action
    (e.g. the Provincial Admin who created a station doesn't need to be told
    they just did that).

    agency_type, when given, additionally restricts recipients to that
    agency_type — for `provincial_admin` this means only the ONE Provincial
    Admin who owns that agency_type is notified, not all three. Leave it
    None for platform-wide events (e.g. system_config.updated), where every
    Provincial Admin should be notified regardless of agency_type.
    """
    db = get_supabase()
    query = db.table("users").select("id").in_("role", list(roles))
    if agency_type is not None:
        query = query.eq("agency_type", agency_type)
    result = query.execute()
    recipient_ids = [
        row["id"] for row in (result.data or [])
        if not exclude_user_id or str(row["id"]) != str(exclude_user_id)
    ]
    _insert_for_recipients(
        recipient_ids, type_=type_, title=title, body=body, link=link, is_important=is_important,
    )


def create_for_agency(
    agency_id: str,
    *,
    type_: str,
    title: str,
    body: str | None = None,
    link: str | None = None,
    is_important: bool = False,
    exclude_user_id: str | None = None,
) -> None:
    """Notify every user (any role) belonging to the given agency."""
    db = get_supabase()
    result = db.table("users").select("id").eq("agency_id", agency_id).execute()
    recipient_ids = [
        row["id"] for row in (result.data or [])
        if not exclude_user_id or str(row["id"]) != str(exclude_user_id)
    ]
    _insert_for_recipients(
        recipient_ids, type_=type_, title=title, body=body, link=link, is_important=is_important,
    )


def create_for_agency_role(
    agency_id: str,
    role: str,
    *,
    type_: str,
    title: str,
    body: str | None = None,
    link: str | None = None,
    is_important: bool = False,
    exclude_user_id: str | None = None,
    metadata: dict | None = None,
) -> None:
    """
    Notify users of one ROLE belonging to one agency — e.g. "that agency's
    admins", not every responder and admin the agency employs.

    create_for_agency() notifies the whole agency regardless of role, which is
    right for an agency-wide policy change but wrong for an operational event
    like "a new incident arrived", and this is the fan-out incident/roster events
    use instead.

    (This docstring used to add that a responder does not need to be told an
    incident exists before a dispatcher has assigned it. That stopped being the
    rule on 2026-09-25: responders near a new incident are now told directly - see
    app.services.proximity - by a targeted fan-out of their own, not through this
    one, because "near" is a per-responder question this role-wide helper cannot
    ask.)

    `metadata` rides on every row, so a client can open the right screen without
    parsing an id back out of the text.
    """
    db = get_supabase()
    result = (
        db.table("users")
        .select("id")
        .eq("agency_id", agency_id)
        .eq("role", role)
        .execute()
    )
    recipient_ids = [
        row["id"] for row in (result.data or [])
        if not exclude_user_id or str(row["id"]) != str(exclude_user_id)
    ]
    _insert_for_recipients(
        recipient_ids, type_=type_, title=title, body=body, link=link,
        is_important=is_important, metadata=metadata,
    )


def create_for_user(
    user_id: str,
    *,
    type_: str,
    title: str,
    body: str | None = None,
    link: str | None = None,
    is_important: bool = False,
    metadata: dict | None = None,
) -> None:
    """Notify exactly one user - the reporter of an incident, for instance.

    The other create_for_* helpers fan out by role or agency, which is right for
    staff. A resident is told about THEIR report only, so this writes one row.
    `metadata` carries what the app needs to open the right screen - the
    incident id - without parsing it back out of the text.
    """
    _insert_for_recipients(
        [user_id], type_=type_, title=title, body=body, link=link,
        is_important=is_important, metadata=metadata,
    )


def create_for_users(
    user_ids: Iterable[str],
    *,
    type_: str,
    title: str,
    body: str | None = None,
    link: str | None = None,
    is_important: bool = False,
    metadata: dict | None = None,
    chunk: int = 500,
) -> None:
    """Notify an explicit list of users - an audience already worked out by the
    caller (an announcement aimed at two barangays is a list no role or agency
    fan-out can express). Written in chunks so a province-wide alert is not one
    enormous request. Duplicates are dropped."""
    ids: list[str] = []
    seen: set[str] = set()
    for uid in user_ids:
        s = str(uid)
        if s and s not in seen:
            seen.add(s)
            ids.append(s)
    for start in range(0, len(ids), max(1, chunk)):
        _insert_for_recipients(
            ids[start:start + chunk], type_=type_, title=title, body=body, link=link,
            is_important=is_important, metadata=metadata,
        )


def notify_reporter(
    reporter_id: str | None,
    *,
    incident_id: str,
    type_: str,
    title: str,
    body: str | None,
    at: str,
    important: bool = False,
    extra: dict | None = None,
) -> None:
    """Tell the resident who filed a report that something happened to it.

    One helper for every agency or crew action the resident should hear about
    (accepted, dispatched, on the way, arrived, resolved, cancelled, a message),
    so each one arrives as the SPECIFIC thing it is - "A responder is on the way",
    not a generic "Report update". `at` is the moment of the action; the phone keys
    a notice on (incident, kind, at), so the copy that arrives live over realtime
    and this stored copy are recognised as one event.

    Never raises. The action being reported has already happened and been
    recorded; a notification that could not be written must not undo it.
    """
    if not reporter_id:
        return
    try:
        create_for_user(
            str(reporter_id),
            type_=type_,
            title=title,
            body=(body or "")[:240] or None,
            link="/my-reports",
            is_important=important,
            metadata={"incident_id": str(incident_id), "at": at, **(extra or {})},
        )
    except Exception:
        log.error("notification.reporter_notify_failed", incident_id=incident_id, type=type_, exc_info=True)


def list_for_user(user_id: str, *, unread_only: bool = False, limit: int = 50, offset: int = 0) -> dict:
    """One page of a user's own notifications, newest first, plus their unread count."""
    db = get_supabase()

    query = (
        db.table("notifications")
        .select("*", count="exact")
        .eq("recipient_id", user_id)
        .order("created_at", desc=True)
    )
    if unread_only:
        query = query.eq("is_read", False)
    result = query.range(offset, offset + limit - 1).execute()

    unread = (
        db.table("notifications")
        .select("id", count="exact")
        .eq("recipient_id", user_id)
        .eq("is_read", False)
        .execute()
    )

    return {
        "items": result.data or [],
        "total": result.count or 0,
        "unread_count": unread.count or 0,
    }


def mark_read(user_id: str, notification_id: str) -> dict | None:
    """
    Mark one of the CALLER's OWN notifications read. Returns None if the
    notification doesn't exist or belongs to someone else — the router turns
    that into a 404, not a 403, so as not to reveal whether the id exists.
    """
    db = get_supabase()
    result = (
        db.table("notifications")
        .update({"is_read": True})
        .eq("id", notification_id)
        .eq("recipient_id", user_id)
        .execute()
    )
    return (result.data or [None])[0]


def mark_all_read(user_id: str) -> int:
    """Mark every unread notification for this user read. Returns the count updated."""
    db = get_supabase()
    result = (
        db.table("notifications")
        .update({"is_read": True})
        .eq("recipient_id", user_id)
        .eq("is_read", False)
        .execute()
    )
    return len(result.data or [])
