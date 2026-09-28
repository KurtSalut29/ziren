"""Who is told about a new incident, how loudly - and what happens to a busy responder.

The rule under test (see app.services.proximity for the reasoning):

  * Responders ON DUTY and NEAR a new incident are told at once, without waiting
    for a dispatcher to assign them. Near = ellipsoidal (Vincenty) distance from
    a FRESH position, within a radius that grows with severity.
  * A FREE responder in range gets the full alert. A BUSY one - already
    dispatched, en route or on scene - is never alarmed just for being close: it
    gets a quiet advisory only when the new incident is MORE severe than what it
    already holds, or when nobody free is in range (and never if on scene for the
    latter). Nothing here ever assigns or reassigns anything.
  * Nobody is left untold: if no free unit is in range the net widens.

Pure-function tests use Unit/Scene directly; the database layer is exercised
against an in-memory double that really evaluates the queries.

Run with: pytest tests/test_proximity.py -v
"""

import math
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.core import geo
from app.services import proximity as px
from tests.fake_db import FakeDB

NOW = datetime(2026, 9, 25, 12, 0, 0, tzinfo=timezone.utc)
SCENE_LAT, SCENE_LNG = 11.5600, 124.4000
AGENCY = "agency-bfp-naval"
OTHER_AGENCY = "agency-pnp-naval"


@pytest.fixture(autouse=True)
def _forget_who_was_recorded():
    px.clear_memory()
    yield
    px.clear_memory()


def at_distance(meters: float, bearing: float = 0.0) -> tuple[float, float]:
    """A point `meters` (geodesic, to a millimetre) from the scene on `bearing`."""
    if meters == 0:
        return SCENE_LAT, SCENE_LNG
    b = math.radians(bearing)
    scale = 1.0
    lat = lng = 0.0
    for _ in range(8):
        lat = SCENE_LAT + math.cos(b) * meters * scale / 110574.0
        lng = SCENE_LNG + math.sin(b) * meters * scale / (111319.49 * math.cos(math.radians(SCENE_LAT)))
        scale *= meters / geo.geodesic_m(SCENE_LAT, SCENE_LNG, lat, lng)
    return lat, lng


def unit(uid, meters=None, *, bearing=0.0, age=30, calls=(), name=None) -> px.Unit:
    """A responder `meters` from the scene. `calls` is [(status, severity), ...]."""
    lat = lng = None
    if meters is not None:
        lat, lng = at_distance(meters, bearing)
    return px.Unit(
        id=uid, full_name=name or uid, badge_id=None, lat=lat, lng=lng,
        fix_age_s=age if meters is not None else None,
        calls=[{"id": f"call-{uid}-{i}", "status": s, "severity": sev, "category": "fire", "address": "Brgy 1"}
               for i, (s, sev) in enumerate(calls)],
    )


def scene(severity="high", located=True) -> px.Scene:
    return px.Scene(id="inc-1", severity=severity,
                    lat=SCENE_LAT if located else None, lng=SCENE_LNG if located else None)


def by_id(assessed):
    return {a.responder_id: a for a in assessed}


# =============================================================================
# Distance
# =============================================================================

def test_distance_is_ellipsoidal_not_spherical():
    [a] = px.assess(scene(), [unit("r1", 10_000)])
    lat, lng = at_distance(10_000)
    assert a.distance_m == pytest.approx(geo.geodesic_m(lat, lng, SCENE_LAT, SCENE_LNG), abs=0.001)
    assert a.distance_m == pytest.approx(10_000, abs=0.01)
    # ...and Haversine would have been about 50 m long over the same ten kilometres.
    assert geo.haversine_m(lat, lng, SCENE_LAT, SCENE_LNG) - a.distance_m > 40


def test_a_located_units_position_is_exposed_only_when_it_was_used():
    a = by_id(px.assess(scene(), [unit("near", 1_000), unit("stale", 1_000, age=9_999), unit("nofix", None)]))
    d = a["near"].to_dict()
    assert d["latitude"] is not None and d["longitude"] is not None
    assert a["stale"].to_dict()["latitude"] is None and a["nofix"].to_dict()["longitude"] is None


