"""
/announcements — spec Section 14, and the safety alerts of migration 043.

  GET    /                                   any role: what applies to them (see below)
  POST   /audience                           Provincial Admin: how many a draft would reach
  POST   /                                   Provincial Admin: publish
  GET    /{id}                               whoever it reached: one announcement
  POST   /{id}/respond                       resident: "safe" or "need_help"
  GET    /{id}/responses                     admins: the answer board
  POST   /{id}/responses/{user_id}/reached   admins: someone who asked for help was reached
  PATCH  /{id}/deactivate                    Provincial Admin

GET / answers by role: a Provincial Admin with mine_only=false gets every
announcement (the management list); an Agency Admin gets everything announced
to their town; everyone else gets what is aimed at their role and place.
"""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator

from app.core.dependencies import get_current_user, require_provincial_admin
from app.services import announcement_service
from app.services.announcement_service import AlertClosed, SchemaNotReady

router = APIRouter()

_TARGET_TYPES = {"all", "agency_admin", "responder", "resident", "agency"}


class AnnouncementCreateRequest(BaseModel):
    title: str
    body: str
    category: str
    target_type: str = "all"
    target_agency_id: str | None = None
    expires_at: str | None = None
    details: dict | None = None
    target_municipalities: list[str] | None = None
    target_barangay_ids: list[str] | None = None
    asks_response: bool = False
    ends_announcement_id: str | None = None

    @field_validator("category")
    @classmethod
    def valid_category(cls, v: str) -> str:
        if v not in announcement_service.CATEGORIES:
            raise ValueError(f"category must be one of: {', '.join(announcement_service.CATEGORIES)}")
        return v

    @field_validator("target_type")
    @classmethod
    def valid_target_type(cls, v: str) -> str:
        if v not in _TARGET_TYPES:
            raise ValueError(f"target_type must be one of: {', '.join(sorted(_TARGET_TYPES))}")
        return v


class RespondRequest(BaseModel):
    status: Literal["safe", "need_help"]
    note: str | None = Field(default=None, max_length=300)
    latitude: float | None = None
    longitude: float | None = None


class ReachedRequest(BaseModel):
    reached: bool = True


def _fail(exc: Exception) -> HTTPException:
    """One place that turns the service's exceptions into HTTP answers."""
    if isinstance(exc, SchemaNotReady):
        return HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    if isinstance(exc, AlertClosed):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    if isinstance(exc, LookupError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc).strip("'\""))
    if isinstance(exc, PermissionError):
        return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    if isinstance(exc, ValueError):
        return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))
    return HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))


_HANDLED = (SchemaNotReady, AlertClosed, LookupError, PermissionError, ValueError, RuntimeError)


@router.get("/")
def list_announcements(
    mine_only: bool = True,
    current_user: dict = Depends(get_current_user),
):
    """
    Provincial Admin with mine_only=False: every announcement, for the
    management view — Type B, unscoped by agency_type (see migration 034's
    "announcements: provincial_admin full read" policy): a broadcast can
    target any role or agency, so all 3 Provincial Admins manage the same
    shared list rather than only their own agency_type's slice of it.
    """
    role = current_user.get("role")
    if not mine_only and role == "provincial_admin":
        return announcement_service.list_all()
    if role == "agency_admin":
        return announcement_service.list_for_station(current_user)
    return announcement_service.list_for_user(current_user)


def _fields(body: AnnouncementCreateRequest) -> dict:
    return {
        "title": body.title,
        "body": body.body,
        "category": body.category,
        "target_type": body.target_type,
        "target_agency_id": body.target_agency_id,
        "expires_at": body.expires_at,
        "details": body.details,
        "target_municipalities": body.target_municipalities,
        "target_barangay_ids": body.target_barangay_ids,
        "asks_response": body.asks_response,
        "ends_announcement_id": body.ends_announcement_id,
    }


@router.post("/audience")
def preview_audience(
    body: AnnouncementCreateRequest,
    current_user: dict = Depends(require_provincial_admin),
):
    try:
        return announcement_service.preview_audience(current_user, **_fields(body))
    except _HANDLED as exc:
        raise _fail(exc)


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_announcement(
    body: AnnouncementCreateRequest,
    current_user: dict = Depends(require_provincial_admin),
):
    if body.target_type == "agency" and not body.target_agency_id and body.category != "all_clear":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="target_agency_id is required when target_type is 'agency'.",
        )
    try:
        return announcement_service.publish(current_user, **_fields(body))
    except _HANDLED as exc:
        raise _fail(exc)


@router.get("/{announcement_id}")
def get_announcement(
    announcement_id: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        return announcement_service.get_one(announcement_id, current_user)
    except _HANDLED as exc:
        raise _fail(exc)


@router.post("/{announcement_id}/respond")
def respond(
    announcement_id: str,
    body: RespondRequest,
    current_user: dict = Depends(get_current_user),
):
    try:
        return announcement_service.respond(
            announcement_id, current_user,
            status=body.status, note=body.note, latitude=body.latitude, longitude=body.longitude,
        )
    except _HANDLED as exc:
        raise _fail(exc)


@router.get("/{announcement_id}/responses")
def responses(
    announcement_id: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        return announcement_service.responses(announcement_id, current_user)
    except _HANDLED as exc:
        raise _fail(exc)


@router.post("/{announcement_id}/responses/{user_id}/reached")
def mark_reached(
    announcement_id: str,
    user_id: str,
    body: ReachedRequest | None = None,
    current_user: dict = Depends(get_current_user),
):
    try:
        return announcement_service.mark_reached(
            announcement_id, user_id, current_user, reached=(body.reached if body else True),
        )
    except _HANDLED as exc:
        raise _fail(exc)


@router.patch("/{announcement_id}/deactivate")
def deactivate_announcement(
    announcement_id: str,
    current_user: dict = Depends(require_provincial_admin),
):
    try:
        return announcement_service.deactivate(announcement_id, current_user)
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))
