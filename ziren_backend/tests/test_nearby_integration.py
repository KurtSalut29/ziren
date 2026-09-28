"""The proximity feature wired into the rest of the backend.

  * a NEW report tells the near responders as well as the agency's admins, and a
    failure in the responder half can never cost the resident their report;
  * the dispatcher's incident detail carries who is near (sorted, with state,
    distance and what each is already committed to) and how far the routed station
    is - and a failure computing that never stops the detail loading;
  * the endpoints: who may call them, and what they return;
  * every distance the backend uses is now the same ellipsoidal one.

Run with: pytest tests/test_nearby_integration.py -v
"""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.core import geo
from app.main import app
from app.models.incident import SubmissionChannel
from app.services import dispatch_service, incident_service, notification_service
from app.services import proximity as px
from tests.fake_db import FakeDB
from tests.test_proximity import (
    AGENCY, NOW, OTHER_AGENCY, SCENE_LAT, SCENE_LNG, _incident, _point, _user, at_distance, world,
)

client = TestClient(app)


@pytest.fixture(autouse=True)
def _forget_who_was_recorded():
    px.clear_memory()
    yield
    px.clear_memory()


@pytest.fixture(autouse=True)
def _clock_at_now():
    # world() stamps every GPS fix relative to the fixed NOW. These tests reach
    # proximity through endpoints that cannot pass `now`, so without pinning the
    # clock every fix ages past fix_max_age_s a few minutes after NOW and the
    # whole file starts failing on its own, with no code change at all.
    with patch("app.services.proximity._now", return_value=NOW):
        yield


# =============================================================================
# A new report reaches the responders too
# =============================================================================

def _triage(severity="critical"):
    return {
        "severity": SimpleNamespace(value=severity),
        "signals": {"verification_status": "OK", "severity_rule": "test", "engine_version": "t"},
    }


def _create(db, *, severity="critical"):
    with patch("app.services.incident_service.triage_service.triage", return_value=_triage(severity)), \
         patch("app.services.incident_service.notification_service.create_for_agency_role") as admins:
        row = incident_service._create_incident_row(
            db=db, reporter_id="resident-1", report_text="Kitchen fire spreading",
            station_id="station-1", agency_id=AGENCY, latitude=SCENE_LAT, longitude=SCENE_LNG,
            location_address="Brgy Casiawan, Cabucgayan", media_urls=[],
            submitted_via=SubmissionChannel.internet,
        )
    return row, admins


def _db_for_creation():
    db = world()
    # Drop only the NEW report (the code under test inserts it); keep I0, the call
    # the busy responder is already on.
    db.tables["incidents"] = [i for i in db.tables["incidents"] if i["id"] == "I0"]
    return db


def test_a_new_report_tells_the_near_responders_as_well_as_the_agencys_admins():
    db = _db_for_creation()
    row, admins = _create(db)

    admins.assert_called_once()                                        # unchanged: the agency is told
    assert admins.call_args.args == (AGENCY, "agency_admin")

    told = {r["recipient_id"]: r for r in db.inserted["notifications"] if r["type"] == px.TYPE_NEARBY}
    assert set(told) >= {"R1", "R2"}                                   # free and in range
    assert told["R1"]["metadata"]["incident_id"] == row["id"]
    assert told["R1"]["metadata"]["level"] == "alarm" and told["R1"]["is_important"] is True
    # the ranking was measured from the coordinates the resident sent
    assert told["R1"]["metadata"]["distance_m"] == 1_000


def test_the_busy_responder_is_advised_quietly_of_a_critical_report():
    db = _db_for_creation()
    _create(db, severity="critical")
    r3 = next(r for r in db.inserted["notifications"] if r["recipient_id"] == "R3")
    assert r3["metadata"]["level"] == "advisory" and r3["metadata"]["reason"] == "escalation"
    assert r3["is_important"] is False


