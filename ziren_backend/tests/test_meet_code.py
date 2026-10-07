"""The Ziren code: how a crew identifies the reporter without judging how
they look (app/core/meet_code.py)."""

import uuid

from app.core.meet_code import meet_code
from app.models.incident import IncidentResponse


def test_four_digits_stable_and_per_report():
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    assert meet_code(a) == meet_code(a)
    assert len(meet_code(a)) == 4 and meet_code(a).isdigit()
    codes = {meet_code(str(uuid.uuid4())) for _ in range(200)}
    assert len(codes) > 150  # spread, not a constant


def test_it_depends_on_the_server_secret(monkeypatch):
    from app.core import meet_code as mc
    # Fixed id, so a 1-in-10000 collision cannot make this flaky.
    iid2 = "00000000-0000-4000-8000-000000000001"
    monkeypatch.setattr(mc.settings, "secret_key", "secret-one")
    one = meet_code(iid2)
    monkeypatch.setattr(mc.settings, "secret_key", "secret-two")
    assert meet_code(iid2) != one


def test_the_reporter_gets_it_with_their_report():
    iid = uuid.uuid4()
    now = "2026-10-07T00:00:00+00:00"
    r = IncidentResponse(
        id=iid, reporter_id=uuid.uuid4(), station_id=None, report_text="x",
        location_address=None, latitude=None, longitude=None, status="received",
        severity=None, suggested_agency_id=None, assigned_agency_id=None, signals=None,
        signals_confidence=None, submitted_via="internet", created_at=now, updated_at=now,
        dispatched_at=None, resolved_at=None,
    )
    assert r.model_dump()["meet_code"] == meet_code(iid)


def test_responder_and_dispatcher_payloads_carry_it():
    import inspect
    from app.services import dispatch_service, responder_service
    assert 'row["meet_code"]' in inspect.getsource(responder_service.get_incident_detail)
    assert 'row["meet_code"]' in inspect.getsource(dispatch_service.get_incident_detail_admin)
