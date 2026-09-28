"""
incident_notes_service + the /dispatch and /responder note endpoints —
Agency Admin spec Section 5 (operational notes) and Section 18 (Agency
Communication). One append-only, incident-scoped thread serves both roles,
each seeing only what migration 030's RLS policies would also allow.

The resident-scoped cases below cover migration 031's addition: the
reporter's own use of the same thread for Resident spec Sections 14
("Add Information to an Existing Report") and 16 ("Incident-Specific
Communication"), exposed at /incidents/{id}/notes.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import app
from app.services import incident_notes_service

client = TestClient(app)

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
OTHER_AGENCY_ID = "b0000002-0000-0000-0000-000000000002"
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"
RESPONDER_ID = "e0000005-0000-0000-0000-000000000005"

AGENCY_ADMIN = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}
RESPONDER = {"id": RESPONDER_ID, "role": "responder", "agency_id": AGENCY_ID}
PROVINCIAL_ADMIN_AGENCY_TYPE = "BFP"
PROVINCIAL_ADMIN = {
    "id": "f0000006-0000-0000-0000-000000000006", "role": "provincial_admin",
    "agency_id": None, "agency_type": PROVINCIAL_ADMIN_AGENCY_TYPE,
}
REPORTER_ID = "g0000007-0000-0000-0000-000000000007"
RESIDENT = {"id": REPORTER_ID, "role": "resident", "agency_id": None}


def _scope_db(agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE):
    """
    assert_agency_scope's provincial_admin branch resolves the target
    agency_id's own agency_type via get_supabase() imported INTO
    app.core.dependencies — a different seam from
    app.services.incident_notes_service.get_supabase, and one that has to be
    patched even for a direct service-level call like list_notes(), since
    assert_agency_scope is called from inside it.
    """
    db = MagicMock()
    lookup = MagicMock()
    lookup.data = [{"agency_type": agency_type}]
    db.table.return_value.select.return_value.eq.return_value.limit.return_value.execute.return_value = lookup
    return db


def _incident(assigned_agency_id=AGENCY_ID, assigned_responder_id=RESPONDER_ID, reporter_id=REPORTER_ID):
    return {
        "id": INCIDENT_ID,
        "reporter_id": reporter_id,
        "assigned_agency_id": assigned_agency_id,
        "assigned_responder_id": assigned_responder_id,
    }


def _db(incident_row, notes_rows=None):
    db = MagicMock()
    inc_result = MagicMock()
    inc_result.data = incident_row
    db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = inc_result

    if notes_rows is not None:
        notes_result = MagicMock()
        notes_result.data = notes_rows
        db.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value = notes_result

    insert_result = MagicMock()
    insert_result.data = None
    db.table.return_value.insert.return_value.execute.return_value = insert_result
    return db


# ── Service-level scoping ──────────────────────────────────────────────────

def test_agency_admin_can_list_own_agency_incident_notes():
    db = _db(_incident(), notes_rows=[])
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        result = incident_notes_service.list_notes(INCIDENT_ID, AGENCY_ADMIN)
    assert result == []


def test_agency_admin_forbidden_from_other_agency_incident():
    db = _db(_incident(assigned_agency_id=OTHER_AGENCY_ID))
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            incident_notes_service.list_notes(INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 403


def test_responder_can_list_own_assignment_notes():
    db = _db(_incident(), notes_rows=[])
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        result = incident_notes_service.list_notes(INCIDENT_ID, RESPONDER)
    assert result == []


def test_responder_forbidden_from_incident_not_assigned_to_them():
    db = _db(_incident(assigned_responder_id="someone-else"))
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            incident_notes_service.list_notes(INCIDENT_ID, RESPONDER)
    assert exc.value.status_code == 403


def test_provincial_admin_can_list_notes_for_their_own_agency_type():
    db = _db(_incident(assigned_agency_id=OTHER_AGENCY_ID), notes_rows=[])
    with patch("app.services.incident_notes_service.get_supabase", return_value=db), \
         patch("app.core.dependencies.get_supabase", return_value=_scope_db()):
        result = incident_notes_service.list_notes(INCIDENT_ID, PROVINCIAL_ADMIN)
    assert result == []


def test_provincial_admin_forbidden_from_a_different_agency_type():
    """
    Migration 034's rescoping: unlike the old cross-agency super_admin, a
    Provincial Admin only sees incident notes for their own agency_type —
    OTHER_AGENCY_ID here belongs to a different type than the actor.
    """
    db = _db(_incident(assigned_agency_id=OTHER_AGENCY_ID))
    with patch("app.services.incident_notes_service.get_supabase", return_value=db), \
         patch("app.core.dependencies.get_supabase", return_value=_scope_db(agency_type="PNP")):
        with pytest.raises(HTTPException) as exc:
            incident_notes_service.list_notes(INCIDENT_ID, PROVINCIAL_ADMIN)
    assert exc.value.status_code == 403


def test_missing_incident_is_404():
    db = _db(None)
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            incident_notes_service.list_notes(INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 404


# ── add_note ─────────────────────────────────────────────────────────────

def test_add_note_rejects_empty_body():
    db = _db(_incident())
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            incident_notes_service.add_note(INCIDENT_ID, AGENCY_ADMIN, "   ")
    assert exc.value.status_code == 422


def test_add_note_stamps_author_and_role():
    db = _db(_incident())
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        incident_notes_service.add_note(INCIDENT_ID, AGENCY_ADMIN, "Proceed to the eastern entrance.")

    insert_payload = db.table.return_value.insert.call_args[0][0]
    assert insert_payload["author_id"] == AGENCY_ADMIN["id"]
    assert insert_payload["author_role"] == "agency_admin"
    assert insert_payload["body"] == "Proceed to the eastern entrance."


def test_responder_can_add_note_to_own_assignment():
    db = _db(_incident())
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        incident_notes_service.add_note(INCIDENT_ID, RESPONDER, "Arrived at location.")
    insert_payload = db.table.return_value.insert.call_args[0][0]
    assert insert_payload["author_role"] == "responder"


# ── Router: agency_admin writes, provincial_admin reads only ───────────────

def _profile(user_id, role, agency_id=None, agency_type=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": agency_id, "agency_type": agency_type,
        "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role, agency_id=None, agency_type=None):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id, role, agency_id, agency_type)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    # assert_agency_scope's own provincial_admin lookup -- see _scope_db above.
    lookup = MagicMock()
    lookup.data = [{"agency_type": agency_type}]
    db.table.return_value.select.return_value.eq.return_value.limit.return_value.execute.return_value = lookup
    return db


def test_router_provincial_admin_cannot_post_a_note():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN["id"], "provincial_admin", agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)):
        resp = client.post(
            f"/dispatch/queue/{INCIDENT_ID}/notes",
            json={"body": "hello"},
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 403


def test_router_agency_admin_can_post_a_note():
    db = _db(_incident())
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN["id"], "agency_admin", AGENCY_ID)), \
         patch("app.services.incident_notes_service.get_supabase", return_value=db):
        resp = client.post(
            f"/dispatch/queue/{INCIDENT_ID}/notes",
            json={"body": "Proceed to the eastern entrance."},
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 200, resp.text


def test_router_provincial_admin_can_read_notes():
    db = _db(_incident(), notes_rows=[])
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN["id"], "provincial_admin", agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)), \
         patch("app.services.incident_notes_service.get_supabase", return_value=db):
        resp = client.get(f"/dispatch/queue/{INCIDENT_ID}/notes", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text


# ── Resident side (migration 031, /incidents/{id}/notes) ───────────────────

def test_resident_can_list_own_incident_notes():
    db = _db(_incident(), notes_rows=[])
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        result = incident_notes_service.list_notes(INCIDENT_ID, RESIDENT)
    assert result == []


def test_resident_forbidden_from_someone_elses_incident():
    db = _db(_incident(reporter_id="someone-else"))
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            incident_notes_service.list_notes(INCIDENT_ID, RESIDENT)
    assert exc.value.status_code == 403


def test_resident_can_add_note_to_own_incident():
    db = _db(_incident())
    with patch("app.services.incident_notes_service.get_supabase", return_value=db):
        incident_notes_service.add_note(INCIDENT_ID, RESIDENT, "3 people still inside.")
    insert_payload = db.table.return_value.insert.call_args[0][0]
    assert insert_payload["author_id"] == REPORTER_ID
    assert insert_payload["author_role"] == "resident"
    assert insert_payload["body"] == "3 people still inside."


def test_router_resident_can_read_and_post_own_incident_notes():
    db = _db(_incident(), notes_rows=[])
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(REPORTER_ID, "resident")), \
         patch("app.services.incident_notes_service.get_supabase", return_value=db):
        get_resp = client.get(f"/incidents/{INCIDENT_ID}/notes", headers={"Authorization": "Bearer token"})
        post_resp = client.post(
            f"/incidents/{INCIDENT_ID}/notes",
            json={"body": "Naa pay tulo ka tawo sulod."},
            headers={"Authorization": "Bearer token"},
        )
    assert get_resp.status_code == 200, get_resp.text
    assert post_resp.status_code == 201, post_resp.text


def test_router_resident_cannot_read_someone_elses_incident_notes():
    db = _db(_incident(reporter_id="someone-else"))
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(REPORTER_ID, "resident")), \
         patch("app.services.incident_notes_service.get_supabase", return_value=db):
        resp = client.get(f"/incidents/{INCIDENT_ID}/notes", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403