def test_a_failure_telling_the_responders_never_costs_the_resident_their_report():
    db = _db_for_creation()
    db.fail_on_insert = set()
    with patch("app.services.incident_service.proximity.notify_nearby", side_effect=RuntimeError("boom")):
        row, admins = _create(db)
    assert row["id"] and db.rows("incidents")[-1]["id"] == row["id"]    # the report is saved
    admins.assert_called_once()                                         # and the admins were told


def test_no_responder_is_told_when_the_notification_write_fails_but_the_report_still_lands():
    db = _db_for_creation()
    db.fail_on_insert = {"notifications"}
    row, admins = _create(db)
    assert row["id"]
    admins.assert_called_once()


# =============================================================================
# The dispatcher's detail carries who is near
# =============================================================================

def _detail_db():
    db = world()
    inc = db.tables["incidents"][1]
    inc["stations"] = {"name": "BFP Naval", "address": "Poblacion", "location": _point(2_345, 90),
                       "agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Naval", "contact_number": None}}
    inc["responder"] = None
    inc["users"] = {"id": "resident-1", "full_name": "Resident One"}
    db.tables["dispatch_log"] = []
    return db


ADMIN = {"id": "admin-1", "role": "agency_admin", "agency_id": AGENCY, "full_name": "Ad Min"}


def test_the_detail_lists_the_responders_nearest_and_freest_first_with_their_state_and_distance():
    db = _detail_db()
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        out = dispatch_service.get_incident_detail_admin("I1", ADMIN)

    rows = out["available_responders"]
    ids = [r["id"] for r in rows]
    # Ana (free, 1 km) before Ben (free, 4 km) before Cara (busy) before Dan (no position); the admin last.
    assert ids[:4] == ["R1", "R2", "R3", "R7"] and ids[-1] == "admin-1"
    ana, ben, cara, dan = rows[:4]
    assert ana["state"] == "free" and ana["distance_km"] == 1.0 and ana["eta_min"] == 3 and ana["level"] == "alarm"
    assert ben["distance_km"] == 4.0
    assert cara["state"] == "en_route" and cara["current_calls"][0]["incident_id"] == "I0"
    assert dan["located"] is False and dan["distance_km"] is None
    assert "distance_km" not in rows[-1]                     # the admin's own "yourself" entry is not a responder
    assert out["nearby"]["summary"]["on_duty"] == 4 and out["nearby"]["policy"]["radius_km"] == 10.0
    assert out["station_distance_km"] == 2.35                # how far the routed station is from the report


def test_the_detail_still_loads_when_the_ranking_fails():
    db = _detail_db()
    with patch("app.services.dispatch_service.get_supabase", return_value=db), \
         patch("app.services.dispatch_service.proximity.nearby_for_admin", side_effect=RuntimeError("boom")):
        out = dispatch_service.get_incident_detail_admin("I1", ADMIN)
    assert out["nearby"] is None
    assert [r["id"] for r in out["available_responders"]][:4] == ["R1", "R2", "R3", "R7"]   # plain roster, unsorted


def test_an_incident_with_no_agency_has_no_ranking_and_no_error():
    db = _detail_db()
    db.tables["incidents"][1]["assigned_agency_id"] = None
    admin = {**ADMIN, "role": "provincial_admin", "agency_type": "BFP", "agency_id": None}
    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        out = dispatch_service.get_incident_detail_admin("I1", admin)
    assert out["nearby"] is None and out["available_responders"] == []


# =============================================================================
# The endpoints
# =============================================================================

def _auth_db(user_id, role, agency_id=AGENCY, agency_type="BFP", full_name="Test User"):
    mock_get = MagicMock()
    mock_get.user = MagicMock(id=user_id)
    profile = MagicMock()
    profile.data = {
        "id": user_id, "email": f"{user_id}@example.com", "full_name": full_name, "role": role,
        "approval_status": "approved" if role == "responder" else "not_required",
        "agency_id": agency_id, "agency_type": agency_type, "badge_id": None, "is_verified": True,
    }
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


