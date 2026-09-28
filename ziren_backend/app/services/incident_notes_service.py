"""
incident_notes_service — Agency Admin spec Section 5 (operational notes) and
Section 18 (Agency Communication). One append-only, incident-scoped thread
serves both — see migration 030's header for why.

Shared between dispatch.py (agency_admin/provincial_admin) and responder.py
(the responder assigned to the incident) rather than living inside either
dispatch_service or responder_service, so neither has to import the other.
"""

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase
from app.services import notification_service

log = structlog.get_logger()


def _assert_can_see_incident(db: Client, incident_id: str, actor: dict) -> dict:
    """Same scope rule as every other incident read in this codebase:
    agency_admin scoped to their own agency, provincial_admin scoped to
    every agency of their own agency_type, responder scoped to their own
    assignment."""
    result = (
        db.table("incidents")
        .select("id, reporter_id, assigned_agency_id, assigned_responder_id, review_status")
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = result.data
    role = actor.get("role")
    if role in ("agency_admin", "provincial_admin"):
        assert_agency_scope(actor, str(incident.get("assigned_agency_id") or ""))
    elif role == "responder":
        if str(incident.get("assigned_responder_id")) != str(actor.get("id") or ""):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not assigned to this incident.",
            )
    elif role == "resident":
        # The reporter's own incident, and only their own — see migration
        # 031's header for why this is the same thread agency staff use,
        # not a separate resident-only copy of it.
        if str(incident.get("reporter_id")) != str(actor.get("id") or ""):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view notes on your own reports.",
            )
    return incident


def list_notes(incident_id: str, actor: dict) -> list[dict]:
    db: Client = get_supabase()
    _assert_can_see_incident(db, incident_id, actor)

    result = (
        db.table("incident_notes")
        .select("id, incident_id, author_id, author_role, body, created_at, users(full_name)")
        .eq("incident_id", incident_id)
        .order("created_at", desc=False)
        .execute()
    )
    return result.data or []


def add_note(incident_id: str, actor: dict, body: str) -> dict:
    if not body or not body.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Note cannot be empty.")

    db: Client = get_supabase()
    incident = _assert_can_see_incident(db, incident_id, actor)

    payload = {
        "incident_id": incident_id,
        "author_id": str(actor["id"]),
        "author_role": actor.get("role"),
        "body": body.strip(),
    }
    result = db.table("incident_notes").insert(payload).execute()
    note = (result.data or [payload])[0]

    if actor.get("role") == "resident":
        _reporter_replied(db, incident, actor, body.strip())
    else:
        _tell_reporter_of_message(incident, actor, body.strip(), note)

    return note


def _tell_reporter_of_message(incident: dict, actor: dict, body: str, note: dict) -> None:
    """An agency admin or the assigned crew wrote on the report: the resident is told.

    A note written after the report was decided is the agency talking to the
    resident - and until now the only way the resident found out was to open the
    report and look. Best-effort, like every notification: the note is already saved.
    """
    who = "the responder" if actor.get("role") == "responder" else "the agency"
    notification_service.notify_reporter(
        incident.get("reporter_id"),
        incident_id=str(incident.get("id")),
        type_="incident.message",
        title=f"New message from {who}",
        body=body,
        at=str(note.get("created_at") or ""),
        extra={"note_id": str(note.get("id") or "")},
    )


def _reporter_replied(db: Client, incident: dict, actor: dict, body: str) -> None:
    """The resident wrote on their own report - close the loop with the agency.

    Two things, both best-effort and neither able to fail the note itself:

      * If the agency had asked a question (review_status
        'clarification_requested'), the answer puts the report back to
        'pending'. Without this a clarified report sat in its own state forever
        - the agency asked, the resident answered, and nothing on the
        dashboard changed to say so. The question itself stays on the row
        (clarification_note, clarification_requested_at) so the thread reads in
        order: the dashboard shows "Resident replied" when a resident note
        postdates the request.
      * The agency's admins are told, important when it is an answer to their
        own question.
    """
    was_question = incident.get("review_status") == "clarification_requested"
    try:
        if was_question:
            db.table("incidents").update({"review_status": "pending"}).eq(
                "id", incident["id"]
            ).execute()
        agency_id = incident.get("assigned_agency_id")
        if agency_id:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_="incident.clarification_answered" if was_question else "incident.note_added",
                title=(
                    "Resident answered your question"
                    if was_question
                    else "Resident added information to a report"
                ),
                body=body[:140],
                link=f"/incidents/{incident['id']}",
                is_important=was_question,
            )
    except Exception:
        log.error("incident_notes.reporter_reply_side_effects_failed",
                  incident_id=incident.get("id"), exc_info=True)
