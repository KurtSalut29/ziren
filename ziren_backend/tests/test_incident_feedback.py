"""
feedback_service — Resident spec Section 26, post-resolution rating.
See migration 032 for the schema and RLS this mirrors at the service layer.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import feedback_service

INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"
REPORTER_ID = "g0000007-0000-0000-0000-000000000007"
OTHER_ID = "h0000008-0000-0000-0000-000000000008"


def _incident_result(status="resolved", reporter_id=REPORTER_ID, data=True):
    result = MagicMock()
    result.data = {"id": INCIDENT_ID, "reporter_id": reporter_id, "status": status} if data else None
    return result


def _db(incident_result, existing_feedback=None, insert_payload_out=None):
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = incident_result

    feedback_result = MagicMock()
    feedback_result.data = existing_feedback
    db.table.return_value.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = feedback_result

    insert_result = MagicMock()
    insert_result.data = [insert_payload_out] if insert_payload_out else None
    db.table.return_value.insert.return_value.execute.return_value = insert_result
    return db


def test_get_my_feedback_returns_none_when_not_yet_rated():
    db = MagicMock()
    result = MagicMock()
    result.data = None
    db.table.return_value.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        assert feedback_service.get_my_feedback(INCIDENT_ID, REPORTER_ID) is None


def test_submit_feedback_success():
    db = _db(_incident_result())
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        result = feedback_service.submit_feedback(INCIDENT_ID, REPORTER_ID, rating=5, comment="Mabilis!")
    insert_payload = db.table.return_value.insert.call_args[0][0]
    assert insert_payload["reporter_id"] == REPORTER_ID
    assert insert_payload["rating"] == 5
    assert insert_payload["comment"] == "Mabilis!"
    assert result["rating"] == 5


def test_submit_feedback_rejects_missing_incident():
    db = _db(_incident_result(data=False))
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            feedback_service.submit_feedback(INCIDENT_ID, REPORTER_ID, rating=4, comment=None)
    assert exc.value.status_code == 404


def test_submit_feedback_rejects_someone_elses_incident():
    db = _db(_incident_result(reporter_id=OTHER_ID))
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            feedback_service.submit_feedback(INCIDENT_ID, REPORTER_ID, rating=4, comment=None)
    assert exc.value.status_code == 403


def test_submit_feedback_rejects_unresolved_incident():
    db = _db(_incident_result(status="dispatched"))
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            feedback_service.submit_feedback(INCIDENT_ID, REPORTER_ID, rating=4, comment=None)
    assert exc.value.status_code == 409


def test_submit_feedback_rejects_duplicate():
    db = _db(_incident_result(), existing_feedback={"id": "x", "rating": 3})
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            feedback_service.submit_feedback(INCIDENT_ID, REPORTER_ID, rating=4, comment=None)
    assert exc.value.status_code == 409


def test_submit_feedback_blanks_out_whitespace_only_comment():
    db = _db(_incident_result())
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        feedback_service.submit_feedback(INCIDENT_ID, REPORTER_ID, rating=5, comment="   ")
    insert_payload = db.table.return_value.insert.call_args[0][0]
    assert insert_payload["comment"] is None
