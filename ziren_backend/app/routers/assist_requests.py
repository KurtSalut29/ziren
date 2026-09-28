"""
/assist-requests — cross-agency "we need your help on this incident"
requests. agency_admin sends, receives and replies; provincial_admin gets
read-only oversight of their own agency_type's requests on either side
(migration 037) — never candidates/create/messages/status, which stay
agency_admin only per the design spec's Global Constraints. See
docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.

ROUTE ORDER MATTERS: GET /candidates is registered before GET /{request_id}
so "candidates" is never swallowed as a request_id path parameter.
"""

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.core.dependencies import require_admin, require_role
from app.services import assist_request_service

router = APIRouter()
_agency_admin = require_role("agency_admin")


class CreateAssistRequestBody(BaseModel):
    incident_id: str
    requested_agency_id: str
    message: str
    overlap_flag: str | None = None


class PostMessageBody(BaseModel):
    body: str


class SetStatusBody(BaseModel):
    status: str  # "acknowledged" | "declined" — validated in the service


@router.get("/candidates")
def candidates(incident_id: str = Query(...), current_user: dict = Depends(_agency_admin)):
    return assist_request_service.list_candidate_agencies(incident_id, current_user)


@router.post("")
def create(payload: CreateAssistRequestBody, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.create_request(
        payload.incident_id, payload.requested_agency_id, payload.message,
        payload.overlap_flag, current_user,
    )


@router.get("")
def list_mine(scope: str | None = Query(None), current_user: dict = Depends(require_admin)):
    return assist_request_service.list_for_agency(current_user, scope)


@router.get("/{request_id}")
def thread(request_id: str, current_user: dict = Depends(require_admin)):
    return assist_request_service.get_thread(request_id, current_user)


@router.post("/{request_id}/messages")
def send_message(request_id: str, payload: PostMessageBody, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.post_message(request_id, payload.body, current_user)


@router.patch("/{request_id}/status")
def respond(request_id: str, payload: SetStatusBody, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.set_status(request_id, payload.status, current_user)
