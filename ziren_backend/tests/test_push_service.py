"""Evaluator findings #11 / #12: notices reach a phone with the app closed.

Push goes through FCM HTTP v1 with a service account. These pin that it is
off without configuration, that every stored notification is offered to it,
that a dispatch pushes to the responder, how the request to FCM is built, and
that a dead token is forgotten. No network: httpx and the database are faked.

Run with: pytest tests/test_push_service.py -v
"""

import json
from unittest.mock import MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.services import notification_service, push_service


@pytest.fixture()
def service_account(monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    info = {"project_id": "ziren-test", "client_email": "push@ziren-test.iam.gserviceaccount.com",
            "private_key": pem}
    monkeypatch.setenv("FCM_SERVICE_ACCOUNT_JSON", json.dumps(info))
    push_service._cache.update(token=None, exp=0.0)
    return key


def test_push_is_off_without_a_service_account(monkeypatch):
    monkeypatch.delenv("FCM_SERVICE_ACCOUNT_JSON", raising=False)
    with patch.object(push_service, "_pool") as pool:
        push_service.send_to_users(["u1"], title="x")
    assert not push_service.enabled()
    assert not pool.submit.called


def test_every_stored_notification_is_offered_to_push():
    db = MagicMock()
    with patch("app.services.notification_service.get_supabase", return_value=db), \
         patch.object(notification_service.push_service, "send_to_users") as send:
        notification_service.notify_reporter("u1", incident_id="inc-1", type_="incident.message",
                                             title="New message", body="Please confirm the address",
                                             at="2026-10-05T00:00:00Z", important=True)
    kwargs = send.call_args.kwargs
    assert send.call_args.args[0] == ["u1"]
    assert kwargs["title"] == "New message" and kwargs["important"] is True
    assert kwargs["data"]["incident_id"] == "inc-1" and kwargs["data"]["type"] == "incident.message"


def _db_with_tokens(tokens):
    db = MagicMock()
    db.table.return_value.select.return_value.in_.return_value.execute.return_value = MagicMock(
        data=[{"token": t} for t in tokens])
    return db


def test_a_push_is_signed_with_the_service_account_and_sent_to_each_phone(service_account):
    db = _db_with_tokens(["tok-aaaaaaaaaaaaaaaaaaaaaaaa", "tok-bbbbbbbbbbbbbbbbbbbbbbbb"])
    posts = []

    def token_post(url, data, timeout):
        claims = jwt.decode(data["assertion"], service_account.public_key(), algorithms=["RS256"],
                            audience=push_service._TOKEN_URL)
        assert claims["scope"] == push_service._SCOPE
        r = MagicMock(); r.json.return_value = {"access_token": "at-1", "expires_in": 3600}
        return r

    class Client:
        def __init__(self, **kw): self.headers = kw["headers"]
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def post(self, url, json):
            posts.append((url, self.headers, json))
            return MagicMock(status_code=200, text="{}")

    with patch.object(push_service, "get_supabase", return_value=db), \
         patch.object(push_service.httpx, "post", side_effect=token_post), \
         patch.object(push_service.httpx, "Client", Client):
        push_service._deliver(["u1"], "A responder is on the way", "ETA 6 min",
                              {"incident_id": "inc-1", "count": 2}, True)

    assert len(posts) == 2
    url, headers, body = posts[0]
    assert url.endswith("/projects/ziren-test/messages:send")
    assert headers["Authorization"] == "Bearer at-1"
    msg = body["message"]
    assert msg["notification"]["title"] == "A responder is on the way"
    assert msg["android"]["priority"] == "HIGH"
    assert msg["data"] == {"incident_id": "inc-1", "count": "2"}, "FCM data values must be strings"


def test_a_dead_token_is_forgotten(service_account):
    db = _db_with_tokens(["tok-deadxxxxxxxxxxxxxxxxxxxx"])

    class Client:
        def __init__(self, **kw): pass
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def post(self, url, json):
            return MagicMock(status_code=404, text='{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}')

    token_resp = MagicMock(); token_resp.json.return_value = {"access_token": "at", "expires_in": 3600}
    with patch.object(push_service, "get_supabase", return_value=db), \
         patch.object(push_service.httpx, "post", return_value=token_resp), \
         patch.object(push_service.httpx, "Client", Client):
        push_service._deliver(["u1"], "x", None, {}, False)
    db.table.return_value.delete.return_value.eq.assert_called_with("token", "tok-deadxxxxxxxxxxxxxxxxxxxx")


def test_a_responder_alert_is_data_only_so_the_app_can_raise_the_full_screen_alarm(service_account):
    """An FCM `notification` block is drawn by Android as a plain banner; the
    full-screen, over-the-lock-screen alarm needs the app to draw it."""
    msg = push_service._message("tok", "New assignment", "HIGH incident", {"ziren_alert": "assignment"},
                                True, None, True, 600)
    assert "notification" not in msg and "notification" not in msg["android"]
    assert msg["android"] == {"priority": "HIGH", "ttl": "600s"}
    assert msg["data"]["ziren_alert"] == "assignment"

    with patch.object(push_service, "_pool") as pool:
        push_service.send_alert_to_users(["r1"], kind="nearby", title="New HIGH incident near you",
                                         body="Brgy X - 1.0 km", data={"incident_id": "inc-1", "distance_m": 1000})
    args = pool.submit.call_args.args
    payload = args[4]
    assert payload["ziren_alert"] == "nearby" and payload["incident_id"] == "inc-1"
    assert payload["title"] == "New HIGH incident near you" and payload["body"] == "Brgy X - 1.0 km"
    assert args[7] is True                                            # alert


def test_an_unknown_alert_kind_is_refused():
    with pytest.raises(ValueError):
        push_service.send_alert_to_users(["r1"], kind="party", title="x")


def test_a_dispatch_alerts_the_responder_with_the_full_screen_alarm():
    import inspect
    from app.services import dispatch_service

    src = inspect.getsource(dispatch_service.assign_responder)
    assert "send_alert_to_users" in src and 'kind="assignment"' in src


def test_requirements_install_what_rs256_signing_needs():
    """The first live push failed with "Algorithm 'RS256' could not be found":
    PyJWT came in through supabase without its crypto extra, and only the dev
    venv happened to have `cryptography`. The test above signs with RS256 and
    passed locally, so pin the dependency itself."""
    from pathlib import Path

    reqs = (Path(__file__).resolve().parents[1] / "requirements.txt").read_text(encoding="utf-8").lower()
    lines = [ln.split("#")[0].strip() for ln in reqs.splitlines()]
    assert any(ln.startswith("cryptography") for ln in lines)
    assert any(ln.startswith("pyjwt[crypto]") for ln in lines)


def test_registering_a_token_validates_it():
    with pytest.raises(ValueError):
        push_service.register_token("u1", "short")


def test_sign_out_forgets_the_token_sent_in_the_body_not_the_url():
    """The DELETE ?token= form wrote every phone's token into the access log."""
    from fastapi.testclient import TestClient
    from app.core.dependencies import get_current_user
    from app.main import app

    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "role": "resident"}
    try:
        with patch.object(push_service, "forget_token") as forget:
            r = TestClient(app).post("/users/me/push-token/forget", json={"token": "tok-" + "x" * 30})
        assert r.status_code == 204
        forget.assert_called_once_with("u1", "tok-" + "x" * 30)
    finally:
        app.dependency_overrides.clear()
