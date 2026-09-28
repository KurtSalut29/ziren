"""
audit_service.record() — the shared write-path for the admin audit trail.

Covers:
  - a successful insert returns the inserted row
  - the row shape sent to Supabase matches the documented payload
  - an action in NOTIFY_ACTIONS fans out via notification_service
  - an action NOT in NOTIFY_ACTIONS does not notify anyone
  - a failed insert is swallowed, not raised (the operation being audited
    must not fail just because the audit write did)

Run: pytest tests/test_audit_service.py -v
"""

from unittest.mock import MagicMock, patch

from app.services import audit_service

ACTOR = {"id": "00000000-0000-0000-0000-0000000000aa", "role": "provincial_admin", "full_name": "Test Admin"}


def _db_with_insert_result(row: dict):
    db = MagicMock()
    result = MagicMock()
    result.data = [row]
    db.table.return_value.insert.return_value.execute.return_value = result
    return db


def test_record_inserts_the_documented_payload_shape():
    db = _db_with_insert_result({"id": "row-1"})
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_roles") as notify:
        audit_service.record(
            actor=ACTOR,
            action="station.created",
            target_type="station",
            target_id="station-1",
            target_label="BFP Naval",
            new={"name": "BFP Naval"},
        )

    payload = db.table.return_value.insert.call_args[0][0]
    assert payload["actor_id"] == ACTOR["id"]
    assert payload["actor_role"] == "provincial_admin"
    assert payload["actor_name"] == "Test Admin"
    assert payload["action"] == "station.created"
    assert payload["target_type"] == "station"
    assert payload["target_id"] == "station-1"
    assert payload["target_label"] == "BFP Naval"
    assert payload["new_value"] == {"name": "BFP Naval"}
    assert payload["previous_value"] is None


def test_record_returns_the_inserted_row():
    db = _db_with_insert_result({"id": "row-1", "action": "station.created"})
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_roles"):
        row = audit_service.record(actor=ACTOR, action="station.created", target_type="station")

    assert row == {"id": "row-1", "action": "station.created"}


def test_notify_actions_triggers_notification_fan_out():
    db = _db_with_insert_result({"id": "row-1"})
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_roles") as notify:
        audit_service.record(
            actor=ACTOR,
            action="station.created",
            target_type="station",
            target_label="BFP Naval",
        )

    assert notify.called
    kwargs = notify.call_args.kwargs
    assert kwargs["roles"] == ("provincial_admin",)
    assert "BFP Naval" in kwargs["title"]
    assert kwargs["exclude_user_id"] == ACTOR["id"]


def test_action_not_in_notify_actions_does_not_notify():
    db = _db_with_insert_result({"id": "row-1"})
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_roles") as notify:
        audit_service.record(actor=ACTOR, action="something.unmapped", target_type="thing")

    assert not notify.called


def test_failed_insert_is_swallowed_not_raised():
    db = MagicMock()
    db.table.return_value.insert.return_value.execute.side_effect = RuntimeError("db down")
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_roles") as notify:
        row = audit_service.record(actor=ACTOR, action="station.created", target_type="station")

    # Falls back to returning the payload it tried to write, and never notifies
    # on a write it could not confirm happened.
    assert row["action"] == "station.created"
    assert not notify.called


def test_failed_notify_does_not_raise_or_break_the_audit_write():
    db = _db_with_insert_result({"id": "row-1"})
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_roles", side_effect=RuntimeError("boom")):
        row = audit_service.record(actor=ACTOR, action="station.created", target_type="station")

    assert row == {"id": "row-1"}