HEADERS = {"Authorization": "Bearer token"}


def test_a_responder_reads_what_is_near_them():
    data_db = world()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("R1", "responder")), \
         patch("app.routers.responder.get_supabase", return_value=data_db):
        r = client.get("/responder/nearby", headers=HEADERS)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["on_duty"] is True and [i["incident_id"] for i in body["items"]] == ["I1"]
    assert body["items"][0]["level"] == "alarm" and body["items"][0]["distance_m"] == 1000


def test_the_phones_own_position_is_passed_through_and_validated():
    data_db = world()
    lat, lng = at_distance(500, 45)
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("R2", "responder")), \
         patch("app.routers.responder.get_supabase", return_value=data_db):
        ok = client.get(f"/responder/nearby?latitude={lat}&longitude={lng}", headers=HEADERS)
        bad = client.get("/responder/nearby?latitude=95&longitude=0", headers=HEADERS)
    assert ok.status_code == 200 and ok.json()["position"] == "device" and ok.json()["items"][0]["distance_m"] == 500
    assert bad.status_code == 422


@pytest.mark.parametrize("role", ["resident", "agency_admin", "provincial_admin"])
def test_only_a_responder_may_read_or_answer_nearby(role):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("U1", role)):
        assert client.get("/responder/nearby", headers=HEADERS).status_code == 403
        assert client.post("/responder/nearby/I1/answer", json={"answer": "can_respond"}, headers=HEADERS).status_code == 403


def test_a_responder_answers_and_the_admins_are_told():
    data_db = world()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("R1", "responder", full_name="Ana Free")), \
         patch("app.routers.responder.get_supabase", return_value=data_db), \
         patch("app.services.proximity.notification_service.create_for_agency_role") as notify:
        r = client.post("/responder/nearby/I1/answer", json={"answer": "can_respond"}, headers=HEADERS)
    assert r.status_code == 200, r.text
    assert r.json()["answer"] == "can_respond"
    notify.assert_called_once()
    assert data_db.rows("incidents")[1]["assigned_responder_id"] is None        # nothing was assigned


def test_an_unknown_answer_is_a_422_that_names_the_choices():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("R1", "responder")), \
         patch("app.routers.responder.get_supabase", return_value=world()):
        r = client.post("/responder/nearby/I1/answer", json={"answer": "maybe"}, headers=HEADERS)
    assert r.status_code == 422 and "can_respond" in r.json()["detail"]


def _panel(role, **auth):
    data_db = world()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("A1", role, **auth)), \
         patch("app.services.dispatch_service.get_supabase", return_value=data_db):
        return client.get("/dispatch/queue/I1/nearby-responders", headers=HEADERS)


def test_an_agency_admin_sees_who_is_near_their_incident():
    data_db = world()
    data_db.tables["incidents"][1]["stations"] = {"agencies": {"agency_type": "BFP"}}
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("A1", "agency_admin")), \
         patch("app.services.dispatch_service.get_supabase", return_value=data_db):
        r = client.get("/dispatch/queue/I1/nearby-responders", headers=HEADERS)
    assert r.status_code == 200, r.text
    body = r.json()
    assert [x["responder_id"] for x in body["responders"]][:3] == ["R1", "R2", "R3"]
    assert body["summary"]["notified"] == 3


def test_another_agencys_admin_is_refused():
    assert _panel("agency_admin", agency_id=OTHER_AGENCY).status_code == 403


