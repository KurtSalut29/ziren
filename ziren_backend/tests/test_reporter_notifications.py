"""The resident is told, specifically, about each thing that happens to their report.

Before this, the resident's phone heard about a report only when its status
moved, in whatever generic words that status had: a report the AGENCY cancelled
read exactly like one the resident trashed themselves, "en_route" was shown as
"en_route", an accepted report said nothing at all, and a message from the agency
was never announced. Each of these is now a stored notification of its own type,
so the phone can say what actually happened - and, for a cancellation, why.

Properties worth pinning:

  1. Each action writes ONE notification of its own type to the REPORTER (never to
     the actor), with the incident id and the moment of the action, which is what
     the phone keys on to tell the live copy and the stored copy apart.
  2. The moment carried is the one the incident row itself carries (`dispatched_at`,
     `resolved_at`), so the two copies are recognised as one event.
  3. A failed notification never undoes the action it reports.
  4. A resident's own reply notifies the agency (existing), not themselves; only an
     agency admin or the assigned crew notify the resident.

Run with: pytest tests/test_reporter_notifications.py -v
"""

from unittest.mock import MagicMock, patch

import pytest

from app.services import dispatch_service, incident_notes_service, responder_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"
REPORTER_ID = "a0000007-0000-0000-0000-000000000007"
RESPONDER_ID = "e0000005-0000-0000-0000-000000000005"
DISPATCHER = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}


def _tables(incident: dict, extra: dict | None = None):
    """A Supabase double with one mock per table, so a responder lookup and an
    incident lookup can answer differently."""
    tables: dict[str, MagicMock] = {}

    def make(name):
        t = MagicMock()
        row = (extra or {}).get(name, incident)
        chain = t.select.return_value.eq.return_value
        chain.single.return_value.execute.return_value = MagicMock(data=row)
        chain.maybe_single.return_value.execute.return_value = MagicMock(data=row)
        t.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[row])
        t.insert.return_value.execute.return_value = MagicMock(data=[{"id": "n1", "created_at": "2026-09-25T00:00:00+00:00"}])
        return t

    db = MagicMock()
    db.table.side_effect = lambda name: tables.setdefault(name, make(name))
    return db


def _incident(**kw):
    base = {
        "id": INCIDENT_ID, "status": "received", "review_status": "pending", "severity": "high",
        "assigned_agency_id": AGENCY_ID, "assigned_responder_id": None, "reporter_id": REPORTER_ID,
    }
    base.update(kw)
    return base


def _sent(notify):
    """(recipient, kwargs) of the one notification written."""
    notify.assert_called_once()
    return notify.call_args.args[0], notify.call_args.kwargs


# ── the agency acts ─────────────────────────────────────────────────────────

def test_accepting_a_report_tells_the_resident_it_was_accepted():
    with patch("app.services.dispatch_service.get_supabase", return_value=_tables(_incident())), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        dispatch_service.accept_report(INCIDENT_ID, DISPATCHER)

    to, kw = _sent(notify)
    assert to == REPORTER_ID
    assert kw["type_"] == "incident.accepted"
    assert "accepted" in kw["title"].lower()
    assert kw["metadata"]["incident_id"] == INCIDENT_ID and kw["metadata"]["at"]


def test_dispatching_tells_the_resident_help_is_on_the_way_at_the_dispatch_time():
    responder = {
        "id": RESPONDER_ID, "full_name": "Juan", "agency_id": AGENCY_ID,
        "approval_status": "approved", "availability": "on_duty", "role": "responder",
    }
    db = _tables(_incident(), {"users": responder})
    with patch("app.services.dispatch_service.get_supabase", return_value=db), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        result = dispatch_service.assign_responder(
            INCIDENT_ID, RESPONDER_ID, "high", "high", None, None, DISPATCHER,
        )

    to, kw = _sent(notify)
    assert to == REPORTER_ID
    assert kw["type_"] == "incident.dispatched"
    assert "on the way" in kw["title"].lower()
    # The row's own `dispatched_at`: this is what ties the stored copy to the live one.
    assert kw["metadata"]["at"] == result["dispatched_at"]


def test_resolving_tells_the_resident_it_is_resolved():
    with patch("app.services.dispatch_service.get_supabase", return_value=_tables(_incident(status="arrived"))), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        result = dispatch_service.resolve_incident(INCIDENT_ID, None, DISPATCHER)

    to, kw = _sent(notify)
    assert to == REPORTER_ID
    assert kw["type_"] == "incident.resolved"
    assert kw["metadata"]["at"] == result["resolved_at"]


def test_cancelling_tells_the_resident_why_and_marks_it_important():
    with patch("app.services.dispatch_service.get_supabase", return_value=_tables(_incident(status="dispatched"))), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        dispatch_service.cancel_incident(INCIDENT_ID, "  Duplicate of another report  ", DISPATCHER)

    to, kw = _sent(notify)
    assert to == REPORTER_ID
    assert kw["type_"] == "incident.cancelled"
    assert "cancelled" in kw["title"].lower()
    assert kw["body"] == "Reason: Duplicate of another report"
    assert kw["is_important"] is True


def test_the_cancellation_reason_also_stays_in_the_reports_thread():
    db = _tables(_incident(status="dispatched"))
    with patch("app.services.dispatch_service.get_supabase", return_value=db),          patch("app.services.dispatch_service.notification_service.create_for_user"):
        dispatch_service.cancel_incident(INCIDENT_ID, "Duplicate of another report", DISPATCHER)

    posted = [c.args[0] for c in db.table("incident_notes").insert.call_args_list]
    assert posted and posted[-1]["incident_id"] == INCIDENT_ID
    assert posted[-1]["body"] == "This report was cancelled. Reason: Duplicate of another report"
    assert posted[-1]["author_role"] == "agency_admin"


