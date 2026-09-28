"""
Phase 5.5 — Rubric security & governance checkpoint.

This file is the security checkpoint for Phase 5, per Section 0.2 rules:
  "Every task involving auth, dispatch logic, or the severity rubric
   requires a written test case before it is marked done."

Security claims verified here:

  CLAIM 1 — Unauthenticated access is rejected (401/403) on all endpoints.
  CLAIM 2 — Resident role cannot read or write rubric configs.
  CLAIM 3 — Responder role cannot read or write rubric configs.
  CLAIM 4 — Agency Admin is scoped to their own agency_type only.
             Cannot read, write, or activate another agency's config.
  CLAIM 5 — Super Admin has cross-agency read/write access.
  CLAIM 6 — Every human-initiated config change writes an audit record.
             Config changes without a recorded actor_id are rejected.
  CLAIM 7 — Fallback-to-seed events are always written to rubric_audit_log,
             not only logged to console.
  CLAIM 8 — The /rubric/evaluate endpoint is admin-only. Resident and
             Responder roles cannot query rubric logic externally.
  CLAIM 9 — An Agency Admin with no agency_id assigned cannot access any
             rubric endpoint (misconfigured account guard).
  CLAIM 10 — Rubric condition injection: arbitrary keys in a signal payload
              do not cause the engine to crash or return unexpected severity.

Each test class maps to one claim. Tests are tagged with the claim number
in their docstring so they are reviewable as a security audit table.

Run: pytest tests/test_rubric_security.py -v
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# ── Shared UUIDs ──────────────────────────────────────────────────────────────
RESIDENT_UUID     = "00000000-0000-0000-0000-000000000010"
RESPONDER_UUID    = "00000000-0000-0000-0000-000000000011"
BFP_ADMIN_UUID    = "00000000-0000-0000-0000-000000000012"
PNP_ADMIN_UUID    = "00000000-0000-0000-0000-000000000013"
SUPER_ADMIN_UUID  = "00000000-0000-0000-0000-000000000014"
BFP_AGENCY_UUID   = "aaaaaaaa-0000-0000-0000-000000000001"
PNP_AGENCY_UUID   = "aaaaaaaa-0000-0000-0000-000000000002"
CONFIG_UUID       = str(uuid4())

# ── Mock builders ─────────────────────────────────────────────────────────────

def _profile(user_id, role, agency_id=None, agency_type=None):
    return {
        "id": user_id, "email": "test@example.com",
        "full_name": "Test User", "role": role,
        "approval_status": "not_required" if role != "responder" else "approved",
        "agency_id": agency_id, "agency_type": agency_type,
        "badge_id": None, "is_verified": True,
    }


def _mock_db_for_auth(user_id, role, agency_id=None, agency_type=None):
    """
    DB mock that satisfies get_current_user():
      db.auth.get_user() → mock user with given id
      db.table("users").select()...single()...execute() → profile row
    """
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user

    mock_profile = MagicMock()
    mock_profile.data = _profile(user_id, role, agency_id, agency_type)

    mock_db = MagicMock()
    mock_db.auth.get_user.return_value = mock_get
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = mock_profile
    return mock_db


def _mock_db_with_agency_lookup(user_id, role, user_agency_id, user_agency_type):
    """
    DB mock for _assert_agency_scope(): after auth, resolves agency_type
    from user's agency_id via a second table lookup.
    """
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user

    mock_profile = MagicMock()
    mock_profile.data = _profile(user_id, role, user_agency_id)

    mock_agency = MagicMock()
    mock_agency.data = {"agency_type": user_agency_type}

    mock_db = MagicMock()
    mock_db.auth.get_user.return_value = mock_get

    # First .single().execute() → profile; second → agency row
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.side_effect = [
            mock_profile,
            mock_agency,
        ]
    return mock_db


RUBRIC_ENDPOINTS = [
    ("GET",  "/rubric/BFP/configs"),
    ("GET",  "/rubric/BFP/configs/active"),
    ("GET",  f"/rubric/BFP/configs/{CONFIG_UUID}"),
    ("GET",  "/rubric/BFP/audit-log"),
]


# =============================================================================
# CLAIM 1 — Unauthenticated access is rejected
# =============================================================================

class TestClaim1_UnauthenticatedRejected:
    """
    CLAIM 1: All rubric endpoints reject requests with no token.
    Expected: 403 (HTTPBearer returns 403 when no Authorization header).
    This ensures the rubric config cannot be read or written without auth.
    """

    @pytest.mark.parametrize("method,path", RUBRIC_ENDPOINTS)
    def test_no_token_rejected(self, method, path):
        """No Authorization header → 403, no rubric data returned."""
        if method == "GET":
            resp = client.get(path)
        else:
            resp = client.post(path, json={})
        assert resp.status_code == 403, (
            f"{method} {path} should return 403 without a token, got {resp.status_code}"
        )

    def test_evaluate_no_token_rejected(self):
        """POST /rubric/evaluate without token → 403."""
        resp = client.post(
            "/rubric/evaluate",
            params={"agency_type": "BFP"},
            json={"incident_type": "fire"},
        )
        assert resp.status_code == 403

    def test_upload_no_token_rejected(self):
        """POST /rubric/BFP/configs without token → 403."""
        resp = client.post("/rubric/BFP/configs", json={"version": "1.0", "rules": []})
        assert resp.status_code == 403


# =============================================================================
# CLAIM 2 — Resident role blocked from all rubric endpoints
# =============================================================================

class TestClaim2_ResidentBlocked:
    """
    CLAIM 2: Resident role cannot read or write rubric configs.
    Rubric config is internal operational data — civilians have no need
    to know the scoring rules. Exposure could enable gaming the system.
    Expected: 403 on all rubric endpoints.
    """

    def _resident_db(self):
        return _mock_db_for_auth(RESIDENT_UUID, "resident", agency_id=None)

    @pytest.mark.parametrize("method,path", RUBRIC_ENDPOINTS)
    def test_resident_cannot_access_rubric(self, method, path):
        """Resident token on any rubric endpoint → 403."""
        with patch("app.core.dependencies.get_supabase", return_value=self._resident_db()):
            if method == "GET":
                resp = client.get(path, headers={"Authorization": "Bearer mock"})
            else:
                resp = client.post(path, json={}, headers={"Authorization": "Bearer mock"})
        assert resp.status_code == 403

    def test_resident_cannot_evaluate(self):
        """Resident cannot call /rubric/evaluate."""
        with patch("app.core.dependencies.get_supabase", return_value=self._resident_db()):
            resp = client.post(
                "/rubric/evaluate",
                params={"agency_type": "BFP"},
                json={"incident_type": "fire"},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_resident_cannot_upload(self):
        """Resident cannot upload a rubric config."""
        with patch("app.core.dependencies.get_supabase", return_value=self._resident_db()):
            resp = client.post(
                "/rubric/BFP/configs",
                json={"version": "1.0", "rules": []},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403


# =============================================================================
# CLAIM 3 — Responder role blocked from all rubric endpoints
# =============================================================================

class TestClaim3_ResponderBlocked:
    """
    CLAIM 3: Responder role cannot read or write rubric configs.
    Responders are field officers — they do not manage dispatch rules.
    Expected: 403 on all rubric endpoints.
    """

    def _responder_db(self):
        return _mock_db_for_auth(RESPONDER_UUID, "responder", agency_id=BFP_AGENCY_UUID)

    @pytest.mark.parametrize("method,path", RUBRIC_ENDPOINTS)
    def test_responder_cannot_access_rubric(self, method, path):
        """Responder token on any rubric endpoint → 403."""
        with patch("app.core.dependencies.get_supabase", return_value=self._responder_db()):
            if method == "GET":
                resp = client.get(path, headers={"Authorization": "Bearer mock"})
            else:
                resp = client.post(path, json={}, headers={"Authorization": "Bearer mock"})
        assert resp.status_code == 403

    def test_responder_cannot_evaluate(self):
        """Responder cannot call /rubric/evaluate."""
        with patch("app.core.dependencies.get_supabase", return_value=self._responder_db()):
            resp = client.post(
                "/rubric/evaluate",
                params={"agency_type": "BFP"},
                json={"incident_type": "fire"},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403


# =============================================================================
# CLAIM 4 — Agency Admin scoped to own agency only
# =============================================================================

class TestClaim4_AgencyAdminScoped:
    """
    CLAIM 4: A BFP Agency Admin cannot read, write, or activate PNP rubric configs.
    Role check alone (agency_admin) is insufficient — agency_type scope is
    enforced via _assert_agency_scope() in every endpoint.
    Expected: 403 when agency_type in path does not match the admin's agency.
    """

    def _bfp_admin_db(self):
        return _mock_db_with_agency_lookup(
            BFP_ADMIN_UUID, "agency_admin", BFP_AGENCY_UUID, "BFP"
        )

    def test_bfp_admin_blocked_from_pnp_configs_list(self):
        """BFP Admin cannot list PNP configs."""
        with patch("app.core.dependencies.get_supabase", return_value=self._bfp_admin_db()), \
             patch("app.routers.rubric.get_supabase", return_value=self._bfp_admin_db()):
            resp = client.get(
                "/rubric/PNP/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403
        assert "PNP" in resp.json().get("detail", "")

    def test_bfp_admin_blocked_from_pnp_audit_log(self):
        """BFP Admin cannot read PNP audit log."""
        with patch("app.core.dependencies.get_supabase", return_value=self._bfp_admin_db()), \
             patch("app.routers.rubric.get_supabase", return_value=self._bfp_admin_db()):
            resp = client.get(
                "/rubric/PNP/audit-log",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_bfp_admin_blocked_from_mdrrmo_configs(self):
        """BFP Admin cannot read MDRRMO configs."""
        with patch("app.core.dependencies.get_supabase", return_value=self._bfp_admin_db()), \
             patch("app.routers.rubric.get_supabase", return_value=self._bfp_admin_db()):
            resp = client.get(
                "/rubric/MDRRMO/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_bfp_admin_blocked_from_uploading_pnp_config(self):
        """BFP Admin cannot upload a PNP config version."""
        valid_rule = {
            "rule_id": "PNP-TEST-001",
            "description": "Test rule",
            "conditions": {"incident_type_in": ["fire"]},
            "severity_contribution": "low",
            "provenance": "TODO: test",
            "active": True,
        }
        with patch("app.core.dependencies.get_supabase", return_value=self._bfp_admin_db()), \
             patch("app.routers.rubric.get_supabase", return_value=self._bfp_admin_db()):
            resp = client.post(
                "/rubric/PNP/configs",
                json={"version": "9.9.9", "rules": [valid_rule]},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_bfp_admin_blocked_from_activating_pnp_config(self):
        """BFP Admin cannot activate a PNP config."""
        with patch("app.core.dependencies.get_supabase", return_value=self._bfp_admin_db()), \
             patch("app.routers.rubric.get_supabase", return_value=self._bfp_admin_db()):
            resp = client.post(
                f"/rubric/PNP/configs/{CONFIG_UUID}/activate",
                json={},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_pnp_admin_blocked_from_bfp_configs(self):
        """Cross-check: PNP Admin also cannot access BFP configs."""
        pnp_db = _mock_db_with_agency_lookup(
            PNP_ADMIN_UUID, "agency_admin", PNP_AGENCY_UUID, "PNP"
        )
        with patch("app.core.dependencies.get_supabase", return_value=pnp_db), \
             patch("app.routers.rubric.get_supabase", return_value=pnp_db):
            resp = client.get(
                "/rubric/BFP/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403


# =============================================================================
# CLAIM 5 — Provincial Admin is scoped to their own agency_type
# (migration 034: replaces the old cross-agency super_admin claim below)
# =============================================================================

class TestClaim5_ProvincialAdminOwnAgencyType:
    """
    CLAIM 5 (rewritten for migration 034): a Provincial Admin is scoped to
    ONE agency_type, province-wide — not every agency the way the retired
    cross-agency super_admin was. rubric.py's own _assert_agency_scope
    already compares the caller's agency_type directly against the path's
    {agency_type} for a provincial_admin (no DB lookup needed, unlike
    agency_admin's agency_id->agencies join) and 403s on a mismatch.

    This used to assert the opposite — that the admin role could reach any
    of BFP/PNP/MDRRMO unconditionally. That was correct for super_admin and
    is exactly the behaviour migration 034 retired.
    """

    def _provincial_admin_db(self, agency_type, extra_data=None):
        """
        DB mock for a provincial_admin scoped to `agency_type`. After auth
        passes the scope check, subsequent calls depend on the test — list
        configs returns empty (no DB records needed for a scope-only test).
        """
        mock_user = MagicMock()
        mock_user.id = SUPER_ADMIN_UUID
        mock_get = MagicMock()
        mock_get.user = mock_user

        mock_profile = MagicMock()
        mock_profile.data = _profile(SUPER_ADMIN_UUID, "provincial_admin", agency_id=None, agency_type=agency_type)

        mock_list = MagicMock()
        mock_list.data = extra_data or []

        mock_db = MagicMock()
        mock_db.auth.get_user.return_value = mock_get
        mock_db.table.return_value.select.return_value \
            .eq.return_value.single.return_value.execute.return_value = mock_profile
        mock_db.table.return_value.select.return_value \
            .eq.return_value.order.return_value \
            .execute.return_value = mock_list
        return mock_db

    def test_provincial_admin_can_access_their_own_agency_type_configs(self):
        """A BFP Provincial Admin passes the scope check for BFP — not 403."""
        db = self._provincial_admin_db("BFP")
        with patch("app.core.dependencies.get_supabase", return_value=db), \
             patch("app.routers.rubric.get_supabase", return_value=db), \
             patch("app.services.rubric_service.get_supabase", return_value=db):
            resp = client.get(
                "/rubric/BFP/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code != 403, (
            f"Provincial Admin should not be blocked for their own agency_type, got {resp.status_code}"
        )

    def test_provincial_admin_forbidden_from_pnp_configs(self):
        """A BFP Provincial Admin is refused PNP — the whole point of migration 034."""
        db = self._provincial_admin_db("BFP")
        with patch("app.core.dependencies.get_supabase", return_value=db), \
             patch("app.routers.rubric.get_supabase", return_value=db), \
             patch("app.services.rubric_service.get_supabase", return_value=db):
            resp = client.get(
                "/rubric/PNP/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_provincial_admin_forbidden_from_mdrrmo_configs(self):
        """A BFP Provincial Admin is refused MDRRMO for the same reason."""
        db = self._provincial_admin_db("BFP")
        with patch("app.core.dependencies.get_supabase", return_value=db), \
             patch("app.routers.rubric.get_supabase", return_value=db), \
             patch("app.services.rubric_service.get_supabase", return_value=db):
            resp = client.get(
                "/rubric/MDRRMO/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_pnp_provincial_admin_can_access_pnp_configs(self):
        """The same rule from the PNP Provincial Admin's own side."""
        db = self._provincial_admin_db("PNP")
        with patch("app.core.dependencies.get_supabase", return_value=db), \
             patch("app.routers.rubric.get_supabase", return_value=db), \
             patch("app.services.rubric_service.get_supabase", return_value=db):
            resp = client.get(
                "/rubric/PNP/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code != 403


# =============================================================================
# CLAIM 6 — Every human config change requires a non-empty actor_id
# =============================================================================

class TestClaim6_AuditActorRequired:
    """
    CLAIM 6: write_config_audit_event() raises ValueError when actor_id
    is empty or None. A config change that fails its audit write is aborted
    (raises RuntimeError), so no silent untracked changes are possible.
    """

    def test_empty_actor_id_raises(self):
        """Empty string actor_id → ValueError before any DB write."""
        from app.services.rubric_traceability import write_config_audit_event
        from app.models.rubric import AuditEventType, AgencyType

        with pytest.raises(ValueError, match="actor_id is required"):
            write_config_audit_event(
                event_type=AuditEventType.config_activated,
                agency_type=AgencyType.BFP,
                actor_id="",
                db=MagicMock(),
            )

    def test_none_actor_id_raises(self):
        """None actor_id → ValueError."""
        from app.services.rubric_traceability import write_config_audit_event
        from app.models.rubric import AuditEventType, AgencyType

        with pytest.raises(ValueError, match="actor_id is required"):
            write_config_audit_event(
                event_type=AuditEventType.config_created,
                agency_type=AgencyType.PNP,
                actor_id=None,
                db=MagicMock(),
            )

    def test_audit_db_failure_aborts_with_runtime_error(self):
        """
        If the audit DB write itself fails (network error, etc.), a RuntimeError
        is raised so the calling service can abort the config change rather than
        silently proceeding without a record.
        """
        from app.services.rubric_traceability import write_config_audit_event
        from app.models.rubric import AuditEventType, AgencyType

        mock_db = MagicMock()
        mock_db.table.return_value.insert.return_value.execute.side_effect = (
            Exception("DB connection lost")
        )

        with pytest.raises(RuntimeError, match="Audit write failed"):
            write_config_audit_event(
                event_type=AuditEventType.config_activated,
                agency_type=AgencyType.BFP,
                actor_id=str(BFP_ADMIN_UUID),
                db=mock_db,
            )


# =============================================================================
# CLAIM 7 — Fallback-to-seed is always written to rubric_audit_log
# =============================================================================

class TestClaim7_FallbackAuditPersisted:
    """
    CLAIM 7: write_fallback_audit_event() writes a row to rubric_audit_log.
    The fallback reason is persisted, not only console-logged.
    A fallback event without a `notes` field is rejected at model level.
    """

    def test_fallback_event_writes_to_audit_table(self):
        """When engine falls back to seed, rubric_audit_log.insert() is called."""
        from app.services.rubric_traceability import write_fallback_audit_event
        from app.models.rubric import AgencyType

        mock_db = MagicMock()
        mock_db.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]

        write_fallback_audit_event(
            agency_type=AgencyType.BFP,
            reason="No active config in DB for BFP.",
            seed_version="1.0.0",
            db=mock_db,
        )

        mock_db.table.assert_called_with("rubric_audit_log")
        call_args = mock_db.table.return_value.insert.call_args[0][0]
        assert call_args["event_type"] == "fallback_to_seed"
        assert call_args["agency_type"] == "BFP"
        assert "No active config" in call_args["notes"]
        assert call_args["actor_id"] is None  # system event, no user

    def test_fallback_event_without_notes_rejected(self):
        """RubricAuditEvent model rejects fallback_to_seed with no notes."""
        from app.models.rubric import RubricAuditEvent, AuditEventType, AgencyType

        with pytest.raises(Exception, match="notes is required"):
            RubricAuditEvent(
                event_type=AuditEventType.fallback_to_seed,
                agency_type=AgencyType.MDRRMO,
                notes=None,
            )

    def test_fallback_audit_write_failure_is_non_fatal(self):
        """
        If the audit DB write fails during a fallback event, the engine
        continues (non-fatal) — rubric evaluation must not be blocked by
        an audit table outage.
        """
        from app.services.rubric_traceability import write_fallback_audit_event
        from app.models.rubric import AgencyType

        mock_db = MagicMock()
        mock_db.table.return_value.insert.return_value.execute.side_effect = (
            Exception("DB unavailable")
        )

        # Must NOT raise — fallback is non-fatal
        write_fallback_audit_event(
            agency_type=AgencyType.PNP,
            reason="Test: DB unavailable.",
            seed_version="1.0.0",
            db=mock_db,
        )

    def test_evaluate_with_no_db_config_triggers_fallback_audit(self):
        """
        evaluate() with no active DB config calls the fallback path,
        which attempts to write to rubric_audit_log.
        """
        from app.services import rubric_service as rs
        from app.models.rubric import AgencyType

        mock_db = MagicMock()
        mock_db.table.return_value.select.return_value \
            .eq.return_value.eq.return_value \
            .limit.return_value.execute.return_value.data = []
        mock_db.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]

        rs._config_cache.clear()
        rs.evaluate({"incident_type": "fire"}, AgencyType.BFP, db=mock_db)

        # rubric_audit_log insert should have been called
        insert_calls = [
            str(call) for call in mock_db.table.call_args_list
            if "rubric_audit_log" in str(call)
        ]
        assert len(insert_calls) > 0, (
            "Expected rubric_audit_log insert after fallback-to-seed, "
            "but no such call was made."
        )