def test_a_provincial_admin_of_the_same_type_may_look_and_another_type_may_not():
    data_db = world()
    data_db.tables["incidents"][1]["stations"] = {"agencies": {"agency_type": "BFP"}}
    with patch("app.services.dispatch_service.get_supabase", return_value=data_db):
        with patch("app.core.dependencies.get_supabase", return_value=_auth_db("P1", "provincial_admin", agency_id=None, agency_type="BFP")):
            assert client.get("/dispatch/queue/I1/nearby-responders", headers=HEADERS).status_code == 200
        from app.core.dependencies import clear_user_cache
        clear_user_cache()
        with patch("app.core.dependencies.get_supabase", return_value=_auth_db("P2", "provincial_admin", agency_id=None, agency_type="PNP")):
            assert client.get("/dispatch/queue/I1/nearby-responders", headers=HEADERS).status_code == 403


def test_a_resident_or_responder_cannot_read_the_dispatchers_panel():
    for role in ("resident", "responder"):
        from app.core.dependencies import clear_user_cache
        clear_user_cache()
        with patch("app.core.dependencies.get_supabase", return_value=_auth_db("U1", role)):
            assert client.get("/dispatch/queue/I1/nearby-responders", headers=HEADERS).status_code == 403


def test_an_unknown_incident_is_a_404():
    data_db = world()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("A1", "agency_admin")), \
         patch("app.services.dispatch_service.get_supabase", return_value=data_db):
        assert client.get("/dispatch/queue/NOPE/nearby-responders", headers=HEADERS).status_code == 404


# =============================================================================
# One distance for the whole backend
# =============================================================================

def test_the_stations_are_chosen_by_the_ellipsoidal_distance():
    """Two stations, one truly nearer by the geodesic but FARTHER by the sphere's
    reckoning would be needed to see a different pick; here we pin the function
    the router shares and that it is the geodesic, not the sphere."""
    a = (11.56, 124.40, 11.65, 124.40)
    assert incident_service._distance_km(*a) == pytest.approx(geo.geodesic_km(*a), abs=1e-9)
    assert incident_service._distance_km(*a) == pytest.approx(9.9557, abs=0.0005)     # not 10.0075
    assert not hasattr(incident_service, "_haversine")


def test_the_eta_a_responders_ping_writes_is_the_shared_model():
    from app.services import responder_ops_service as ops
    assert ops._ASSUMED_SPEED_KMH == geo.ASSUMED_SPEED_KMH
    db = FakeDB({"incidents": [{
        "id": "I9", "status": "en_route", "assigned_responder_id": "R1", "location": _point(0),   # at the scene
    }]})
    here = at_distance(3_000, 180)                                                      # 3 km from the scene
    out = ops.refresh_eta("R1", *here, db=db)
    expected = geo.estimate_eta_minutes(geo.geodesic_km(*here, SCENE_LAT, SCENE_LNG))
    assert out == [{"incident_id": "I9", "eta_minutes": expected}]
    assert expected in (6, 7)                       # 3 km at 30 km/h is 6 minutes, rounded up


# =============================================================================
# The notification helper carries metadata now
# =============================================================================

def test_create_for_agency_role_can_carry_metadata_and_omits_it_otherwise():
    db = FakeDB({"users": [
        {"id": "adm1", "agency_id": AGENCY, "role": "agency_admin"},
        {"id": "adm2", "agency_id": AGENCY, "role": "agency_admin"},
        {"id": "resp", "agency_id": AGENCY, "role": "responder"},
        {"id": "adm9", "agency_id": OTHER_AGENCY, "role": "agency_admin"},
    ]})
    with patch("app.services.notification_service.get_supabase", return_value=db):
        notification_service.create_for_agency_role(AGENCY, "agency_admin", type_="t", title="x", metadata={"incident_id": "I1"})
        notification_service.create_for_agency_role(AGENCY, "agency_admin", type_="t2", title="y")
    with_meta = [r for r in db.inserted["notifications"] if r["type"] == "t"]
    without = [r for r in db.inserted["notifications"] if r["type"] == "t2"]
    assert {r["recipient_id"] for r in with_meta} == {"adm1", "adm2"}
    assert all(r["metadata"] == {"incident_id": "I1"} for r in with_meta)
    assert all("metadata" not in r for r in without)