def test_eta_is_the_shared_model_and_direction_points_at_the_incident():
    [a] = px.assess(scene(), [unit("r1", 3_000, bearing=180)])     # 3 km SOUTH of the scene
    assert a.eta_min == geo.estimate_eta_minutes(a.distance_m / 1000)
    assert a.direction == "N"                                      # so the way to go is north


# =============================================================================
# Range, freshness, caps
# =============================================================================

def test_free_units_in_range_are_alarmed_nearest_first_and_numbered():
    got = px.assess(scene("high"), [unit("far", 3_000), unit("near", 1_000), unit("mid", 2_000)])
    assert [a.responder_id for a in got] == ["near", "mid", "far"]
    assert [a.level for a in got] == ["alarm"] * 3
    assert [a.rank for a in got] == [1, 2, 3]
    assert {a.reason for a in got} == {"nearest"}


@pytest.mark.parametrize("severity,radius_m", [("critical", 15_000), ("high", 10_000), ("medium", 6_000), ("low", 4_000)])
def test_the_radius_grows_with_severity(severity, radius_m):
    inside, outside = px.assess(scene(severity), [unit("in", radius_m - 10), unit("out", radius_m + 10)])
    a = by_id([inside, outside])
    assert a["in"].in_range and not a["out"].in_range


def test_an_unscored_report_is_treated_as_high():
    a = by_id(px.assess(scene(None), [unit("in", 9_900), unit("out", 10_100)]))
    assert a["in"].in_range and not a["out"].in_range


def test_only_a_fresh_position_is_trusted():
    a = by_id(px.assess(scene(), [
        unit("fresh", 1_000, age=600),          # exactly at the limit: still trusted
        unit("stale", 1_000, age=601),
        unit("nofix", None),
    ]))
    assert a["fresh"].located and a["fresh"].distance_m is not None
    assert not a["stale"].located and a["stale"].distance_m is None
    assert not a["nofix"].located


def test_a_position_of_unknown_age_is_not_trusted():
    u = unit("r1", 1_000)
    u.fix_age_s = None      # a location that predates the timestamp column
    [a] = px.assess(scene(), [u])
    assert not a.located


@pytest.mark.parametrize("severity,cap", [("critical", 8), ("high", 5), ("medium", 3), ("low", 2)])
def test_at_most_cap_free_units_are_alarmed(severity, cap):
    units = [unit(f"r{i}", 300 + i * 100) for i in range(10)]        # all within every radius
    got = px.assess(scene(severity), units)
    assert sum(1 for a in got if a.level == "alarm") == cap
    assert {a.reason for a in got if a.level == "none"} == {"beyond_cap"}
    # and the ones told are the nearest ones
    assert {a.responder_id for a in got if a.level == "alarm"} == {f"r{i}" for i in range(cap)}


# =============================================================================
# THE HARD CASE: a busy responder, and a new incident near them both
# =============================================================================

def test_a_busy_responder_is_never_alarmed_just_for_being_close():
    got = by_id(px.assess(scene("medium"), [
        unit("free", 1_500),
        unit("busy", 300, calls=[("en_route", "medium")]),
    ]))
    assert got["free"].level == "alarm"
    assert got["busy"].level == "none" and got["busy"].reason == "busy"


def test_a_busy_responder_is_advised_quietly_when_the_new_incident_is_more_severe():
    got = by_id(px.assess(scene("critical"), [
        unit("free", 1_500),
        unit("busy", 300, calls=[("en_route", "medium")]),
    ]))
    assert got["free"].level == "alarm"
    assert got["busy"].level == "advisory" and got["busy"].reason == "escalation"


def test_equal_or_lower_severity_is_not_an_escalation():
    for held in ("high", "critical"):
        got = by_id(px.assess(scene("high"), [
            unit("free", 1_500),
            unit("busy", 300, calls=[("committed" if False else "en_route", held)]),
        ]))
        assert got["busy"].level == "none", held


