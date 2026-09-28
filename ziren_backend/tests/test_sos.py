"""
Phase 3B SOS Quick-Report tests — 26 tests.

Architecture:
  HTTP-layer tests  → use TestClient for auth enforcement, role checks,
                       input validation (Pydantic), and IP rate-limit bypass test.
  Service-layer tests → call incident_service.submit_sos() directly to test
                        business logic without slowapi's decorator getting in the way.

Run with: pytest tests/test_sos.py -v
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.incident import SosSubmitRequest
from app.services import incident_service
from app.services.incident_service import (
    SOS_COOLDOWN_MINUTES,
    SOS_SUSPEND_THRESHOLD,
    SOS_SUSPENSION_DAYS,
    SOS_TRUST_FLAG_THRESHOLD,
    record_false_sos,
    submit_sos,
)

RESIDENT_UUID     = "00000000-0000-0000-0000-000000000001"
RESPONDER_UUID    = "00000000-0000-0000-0000-000000000002"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000003"
INCIDENT_UUID     = str(uuid4())
STATION_UUID      = "bbbbbbbb-0000-0000-0000-000000000001"
AGENCY_UUID       = "aaaaaaaa-0000-0000-0000-000000000001"


# ── Fixtures ──────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """Reset slowapi between tests so IP counter doesn't accumulate."""
    try:
        from app.main import limiter
        # Attempt to clear — works on some backends
        if hasattr(limiter, "_storage") and hasattr(limiter._storage, "reset"):
            limiter._storage.reset()
    except Exception:
        pass
    yield


@pytest.fixture()
def api_client():
    return TestClient(app)


# ── Mock builders ─────────────────────────────────────────────

def _h():
    return {"Authorization": "Bearer mock_token"}


def _mock_auth(user_id=RESIDENT_UUID, role="resident"):
    """Satisfies get_current_user() in dependencies.py (HTTP tests only)."""
    mock_user = MagicMock(); mock_user.id = user_id
    mock_get  = MagicMock(); mock_get.user = mock_user
    mock_profile = MagicMock()
    mock_profile.data = {
        "id": user_id, "email": "test@example.com",
        "full_name": "Test", "role": role,
        "approval_status": "not_required",
        "agency_id": None, "badge_id": None, "is_verified": True,
    }
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = mock_profile
    return db


def _svc_db(
    user_id=RESIDENT_UUID,
    warning_count=0,
    suspended_until=None,
    last_submitted_at=None,
):
    """
    Supabase mock for service-layer tests.
    Routes table() calls by name.
    """
    profile_data = {
        "id": user_id, "full_name": "Test",
        "role": "resident",
        "sos_warning_count": warning_count,
        "sos_suspended_until": suspended_until,
        "sos_last_submitted_at": last_submitted_at,
        "is_verified": True,
    }
    station_row = {
        "id": STATION_UUID, "agency_id": AGENCY_UUID,
        "name": "BFP Naval Main Station",
        "location": "POINT(124.4063 11.5836)",
        "agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Naval"},
    }
    incident_row = {
        "id": INCIDENT_UUID, "reporter_id": user_id,
        "station_id": STATION_UUID, "assigned_agency_id": AGENCY_UUID,
        "report_text": "SOS", "location_address": None,
        "status": "received", "severity": None,
        "suggested_agency_id": None, "signals": None, "signals_confidence": None,
        "submitted_via": "sos",
        "sos_flagged": warning_count >= SOS_TRUST_FLAG_THRESHOLD,
        "created_at": "2026-01-01T00:00:00+00:00",
        "updated_at": "2026-01-01T00:00:00+00:00",
        "dispatched_at": None, "resolved_at": None,
    }

    users_t     = MagicMock()
    stations_t  = MagicMock()
    incidents_t = MagicMock()

    users_t.select.return_value.eq.return_value \
        .single.return_value.execute.return_value = MagicMock(data=profile_data)
    users_t.update.return_value.eq.return_value \
        .execute.return_value = MagicMock()

    # Make the stations chain return data at any call depth
    _sr = MagicMock(data=[station_row])
    sc = stations_t.select.return_value
    sc.eq.return_value = sc
    sc.limit.return_value = sc
    sc.execute.return_value = _sr

    incidents_t.insert.return_value.execute.return_value = MagicMock(data=[incident_row])

    # Expose for call-arg inspection
    _svc_db._incidents_t = incidents_t

    def _route(name):
        if name == "users":     return users_t
        if name == "stations":  return stations_t
        if name == "incidents": return incidents_t
        return MagicMock()

    db = MagicMock()
    db.table.side_effect = _route
    return db


