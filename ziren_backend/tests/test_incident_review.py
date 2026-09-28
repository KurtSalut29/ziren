"""
dispatch_service.accept_report / reject_report / request_clarification —
Agency Admin spec Section 3 (Verification): New Report -> Verification ->
Accepted/Rejected, recorded via `review_status` alongside the existing
`status` column (migration 029).
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import dispatch_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
OTHER_AGENCY_ID = "b0000002-0000-0000-0000-000000000002"
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"

DISPATCHER = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}


def _db(incident_row):
    db = MagicMock()
    single_result = MagicMock()
    single_result.data = incident_row
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = single_result
    return db


def _incident(review_status="pending", status="received", agency_id=AGENCY_ID):
    return {"id": INCIDENT_ID, "status": status, "review_status": review_status, "assigned_agency_id": agency_id}


# ── accept_report ──────────────────────────────────────────────────────────

def test_accept_report_sets_review_status_and_logs():
    db = _db(_incident())
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        result = dispatch_service.accept_report(INCIDENT_ID, DISPATCHER)

    assert result == {"incident_id": INCIDENT_ID, "review_status": "accepted", "already_reviewed": False}
    update_call = db.table.return_value.update.call_args[0][0]
    assert update_call["review_status"] == "accepted"
    assert update_call["reviewed_by"] == DISPATCHER["id"]

    # Logged into the same immutable dispatch_log audit trail as every other action.
    log_call = db.table.return_value.insert.call_args[0][0]
    assert log_call["action"] == "accepted"


def test_accept_report_is_idempotent():
    db = _db(_incident(review_status="accepted"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        result = dispatch_service.accept_report(INCIDENT_ID, DISPATCHER)
    assert result["already_reviewed"] is True
    db.table.return_value.update.assert_not_called()


def test_accept_report_refuses_an_already_rejected_report():
    db = _db(_incident(review_status="rejected"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            dispatch_service.accept_report(INCIDENT_ID, DISPATCHER)
    assert exc.value.status_code == 422


def test_accept_report_scoped_to_agency():
    db = _db(_incident(agency_id=OTHER_AGENCY_ID))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            dispatch_service.accept_report(INCIDENT_ID, DISPATCHER)
    assert exc.value.status_code == 403


# ── reject_report ────────────────────────────────────────────────────────

def test_reject_report_requires_a_reason():
    db = _db(_incident())
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            dispatch_service.reject_report(INCIDENT_ID, "  ", DISPATCHER)
    assert exc.value.status_code == 422


def test_reject_report_cancels_the_incident_and_records_the_reason():
    db = _db(_incident())
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        result = dispatch_service.reject_report(INCIDENT_ID, "Duplicate of another report", DISPATCHER)

    assert result == {"incident_id": INCIDENT_ID, "review_status": "rejected", "status": "cancelled"}
    update_call = db.table.return_value.update.call_args[0][0]
    assert update_call["review_status"] == "rejected"
    assert update_call["status"] == "cancelled"
    assert update_call["rejection_reason"] == "Duplicate of another report"


def test_reject_report_refuses_an_already_resolved_incident():
    db = _db(_incident(status="resolved"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            dispatch_service.reject_report(INCIDENT_ID, "too late", DISPATCHER)
    assert exc.value.status_code == 422


# ── request_clarification ───────────────────────────────────────────────

def test_request_clarification_requires_a_note():
    db = _db(_incident())
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            dispatch_service.request_clarification(INCIDENT_ID, "", DISPATCHER)
    assert exc.value.status_code == 422


def test_request_clarification_leaves_status_untouched():
    """
    Nothing has been decided yet, so the report must stay in the live queue —
    only review_status and the clarification fields change.
    """
    db = _db(_incident(status="received"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        result = dispatch_service.request_clarification(INCIDENT_ID, "What barangay exactly?", DISPATCHER)

    assert result == {"incident_id": INCIDENT_ID, "review_status": "clarification_requested"}
    update_call = db.table.return_value.update.call_args[0][0]
    assert update_call["review_status"] == "clarification_requested"
    assert update_call["clarification_note"] == "What barangay exactly?"
    assert "status" not in update_call


def test_request_clarification_refuses_an_already_decided_report():
    db = _db(_incident(review_status="accepted"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            dispatch_service.request_clarification(INCIDENT_ID, "note", DISPATCHER)
    assert exc.value.status_code == 422


# ── assign_responder implicitly accepts a still-pending report ────────────

def test_assigning_a_pending_report_marks_it_accepted():
    """
    A dispatcher who assigns a responder has necessarily judged the report
    real, whether or not they clicked a separate Accept button first.
    """
    incident_row = {
        "id": INCIDENT_ID, "status": "received",
        "assigned_agency_id": AGENCY_ID, "assigned_responder_id": None,
        "review_status": "pending",
    }
    responder_row = {
        "id": "r1", "full_name": "Juan", "agency_id": AGENCY_ID,
        "approval_status": "approved", "availability": "on_duty", "role": "responder",
    }

    incidents_table = MagicMock()
    inc_result = MagicMock()
    inc_result.data = incident_row
    incidents_table.select.return_value.eq.return_value.single.return_value.execute.return_value = inc_result

    users_table = MagicMock()
    resp_result = MagicMock()
    resp_result.data = responder_row
    users_table.select.return_value.eq.return_value.single.return_value.execute.return_value = resp_result

    db = MagicMock()
    db.table.side_effect = lambda name: {"incidents": incidents_table, "users": users_table}.get(name, MagicMock())

    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        dispatch_service.assign_responder(
            incident_id=INCIDENT_ID, responder_id="r1", chosen_severity="high",
            suggested_severity="high", override_reason=None, notes=None, dispatcher=DISPATCHER,
        )

    update_payload = incidents_table.update.call_args[0][0]
    assert update_payload["review_status"] == "accepted"
    assert update_payload["status"] == "dispatched"


def test_assigning_an_already_accepted_report_does_not_touch_review_status():
    incident_row = {
        "id": INCIDENT_ID, "status": "received",
        "assigned_agency_id": AGENCY_ID, "assigned_responder_id": None,
        "review_status": "accepted",
    }
    responder_row = {
        "id": "r1", "full_name": "Juan", "agency_id": AGENCY_ID,
        "approval_status": "approved", "availability": "on_duty", "role": "responder",
    }

    incidents_table = MagicMock()
    inc_result = MagicMock()
    inc_result.data = incident_row
    incidents_table.select.return_value.eq.return_value.single.return_value.execute.return_value = inc_result

    users_table = MagicMock()
    resp_result = MagicMock()
    resp_result.data = responder_row
    users_table.select.return_value.eq.return_value.single.return_value.execute.return_value = resp_result

    db = MagicMock()
    db.table.side_effect = lambda name: {"incidents": incidents_table, "users": users_table}.get(name, MagicMock())

    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        dispatch_service.assign_responder(
            incident_id=INCIDENT_ID, responder_id="r1", chosen_severity="high",
            suggested_severity="high", override_reason=None, notes=None, dispatcher=DISPATCHER,
        )

    update_payload = incidents_table.update.call_args[0][0]
    assert "review_status" not in update_payload


# ── the question is also a message in the thread ─────────────────────────

def test_request_clarification_also_posts_the_question_to_the_thread():
    """The incident row holds ONE question at a time; the thread keeps them all,
    in order, so the chat window shows what the agency asked."""
    db = _db(_incident(status="received"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        dispatch_service.request_clarification(INCIDENT_ID, "What barangay exactly?", DISPATCHER)

    db.table.assert_any_call("incident_notes")
    posted = [c.args[0] for c in db.table.return_value.insert.call_args_list if c.args and "body" in c.args[0]]
    assert posted == [{
        "incident_id": INCIDENT_ID,
        "author_id": DISPATCHER["id"],
        "author_role": "agency_admin",
        "body": "What barangay exactly?",
    }]


def test_a_thread_that_cannot_be_written_does_not_undo_the_question():
    db = _db(_incident(status="received"))

    def _table(name):
        table = MagicMock()
        if name == "incident_notes":
            table.insert.return_value.execute.side_effect = RuntimeError("thread write failed")
        return table

    real = _table
    # Everything else behaves as the shared double does; only the thread refuses.
    base = db.table

    def _dispatch_table(name):
        return real(name) if name == "incident_notes" else base.return_value

    db.table = MagicMock(side_effect=_dispatch_table)
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        result = dispatch_service.request_clarification(INCIDENT_ID, "Which house?", DISPATCHER)

    assert result == {"incident_id": INCIDENT_ID, "review_status": "clarification_requested"}