def test_a_responder_holding_several_calls_is_judged_by_the_worst_of_them():
    calls = [("en_route", "medium"), ("dispatched", "high")]
    high = by_id(px.assess(scene("high"), [unit("free", 1_500), unit("busy", 300, calls=calls)]))
    critical = by_id(px.assess(scene("critical"), [unit("free", 1_500), unit("busy", 300, calls=calls)]))
    assert high["busy"].level == "none"                    # not worse than the HIGH already held
    assert critical["busy"].level == "advisory"


def test_with_nobody_free_in_range_committed_and_en_route_crews_are_asked_quietly():
    got = by_id(px.assess(scene("high"), [
        unit("committed", 800, calls=[("dispatched", "high")]),
        unit("enroute", 900, calls=[("en_route", "high")]),
    ]))
    assert got["committed"].level == "advisory" and got["committed"].reason == "no_free_unit"
    assert got["enroute"].level == "advisory" and got["enroute"].reason == "no_free_unit"


def test_a_crew_on_scene_is_never_asked_to_consider_leaving_for_want_of_a_free_unit():
    got = by_id(px.assess(scene("high"), [unit("onscene", 500, calls=[("arrived", "high")])]))
    assert got["onscene"].level == "none"


def test_a_crew_on_scene_still_hears_of_a_more_severe_incident():
    got = by_id(px.assess(scene("critical"), [unit("onscene", 500, calls=[("arrived", "low")])]))
    assert got["onscene"].level == "advisory" and got["onscene"].reason == "escalation"


def test_no_busy_unit_is_asked_when_a_free_one_is_in_range():
    got = by_id(px.assess(scene("high"), [
        unit("free", 4_000),
        unit("busy", 300, calls=[("en_route", "high")]),
    ]))
    assert got["free"].level == "alarm"
    assert got["busy"].level == "none"


def test_busy_advisories_are_capped():
    units = [unit(f"b{i}", 300 + i * 50, calls=[("en_route", "low")]) for i in range(6)]
    got = px.assess(scene("critical"), units)
    assert sum(1 for a in got if a.level == "advisory") == 3
    assert {a.reason for a in got if a.level == "none"} >= {"beyond_cap"}


def test_a_busy_units_advisory_does_not_count_as_coverage_the_net_still_widens():
    # HIGH, radius 10 km. A busy unit in range is advised (escalation over a MEDIUM call),
    # but the only free unit is 12 km away. Someone who can actually go must hear too.
    got = by_id(px.assess(scene("high"), [
        unit("busy", 500, calls=[("en_route", "medium")]),
        unit("free_far", 12_000),
    ]))
    assert got["busy"].level == "advisory"
    assert got["free_far"].level == "alarm" and got["free_far"].reason == "nobody_in_range"


def test_the_system_never_reassigns_anything():
    """assess() is pure: it returns levels, it does not touch the units' calls."""
    u = unit("busy", 300, calls=[("en_route", "low")])
    before = [dict(c) for c in u.calls]
    px.assess(scene("critical"), [u, unit("free", 500)])
    assert u.calls == before


def test_state_precedence_on_scene_then_en_route_then_committed_then_free():
    st = px.unit_state
    assert st([]) == "free"
    assert st([{"status": "dispatched"}]) == "committed"
    assert st([{"status": "dispatched"}, {"status": "en_route"}]) == "en_route"
    assert st([{"status": "en_route"}, {"status": "arrived"}, {"status": "dispatched"}]) == "on_scene"


# =============================================================================
# Nobody is left untold
# =============================================================================

def test_when_nobody_is_in_range_the_nearest_free_units_beyond_it_are_told():
    units = [unit(f"r{i}", 11_000 + i * 1_000) for i in range(4)]        # 11, 12, 13, 14 km; HIGH radius 10
    got = px.assess(scene("high"), units)
    told = [a for a in got if a.level != "none"]
    assert [a.responder_id for a in told] == ["r0", "r1", "r2"]
    assert {a.level for a in told} == {"alarm"} and {a.reason for a in told} == {"nobody_in_range"}
    assert by_id(got)["r3"].level == "none"


def test_a_widened_alert_for_a_minor_incident_is_quiet():
    got = px.assess(scene("low"), [unit("far", 9_000)])            # LOW radius 4 km
    assert got[0].level == "advisory" and got[0].reason == "nobody_in_range"


