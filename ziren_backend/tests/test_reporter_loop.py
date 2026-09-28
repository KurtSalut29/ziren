"""
The resident's half of the agency's Verification step.

Before this the resident's app was told nothing when an agency rejected a report
(it surfaced as a bare 'Cancelled' and landed in Trash) and never saw a
clarification request at all. Covered here:

  * reject / clarification put a notification in the REPORTER's own inbox
  * a failed notification never undoes the agency's decision
  * GET /incidents/my returns the review fields the app needs to tell a
    rejection from a withdrawal
  * a resident's reply to a clarification request puts the report back in the
    review queue and tells the agency
"""

from unittest.mock import MagicMock, patch

from app.services import dispatch_service, incident_notes_service, incident_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"
REPORTER_ID = "a0000007-0000-0000-0000-000000000007"
DISPATCHER = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}
RESIDENT = {"id": REPORTER_ID, "role": "resident", "agency_id": None}


def _review_db(review_status="pending"):
    db = MagicMock()
    row = MagicMock()
    row.data = {
        "id": INCIDENT_ID, "status": "received", "review_status": review_status,
        "assigned_agency_id": AGENCY_ID, "reporter_id": REPORTER_ID,
    }
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = row
    return db


# ── the agency's decision reaches the reporter ───────────────────────────────

def test_reject_notifies_the_reporter_with_the_reason():
    with patch("app.services.dispatch_service.get_supabase", return_value=_review_db()), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        dispatch_service.reject_report(INCIDENT_ID, "Duplicate of another report", DISPATCHER)

    notify.assert_called_once()
    assert notify.call_args.args[0] == REPORTER_ID
    kwargs = notify.call_args.kwargs
    assert kwargs["type_"] == "incident.rejected"
    assert "Duplicate of another report" in kwargs["body"]
    assert kwargs["is_important"] is True
    # The app finds the report from this, and keys the event on `at`.
    assert kwargs["metadata"]["incident_id"] == INCIDENT_ID
    assert kwargs["metadata"]["at"]


def test_clarification_notifies_the_reporter_with_the_question():
    with patch("app.services.dispatch_service.get_supabase", return_value=_review_db()), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        dispatch_service.request_clarification(INCIDENT_ID, "Which house is on fire?", DISPATCHER)

    kwargs = notify.call_args.kwargs
    assert notify.call_args.args[0] == REPORTER_ID
    assert kwargs["type_"] == "incident.clarification_requested"
    assert kwargs["body"] == "Which house is on fire?"


def test_a_failed_notification_does_not_undo_the_rejection():
    db = _review_db()
    with patch("app.services.dispatch_service.get_supabase", return_value=db), \
         patch(
             "app.services.dispatch_service.notification_service.create_for_user",
             side_effect=RuntimeError("notifications table unavailable"),
         ):
        result = dispatch_service.reject_report(INCIDENT_ID, "Not an emergency", DISPATCHER)

    assert result["review_status"] == "rejected"
    assert db.table.return_value.update.call_args[0][0]["status"] == "cancelled"


# ── the resident can read the decision ───────────────────────────────────────

def _row(**extra):
    return {
        "id": INCIDENT_ID, "reporter_id": REPORTER_ID, "report_text": "Fire", "status": "cancelled",
        "created_at": "2026-09-21T01:00:00+00:00", "updated_at": "2026-09-21T01:05:00+00:00",
        **extra,
    }


def test_response_carries_the_rejection_and_its_reason():
    r = incident_service._row_to_response(_row(
        review_status="rejected", rejection_reason="Duplicate report",
        reviewed_at="2026-09-21T01:05:00+00:00",
    ))
    assert r.review_status == "rejected"
    assert r.rejection_reason == "Duplicate report"
    # A rejection is NOT a withdrawal: the app tells them apart by this.
    assert r.withdrawn_at is None


def test_response_carries_the_clarification_request():
    r = incident_service._row_to_response(_row(
        status="received", review_status="clarification_requested",
        clarification_note="Which house?", clarification_requested_at="2026-09-21T01:06:00+00:00",
    ))
    assert r.review_status == "clarification_requested"
    assert r.clarification_note == "Which house?"


def test_my_incidents_selects_the_review_columns():
    db = MagicMock()
    chain = db.table.return_value.select.return_value.eq.return_value.order.return_value.execute
    chain.return_value.data = []
    with patch("app.services.incident_service.get_supabase", return_value=db):
        incident_service.get_my_incidents(REPORTER_ID)
    selected = db.table.return_value.select.call_args[0][0]
    for column in ("review_status", "rejection_reason", "clarification_note", "clarification_requested_at"):
        assert column in selected


# ── the resident's reply reaches the agency ──────────────────────────────────

def _notes_db(review_status):
    db = MagicMock()
    inc = MagicMock()
    inc.data = {
        "id": INCIDENT_ID, "reporter_id": REPORTER_ID, "assigned_agency_id": AGENCY_ID,
        "assigned_responder_id": None, "review_status": review_status,
    }
    db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = inc
    ins = MagicMock()
    ins.data = [{"id": "n1", "body": "The blue house"}]
    db.table.return_value.insert.return_value.execute.return_value = ins
    return db


def test_answering_a_clarification_puts_the_report_back_in_review_and_tells_the_agency():
    db = _notes_db("clarification_requested")
    with patch("app.services.incident_notes_service.get_supabase", return_value=db), \
         patch("app.services.incident_notes_service.notification_service.create_for_agency_role") as notify:
        incident_notes_service.add_note(INCIDENT_ID, RESIDENT, "The blue house")

    db.table.return_value.update.assert_called_once_with({"review_status": "pending"})
    notify.assert_called_once()
    assert notify.call_args.args[:2] == (AGENCY_ID, "agency_admin")
    assert notify.call_args.kwargs["type_"] == "incident.clarification_answered"
    assert notify.call_args.kwargs["link"] == f"/incidents/{INCIDENT_ID}"


def test_an_ordinary_note_leaves_the_review_state_alone():
    db = _notes_db("pending")
    with patch("app.services.incident_notes_service.get_supabase", return_value=db), \
         patch("app.services.incident_notes_service.notification_service.create_for_agency_role") as notify:
        incident_notes_service.add_note(INCIDENT_ID, RESIDENT, "One more detail")

    db.table.return_value.update.assert_not_called()
    assert notify.call_args.kwargs["type_"] == "incident.note_added"
    assert notify.call_args.kwargs["is_important"] is False


def test_an_agency_note_does_not_trigger_the_resident_side_effects():
    db = _notes_db("clarification_requested")
    with patch("app.services.incident_notes_service.get_supabase", return_value=db), \
         patch("app.services.incident_notes_service.notification_service.create_for_agency_role") as notify, \
         patch("app.services.incident_notes_service.assert_agency_scope"):
        incident_notes_service.add_note(INCIDENT_ID, DISPATCHER, "Following up")

    db.table.return_value.update.assert_not_called()
    notify.assert_not_called()
