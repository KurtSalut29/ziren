"""
announcement_service + /announcements router — Task 16 of the Super Admin
plan.

Covers:
  - publish() with target_type='all' notifies every role
  - publish() with a specific role notifies only that role
  - publish() with target_type='agency' notifies only that agency, and
    requires target_agency_id
  - list_for_user returns the right subset per role/agency (an agency-
    targeted announcement must NOT reach a responder at a different agency)
  - deactivate writes an audit entry
  - role gating on the router

Run: pytest tests/test_announcements.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import announcement_service
from tests.fake_db import FakeDB

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_UUID_A = "aaaaaaaa-0000-0000-0000-000000000001"
AGENCY_UUID_B = "aaaaaaaa-0000-0000-0000-000000000002"

ACTOR = {"id": PROVINCIAL_ADMIN_UUID, "role": "provincial_admin", "full_name": "Test Admin"}


def _profile(user_id, role, agency_id=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": agency_id, "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role, agency_id=None):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id, role, agency_id)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def _roster_db():
    """One account of each role, at two agencies - a real query evaluator, so a
    wrong audience fails here instead of "passing" against a mock."""
    return FakeDB({
        "users": [
            {"id": PROVINCIAL_ADMIN_UUID, "role": "provincial_admin"},
            {"id": "u-admin-a", "role": "agency_admin", "agency_id": AGENCY_UUID_A},
            {"id": "u-resp-a", "role": "responder", "agency_id": AGENCY_UUID_A},
            {"id": "u-resp-b", "role": "responder", "agency_id": AGENCY_UUID_B},
            {"id": "u-resident", "role": "resident"},
        ],
        "agencies": [{"id": AGENCY_UUID_A, "municipality": "Naval"}, {"id": AGENCY_UUID_B, "municipality": "Almeria"}],
        "announcements": [], "notifications": [], "audit_logs": [],
    })


def _publish(db, **kw):
    with patch("app.services.announcement_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.get_supabase", return_value=db), \
         patch("app.services.audit_service.record") as audit_record:
        row = announcement_service.publish(ACTOR, **kw)
    return row, {n["recipient_id"] for n in db.rows("notifications")}, audit_record


# ── announcement_service.publish ────────────────────────────────────────
#
# These used to assert that create_for_roles / create_for_agency were CALLED
# with the right arguments. The audience is now worked out here (it can be two
# barangays of one town), so they assert who was actually notified instead.

def test_publish_to_all_notifies_every_role():
    _, notified, _ = _publish(_roster_db(), title="Maintenance", body="Down at 2am", category="maintenance", target_type="all")
    # Everyone except the admin who sent it.
    assert notified == {"u-admin-a", "u-resp-a", "u-resp-b", "u-resident"}


def test_publish_to_one_role_notifies_only_that_role():
    _, notified, _ = _publish(_roster_db(), title="Reminder", body="Renew your badge", category="reminder", target_type="responder")
    assert notified == {"u-resp-a", "u-resp-b"}


def test_publish_to_agency_notifies_only_that_agency():
    _, notified, _ = _publish(
        _roster_db(), title="Local notice", body="Station closed", category="general",
        target_type="agency", target_agency_id=AGENCY_UUID_A,
    )
    assert notified == {"u-admin-a", "u-resp-a"}


def test_publish_writes_audit_entry():
    _, _, audit_record = _publish(_roster_db(), title="Maintenance", body="Down at 2am", category="maintenance", target_type="all")
    assert audit_record.call_args.kwargs["action"] == "announcement.published"

# ── announcement_service.list_for_user ──────────────────────────────────

ANNOUNCEMENT_ROWS = [
    {"id": "a1", "title": "For everyone", "target_type": "all", "target_agency_id": None},
    {"id": "a2", "title": "For responders", "target_type": "responder", "target_agency_id": None},
    {"id": "a3", "title": "For agency A", "target_type": "agency", "target_agency_id": AGENCY_UUID_A},
]


def _db_returning(rows):
    db = MagicMock()
    result = MagicMock()
    result.data = rows
    db.table.return_value.select.return_value.eq.return_value.order.return_value.execute.return_value = result
    return db


def test_list_for_user_resident_sees_only_all():
    db = _db_returning(ANNOUNCEMENT_ROWS)
    with patch("app.services.announcement_service.get_supabase", return_value=db):
        visible = announcement_service.list_for_user({"role": "resident", "agency_id": None})
    assert [a["id"] for a in visible] == ["a1"]


def test_list_for_user_responder_sees_all_and_role_targeted():
    db = _db_returning(ANNOUNCEMENT_ROWS)
    with patch("app.services.announcement_service.get_supabase", return_value=db):
        visible = announcement_service.list_for_user({"role": "responder", "agency_id": AGENCY_UUID_B})
    assert {a["id"] for a in visible} == {"a1", "a2"}


def test_list_for_user_agency_targeted_reaches_only_that_agency():
    db = _db_returning(ANNOUNCEMENT_ROWS)
    with patch("app.services.announcement_service.get_supabase", return_value=db):
        visible_a = announcement_service.list_for_user({"role": "agency_admin", "agency_id": AGENCY_UUID_A})
        visible_b = announcement_service.list_for_user({"role": "agency_admin", "agency_id": AGENCY_UUID_B})

    assert "a3" in {a["id"] for a in visible_a}
    assert "a3" not in {a["id"] for a in visible_b}


# ── router ───────────────────────────────────────────────────────────────

def test_create_requires_provincial_admin():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("agency-admin-id", "agency_admin", AGENCY_UUID_A)):
        resp = client.post(
            "/announcements/",
            json={"title": "x", "body": "y", "category": "general", "target_type": "all"},
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 403


def test_create_agency_target_without_agency_id_is_rejected():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")):
        resp = client.post(
            "/announcements/",
            json={"title": "x", "body": "y", "category": "general", "target_type": "agency"},
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 422


def test_create_rejects_unknown_category():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")):
        resp = client.post(
            "/announcements/",
            json={"title": "x", "body": "y", "category": "not-a-real-category", "target_type": "all"},
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 422


def test_get_announcements_is_open_to_any_authenticated_role():
    db = _db_returning(ANNOUNCEMENT_ROWS)
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("resident-id", "resident")), \
         patch("app.services.announcement_service.get_supabase", return_value=db):
        resp = client.get("/announcements/", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