def test_units_with_no_usable_position_are_told_when_nobody_is_in_range():
    got = by_id(px.assess(scene("high"), [unit("nofix", None), unit("stale", 500, age=9_999)]))
    assert got["nofix"].level == "alarm" and got["nofix"].reason == "location_unknown"
    assert got["stale"].level == "alarm" and got["stale"].reason == "location_unknown"


def test_units_with_no_position_are_left_alone_when_someone_near_is_covering():
    got = by_id(px.assess(scene("high"), [unit("near", 500), unit("nofix", None)]))
    assert got["near"].level == "alarm"
    assert got["nofix"].level == "none" and got["nofix"].reason == "not_located"


def test_an_incident_with_no_coordinates_alarms_every_free_unit():
    got = by_id(px.assess(scene("critical", located=False), [
        unit("a", 500), unit("b", None), unit("busy", 300, calls=[("en_route", "low")]),
    ]))
    assert got["a"].level == "alarm" and got["a"].reason == "incident_not_located"
    assert got["b"].level == "alarm"
    assert got["busy"].level == "none"


def test_a_minor_incident_with_no_coordinates_is_advisory_only():
    got = px.assess(scene("low", located=False), [unit("a", 500)])
    assert got[0].level == "advisory"


# =============================================================================
# Order and numbers
# =============================================================================

def test_alarm_then_advisory_then_the_rest_and_only_the_told_are_numbered():
    got = px.assess(scene("critical"), [
        unit("none_busy", 100, calls=[("arrived", "critical")]),
        unit("adv", 200, calls=[("en_route", "low")]),
        unit("alarm_far", 4_000),
        unit("alarm_near", 900),
    ])
    assert [a.responder_id for a in got] == ["alarm_near", "alarm_far", "adv", "none_busy"]
    assert [a.rank for a in got] == [1, 2, 3, None]


def test_equal_distances_are_ordered_stably_by_name():
    got = px.assess(scene(), [unit("zed", 1_000, name="Zed"), unit("abe", 1_000, name="Abe")])
    assert [a.full_name for a in got] == ["Abe", "Zed"]


def test_summary_counts():
    got = px.assess(scene("critical"), [
        unit("f1", 500), unit("f2", 900), unit("b", 300, calls=[("en_route", "low")]),
    ])
    s = px.summarize(got)
    assert s == {"on_duty": 3, "free": 2, "busy": 1, "in_range": 3, "notified": 3, "alarm": 2, "advisory": 1}


# =============================================================================
# The database layer
# =============================================================================

def _ts(seconds_ago: int) -> str:
    return (NOW - timedelta(seconds=seconds_ago)).isoformat()


def _point(meters, bearing=0.0):
    lat, lng = at_distance(meters, bearing)
    return {"type": "Point", "coordinates": [lng, lat]}


def _user(uid, meters=None, *, agency=AGENCY, availability="on_duty", approval="approved", age=30, name=None, bearing=0.0):
    return {
        "id": uid, "role": "responder", "agency_id": agency, "availability": availability,
        "approval_status": approval, "full_name": name or f"Responder {uid}", "badge_id": f"B-{uid}",
        "location": None if meters is None else _point(meters, bearing),
        "location_updated_at": None if meters is None else _ts(age),
    }


def _incident(iid, severity="high", *, status="received", agency=AGENCY, responder=None, age_s=120,
              meters=0, address="Brgy Casiawan, Cabucgayan"):
    return {
        "id": iid, "record_number": f"ZIR-2026-{iid}", "status": status, "severity": severity,
        "incident_category": "fire", "report_text": "Smoke coming from a house " * 20,
        "location_address": address, "location": _point(meters), "created_at": _ts(age_s),
        "sos_flagged": False, "assigned_agency_id": agency, "assigned_responder_id": responder,
    }


