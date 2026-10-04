"""
PATCH /users/provincial/residents/{id}/status and
PATCH /users/provincial/responders/{id}/reassign — Task 9 of the Provincial
Admin plan (migration 034 renamed super_admin -> provincial_admin and
rescoped it to one agency_type across the province).

Covers:
  - resident status toggle sets is_verified and writes the right audit action
    (unscoped by agency_type -- residents carry no agency dimension at all,
    see migration 034's header)
  - rejects a non-resident target
  - responder reassignment sets agency_id after checking the new agency
    exists AND that both the FROM and TO agencies are of the caller's own
    agency_type (migration 034: "reassigning a PNP responder to a BFP
    station was never meaningful")
  - rejects a non-responder target
  - both are provincial_admin only

Run: pytest tests/test_account_status.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from tests.audit_helpers import patch_audit_action

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"
RESIDENT_UUID     = "00000000-0000-0000-0000-0000000000a1"
RESPONDER_UUID    = "00000000-0000-0000-0000-0000000000a2"
OLD_AGENCY_UUID   = "aaaaaaaa-0000-0000-0000-000000000001"
NEW_AGENCY_UUID   = "aaaaaaaa-0000-0000-0000-000000000002"

# Both the old and new agency are PNP in the reassignment tests -- the
# scope check now requires BOTH ends to match the caller's own agency_type.
AGENCY_TYPE = "PNP"


def _profile(user_id, role, agency_type=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": None, "agency_type": agency_type,
        "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role, agency_type=None):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id, role, agency_type)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    # assert_agency_scope's own lookup (used by the reassignment endpoint)
    # chains .select(...).eq("id", agency_id).limit(1).execute() -- a
    # DIFFERENT chain from the .single() one above, so it needs its own
    # configuration. Every agency this fixture is asked about is reported as
    # AGENCY_TYPE, which is what makes the "both ends match" scope check pass.
    scope_lookup = MagicMock()
    scope_lookup.data = [{"agency_type": AGENCY_TYPE}]
    db.table.return_value.select.return_value.eq.return_value.limit.return_value.execute.return_value = scope_lookup
    return db


@pytest.mark.parametrize("is_active,expected_action", [(False, "account.suspended"), (True, "account.reactivated")])
def test_resident_status_toggle(is_active, expected_action):
    db = MagicMock()
    check = MagicMock()
    check.data = {"id": RESIDENT_UUID, "role": "resident", "full_name": "Juan Dela Cruz"}
    updated = MagicMock()
    updated.data = [{"id": RESIDENT_UUID, "is_verified": is_active}]
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = updated

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", AGENCY_TYPE)), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(
            f"/users/provincial/residents/{RESIDENT_UUID}/status",
            json={"is_active": is_active},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    db.table.return_value.update.assert_called_with({"is_verified": is_active})
    assert audit_record.call_args.kwargs["action"] == expected_action
    # Type B: resident status has no agency dimension, so no Provincial
    # Admin should be excluded from the notification fan-out for it.
    assert audit_record.call_args.kwargs.get("agency_type") is None


def test_resident_status_rejects_non_resident_target():
    db = MagicMock()
    check = MagicMock()
    check.data = {"id": RESPONDER_UUID, "role": "responder", "full_name": "R"}
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", AGENCY_TYPE)), \
         patch("app.routers.users.get_supabase", return_value=db):
        resp = client.patch(
            f"/users/provincial/residents/{RESPONDER_UUID}/status",
            json={"is_active": False},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 422


def test_resident_status_forbidden_for_agency_admin():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin")):
        resp = client.patch(
            f"/users/provincial/residents/{RESIDENT_UUID}/status",
            json={"is_active": False},
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 403


def test_responder_reassignment_writes_audit_log():
    db = MagicMock()
    check = MagicMock()
    check.data = {"id": RESPONDER_UUID, "role": "responder", "full_name": "Ana Reyes", "agency_id": OLD_AGENCY_UUID}
    agency_check = MagicMock()
    agency_check.data = {"id": NEW_AGENCY_UUID, "agency_type": AGENCY_TYPE}
    updated = MagicMock()
    updated.data = [{"id": RESPONDER_UUID, "agency_id": NEW_AGENCY_UUID}]

    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.side_effect = [
        check, agency_check,
    ]
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = updated

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", AGENCY_TYPE)), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(
            f"/users/provincial/responders/{RESPONDER_UUID}/reassign",
            json={"agency_id": NEW_AGENCY_UUID},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "responder.reassigned"
    assert kwargs["new"] == {"agency_id": NEW_AGENCY_UUID}
    assert kwargs["previous"] == {"agency_id": OLD_AGENCY_UUID}
    assert kwargs["agency_type"] == AGENCY_TYPE


def test_responder_reassignment_rejects_cross_agency_type():
    """
    New behaviour under migration 034: a Provincial Admin may only reassign
    a Responder to a station of their OWN agency_type. Reassigning a PNP
    responder to a BFP station was never meaningful, and now it is refused
    rather than silently allowed the way the old cross-agency super_admin
    would have let it through.
    """
    db = MagicMock()
    check = MagicMock()
    check.data = {"id": RESPONDER_UUID, "role": "responder", "full_name": "Ana Reyes", "agency_id": OLD_AGENCY_UUID}
    agency_check = MagicMock()
    agency_check.data = {"id": NEW_AGENCY_UUID, "agency_type": "BFP"}  # different type than the caller's PNP

    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.side_effect = [
        check, agency_check,
    ]

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", AGENCY_TYPE)), \
         patch("app.routers.users.get_supabase", return_value=db):
        resp = client.patch(
            f"/users/provincial/responders/{RESPONDER_UUID}/reassign",
            json={"agency_id": NEW_AGENCY_UUID},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 403


def test_responder_reassignment_rejects_unknown_agency():
    db = MagicMock()
    check = MagicMock()
    check.data = {"id": RESPONDER_UUID, "role": "responder", "full_name": "Ana Reyes", "agency_id": OLD_AGENCY_UUID}
    agency_check = MagicMock()
    agency_check.data = None
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.side_effect = [
        check, agency_check,
    ]

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", AGENCY_TYPE)), \
         patch("app.routers.users.get_supabase", return_value=db):
        resp = client.patch(
            f"/users/provincial/responders/{RESPONDER_UUID}/reassign",
            json={"agency_id": "no-such-agency"},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 404


def test_responder_reassignment_rejects_non_responder_target():
    db = MagicMock()
    check = MagicMock()
    check.data = {"id": RESIDENT_UUID, "role": "resident", "full_name": "R"}
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", AGENCY_TYPE)), \
         patch("app.routers.users.get_supabase", return_value=db):
        resp = client.patch(
            f"/users/provincial/responders/{RESIDENT_UUID}/reassign",
            json={"agency_id": NEW_AGENCY_UUID},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 422