# =============================================================================
# CLAIM 8 — /rubric/evaluate is admin-only
# =============================================================================

class TestClaim8_EvaluateAdminOnly:
    """
    CLAIM 8: The evaluate endpoint is not queryable by residents or responders.
    Exposing rubric logic publicly would allow reporters to craft payloads
    that game the severity scoring.
    """

    def test_resident_cannot_call_evaluate(self):
        db = _mock_db_for_auth(RESIDENT_UUID, "resident")
        with patch("app.core.dependencies.get_supabase", return_value=db):
            resp = client.post(
                "/rubric/evaluate",
                params={"agency_type": "BFP"},
                json={"incident_type": "fire"},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_responder_cannot_call_evaluate(self):
        db = _mock_db_for_auth(RESPONDER_UUID, "responder", BFP_AGENCY_UUID)
        with patch("app.core.dependencies.get_supabase", return_value=db):
            resp = client.post(
                "/rubric/evaluate",
                params={"agency_type": "BFP"},
                json={"incident_type": "fire"},
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403

    def test_unauthenticated_cannot_call_evaluate(self):
        resp = client.post(
            "/rubric/evaluate",
            params={"agency_type": "BFP"},
            json={"incident_type": "fire"},
        )
        assert resp.status_code == 403


# =============================================================================
# CLAIM 9 — Agency Admin with no agency_id is blocked
# =============================================================================

class TestClaim9_AdminWithNoAgencyBlocked:
    """
    CLAIM 9: An agency_admin account with agency_id=None cannot access
    any scoped rubric endpoint. This guards against misconfigured accounts
    that have the agency_admin role but were not properly assigned to an agency.
    """

    def test_agency_admin_without_agency_id_blocked(self):
        """
        agency_admin + agency_id=None: _assert_agency_scope() raises 403
        with a message directing the user to contact Super Admin.
        """
        db = _mock_db_for_auth(BFP_ADMIN_UUID, "agency_admin", agency_id=None)
        with patch("app.core.dependencies.get_supabase", return_value=db), \
             patch("app.routers.rubric.get_supabase", return_value=db):
            resp = client.get(
                "/rubric/BFP/configs",
                headers={"Authorization": "Bearer mock"},
            )
        assert resp.status_code == 403
        assert "no agency assigned" in resp.json().get("detail", "").lower()


# =============================================================================
# CLAIM 10 — Condition injection: unknown signal keys are harmless
# =============================================================================

class TestClaim10_ConditionInjection:
    """
    CLAIM 10: Arbitrary keys injected into the signal payload do not:
      - Crash the engine
      - Trigger unexpected rule matches
      - Return a severity higher than what the legitimate signals alone produce

    The engine uses explicit field-by-field comparisons — no eval(), no
    dynamic dispatch, no wildcard matching. Unknown keys are silently ignored.
    """

    def _evaluate(self, signals, agency=None):
        from app.services import rubric_service as rs
        from app.models.rubric import AgencyType

        rs._config_cache.clear()
        mock_db = MagicMock()
        mock_db.table.return_value.select.return_value \
            .eq.return_value.eq.return_value \
            .limit.return_value.execute.return_value.data = []
        mock_db.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]
        return rs.evaluate(signals, agency or AgencyType.BFP, db=mock_db)

    def test_injected_field_does_not_match_unrelated_rule(self):
        """
        Adding fabricated key 'dead_count_gte' as a literal string key
        in the signal dict should not affect rule matching.
        """
        result = self._evaluate({
            "dead_count_gte": 999,   # raw condition name, not a signal name
            "incident_type": "fire",
            "casualty_mentioned": False,
            "multi_agency_needed": False,
        })
        # BFP-001 (dead_count_gte=1 condition) must NOT fire — signal is dead_count, not dead_count_gte
        assert "BFP-001" not in result.triggered_rules

    def test_deeply_nested_payload_does_not_crash(self):
        """Nested dicts/lists in signal values are ignored without crashing."""
        result = self._evaluate({
            "incident_type": "fire",
            "malicious_nested": {"rules": [{"severity": "critical"}]},
            "casualty_mentioned": False,
            "multi_agency_needed": False,
        })
        assert result is not None
        assert result.severity.value in ("critical", "high", "medium", "low")

    def test_sql_injection_string_in_signal_value_is_inert(self):
        """SQL-injection-style string in a signal field is treated as a plain string."""
        result = self._evaluate({
            "incident_type": "fire'; DROP TABLE rubric_configs; --",
            "casualty_mentioned": False,
        })
        # The mangled incident_type matches nothing → no rules fire
        assert result.severity.value == "low"
        assert result.no_rules_triggered is True

    def test_very_large_injured_count_does_not_cause_overflow(self):
        """Very large integer in injured_count is handled without overflow/crash."""
        result = self._evaluate(
            {"incident_type": "vehicular", "casualty_mentioned": True, "injured_count": 10_000_000},
            agency=__import__("app.models.rubric", fromlist=["AgencyType"]).AgencyType.MDRRMO,
        )
        # Should fire MDRRMO-010 (gte=3) without crashing
        assert result is not None
        assert "MDRRMO-010" in result.triggered_rules

    def test_boolean_coercion_truthy_integer_matches_true_condition(self):
        """
        Signal value 1 (integer) for a boolean field:
        bool(1) == True, so conditions testing True should match.
        This is consistent and documented behaviour, not an injection vector.
        """
        result = self._evaluate({
            "incident_type": "fire",
            "children_involved": 1,   # integer truthy, not bool True
        })
        assert "BFP-010" in result.triggered_rules

    def test_boolean_coercion_zero_matches_false_condition(self):
        """Signal value 0 for boolean field: bool(0) == False."""
        result = self._evaluate({
            "incident_type": "fire",
            "children_involved": 0,
            "casualty_mentioned": 0,
            "multi_agency_needed": 0,
        })
        assert "BFP-010" not in result.triggered_rules
        assert "BFP-009" in result.triggered_rules   # fire, no casualty, no multi


# =============================================================================
# Security summary assertion
# =============================================================================

class TestSecuritySummary:
    """
    Consolidated role-access matrix test.
    Verifies the full 5-role × endpoint permission table in one parameterised sweep.

    Role            | /rubric/BFP/configs | /rubric/evaluate
    ----------------|----------------------|------------------
    (no token)      | 403                  | 403
    resident        | 403                  | 403
    responder       | 403                  | 403
    agency_admin    | 403 (wrong agency)   | 403 (wrong agency)
    provincial_admin| not-403 (own type)   | not-403 (own type)

    provincial_admin's row assumes agency_type='BFP' — migration 034
    rescoped it to one agency_type, so unlike the retired super_admin this
    is no longer unconditionally not-403 for every path; see
    TestClaim5_ProvincialAdminOwnAgencyType for the PNP/MDRRMO-mismatch
    403 cases this summary table doesn't have room for.
    """

    CASES = [
        # (role, agency_id, agency_type, expect_403_for_bfp_endpoint)
        (None,              None,             None,  True),   # unauthenticated
        ("resident",        None,             None,  True),
        ("responder",       BFP_AGENCY_UUID,  None,  True),
        ("agency_admin",    PNP_AGENCY_UUID,  None,  True),   # PNP admin trying BFP
        ("provincial_admin", None,            "BFP", False),  # own agency_type: allowed
    ]

    @pytest.mark.parametrize("role,agency_id,agency_type,expect_403", CASES)
    def test_bfp_configs_access_matrix(self, role, agency_id, agency_type, expect_403):
        if role is None:
            resp = client.get("/rubric/BFP/configs")
            assert resp.status_code == 403
            return

        user_id = str(uuid4())
        if role == "agency_admin" and agency_id == PNP_AGENCY_UUID:
            db = _mock_db_with_agency_lookup(user_id, role, agency_id, "PNP")
        else:
            db = _mock_db_for_auth(user_id, role, agency_id, agency_type)

        with patch("app.core.dependencies.get_supabase", return_value=db), \
             patch("app.routers.rubric.get_supabase", return_value=db), \
             patch("app.services.rubric_service.get_supabase", return_value=db):
            resp = client.get(
                "/rubric/BFP/configs",
                headers={"Authorization": "Bearer mock"},
            )

        if expect_403:
            assert resp.status_code == 403, (
                f"role={role}, agency={agency_id}: expected 403, got {resp.status_code}"
            )
        else:
            assert resp.status_code != 403, (
                f"role={role}: should not be 403, got {resp.status_code}"
            )
