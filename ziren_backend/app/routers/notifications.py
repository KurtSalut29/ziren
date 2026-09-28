"""
/notifications — the notification bell/center.

Every route reads or writes only the CALLER's own notifications
(recipient_id = current_user["id"]) — any authenticated role, not just
admins. A resident gets notified about their own incident's status just as
much as a Provincial Admin gets notified about a new station.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.dependencies import get_current_user
from app.services import notification_service

router = APIRouter()


@router.get("/")
def list_notifications(
    unread_only: bool = Query(False),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user),
):
    return notification_service.list_for_user(
        str(current_user["id"]), unread_only=unread_only, limit=limit, offset=offset,
    )


@router.get("/unread-count")
def unread_count(current_user: dict = Depends(get_current_user)):
    result = notification_service.list_for_user(str(current_user["id"]), unread_only=True, limit=1)
    return {"unread_count": result["unread_count"]}


@router.patch("/read-all")
def mark_all_read(current_user: dict = Depends(get_current_user)):
    updated = notification_service.mark_all_read(str(current_user["id"]))
    return {"updated": updated}


@router.patch("/{notification_id}/read")
def mark_read(notification_id: str, current_user: dict = Depends(get_current_user)):
    row = notification_service.mark_read(str(current_user["id"]), notification_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Notification not found.")
    return row