def world(**extra_rows):
    """A small province: five responders, one of them busy, and one new incident."""
    users = [
        _user("R1", 1_000, name="Ana Free"),                   # free, 1 km
        _user("R2", 4_000, bearing=90, name="Ben Free"),       # free, 4 km east
        _user("R3", 600, name="Cara Busy"),                    # busy: en route to a MEDIUM call
        _user("R4", 500, availability="off_duty"),             # off duty
        _user("R5", 500, agency=OTHER_AGENCY),                 # another agency
        _user("R6", 500, approval="pending"),                  # not approved
        _user("R7", None, name="Dan NoFix"),                   # on duty, no position
    ]
    incidents = [
        _incident("I0", "medium", status="en_route", responder="R3", meters=8_000, age_s=900),
        _incident("I1", "high"),
    ]
    tables = {"users": users, "incidents": incidents, "notifications": []}
    tables.update(extra_rows)
    return FakeDB(tables, clock=lambda: NOW)


def test_load_units_returns_only_approved_on_duty_responders_of_the_agency():
    units = {u.id: u for u in px.load_units(world(), AGENCY, now=NOW)}
    assert set(units) == {"R1", "R2", "R3", "R7"}                # not R4 (off), R5 (other), R6 (pending)
    assert units["R1"].fix_age_s == 30 and units["R1"].lat is not None
    assert units["R7"].lat is None and units["R7"].fix_age_s is None
    assert [c["status"] for c in units["R3"].calls] == ["en_route"]
    assert units["R1"].calls == []


def test_notify_nearby_records_who_was_told_with_distance_and_state():
    db = world()
    inc = db.rows("incidents")[1]
    told = px.notify_nearby(db, inc, lat=SCENE_LAT, lng=SCENE_LNG, now=NOW)

    assert {a.responder_id for a in told} == {"R1", "R2", "R3"}      # R3: escalation, HIGH over MEDIUM
    rows = {r["recipient_id"]: r for r in db.inserted["notifications"]}
    assert set(rows) == {"R1", "R2", "R3"}                          # never R4/R5/R6/R7
    r1 = rows["R1"]
    assert r1["type"] == px.TYPE_NEARBY and r1["title"] == "New HIGH incident near you"
    assert r1["is_important"] is True                               # an alarm on a HIGH
    assert r1["metadata"]["incident_id"] == "I1"
    assert r1["metadata"]["level"] == "alarm" and r1["metadata"]["state"] == "free"
    assert r1["metadata"]["distance_m"] == 1_000 and r1["metadata"]["eta_min"] == 3
    assert "1.0 km" in r1["body"] and "Brgy Casiawan" in r1["body"]
    assert rows["R3"]["metadata"]["level"] == "advisory" and rows["R3"]["metadata"]["state"] == "en_route"
    assert rows["R3"]["is_important"] is False                      # advisories never ring


def test_notify_nearby_says_so_when_a_responders_position_is_not_known():
    db = world()
    for u in db.rows("users"):
        u["location"], u["location_updated_at"] = None, None       # nobody has a position
    told = px.notify_nearby(db, db.rows("incidents")[1], lat=SCENE_LAT, lng=SCENE_LNG, now=NOW)
    assert {a.responder_id for a in told} == {"R1", "R2", "R7"}     # every FREE on-duty unit; the busy one is not
    row = next(r for r in db.inserted["notifications"] if r["recipient_id"] == "R1")
    assert row["metadata"]["reason"] == "location_unknown"
    assert "not known" in row["body"]


def test_notify_nearby_never_raises_when_the_database_does():
    db = world()
    db.fail_on_insert = {"notifications"}
    assert px.notify_nearby(db, db.rows("incidents")[1], lat=SCENE_LAT, lng=SCENE_LNG, now=NOW) == []
    db2 = world()
    db2.fail_on_select = {"users"}
    assert px.notify_nearby(db2, db2.rows("incidents")[1], lat=SCENE_LAT, lng=SCENE_LNG, now=NOW) == []


def test_notify_nearby_with_no_agency_writes_nothing():
    db = world()
    inc = {**db.rows("incidents")[1], "assigned_agency_id": None}
    assert px.notify_nearby(db, inc, now=NOW) == []
    assert "notifications" not in db.inserted


# -- the responder's own view --------------------------------------------------

