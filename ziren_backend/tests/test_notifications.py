"""
notification_service + /notifications router.

Covers:
  - create_for_roles excludes the actor and inserts one row per matching-role user
  - create_for_agency scopes to one agency
  - GET /notifications/ returns only the caller's own rows
  - PATCH /notifications/{id}/read 404s for a notification belonging to someone
    else (not 403 — existence isn't leaked)
  - PATCH /notifications/read-all marks every unread row read

Run: pytest tests/test_notifications.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import notification_service

client = TestClient(app)

USER_UUID  = "00000000-0000-0000-0000-0000000000aa"
OTHER_UUID = "00000000-0000-0000-0000-0000000000bb"


# ── notification_service ────────────────────────────────────────────────

def test_create_for_roles_excludes_the_actor_and_inserts_one_row_per_recipient():
    db = MagicMock()
    users_result = MagicMock()
    users_result.data = [{"id": "u1"}, {"id": "u2"}, {"id": USER_UUID}]
    db.table.return_value.select.return_value.in_.return_value.execute.return_value = users_result

    with patch("app.services.notification_service.get_supabase", return_value=db):
        notification_service.create_for_roles(
            roles=("provincial_admin",), type_="station.created", title="New station",
            exclude_user_id=USER_UUID,
        )

    insert_call = db.table.return_value.insert.call_args[0][0]
    recipient_ids = {row["recipient_id"] for row in insert_call}
    assert recipient_ids == {"u1", "u2"}
    assert USER_UUID not in recipient_ids


def test_create_for_roles_with_no_recipients_does_not_insert():
    db = MagicMock()
    users_result = MagicMock()
    users_result.data = []
    db.table.return_value.select.return_value.in_.return_value.execute.return_value = users_result

    with patch("app.services.notification_service.get_supabase", return_value=db):
        notification_service.create_for_roles(roles=("provincial_admin",), type_="x", title="x")

    db.table.return_value.insert.assert_not_called()


def test_create_for_agency_scopes_to_one_agency():
    db = MagicMock()
    users_result = MagicMock()
    users_result.data = [{"id": "u1"}, {"id": "u2"}]
    db.table.return_value.select.return_value.eq.return_value.execute.return_value = users_result

    with patch("app.services.notification_service.get_supabase", return_value=db):
        notification_service.create_for_agency("agency-1", type_="announcement.published", title="Notice")

    db.table.return_value.select.return_value.eq.assert_called_with("agency_id", "agency-1")
    insert_call = db.table.return_value.insert.call_args[0][0]
    assert {row["recipient_id"] for row in insert_call} == {"u1", "u2"}


# ── router ───────────────────────────────────────────────────────────────

def _profile(user_id):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": "provincial_admin", "approval_status": "not_required",
        "agency_id": None, "badge_id": None, "is_verified": True,
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
    return db


def test_list_notifications_filters_to_the_caller():
    result = MagicMock()
    result.data = [{"id": "n1", "recipient_id": USER_UUID}]
    result.count = 1
    unread_result = MagicMock()
    unread_result.count = 1

    service_db = MagicMock()
    chain = service_db.table.return_value.select.return_value.eq.return_value.order.return_value
    chain.range.return_value.execute.return_value = result
    service_db.table.return_value.select.return_value.eq.return_value.eq.return_value.execute.return_value = unread_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(USER_UUID)), \
         patch("app.services.notification_service.get_supabase", return_value=service_db):
        resp = client.get("/notifications/", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200
    eq_call = service_db.table.return_value.select.return_value.eq.call_args[0]
    assert eq_call == ("recipient_id", USER_UUID)


def test_mark_read_404s_for_someone_elses_notification():
    service_db = MagicMock()
    result = MagicMock()
    result.data = []  # no row matched id AND recipient_id -> not found/not owned
    service_db.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value = result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(USER_UUID)), \
         patch("app.services.notification_service.get_supabase", return_value=service_db):
        resp = client.patch("/notifications/not-mine/read", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 404


def test_mark_all_read_returns_updated_count():
    service_db = MagicMock()
    result = MagicMock()
    result.data = [{"id": "n1"}, {"id": "n2"}]
    service_db.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value = result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(USER_UUID)), \
         patch("app.services.notification_service.get_supabase", return_value=service_db):
        resp = client.patch("/notifications/read-all", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200
    assert resp.json() == {"updated": 2}
