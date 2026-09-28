"""
feedback_service — Resident spec Section 26, post-resolution rating.

Deliberately thin and isolated: nothing here is imported by
dispatch_service, rubric_service, or triage_service, and nothing in those
modules imports this one. The spec is explicit that a rating must never
affect emergency prioritization, so the surest way to guarantee that is for
this table to have no read path into the code that decides anything about
an incident's handling — see migration 032's header.
"""

from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase


def get_feedback_for_admin(incident_id: str, dispatcher: dict) -> dict | None:
    """
    A dispatcher's read of the resident's own post-resolution rating —
    same table get_my_feedback reads, but not scoped to a reporter_id since
    the caller here is the agency, not the person who filed it.

    None means "not yet rated", same contract as get_my_feedback — most
    incidents will never get one, since rating is optional, and that is not
    an error state.
    """
    db: Client = get_supabase()

    incident = (
        db.table("incidents")
        .select("id, assigned_agency_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not incident.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    # Same scope rule as get_incident_media: an agency_admin sees only what
    # was assigned to their own agency, a provincial_admin sees anything
    # assigned to their own agency_type.
    if dispatcher.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(dispatcher, str(incident.data.get("assigned_agency_id") or ""))

    result = (
        db.table("incident_feedback")
        .select("id, incident_id, rating, comment, created_at")
        .eq("incident_id", incident_id)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def get_my_feedback(incident_id: str, reporter_id: str) -> dict | None:
    """None means "not yet rated" — never 404. The mobile app uses this to
    decide whether to show the rating prompt at all."""
    db: Client = get_supabase()
    result = (
        db.table("incident_feedback")
        .select("id, incident_id, rating, comment, created_at")
        .eq("incident_id", incident_id)
        .eq("reporter_id", reporter_id)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def submit_feedback(
    incident_id: str,
    reporter_id: str,
    rating: int,
    comment: str | None,
) -> dict:
    db: Client = get_supabase()

    incident = (
        db.table("incidents")
        .select("id, reporter_id, status")
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if incident is None or not incident.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")
    if str(incident.data.get("reporter_id")) != str(reporter_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You can only rate your own reports.")
    if incident.data.get("status") != "resolved":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Feedback can only be given once a report is resolved.",
        )

    existing = get_my_feedback(incident_id, reporter_id)
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="You already rated this report.")

    payload = {
        "incident_id": incident_id,
        "reporter_id": reporter_id,
        "rating": rating,
        "comment": (comment.strip() if comment and comment.strip() else None),
    }
    result = db.table("incident_feedback").insert(payload).execute()
    return (result.data or [payload])[0]
