"""The resident-account rules, through the real HTTP routes.

tests/test_resident_accounts.py pins the service. This pins what a phone and
the dashboard actually hit:

  1. A suspended resident's POST /incidents/ and POST /incidents/sos are refused
     with 403, and the message names an emergency number. Before, a suspension
     stopped only SOS, and an ordinary report went straight through.
  2. The warn / suspend / reinstate routes are admin-only, validate their body,
     and write to the resident's row.

Run with: pytest tests/test_resident_accounts_http.py -v
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.fake_db import FakeDB

client = TestClient(app)

RESIDENT = "00000000-0000-0000-0000-0000000000a1"
ADMIN = "00000000-0000-0000-0000-000000000014"
STATION = "bbbbbbbb-0000-0000-0000-000000000001"


def _auth(user_id: str, role: str):
    """The auth dependency's Supabase: who the bearer token belongs to."""
    user = MagicMock(); user.id = user_id
    got = MagicMock(); got.user = user
    profile = MagicMock()
    profile.data = {
        "id": user_id, "email": f"{role}@example.test", "full_name": f"Test {role}", "role": role,
        "approval_status": "not_required", "agency_id": None, "agency_type": "BFP",
        "badge_id": None, "is_verified": True,
    }
    db = MagicMock()
    db.auth.get_user.return_value = got
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def _db(**user):
    return FakeDB({
        "users": [{
            "id": RESIDENT, "role": "resident", "full_name": "Maria Santos", "email": "maria@example.test",
            "municipality_address": "Naval", "sos_warning_count": 0, "sos_suspended_until": None,
            "sos_last_submitted_at": None, "is_verified": True, **user,
        }],
        "incidents": [], "audit_logs": [], "notifications": [],
    })


def _future(days=5):
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()


H = {"Authorization": "Bearer token"}
REPORT = {
    "report_text": "[FIRE] Sunog na bahay sa Naval", "station_id": STATION, "incident_category": "fire",
    "latitude": 11.5836, "longitude": 124.4063,
}


# ── The block, where the phone meets it ─────────────────────────────────────

def test_a_suspended_resident_cannot_file_an_ordinary_report():
    db = _db(sos_suspended_until=_future())
    with patch("app.core.dependencies.get_supabase", return_value=_auth(RESIDENT, "resident")), \
         patch("app.services.incident_service.get_supabase", return_value=db):
        resp = client.post("/incidents/", json=REPORT, headers=H)
    assert resp.status_code == 403, resp.text
    assert "suspended from sending reports" in resp.json()["detail"]
    assert "911" in resp.json()["detail"]
    assert db.rows("incidents") == []


def test_a_suspended_resident_cannot_send_an_sos():
    db = _db(sos_suspended_until=_future())
    with patch("app.core.dependencies.get_supabase", return_value=_auth(RESIDENT, "resident")), \
         patch("app.services.incident_service.get_supabase", return_value=db):
        resp = client.post("/incidents/sos", json={"latitude": 11.58, "longitude": 124.40}, headers=H)
    assert resp.status_code == 403, resp.text
    assert "911" in resp.json()["detail"]


def test_an_expired_suspension_does_not_stop_the_report_at_the_door():
    """It gets past the suspension check. (It then fails later on this fake
    database, which has no station to resolve - but not with a 403.)"""
    db = _db(sos_suspended_until=(datetime.now(timezone.utc) - timedelta(hours=1)).isoformat())
    with patch("app.core.dependencies.get_supabase", return_value=_auth(RESIDENT, "resident")), \
         patch("app.services.incident_service.get_supabase", return_value=db):
        try:
            resp = client.post("/incidents/", json=REPORT, headers=H)
            status = resp.status_code
        except Exception:
            status = None  # failed past the gate, on the fake station lookup
    assert status != 403


# ── The admin routes ─────────────────────────────────────────────────────────

def _admin_call(path, body, role="provincial_admin", db=None):
    db = db or _db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth(ADMIN, role)), \
         patch("app.services.resident_account_service.get_supabase", return_value=db), \
         patch("app.services.audit_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.get_supabase", return_value=db):
        return client.post(path, json=body, headers=H), db


def test_warn_route_warns_and_notifies():
    resp, db = _admin_call(f"/users/residents/{RESIDENT}/warn",
                           {"violation": "false_report", "note": "Reported a fire that did not exist."})
    assert resp.status_code == 200, resp.text
    assert resp.json()["warning_count"] == 1
    assert db.rows("users")[0]["sos_warning_count"] == 1
    assert [n["type"] for n in db.rows("notifications")] == ["account.warned"]


def test_suspend_route_accepts_until_further_notice():
    resp, db = _admin_call(f"/users/residents/{RESIDENT}/suspend",
                           {"violation": "fake_identity", "note": "Uses somebody else's ID.", "days": None})
    assert resp.status_code == 200, resp.text
    assert resp.json()["suspension"]["indefinite"] is True
    assert db.rows("users")[0]["sos_suspended_until"].startswith("9999-12-31")


def test_reinstate_route_lifts_it():
    resp, db = _admin_call(f"/users/residents/{RESIDENT}/reinstate", {"clear_warnings": True},
                           db=_db(sos_suspended_until=_future(), sos_warning_count=3))
    assert resp.status_code == 200, resp.text
    assert db.rows("users")[0]["sos_suspended_until"] is None
    assert db.rows("users")[0]["sos_warning_count"] == 0


def test_the_routes_validate_their_body():
    assert _admin_call(f"/users/residents/{RESIDENT}/warn", {"violation": "nope", "note": "Something happened."})[0].status_code == 422
    assert _admin_call(f"/users/residents/{RESIDENT}/warn", {"violation": "spam"})[0].status_code == 422
    assert _admin_call(f"/users/residents/{RESIDENT}/suspend", {"violation": "spam", "note": "Too many.", "days": 999})[0].status_code == 422


def test_a_resident_or_responder_cannot_use_them():
    for role in ("resident", "responder"):
        resp, db = _admin_call(f"/users/residents/{RESIDENT}/warn",
                               {"violation": "spam", "note": "Should never apply."}, role=role)
        assert resp.status_code == 403
        assert db.rows("users")[0]["sos_warning_count"] == 0


def test_the_list_route_answers():
    db = _db(verification_level=2, verified_at="2026-09-01T00:00:00+00:00", created_at="2026-08-01T00:00:00+00:00")
    with patch("app.core.dependencies.get_supabase", return_value=_auth(ADMIN, "provincial_admin")), \
         patch("app.services.resident_account_service.get_supabase", return_value=db):
        resp = client.get("/users/residents?standing=verified", headers=H)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["counts"]["verified"] == 1 and body["items"][0]["standing"] == "good"
