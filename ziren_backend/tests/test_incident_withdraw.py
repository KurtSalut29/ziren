"""A resident taking back their own report, and the three things that must not happen.

Withdrawal is the one destructive-looking action a resident can perform, so the
guards are the test. In order of how much they would cost if they broke:

  1. Somebody else's report must not be withdrawable. The 403 deliberately
     matches the message get_incident_by_id gives, so the endpoint cannot be
     used to discover which incident ids exist.
  2. A report that responders are already moving on must not vanish from the
     queue. The resident is told to call the station instead — the only correct
     answer once a truck is out.
  3. The row must survive. status goes to 'cancelled', which /dispatch/queue
     excludes, so the incident leaves the dispatcher's working queue without
     the record being destroyed.

Run with: pytest tests/test_incident_withdraw.py -v
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

RESIDENT_UUID = "00000000-0000-0000-0000-000000000001"
OTHER_UUID    = "00000000-0000-0000-0000-0000000000ff"
INCIDENT_UUID = str(uuid4())
AGENCY_UUID   = "aaaaaaaa-0000-0000-0000-000000000001"


def _auth_profile():
    return {
        "id": RESIDENT_UUID, "email": "resident@example.com",
        "full_name": "Test Resident", "role": "resident",
        "approval_status": "not_required", "agency_id": None,
        "badge_id": None, "is_verified": True,
    }


def _row(**overrides):
    # assigned_agency_id and station_id are populated AT SUBMISSION from the
    # reporter's location (see _create_incident_row) — a freshly filed report
    # already has both. The first version of this fixture defaulted them to
    # None, which no real row ever is, and the guard under test read
    # assigned_agency_id as "a dispatcher acted". Every test passed and every
    # real withdrawal was refused. The default here is now a real row.
    row = {
        "id": INCIDENT_UUID,
        "reporter_id": RESIDENT_UUID,
        "station_id": "bbbbbbbb-0000-0000-0000-000000000001",
        "assigned_agency_id": AGENCY_UUID,
        "assigned_responder_id": None,
        "report_text": "[FIRE] Sunog na bahay",
        "location_address": None,
        "status": "received",
        "severity": None,
        "suggested_agency_id": None,
        "signals": None,
        "signals_confidence": None,
        "submitted_via": "internet",
        "created_at": "2026-01-01T00:00:00+00:00",
        "updated_at": "2026-01-01T00:00:00+00:00",
        "dispatched_at": None,
        "resolved_at": None,
        "incident_category": "fire",
        "wizard_answers": {},
        "overlap_agencies": None,
        "landmark_note": None,
        "victim_relationship": None,
        "nlp_review_needed": False,
    }
    row.update(overrides)
    return row


def _mock_auth_resident():
    """The db the auth dependency sees: token -> user -> profile row."""
    mock_user = MagicMock(); mock_user.id = RESIDENT_UUID
    mock_get = MagicMock(); mock_get.user = mock_user
    profile = MagicMock(); profile.data = _auth_profile()

    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = profile
    return db


def _mock_db(incident_row):
    """The db the service sees: the incident lookup, then the update."""
    incident = MagicMock(); incident.data = incident_row
    db = MagicMock()
    db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = incident
    return db


def _withdraw(db, body=None):
    with patch("app.core.dependencies.get_supabase", return_value=_mock_auth_resident()), \
         patch("app.services.incident_service.get_supabase", return_value=db):
        return client.post(
            f"/incidents/{INCIDENT_UUID}/withdraw",
            json=body or {},
            headers={"Authorization": "Bearer token"},
        )


class TestOnlyTheReporter:
    def test_another_residents_report_is_refused(self):
        res = _withdraw(_mock_db(_row(reporter_id=OTHER_UUID)))
        assert res.status_code == 403

    def test_the_refusal_does_not_confirm_the_incident_exists(self):
        """Same wording as a plain fetch, so this is not an id oracle."""
        res = _withdraw(_mock_db(_row(reporter_id=OTHER_UUID)))
        assert "do not have access" in res.json()["detail"]
        assert INCIDENT_UUID not in res.json()["detail"]

    def test_requires_auth(self):
        res = client.post(f"/incidents/{INCIDENT_UUID}/withdraw", json={})
        assert res.status_code in (401, 403)


class TestNotOnceHelpIsMoving:
    """The guard that matters. A truck may already be out."""

    @pytest.mark.parametrize(
        "overrides",
        [
            {"status": "processing"},
            {"status": "dispatched"},
            {"status": "resolved"},
            {"dispatched_at": "2026-01-01T00:05:00+00:00"},
            {"assigned_responder_id": "cccccccc-0000-0000-0000-000000000001"},
        ],
    )
    def test_refused_with_a_usable_instruction(self, overrides):
        res = _withdraw(_mock_db(_row(**overrides)))
        assert res.status_code == 409
        # The resident must be told what to do instead, not just refused.
        assert "call the station" in res.json()["detail"].lower()

    def test_an_agency_alone_does_not_block_it(self):
        """The regression this file failed to catch the first time.

        assigned_agency_id is set at submission from geography, so treating it
        as a dispatch decision refuses every report the moment it is filed.
        """
        res = _withdraw(_mock_db(_row(assigned_agency_id=AGENCY_UUID)))
        assert res.status_code == 200, res.json()


class TestWithdrawal:
    def test_sets_cancelled_and_stamps_the_time(self):
        db = _mock_db(_row())
        res = _withdraw(db, {"reason": "false alarm, tulog lang siya"})
        assert res.status_code == 200

        update = db.table.return_value.update.call_args[0][0]
        assert update["status"] == "cancelled"
        assert update["withdrawn_at"]
        assert update["withdrawn_reason"] == "false alarm, tulog lang siya"

    def test_the_row_is_updated_never_deleted(self):
        """Soft withdrawal: an emergency report is an audit record."""
        db = _mock_db(_row())
        _withdraw(db)
        assert db.table.return_value.update.called
        assert not db.table.return_value.delete.called

    def test_a_reason_is_optional(self):
        db = _mock_db(_row())
        assert _withdraw(db).status_code == 200
        assert db.table.return_value.update.call_args[0][0]["withdrawn_reason"] is None

    def test_blank_reason_is_stored_as_null_not_empty_string(self):
        db = _mock_db(_row())
        _withdraw(db, {"reason": "   "})
        assert db.table.return_value.update.call_args[0][0]["withdrawn_reason"] is None

    def test_withdrawing_twice_is_not_an_error(self):
        """A double tap on a slow connection should not raise at the user."""
        db = _mock_db(_row(status="cancelled"))
        res = _withdraw(db)
        assert res.status_code == 200
        assert not db.table.return_value.update.called

    def test_missing_incident_is_404(self):
        db = _mock_db(None)
        assert _withdraw(db).status_code == 404