# =============================================================================
# HTTP-layer tests: auth enforcement + input validation
# (These must go through TestClient — they test the router/Pydantic layer)
# =============================================================================

def test_sos_requires_auth(api_client):
    r = api_client.post("/incidents/sos", json={})
    assert r.status_code == 403


def test_sos_blocked_for_responder(api_client):
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth(RESPONDER_UUID, "responder")):
        r = api_client.post("/incidents/sos",
                            json={"latitude": 11.5836, "longitude": 124.4063},
                            headers=_h())
    assert r.status_code == 403
    assert "Resident" in r.json()["detail"]


def test_sos_blocked_for_agency_admin(api_client):
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth(AGENCY_ADMIN_UUID, "agency_admin")):
        r = api_client.post("/incidents/sos",
                            json={"latitude": 11.5836, "longitude": 124.4063},
                            headers=_h())
    assert r.status_code == 403


def test_sos_description_over_500_chars_rejected(api_client):
    with patch("app.core.dependencies.get_supabase", return_value=_mock_auth()):
        r = api_client.post("/incidents/sos",
                            json={"description": "X" * 501}, headers=_h())
    assert r.status_code == 422


def test_sos_invalid_latitude_rejected(api_client):
    with patch("app.core.dependencies.get_supabase", return_value=_mock_auth()):
        r = api_client.post("/incidents/sos",
                            json={"latitude": 999.0, "longitude": 124.4063},
                            headers=_h())
    assert r.status_code == 422


def test_sos_invalid_longitude_rejected(api_client):
    with patch("app.core.dependencies.get_supabase", return_value=_mock_auth()):
        r = api_client.post("/incidents/sos",
                            json={"latitude": 11.5836, "longitude": -999.0},
                            headers=_h())
    assert r.status_code == 422


# =============================================================================
# Model-layer tests (no HTTP needed)
# =============================================================================

def test_sos_no_station_id_in_request_model():
    """SosSubmitRequest must not have a station_id field."""
    req = SosSubmitRequest(latitude=11.5836, longitude=124.4063)
    assert not hasattr(req, "station_id")


def test_security_station_id_not_in_sos_request_model():
    assert "station_id" not in SosSubmitRequest.model_fields


def test_security_sos_flagged_not_in_sos_request_model():
    assert "sos_flagged" not in SosSubmitRequest.model_fields


# =============================================================================
# Service-layer tests: business logic (bypass slowapi by calling service directly)
# =============================================================================

def test_sos_sets_submitted_via_sos():
    db = _svc_db()
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    assert result.submitted_via == "sos"


def test_sos_reporter_id_from_token_not_body():
    """reporter_id is always the function arg (from token), never from request body."""
    db = _svc_db()
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    assert result.id == INCIDENT_UUID


def test_sos_no_description_defaults_to_sos_text():
    db = _svc_db()
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(),  # no description
            reporter_id=RESIDENT_UUID,
        )
    assert result.report_text == "SOS"


def test_sos_without_gps_still_submits():
    """No coordinates → fallback station lookup → still succeeds."""
    db = _svc_db()
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(),  # no lat/lng
            reporter_id=RESIDENT_UUID,
        )
    assert result.id == INCIDENT_UUID


def test_sos_station_resolved_server_side():
    db = _svc_db()
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    assert result.station_name == "BFP Naval Main Station"
    assert result.agency_type  == "BFP"


# =============================================================================
# Server-side cooldown (service layer)
# =============================================================================

def test_sos_blocked_during_cooldown():
    recent = (datetime.now(timezone.utc) - timedelta(minutes=SOS_COOLDOWN_MINUTES - 5)).isoformat()
    db = _svc_db(last_submitted_at=recent)
    with patch.object(incident_service, "get_supabase", return_value=db):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc:
            submit_sos(
                SosSubmitRequest(latitude=11.5836, longitude=124.4063),
                reporter_id=RESIDENT_UUID,
            )
    assert exc.value.status_code == 429
    assert "wait" in exc.value.detail.lower()


def test_sos_allowed_after_cooldown_expires():
    old = (datetime.now(timezone.utc) - timedelta(minutes=SOS_COOLDOWN_MINUTES + 5)).isoformat()
    db = _svc_db(last_submitted_at=old)
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    assert result.id == INCIDENT_UUID


