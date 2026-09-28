"""
POST /responder/queue/{id}/escalate — Responder spec Section 14.

"The situation is worse than assessed." Deliberately does not touch
incidents.severity — see responder_ops_service.escalate_incident's
docstring for why that stays the Agency Admin's decision. Mirrors
TestAccept's fixtures in test_responder_accountability.py.

Run with: pytest tests/test_responder_escalate.py -v
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

RESPONDER_UUID = "00000000-0000-0000-0000-0000000000aa"
OTHER_UUID = "00000000-0000-0000-0000-0000000000bb"
INCIDENT_UUID = str(uuid4())


def _auth_responder():
    mock_user = MagicMock()
    mock_user.id = RESPONDER_UUID
    mock_get = MagicMock()
    mock_get.user = mock_user

    profile = MagicMock()
    profile.data = {
        "id": RESPONDER_UUID,
        "email": "responder@example.com",
        "full_name": "Test Responder",
        "role": "responder",
        "approval_status": "approved",
        "agency_id": "agency-1",
        "badge_id": "B-1",
        "is_verified": True,
    }

    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = profile
    return db


def _ops_db(incident: dict):
    loaded = MagicMock()
    loaded.data = incident

    db = MagicMock()
    db.table.return_value.select.return_value \
        .eq.return_value.maybe_single.return_value.execute.return_value = loaded
    return db


def _call(method, path, ops_db, body=None):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_responder()), \
         patch("app.services.responder_ops_service.get_supabase", return_value=ops_db):
        fn = getattr(client, method)
        kwargs = {"headers": {"Authorization": "Bearer token"}}
        if body is not None:
            kwargs["json"] = body
        return fn(path, **kwargs)


def _incident(assigned_responder_id=RESPONDER_UUID, agency_id="agency-1", severity="medium"):
    return {
        "id": INCIDENT_UUID,
        "severity": severity,
        "assigned_responder_id": assigned_responder_id,
        "assigned_agency_id": agency_id,
    }


def test_escalating_returns_the_reason_and_does_not_touch_severity():
    db = _ops_db(_incident(severity="medium"))
    r = _call(
        "post", f"/responder/queue/{INCIDENT_UUID}/escalate", db,
        body={"reason": "Fire has spread to the second floor."},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["incident_id"] == INCIDENT_UUID
    assert body["reason"] == "Fire has spread to the second floor."
    # No update() call at all — nothing on the incident row changes.
    db.table.return_value.update.assert_not_called()


def test_empty_reason_is_rejected():
    db = _ops_db(_incident())
    r = _call(
        "post", f"/responder/queue/{INCIDENT_UUID}/escalate", db,
        body={"reason": "   "},
    )
    assert r.status_code == 422


def test_somebody_elses_incident_is_403():
    db = _ops_db(_incident(assigned_responder_id=OTHER_UUID))
    r = _call(
        "post", f"/responder/queue/{INCIDENT_UUID}/escalate", db,
        body={"reason": "Multiple casualties."},
    )
    assert r.status_code == 403


def test_missing_incident_is_404():
    empty = MagicMock()
    empty.data = None
    db = MagicMock()
    db.table.return_value.select.return_value \
        .eq.return_value.maybe_single.return_value.execute.return_value = empty
    r = _call(
        "post", f"/responder/queue/{INCIDENT_UUID}/escalate", db,
        body={"reason": "Additional agency required."},
    )
    assert r.status_code == 404


def test_a_notification_failure_does_not_fail_the_request():
    """The escalation itself must land even if the notification fan-out
    cannot reach the database — the responder's flag is the thing that must
    not be lost, and the notification is best-effort on top of it."""
    db = _ops_db(_incident())
    r = _call(
        "post", f"/responder/queue/{INCIDENT_UUID}/escalate", db,
        body={"reason": "Additional BFP unit needed."},
    )
    assert r.status_code == 200, r.text