def test_a_free_responder_sees_the_incident_with_a_live_measurement():
    db = world()
    out = px.nearby_for_responder(db, {"id": "R1", "agency_id": AGENCY}, now=NOW)
    assert out["on_duty"] is True and out["position"] == "last_reported"
    [item] = out["items"]
    assert item["incident_id"] == "I1" and item["level"] == "alarm" and item["reason"] == "nearest"
    assert item["distance_m"] == 1_000 and item["distance_km"] == 1.0 and item["eta_min"] == 3
    assert item["direction"] == "S"                                  # the incident is south of R1
    assert item["you"]["state"] == "free" and item["units_free_in_range"] == 2
    assert len(item["report_text"]) <= 240                           # trimmed, never the whole essay
    assert item["answered"] is None
    assert "reporter" not in " ".join(item)                          # nothing identifying the resident


def test_an_off_duty_responder_is_told_nothing():
    out = px.nearby_for_responder(world(), {"id": "R4", "agency_id": AGENCY}, now=NOW)
    assert out == {"on_duty": False, "position": "none", "items": []}


def test_only_undispatched_recent_incidents_of_my_agency_are_listed():
    db = world()
    db.tables["incidents"] += [
        _incident("I2", "high", responder="R2"),                     # already assigned
        _incident("I3", "high", status="dispatched"),                # already dispatched
        _incident("I4", "high", status="resolved"),
        _incident("I5", "high", agency=OTHER_AGENCY),                # someone else's
        _incident("I6", "high", age_s=13 * 3600),                    # stale (12 h ceiling)
        _incident("I7", "high", status="processing"),                # still being triaged: listed
    ]
    ids = {i["incident_id"] for i in px.nearby_for_responder(db, {"id": "R1", "agency_id": AGENCY}, now=NOW)["items"]}
    assert ids == {"I1", "I7"}


def test_a_responder_who_declined_the_incident_is_not_woken_for_it_again():
    db = world()
    db.tables["incidents"][1]["declined_by"] = "R1"        # R1 handed it back; it returned to the pool
    assert px.nearby_for_responder(db, {"id": "R1", "agency_id": AGENCY}, now=NOW)["items"] == []
    # everyone else is still told: the incident needs a new crew
    assert [i["incident_id"] for i in px.nearby_for_responder(db, {"id": "R2", "agency_id": AGENCY}, now=NOW)["items"]] == ["I1"]


def test_the_phones_own_position_beats_the_last_reported_one():
    db = world()
    # R2 last reported 4 km east; but the phone says they are 500 m from the scene.
    lat, lng = at_distance(500, 45)
    stale = px.nearby_for_responder(db, {"id": "R2", "agency_id": AGENCY}, now=NOW)
    live = px.nearby_for_responder(db, {"id": "R2", "agency_id": AGENCY}, lat=lat, lng=lng, now=NOW)
    assert stale["position"] == "last_reported" and live["position"] == "device"
    assert live["items"][0]["distance_m"] == 500
    assert stale["items"][0]["distance_m"] == 4_000


def test_a_busy_responder_hears_only_what_matters():
    db = world()
    me = {"id": "R3", "agency_id": AGENCY}                           # en route to a MEDIUM call
    high = px.nearby_for_responder(db, me, now=NOW)["items"]
    assert [(i["incident_id"], i["level"], i["reason"]) for i in high] == [("I1", "advisory", "escalation")]
    assert high[0]["you"]["state"] == "en_route"
    assert high[0]["you"]["current_calls"][0]["incident_id"] == "I0"  # told what they are already on

    db.tables["incidents"][1]["severity"] = "medium"                # not more severe than what they hold
    assert px.nearby_for_responder(db, me, now=NOW)["items"] == []


def test_a_responder_shown_an_incident_for_the_first_time_is_recorded_once():
    db = world()          # nobody was recorded at creation
    me = {"id": "R1", "agency_id": AGENCY}
    px.nearby_for_responder(db, me, now=NOW)
    px.nearby_for_responder(db, me, now=NOW)
    px.clear_memory()                                               # even a restarted process finds the row
    px.nearby_for_responder(db, me, now=NOW)
    rows = [r for r in db.inserted["notifications"] if r["recipient_id"] == "R1" and r["type"] == px.TYPE_NEARBY]
    assert len(rows) == 1 and rows[0]["metadata"]["incident_id"] == "I1"