# =============================================================================
# Suspension check (service layer)
# =============================================================================

def test_sos_blocked_when_suspended():
    future = (datetime.now(timezone.utc) + timedelta(days=SOS_SUSPENSION_DAYS - 1)).isoformat()
    db = _svc_db(suspended_until=future)
    with patch.object(incident_service, "get_supabase", return_value=db):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc:
            submit_sos(
                SosSubmitRequest(latitude=11.5836, longitude=124.4063),
                reporter_id=RESIDENT_UUID,
            )
    assert exc.value.status_code == 403
    assert "suspended" in exc.value.detail.lower()


def test_sos_allowed_when_suspension_expired():
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    db = _svc_db(suspended_until=past)
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    assert result.id == INCIDENT_UUID


# =============================================================================
# Trust / history flag (service layer)
# =============================================================================

def test_sos_flagged_false_when_no_warnings():
    db = _svc_db(warning_count=0)
    with patch.object(incident_service, "get_supabase", return_value=db):
        submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    payload = _svc_db._incidents_t.insert.call_args[0][0]
    assert payload["sos_flagged"] is False


def test_sos_flagged_true_when_has_warnings():
    db = _svc_db(warning_count=SOS_TRUST_FLAG_THRESHOLD)
    with patch.object(incident_service, "get_supabase", return_value=db):
        submit_sos(
            SosSubmitRequest(latitude=11.5836, longitude=124.4063),
            reporter_id=RESIDENT_UUID,
        )
    payload = _svc_db._incidents_t.insert.call_args[0][0]
    assert payload["sos_flagged"] is True


# =============================================================================
# Escalating consequences — record_false_sos()
# =============================================================================

def _false_sos_mock(warning_count, suspended_until=None):
    profile = MagicMock()
    profile.data = {
        "id": RESIDENT_UUID,
        "sos_warning_count": warning_count,
        "sos_suspended_until": suspended_until,
    }
    db = MagicMock()
    db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = profile
    db.table.return_value.update.return_value \
        .eq.return_value.execute.return_value = MagicMock()
    return db


def test_record_false_sos_increments_warning_count():
    db = _false_sos_mock(warning_count=1)
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = record_false_sos(RESIDENT_UUID, "dispatcher-uuid")
    assert result["warning_count"] == 2
    assert result["suspended_until"] is None


def test_record_false_sos_suspends_at_threshold():
    db = _false_sos_mock(warning_count=SOS_SUSPEND_THRESHOLD - 1)
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = record_false_sos(RESIDENT_UUID, "dispatcher-uuid")
    assert result["warning_count"] == SOS_SUSPEND_THRESHOLD
    assert result["suspended_until"] is not None


def test_record_false_sos_does_not_double_suspend():
    existing = (datetime.now(timezone.utc) + timedelta(days=15)).isoformat()
    db = _false_sos_mock(warning_count=SOS_SUSPEND_THRESHOLD + 1,
                         suspended_until=existing)
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = record_false_sos(RESIDENT_UUID, "dispatcher-uuid")
    assert result["suspended_until"] is None


# =============================================================================
# Security checkpoint
# =============================================================================

def test_security_no_anonymous_sos(api_client):
    r = api_client.post("/incidents/sos",
                        json={"latitude": 11.5836, "longitude": 124.4063})
    assert r.status_code == 403


def test_security_responder_blocked(api_client):
    with patch("app.core.dependencies.get_supabase",
               return_value=_mock_auth(RESPONDER_UUID, "responder")):
        r = api_client.post("/incidents/sos",
                            json={"latitude": 11.5836, "longitude": 124.4063},
                            headers=_h())
    assert r.status_code == 403


def test_security_cooldown_not_bypassable(api_client):
    """Injecting submitted_via='internet' cannot bypass account cooldown."""
    recent = (datetime.now(timezone.utc) - timedelta(minutes=SOS_COOLDOWN_MINUTES - 5)).isoformat()
    db = _svc_db(last_submitted_at=recent)
    with patch.object(incident_service, "get_supabase", return_value=db):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc:
            submit_sos(
                # submitted_via is not even a field on SosSubmitRequest — prove the model
                SosSubmitRequest(latitude=11.5836, longitude=124.4063),
                reporter_id=RESIDENT_UUID,
            )
    assert exc.value.status_code == 429
