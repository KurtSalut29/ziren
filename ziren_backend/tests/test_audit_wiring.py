"""
Regression coverage for Task 5 of the Super Admin plan: every existing
mutation endpoint that should write to the general audit trail actually
does, with the right action/target — and, just as importantly, that
exercising these endpoints in tests never reaches a REAL Supabase call.

Why the second half matters: audit_service.record() calls
app.services.audit_service.get_supabase() — a DIFFERENT import site than
whatever a router's own get_supabase() patch covers. A test that mocks only
the router's get_supabase and forgets this would silently fall through to
the real singleton client on every call audit_service makes. record()
swallows any resulting exception (by design — an audit write must never fail
the operation it describes), so such a test would still pass, but every run
would attempt a live network call to the configured Supabase project. Every
test below patches `app.services.audit_service.record` directly instead —
which also doubles as the assertion surface for "was the right action
recorded".

Run: pytest tests/test_audit_wiring.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from tests.audit_helpers import patch_audit_action

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_UUID      = "aaaaaaaa-0000-0000-0000-000000000001"
STATION_UUID     = "bbbbbbbb-0000-0000-0000-000000000001"
NEW_USER_UUID    = "cccccccc-0000-0000-0000-000000000001"
TARGET_USER_UUID = "dddddddd-0000-0000-0000-000000000001"

# Every fixture below scopes the acting Provincial Admin AND the target
# agency/station to this one agency_type, so the migration 034 scope checks
# (assert_agency_scope / the direct agency_type comparisons in stations.py
# and users.py) pass the same way an unconditional super_admin used to.
AGENCY_TYPE = "BFP"


def _profile(user_id, role="provincial_admin"):
    return {
        "id": user_id, "email": "admin@ziren.test", "full_name": "Test Admin",
        "role": role, "approval_status": "not_required",
        "agency_id": None, "agency_type": AGENCY_TYPE if role == "provincial_admin" else None,
        "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    # assert_agency_scope's own provincial_admin lookup chains
    # .select(...).eq("id", agency_id).limit(1).execute() -- a different
    # chain from the .single() one above (used by users.py's
    # update_agency_admin/reassign_responder). Every agency it's asked
    # about reports AGENCY_TYPE, matching the acting admin's own.
    scope_lookup = MagicMock()
    scope_lookup.data = [{"agency_type": AGENCY_TYPE}]
    db.table.return_value.select.return_value.eq.return_value.limit.return_value.execute.return_value = scope_lookup
    return db


# ── stations.py ──────────────────────────────────────────────────────────

def test_create_station_writes_audit_log():
    db = MagicMock()
    agency_result = MagicMock()
    agency_result.data = {"id": AGENCY_UUID, "name": "BFP Naval", "agency_type": "BFP"}
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = agency_result

    insert_result = MagicMock()
    insert_result.data = [{"id": STATION_UUID, "name": "BFP Naval Sub-Station"}]
    db.table.return_value.insert.return_value.execute.return_value = insert_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.stations.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.post(
            "/stations/",
            json={"agency_id": AGENCY_UUID, "name": "BFP Naval Sub-Station"},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    assert audit_record.called
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "station.created"
    assert kwargs["target_type"] == "station"
    # The id is chosen before the insert so the audit row (written first) can
    # name it, and the station is inserted with that same id.
    inserted = db.table.return_value.insert.call_args.args[0]
    assert kwargs["target_id"] == inserted["id"]


def test_deactivate_station_writes_audit_log():
    db = MagicMock()
    check_result = MagicMock()
    check_result.data = {
        "id": STATION_UUID, "name": "BFP Naval", "agency_id": AGENCY_UUID, "is_active": True,
        "agencies": {"agency_type": AGENCY_TYPE},
    }
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check_result

    update_result = MagicMock()
    update_result.data = [{"id": STATION_UUID, "is_active": False}]
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = update_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.stations.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(f"/stations/{STATION_UUID}/deactivate", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "station.deactivated"
    assert kwargs["target_id"] == STATION_UUID


def test_activate_station_writes_audit_log():
    db = MagicMock()
    check_result = MagicMock()
    check_result.data = {
        "id": STATION_UUID, "name": "BFP Naval", "agency_id": AGENCY_UUID, "is_active": False,
        "agencies": {"agency_type": AGENCY_TYPE},
    }
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check_result

    update_result = MagicMock()
    update_result.data = [{"id": STATION_UUID, "is_active": True}]
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = update_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.stations.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(f"/stations/{STATION_UUID}/activate", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "station.activated"


def test_activate_already_active_station_is_rejected_and_does_not_audit():
    db = MagicMock()
    check_result = MagicMock()
    check_result.data = {
        "id": STATION_UUID, "name": "BFP Naval", "agency_id": AGENCY_UUID, "is_active": True,
        "agencies": {"agency_type": AGENCY_TYPE},
    }
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.stations.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(f"/stations/{STATION_UUID}/activate", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 422
    assert not audit_record.called


# ── users.py: agency admin create/update ────────────────────────────────

def test_create_agency_admin_writes_audit_log():
    db = MagicMock()
    agency_result = MagicMock()
    agency_result.data = {"id": AGENCY_UUID, "name": "BFP Naval", "agency_type": "BFP"}
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = agency_result

    existing_result = MagicMock()
    existing_result.data = []
    db.table.return_value.select.return_value.ilike.return_value.limit.return_value.execute.return_value = existing_result

    invited_user = MagicMock()
    invited_user.id = NEW_USER_UUID
    invite_response = MagicMock()
    invite_response.user = invited_user
    db.auth.admin.invite_user_by_email.return_value = invite_response

    upsert_result = MagicMock()
    upsert_result.data = [{"id": NEW_USER_UUID, "full_name": "New Admin", "agency_id": AGENCY_UUID}]
    db.table.return_value.upsert.return_value.execute.return_value = upsert_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.post(
            "/users/provincial/agency-admins",
            json={"full_name": "New Admin", "email": "new.admin@bfp.gov.ph", "agency_id": AGENCY_UUID},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 201, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "agency_admin.created"
    # Written before the invite, so the new account's id (which only exists
    # once Supabase creates it) is filled into the entry afterwards.
    assert audit_record.entries[0].new["user_id"] == str(NEW_USER_UUID)


@pytest.mark.parametrize("is_active,expected_action", [(False, "account.deactivated"), (True, "account.reactivated")])
def test_update_agency_admin_active_toggle_writes_audit_log(is_active, expected_action):
    db = MagicMock()
    check_result = MagicMock()
    check_result.data = {"id": TARGET_USER_UUID, "role": "agency_admin", "agency_id": AGENCY_UUID}
    update_result = MagicMock()
    update_result.data = [{"id": TARGET_USER_UUID, "full_name": "Existing Admin"}]

    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = check_result
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = update_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(
            f"/users/provincial/agency-admins/{TARGET_USER_UUID}",
            json={"is_active": is_active},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == expected_action


def test_update_agency_admin_reassignment_writes_audit_log():
    new_agency = "eeeeeeee-0000-0000-0000-000000000001"
    db = MagicMock()
    check_result = MagicMock()
    check_result.data = {"id": TARGET_USER_UUID, "role": "agency_admin", "agency_id": AGENCY_UUID}
    agency_check = MagicMock()
    agency_check.data = {"id": new_agency, "agency_type": AGENCY_TYPE}
    update_result = MagicMock()
    update_result.data = [{"id": TARGET_USER_UUID, "full_name": "Existing Admin"}]

    # First .single() call resolves the target user, second resolves the new agency.
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.side_effect = [
        check_result, agency_check,
    ]
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = update_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        resp = client.patch(
            f"/users/provincial/agency-admins/{TARGET_USER_UUID}",
            json={"agency_id": new_agency},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "agency_admin.assigned"
    assert kwargs["new"] == {"agency_id": new_agency}


# ── rubric.py: activate_config ───────────────────────────────────────────

def test_rubric_activate_writes_general_audit_log_too():
    """
    rubric_service.activate_config() already writes its own rubric_audit_log
    row (unchanged, tested elsewhere) — this checks the ADDITIONAL call this
    task added, into the general audit_logs table, so Super Admin's
    system-wide Audit Logs / Configuration History see rubric activations
    too. rubric_service.activate_config itself is mocked here rather than
    its internal DB chain, since the router's only obligation to it is
    calling it and then calling audit_service.record().
    """
    from datetime import datetime, timezone
    from uuid import UUID as UUIDType
    from app.models.rubric import RubricConfig, AgencyType

    config_id = "11111111-0000-0000-0000-000000000001"
    fake_config = RubricConfig.model_construct(
        id=UUIDType(config_id),
        agency_type=AgencyType.BFP,
        version="1.3",
        rules=[],
        is_active=True,
        created_by=UUIDType(PROVINCIAL_ADMIN_UUID),
        activated_by=UUIDType(PROVINCIAL_ADMIN_UUID),
        activated_at=datetime.now(timezone.utc),
        created_at=datetime.now(timezone.utc),
    )

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID)), \
         patch("app.routers.rubric.get_supabase", return_value=MagicMock()), \
         patch("app.routers.rubric.rubric_service.activate_config", return_value=fake_config), \
         patch_audit_action() as audit_record:
        resp = client.post(
            f"/rubric/BFP/configs/{config_id}/activate",
            json={"reason": "Quarterly review"},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "rubric.activated"
    assert kwargs["target_type"] == "rubric_config"
    # The version is known once the activation has run, so it is filled in.
    assert audit_record.entries[0].new == {"version": "1.3", "agency_type": "BFP"}