def test_a_responder_recorded_at_creation_is_not_recorded_again():
    db = world()
    px.notify_nearby(db, db.rows("incidents")[1], lat=SCENE_LAT, lng=SCENE_LNG, now=NOW)
    before = len(db.inserted["notifications"])
    px.clear_memory()
    px.nearby_for_responder(db, {"id": "R1", "agency_id": AGENCY}, now=NOW)
    assert len(db.inserted["notifications"]) == before


# -- answering -------------------------------------------------------------------

def _answer(db, who, incident="I1", answer="can_respond", **kw):
    return px.answer_nearby(db, {"id": who, "agency_id": AGENCY}, incident, answer, now=NOW, **kw)


def test_can_respond_tells_the_agencys_admins_who_is_ready_and_how_long_they_would_take():
    db = world()
    with patch("app.services.proximity.notification_service.create_for_agency_role") as notify:
        out = _answer(db, "R1")
    assert out["answer"] == "can_respond" and out["incident_id"] == "I1"

    audit = next(r for r in db.inserted["notifications"] if r["type"] == px.TYPE_ANSWER)
    assert audit["recipient_id"] == "R1" and audit["metadata"]["answer"] == "can_respond"
    assert audit["metadata"]["distance_m"] == 1_000 and audit["metadata"]["state"] == "free"

    notify.assert_called_once()
    args, kw = notify.call_args
    assert args == (AGENCY, "agency_admin")
    assert kw["type_"] == px.TYPE_RESPONSE and kw["title"] == "Ana Free can respond"
    assert "1.0 km" in kw["body"] and "free" in kw["body"] and "Brgy Casiawan" in kw["body"]
    assert kw["is_important"] is True and kw["link"] == "/incidents/I1"
    assert kw["metadata"]["responder_id"] == "R1" and kw["metadata"]["incident_id"] == "I1"


def test_a_busy_responder_who_can_also_respond_says_what_they_are_already_doing():
    db = world()
    with patch("app.services.proximity.notification_service.create_for_agency_role") as notify:
        _answer(db, "R3")
    assert "en route to another call" in notify.call_args.kwargs["body"]
    assert notify.call_args.kwargs["metadata"]["state"] == "en_route"


def test_unavailable_is_recorded_without_ringing_anyones_bell():
    db = world()
    with patch("app.services.proximity.notification_service.create_for_agency_role") as notify:
        _answer(db, "R1", answer="unavailable")
    notify.assert_not_called()
    assert [r["metadata"]["answer"] for r in db.inserted["notifications"] if r["type"] == px.TYPE_ANSWER] == ["unavailable"]


def test_the_latest_answer_wins_and_is_shown_back_to_the_responder():
    db = world()
    with patch("app.services.proximity.notification_service.create_for_agency_role"):
        _answer(db, "R1", answer="unavailable")
        db.clock = lambda: NOW + timedelta(seconds=5)
        _answer(db, "R1", answer="can_respond")
    item = px.nearby_for_responder(db, {"id": "R1", "agency_id": AGENCY}, now=NOW + timedelta(seconds=10))["items"][0]
    assert item["answered"] == "can_respond"


def test_answering_nothing_of_the_dispatchers_is_touched():
    db = world()
    with patch("app.services.proximity.notification_service.create_for_agency_role"):
        _answer(db, "R1")
    inc = next(r for r in db.rows("incidents") if r["id"] == "I1")
    assert inc["assigned_responder_id"] is None and inc["status"] == "received"   # nothing assigned, nothing moved


@pytest.mark.parametrize("who,incident,answer,code", [
    ("R1", "I1", "maybe", 422),
    ("R1", "NOPE", "can_respond", 404),
    ("R5", "I1", "can_respond", 403),          # another agency's responder
    ("R4", "I1", "can_respond", 409),          # off duty
])
def test_answers_are_refused_for_the_wrong_person_or_incident(who, incident, answer, code):
    db = world()
    # R5's row says OTHER_AGENCY; the call passes the profile it was authenticated with.
    caller = {"id": who, "agency_id": OTHER_AGENCY if who == "R5" else AGENCY}
    with pytest.raises(HTTPException) as e:
        px.answer_nearby(db, caller, incident, answer, now=NOW)
    assert e.value.status_code == code


