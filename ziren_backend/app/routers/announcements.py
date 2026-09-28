"""
/announcements — spec Section 14.

GET / is open to any authenticated role (filtered to what applies to them);
POST / and the deactivate route are Provincial Admin only.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, field_validator

from app.core.dependencies import get_current_user, require_provincial_admin
from app.services import announcement_service

router = APIRouter()

_CATEGORIES = {"maintenance", "emergency", "service_interruption", "feature", "reminder", "general"}
_TARGET_TYPES = {"all", "agency_admin", "responder", "resident", "agency"}


class AnnouncementCreateRequest(BaseModel):
    title: str
    body: str
    category: str
    target_type: str
    target_agency_id: str | None = None
    expires_at: str | None = None

    @field_validator("category")
    @classmethod
    def valid_category(cls, v: str) -> str:
        if v not in _CATEGORIES:
            raise ValueError(f"category must be one of: {', '.join(sorted(_CATEGORIES))}")
        return v

    @field_validator("target_type")
    @classmethod
    def valid_target_type(cls, v: str) -> str:
        if v not in _TARGET_TYPES:
            raise ValueError(f"target_type must be one of: {', '.join(sorted(_TARGET_TYPES))}")
        return v


@router.get("/")
def list_announcements(
    mine_only: bool = True,
    current_user: dict = Depends(get_current_user),
):
    """
    Any role: announcements that apply to them (mine_only=True, the default).
    Provincial Admin with mine_only=False: every announcement, for the
    management view — Type B, unscoped by agency_type (see migration 034's
    "announcements: provincial_admin full read" policy): a broadcast can
    target any role or agency, so all 3 Provincial Admins manage the same
    shared list rather than only their own agency_type's slice of it.
    """
    if not mine_only and current_user.get("role") == "provincial_admin":
        return announcement_service.list_all()
    return announcement_service.list_for_user(current_user)


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_announcement(
    body: AnnouncementCreateRequest,
    current_user: dict = Depends(require_provincial_admin),
):
    if body.target_type == "agency" and not body.target_agency_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="target_agency_id is required when target_type is 'agency'.",
        )
    try:
        return announcement_service.publish(
            current_user,
            title=body.title,
            body=body.body,
            category=body.category,
            target_type=body.target_type,
            target_agency_id=body.target_agency_id,
            expires_at=body.expires_at,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))


@router.patch("/{announcement_id}/deactivate")
def deactivate_announcement(
    announcement_id: str,
    current_user: dict = Depends(require_provincial_admin),
):
    try:
        return announcement_service.deactivate(announcement_id, current_user)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))
