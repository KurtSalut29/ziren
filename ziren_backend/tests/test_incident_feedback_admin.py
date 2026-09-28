"""
feedback_service.get_feedback_for_admin — a dispatcher's read of the
resident's own post-resolution rating (Resident spec Section 26).

Before this, GET .../feedback existed only for the reporter themselves
(app/routers/incidents.py get_own_feedback); an admin had no way to see a
rating had been given at all. Same scope rule as get_incident_media: an
agency_admin sees only incidents assigned to their own agency, a
provincial_admin sees any incident assigned to their own agency_type
(migration 034 rescoped the old cross-agency super_admin this way).

Run: pytest tests/test_incident_feedback_admin.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import feedback_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
OTHER_AGENCY_ID = "b0000002-0000-0000-0000-000000000002"
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"

AGENCY_ADMIN = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}
PROVINCIAL_ADMIN_AGENCY_TYPE = "BFP"
PROVINCIAL_ADMIN = {
    "id": "f0000006-0000-0000-0000-000000000006", "role": "provincial_admin",
    "agency_id": None, "agency_type": PROVINCIAL_ADMIN_AGENCY_TYPE,
}

FEEDBACK_ROW = {
    "id": "h0000008-0000-0000-0000-000000000008",
    "incident_id": INCIDENT_ID,
    "rating": 4,
    "comment": "Mabilis ang pagtugon.",
    "created_at": "2026-01-01T00:00:00+00:00",
}


def _db(incident_row, feedback_row=None):
    db = MagicMock()
    inc_result = MagicMock()
    inc_result.data = incident_row
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = inc_result

    fb_result = MagicMock()
    fb_result.data = feedback_row
    db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = fb_result
    return db


def _scope_db(agency_type):
    """
    assert_agency_scope's provincial_admin branch resolves the target
    agency_id's own agency_type via get_supabase() imported INTO
    app.core.dependencies -- a different seam from
    app.services.feedback_service.get_supabase, and one that has to be
    patched even for a direct get_feedback_for_admin() call, since
    assert_agency_scope is called from inside it.
    """
    db = MagicMock()
    lookup = MagicMock()
    lookup.data = [{"agency_type": agency_type}]
    db.table.return_value.select.return_value.eq.return_value.limit.return_value.execute.return_value = lookup
    return db


def test_agency_admin_sees_feedback_for_own_agency_incident():
    db = _db({"id": INCIDENT_ID, "assigned_agency_id": AGENCY_ID}, feedback_row=FEEDBACK_ROW)
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        result = feedback_service.get_feedback_for_admin(INCIDENT_ID, AGENCY_ADMIN)
    assert result == FEEDBACK_ROW


def test_agency_admin_forbidden_from_other_agency_incident():
    db = _db({"id": INCIDENT_ID, "assigned_agency_id": OTHER_AGENCY_ID})
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            feedback_service.get_feedback_for_admin(INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 403


def test_provincial_admin_sees_feedback_for_their_own_agency_type():
    db = _db({"id": INCIDENT_ID, "assigned_agency_id": OTHER_AGENCY_ID}, feedback_row=FEEDBACK_ROW)
    with patch("app.services.feedback_service.get_supabase", return_value=db), \
         patch("app.core.dependencies.get_supabase", return_value=_scope_db(PROVINCIAL_ADMIN_AGENCY_TYPE)):
        result = feedback_service.get_feedback_for_admin(INCIDENT_ID, PROVINCIAL_ADMIN)
    assert result == FEEDBACK_ROW


def test_provincial_admin_forbidden_from_a_different_agency_type():
    """
    Migration 034's rescoping: unlike the old cross-agency super_admin, a
    Provincial Admin only sees feedback for incidents of their own
    agency_type.
    """
    db = _db({"id": INCIDENT_ID, "assigned_agency_id": OTHER_AGENCY_ID}, feedback_row=FEEDBACK_ROW)
    with patch("app.services.feedback_service.get_supabase", return_value=db), \
         patch("app.core.dependencies.get_supabase", return_value=_scope_db("PNP")):
        with pytest.raises(HTTPException) as exc:
            feedback_service.get_feedback_for_admin(INCIDENT_ID, PROVINCIAL_ADMIN)
    assert exc.value.status_code == 403


def test_returns_none_not_404_when_not_yet_rated():
    """Most incidents will never get a rating — that is not an error state."""
    db = _db({"id": INCIDENT_ID, "assigned_agency_id": AGENCY_ID}, feedback_row=None)
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        result = feedback_service.get_feedback_for_admin(INCIDENT_ID, AGENCY_ADMIN)
    assert result is None


def test_incident_not_found():
    db = _db(None)
    with patch("app.services.feedback_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            feedback_service.get_feedback_for_admin(INCIDENT_ID, PROVINCIAL_ADMIN)
    assert exc.value.status_code == 404