def test_an_incident_someone_has_already_been_assigned_cannot_be_answered():
    db = world()
    db.tables["incidents"][1]["assigned_responder_id"] = "R2"
    with pytest.raises(HTTPException) as e:
        _answer(db, "R1")
    assert e.value.status_code == 409 and "already been assigned" in e.value.detail
    db2 = world()
    db2.tables["incidents"][1]["status"] = "dispatched"
    with pytest.raises(HTTPException) as e2:
        _answer(db2, "R1")
    assert e2.value.status_code == 409


def test_a_failure_telling_the_admins_never_fails_the_answer():
    db = world()
    with patch("app.services.proximity.notification_service.create_for_agency_role", side_effect=RuntimeError("boom")):
        out = _answer(db, "R1")
    assert out["answer"] == "can_respond"
    assert any(r["type"] == px.TYPE_ANSWER for r in db.inserted["notifications"])   # still on the record


# -- the dispatcher's panel --------------------------------------------------------

def test_the_dispatchers_panel_ranks_everyone_and_shows_who_was_told_and_who_answered():
    db = world()
    inc = db.rows("incidents")[1]
    px.notify_nearby(db, inc, lat=SCENE_LAT, lng=SCENE_LNG, now=NOW)
    with patch("app.services.proximity.notification_service.create_for_agency_role"):
        _answer(db, "R1")

    out = px.nearby_for_admin(db, inc, now=NOW)
    assert out["incident_id"] == "I1"
    assert [r["responder_id"] for r in out["responders"]] == ["R1", "R2", "R3", "R7"]   # alarm, alarm, advisory, unlocated
    r1, r2, r3, r7 = out["responders"]
    assert r1["notified_at"] and r1["answer"] == "can_respond" and r1["answered_at"]
    assert r2["notified_at"] and r2["answer"] is None
    assert r3["state"] == "en_route" and r3["level"] == "advisory" and r3["current_calls"][0]["incident_id"] == "I0"
    assert r7["located"] is False and r7["level"] == "none"
    assert out["summary"]["off_duty"] == 1                                # R4; not the other agency's, not the pending one
    assert out["summary"]["notified"] == 3
    assert out["policy"] == {"radius_km": 10.0, "fix_max_age_s": 600}


def test_a_panel_for_an_incident_with_no_agency_is_empty_not_an_error():
    db = world()
    inc = {**db.rows("incidents")[1], "assigned_agency_id": None}
    out = px.nearby_for_admin(db, inc, now=NOW)
    assert out["responders"] == [] and out["summary"]["on_duty"] == 0


# -- small helpers -----------------------------------------------------------------

def test_station_distance_uses_the_same_ellipsoidal_distance():
    s_lat, s_lng = at_distance(2_345, 90)
    inc = {"location": {"type": "Point", "coordinates": [SCENE_LNG, SCENE_LAT]},
           "stations": {"location": {"type": "Point", "coordinates": [s_lng, s_lat]}}}
    assert px.station_distance_km(inc) == 2.35
    assert px.station_distance_km({"location": inc["location"], "stations": None}) is None
    assert px.station_distance_km({"location": None, "stations": inc["stations"]}) is None


def test_explicit_coordinates_beat_the_rows_own_geometry():
    row = {"id": "x", "severity": "high", "location": {"type": "Point", "coordinates": [1.0, 2.0]}}
    s = px.scene_from_row(row, lat=11.5, lng=124.4)
    assert (s.lat, s.lng) == (11.5, 124.4)
    assert (px.scene_from_row(row).lat, px.scene_from_row(row).lng) == (2.0, 1.0)


@pytest.mark.parametrize("value,rank", [
    ("critical", 0), ("HIGH", 1), (" medium ", 2), ("low", 3), (None, 1), ("", 1), ("bogus", 1),
])
def test_severity_rank(value, rank):
    assert px.severity_rank(value) == rank
