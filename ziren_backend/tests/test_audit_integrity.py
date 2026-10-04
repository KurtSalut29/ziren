"""Evaluator finding #6: an action and its audit record succeed or fail together.

audit_service.action() writes the audit row FIRST ('pending'), refuses the
action (503) when it cannot, and afterwards marks the row 'succeeded' or
'failed'. These pin each branch, including the database that predates
migration 044 (no outcome column).

Run with: pytest tests/test_audit_integrity.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import audit_service

ACTOR = {"id": "u1", "role": "agency_admin", "full_name": "Admin"}


def _db(insert_side_effect=None, insert_data=None):
    db = MagicMock()
    table = db.table.return_value
    if insert_side_effect is not None:
        table.insert.return_value.execute.side_effect = insert_side_effect
    else:
        table.insert.return_value.execute.return_value = MagicMock(
            data=insert_data if insert_data is not None else [{"id": "a1"}]
        )
    return db


def _run(db, body=lambda e: None):
    with patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.audit_service.notification_service"):
        with audit_service.action(actor=ACTOR, action="station.deactivated",
                                  target_type="station", target_id="s1") as entry:
            body(entry)


def test_the_row_is_written_pending_before_the_action():
    db = _db()
    order = []
    db.table.return_value.insert.side_effect = lambda payload: (order.append(("insert", payload)),
                                                                 MagicMock(execute=lambda: MagicMock(data=[{"id": "a1"}])))[1]
    _run(db, lambda e: order.append(("action", None)))
    assert order[0][0] == "insert" and order[0][1]["outcome"] == "pending"
    assert order[1][0] == "action"


def test_no_record_means_no_action():
    db = _db(insert_side_effect=RuntimeError("connection reset"))
    ran = []
    with pytest.raises(HTTPException) as exc:
        _run(db, lambda e: ran.append(1))
    assert exc.value.status_code == 503
    assert ran == [], "the action must not run when its record could not be written"


def test_an_insert_that_returns_nothing_is_not_a_record():
    db = _db(insert_data=[])
    ran = []
    with pytest.raises(HTTPException):
        _run(db, lambda e: ran.append(1))
    assert ran == []


def test_success_marks_the_row_succeeded_with_what_the_block_filled_in():
    db = _db()

    def body(e):
        e.new = {"is_active": False}

    _run(db, body)
    update = db.table.return_value.update.call_args.args[0]
    assert update["outcome"] == "succeeded" and update["completed_at"]
    assert update["new_value"] == {"is_active": False}
    db.table.return_value.update.return_value.eq.assert_called_with("id", "a1")


def test_a_failed_action_is_recorded_as_failed_and_still_raises():
    db = _db()

    def body(e):
        raise HTTPException(status_code=500, detail="Failed to deactivate station.")

    with pytest.raises(HTTPException):
        _run(db, body)
    update = db.table.return_value.update.call_args.args[0]
    assert update["outcome"] == "failed"
    assert update["error"] == "Failed to deactivate station."


def test_before_migration_044_the_row_is_still_written_first_without_an_outcome():
    missing = Exception("{'code': 'PGRST204', 'message': \"Could not find the 'outcome' column\"}")
    calls = []

    def insert(payload):
        calls.append(dict(payload))
        b = MagicMock()
        if "outcome" in payload:
            b.execute.side_effect = missing
        else:
            b.execute.return_value = MagicMock(data=[{"id": "a1"}])
        return b

    db = MagicMock()
    db.table.return_value.insert.side_effect = insert
    ran = []
    _run(db, lambda e: ran.append(1))
    assert ran == [1]
    assert "outcome" in calls[0] and "outcome" not in calls[1]
    assert not db.table.return_value.update.called, "nothing to complete without the column"


def test_a_completion_that_cannot_be_written_does_not_undo_the_action():
    """The row stays 'pending' — still naming who attempted what."""
    db = _db()
    db.table.return_value.update.return_value.eq.return_value.execute.side_effect = RuntimeError("blip")
    ran = []
    _run(db, lambda e: ran.append(1))
    assert ran == [1]