def test_a_failed_notification_does_not_undo_a_cancellation():
    with patch("app.services.dispatch_service.get_supabase", return_value=_tables(_incident(status="dispatched"))), \
         patch("app.services.dispatch_service.notification_service.create_for_user", side_effect=RuntimeError("down")):
        result = dispatch_service.cancel_incident(INCIDENT_ID, "Duplicate", DISPATCHER)
    assert result == {"incident_id": INCIDENT_ID, "status": "cancelled"}


def test_an_incident_with_no_known_reporter_notifies_nobody():
    with patch("app.services.dispatch_service.get_supabase", return_value=_tables(_incident(reporter_id=None))), \
         patch("app.services.dispatch_service.notification_service.create_for_user") as notify:
        dispatch_service.accept_report(INCIDENT_ID, DISPATCHER)
    notify.assert_not_called()


# ── the crew acts ───────────────────────────────────────────────────────────

@pytest.mark.parametrize("current,new_status,title_fragment", [
    ("dispatched", "en_route", "on the way"),
    ("en_route", "arrived", "arrived"),
    ("arrived", "resolved", "resolved"),
])
def test_the_crews_progress_reaches_the_resident_in_its_own_words(current, new_status, title_fragment):
    incident = _incident(status=current, assigned_responder_id=RESPONDER_ID)
    with patch("app.services.responder_service.get_supabase", return_value=_tables(incident)), \
         patch("app.services.responder_service.notification_service.notify_reporter") as tell, \
         patch("app.services.responder_service.notification_service.create_for_agency_role"):
        responder_service.update_incident_status(INCIDENT_ID, RESPONDER_ID, new_status)

    tell.assert_called_once()
    assert tell.call_args.args[0] == REPORTER_ID
    kw = tell.call_args.kwargs
    assert kw["type_"] == f"incident.{new_status}"
    assert title_fragment in kw["title"].lower()
    assert kw["incident_id"] == INCIDENT_ID and kw["at"]


def test_the_stored_notification_is_keyed_for_the_phone():
    """notify_reporter is what writes the row; check the row's shape."""
    from app.services import notification_service

    with patch.object(notification_service, "create_for_user") as create:
        notification_service.notify_reporter(
            REPORTER_ID, incident_id=INCIDENT_ID, type_="incident.arrived",
            title="The responder has arrived", body="x" * 500, at="2026-09-25T01:02:03+00:00",
            extra={"note_id": "n9"},
        )
    kw = create.call_args.kwargs
    assert create.call_args.args[0] == REPORTER_ID
    assert kw["metadata"] == {"incident_id": INCIDENT_ID, "at": "2026-09-25T01:02:03+00:00", "note_id": "n9"}
    assert len(kw["body"]) == 240
    assert kw["link"] == "/my-reports"


def test_notify_reporter_never_raises():
    from app.services import notification_service

    with patch.object(notification_service, "create_for_user", side_effect=RuntimeError("db down")):
        notification_service.notify_reporter(
            REPORTER_ID, incident_id=INCIDENT_ID, type_="incident.arrived", title="t", body=None, at="now",
        )
        notification_service.notify_reporter(
            None, incident_id=INCIDENT_ID, type_="incident.arrived", title="t", body=None, at="now",
        )


# ── messages ────────────────────────────────────────────────────────────────

def _notes_db(incident: dict):
    db = _tables(incident)
    return db


def test_a_message_from_the_agency_reaches_the_resident():
    incident = _incident(status="dispatched")
    with patch("app.services.incident_notes_service.get_supabase", return_value=_notes_db(incident)), \
         patch("app.services.incident_notes_service.assert_agency_scope"), \
         patch("app.services.incident_notes_service.notification_service.notify_reporter") as tell:
        incident_notes_service.add_note(INCIDENT_ID, DISPATCHER, "  Please stay on the line.  ")

    tell.assert_called_once()
    assert tell.call_args.args[0] == REPORTER_ID
    kw = tell.call_args.kwargs
    assert kw["type_"] == "incident.message"
    assert kw["title"] == "New message from the agency"
    assert kw["body"] == "Please stay on the line."
    assert kw["extra"] == {"note_id": "n1"}


def test_a_message_from_the_crew_says_it_is_from_the_responder():
    incident = _incident(status="dispatched", assigned_responder_id=RESPONDER_ID)
    responder = {"id": RESPONDER_ID, "role": "responder", "agency_id": AGENCY_ID}
    with patch("app.services.incident_notes_service.get_supabase", return_value=_notes_db(incident)), \
         patch("app.services.incident_notes_service.notification_service.notify_reporter") as tell:
        incident_notes_service.add_note(INCIDENT_ID, responder, "Two minutes away.")
    assert tell.call_args.kwargs["title"] == "New message from the responder"


def test_a_residents_own_reply_does_not_notify_the_resident():
    incident = _incident(status="dispatched", review_status="pending")
    resident = {"id": REPORTER_ID, "role": "resident", "agency_id": None}
    with patch("app.services.incident_notes_service.get_supabase", return_value=_notes_db(incident)), \
         patch("app.services.incident_notes_service.notification_service.notify_reporter") as tell, \
         patch("app.services.incident_notes_service.notification_service.create_for_agency_role"):
        incident_notes_service.add_note(INCIDENT_ID, resident, "Salamat po")
    tell.assert_not_called()
