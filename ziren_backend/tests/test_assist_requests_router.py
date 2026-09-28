"""Router-level checks for /assist-requests: role enforcement and that each
route reaches the right service function. Service logic itself is covered
by tests/test_assist_requests.py — these tests only prove the wiring."""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

AGENCY_ADMIN_USER = {"id": "u1", "role": "agency_admin", "agency_id": "a1", "full_name": "Admin"}
RESPONDER_USER = {"id": "u2", "role": "responder", "agency_id": "a1", "full_name": "Resp"}
PROVINCIAL_ADMIN_USER = {"id": "u3", "role": "provincial_admin", "agency_type": "BFP", "full_name": "Provincial"}


def _as(user):
    from app.core.dependencies import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user


def teardown_function():
    app.dependency_overrides.clear()


def test_responder_forbidden_from_every_route():
    _as(RESPONDER_USER)
    assert client.get("/assist-requests?scope=sent").status_code == 403
    assert client.get("/assist-requests/candidates?incident_id=i1").status_code == 403
    assert client.post("/assist-requests", json={"incident_id": "i1", "requested_agency_id": "a2", "message": "hi"}).status_code == 403
    assert client.get("/assist-requests/r1").status_code == 403
    assert client.post("/assist-requests/r1/messages", json={"body": "hi"}).status_code == 403
    assert client.patch("/assist-requests/r1/status", json={"status": "acknowledged"}).status_code == 403


def test_list_route_reaches_list_for_agency():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.list_for_agency", return_value=[]) as mock_fn:
        res = client.get("/assist-requests?scope=received")
    assert res.status_code == 200
    assert res.json() == []
    mock_fn.assert_called_once_with(AGENCY_ADMIN_USER, "received", incident_id=None)


def test_candidates_route_does_not_collide_with_the_id_route():
    """/assist-requests/candidates must resolve to the candidates handler,
    not be swallowed by GET /assist-requests/{request_id} — this only
    passes if candidates() is registered before the {request_id} route."""
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.list_candidate_agencies", return_value=[]) as mock_fn:
        res = client.get("/assist-requests/candidates?incident_id=i1")
    assert res.status_code == 200
    mock_fn.assert_called_once_with("i1", AGENCY_ADMIN_USER)


def test_create_route_reaches_create_request_with_all_fields():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.create_request", return_value={"id": "r1"}) as mock_fn:
        res = client.post("/assist-requests", json={
            "incident_id": "i1", "requested_agency_id": "a2", "message": "help", "overlap_flag": "fire",
        })
    assert res.status_code == 200
    mock_fn.assert_called_once_with("i1", "a2", "help", "fire", AGENCY_ADMIN_USER)


def test_thread_route_reaches_get_thread():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.get_thread", return_value={"id": "r1"}) as mock_fn:
        res = client.get("/assist-requests/r1")
    assert res.status_code == 200
    mock_fn.assert_called_once_with("r1", AGENCY_ADMIN_USER)


def test_messages_route_reaches_post_message():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.post_message", return_value={"id": "m1"}) as mock_fn:
        res = client.post("/assist-requests/r1/messages", json={"body": "test message"})
    assert res.status_code == 200
    mock_fn.assert_called_once_with("r1", "test message", AGENCY_ADMIN_USER)


def test_status_route_reaches_set_status():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.set_status", return_value={"id": "r1", "status": "acknowledged"}) as mock_fn:
        res = client.patch("/assist-requests/r1/status", json={"status": "acknowledged"})
    assert res.status_code == 200
    mock_fn.assert_called_once_with("r1", "acknowledged", AGENCY_ADMIN_USER)


def test_provincial_admin_can_read_but_not_write():
    """Migration 037 / oversight read: list and thread open to provincial_admin;
    candidates/create/messages/status stay agency_admin only (Global Constraints)."""
    _as(PROVINCIAL_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.list_for_agency", return_value=[]) as mock_fn:
        res = client.get("/assist-requests")
    assert res.status_code == 200
    mock_fn.assert_called_once_with(PROVINCIAL_ADMIN_USER, None, incident_id=None)

    with patch("app.routers.assist_requests.assist_request_service.get_thread", return_value={"id": "r1"}):
        assert client.get("/assist-requests/r1").status_code == 200

    assert client.get("/assist-requests/candidates?incident_id=i1").status_code == 403
    assert client.post("/assist-requests", json={"incident_id": "i1", "requested_agency_id": "a2", "message": "hi"}).status_code == 403
    assert client.post("/assist-requests/r1/messages", json={"body": "hi"}).status_code == 403
    assert client.patch("/assist-requests/r1/status", json={"status": "acknowledged"}).status_code == 403


def test_list_route_passes_incident_id_and_all_scope():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.list_for_agency", return_value=[]) as mock_fn:
        res = client.get("/assist-requests?scope=all&incident_id=i9")
    assert res.status_code == 200
    mock_fn.assert_called_once_with(AGENCY_ADMIN_USER, "all", incident_id="i9")
