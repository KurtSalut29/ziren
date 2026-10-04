"""
governance_service + /governance router — Task 13 of the Super Admin plan.

Covers:
  - incident configuration reads live from the IncidentCategory/IncidentStatus
    enums, not a second hand-maintained list
  - policy get/update round-trips through system_config and writes an audit
    trail entry with the real previous value
  - configuration history filters to exactly the two config-change actions
  - provincial_admin-only access

Run: pytest tests/test_governance.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.incident import IncidentCategory, IncidentStatus
from app.services import governance_service
from tests.audit_helpers import patch_audit_action

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"


def _profile(user_id, role):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test Admin",
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


def test_incident_configuration_reads_from_the_real_enums():
    config = governance_service.get_incident_configuration()
    assert config["incident_categories"] == [c.value for c in IncidentCategory]
    assert config["incident_statuses"] == [s.value for s in IncidentStatus]
    assert config["editable"] is False


def test_get_policy_rejects_unknown_key():
    with pytest.raises(ValueError):
        governance_service.get_policy("not_a_real_policy")


def test_update_policy_writes_audit_entry_with_previous_value():
    db = MagicMock()
    existing = MagicMock()
    existing.data = {"key": "account_policies", "value": {"require_id_verification": True}}
    updated = MagicMock()
    updated.data = [{"key": "account_policies", "value": {"require_id_verification": False}}]

    db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = existing
    db.table.return_value.update.return_value.eq.return_value.execute.return_value = updated

    actor = {"id": PROVINCIAL_ADMIN_UUID, "role": "provincial_admin", "full_name": "Test Admin"}

    with patch("app.services.governance_service.get_supabase", return_value=db), \
         patch_audit_action() as audit_record:
        result = governance_service.update_policy(
            "account_policies", {"require_id_verification": False}, actor,
        )

    assert result["value"] == {"require_id_verification": False}
    kwargs = audit_record.call_args.kwargs
    assert kwargs["action"] == "system_config.updated"
    assert kwargs["target_id"] == "account_policies"
    assert kwargs["previous"] == {"value": {"require_id_verification": True}}
    assert kwargs["new"] == {"value": {"require_id_verification": False}}


def test_configuration_history_filters_to_config_change_actions():
    db = MagicMock()
    result = MagicMock()
    result.data = [{"id": "log-1", "action": "rubric.activated"}]
    result.count = 1
    chain = db.table.return_value.select.return_value.in_.return_value.order.return_value
    chain.range.return_value.execute.return_value = result

    with patch("app.services.governance_service.get_supabase", return_value=db):
        history = governance_service.get_configuration_history()

    assert history == {"items": [{"id": "log-1", "action": "rubric.activated"}], "total": 1}
    in_args = db.table.return_value.select.return_value.in_.call_args[0]
    assert in_args == ("action", ["system_config.updated", "rubric.activated"])


@pytest.mark.parametrize("path", [
    "/governance/incident-configuration",
    "/governance/account-policies",
    "/governance/notification-policies",
    "/governance/configuration-history",
])
def test_router_forbidden_for_agency_admin(path):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin")):
        resp = client.get(path, headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_router_allows_provincial_admin_for_incident_configuration():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")):
        resp = client.get("/governance/incident-configuration", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
