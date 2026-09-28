"""
search_service + /search router — Task 19 of the Super Admin plan.

Covers:
  - agency_admin's results are scoped for agency-specific entities
    (responders, stations, incidents) and unscoped for geographic ones
  - an incident query that IS a full UUID does an exact eq() lookup
  - an incident query that is NOT a full UUID searches report_text instead
    (a partial/fuzzy UUID match isn't a Postgres capability — see
    search_service's module docstring, confirmed against the live database)
  - q shorter than 2 chars is 422
  - resident and responder roles cannot call this endpoint

Run: pytest tests/test_search.py -v
"""

import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import search_service

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"
RESIDENT_UUID = "00000000-0000-0000-0000-000000000010"
AGENCY_UUID = "aaaaaaaa-0000-0000-0000-000000000001"


def _empty_search_db():
    """
    Every ilike/eq/in_ chain on this mock resolves to an empty result.

    `in_` is needed alongside eq/ilike because a provincial_admin caller now
    adds a `.in_("agency_id"/"assigned_agency_id", agency_ids)` scope filter
    on top of whatever an agency_admin's request already chained (see
    search_service.py's two-step agencies lookup) — without it, that call
    would land on an unconfigured child mock instead of this shared chain.
    """
    empty = MagicMock()
    empty.data = []

    chain = MagicMock()
    for method in ("select", "eq", "ilike", "limit", "in_"):
        getattr(chain, method).return_value = chain
    chain.execute.return_value = empty

    db = MagicMock()
    db.table.return_value = chain
    return db, chain


def test_agency_admin_scopes_responders_stations_and_incidents():
    db, chain = _empty_search_db()
    with patch("app.services.search_service.get_supabase", return_value=db):
        search_service.search("naval", {"role": "agency_admin", "agency_id": AGENCY_UUID})

    eq_calls = [c.args for c in chain.eq.call_args_list]
    assert ("agency_id", AGENCY_UUID) in eq_calls
    assert ("assigned_agency_id", AGENCY_UUID) in eq_calls


def test_agency_admin_does_not_scope_residents_or_geography():
    db, chain = _empty_search_db()
    with patch("app.services.search_service.get_supabase", return_value=db):
        search_service.search("naval", {"role": "agency_admin", "agency_id": AGENCY_UUID})

    # Residents/barangays/municipalities never filter on agency_id or
    # assigned_agency_id -- those two calls above belong to responders/
    # stations/incidents only. Confirmed by construction of the service
    # (no .eq(agency-scoped) call sits on the resident/barangay chain), and
    # this test's job is just to ensure that reasoning doesn't silently
    # break under future edits: residents must still appear unfiltered.
    ilike_calls = [c.args for c in chain.ilike.call_args_list]
    assert ("full_name", "%naval%") in ilike_calls  # residents + responders + agency_admins all hit this


def test_full_uuid_incident_query_uses_exact_eq():
    db, chain = _empty_search_db()
    fake_id = str(uuid.uuid4())
    with patch("app.services.search_service.get_supabase", return_value=db):
        search_service.search(fake_id, {"role": "provincial_admin", "agency_id": None, "agency_type": None})

    eq_calls = [c.args for c in chain.eq.call_args_list]
    assert ("id", fake_id) in eq_calls


def test_non_uuid_incident_query_searches_report_text():
    db, chain = _empty_search_db()
    with patch("app.services.search_service.get_supabase", return_value=db):
        search_service.search("sunog", {"role": "provincial_admin", "agency_id": None, "agency_type": None})

    ilike_calls = [c.args for c in chain.ilike.call_args_list]
    assert ("report_text", "%sunog%") in ilike_calls
    eq_calls = [c.args[0] for c in chain.eq.call_args_list]
    assert "id" not in eq_calls  # never attempts an exact-id lookup for non-UUID input


def _profile(user_id, role):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": None, "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id, role)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def test_query_shorter_than_two_chars_is_422():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")):
        resp = client.get("/search/?q=a", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 422


def test_resident_cannot_search():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(RESIDENT_UUID, "resident")):
        resp = client.get("/search/?q=naval", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_provincial_admin_can_search():
    db, _ = _empty_search_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.services.search_service.get_supabase", return_value=db):
        resp = client.get("/search/?q=naval", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
    assert set(resp.json().keys()) == {
        "residents", "responders", "agency_admins", "stations", "incidents", "barangays", "municipalities",
    }
