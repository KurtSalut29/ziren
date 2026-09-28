"""
operational_area_service and GET /geographic/operational-area.

The service is tested at two levels:

  1. The PURE functions (rows in, figures out) each get hand-computed expectations —
     the comments show the arithmetic so a wrong expectation is easy to spot.
  2. get_operational_area() runs against a small table-backed fake database, so the
     real query-building code (scoping, windows, paging, the barangay filter) is
     exercised end to end. A fake cannot know the live schema, so the same function
     was also run read-only against the real database when it was written.

Fixture clock: NOW = Friday 2026-03-20 12:00 Philippine time (04:00 UTC).

Run: pytest tests/test_operational_area.py -v
"""

from datetime import date, datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import operational_area_service as svc

client = TestClient(app)

NOW = datetime(2026, 3, 20, 4, 0, tzinfo=timezone.utc)
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"
PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"

A1, A2, A3 = "agency-bfp-naval", "agency-pnp-naval", "agency-bfp-almeria"


def ago(**kw) -> datetime:
    return NOW - timedelta(**kw)


def iso(dt: datetime) -> str:
    return dt.isoformat()


# ── A table-backed fake of the slice of supabase-py this module uses ─────

def _instant(value):
    """An ISO timestamp as a datetime, so two offsets compare as the moments they are. Anything else compares as itself."""
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
    return value


class _Res:
    def __init__(self, data, count=None):
        self.data = data
        self.count = count


class _Query:
    def __init__(self, rows):
        self._rows = list(rows)
        self._filters = []
        self._order = None
        self._range = None
        self._want_count = False

    def select(self, cols="*", count=None):
        self._want_count = count is not None
        return self

    def eq(self, col, val):
        self._filters.append(lambda r: r.get(col) == val)
        return self

    def in_(self, col, vals):
        allowed = set(vals)
        self._filters.append(lambda r: r.get(col) in allowed)
        return self

    def gte(self, col, val):
        self._filters.append(lambda r: r.get(col) is not None and _instant(r[col]) >= _instant(val))
        return self

    def lt(self, col, val):
        self._filters.append(lambda r: r.get(col) is not None and _instant(r[col]) < _instant(val))
        return self

    def order(self, col, desc=False):
        self._order = (col, desc)
        return self

    def range(self, start, end):
        self._range = (start, end)
        return self

    def execute(self):
        rows = [r for r in self._rows if all(f(r) for f in self._filters)]
        count = len(rows)
        if self._order:
            col, desc = self._order
            rows.sort(key=lambda r: (r.get(col) is None, r.get(col)), reverse=desc)
        if self._range:
            a, b = self._range
            rows = rows[a:b + 1]
        return _Res(rows, count if self._want_count else None)


class FakeDB:
    def __init__(self, tables):
        self.tables = tables

    def table(self, name):
        return _Query(self.tables.get(name, []))


# ── The fixture ──────────────────────────────────────────────────────────

def _incident(i, *, hours=None, days=None, **over):
    created = ago(hours=hours or 0, days=days or 0)
    row = {
        "id": i, "record_number": f"ZIR-2026-{i}", "status": "resolved", "severity": "medium",
        "incident_category": "fire", "created_at": iso(created), "dispatched_at": None, "accepted_at": None,
        "resolved_at": None, "location": {"type": "Point", "coordinates": [124.4, 11.56]},
        "location_address": None, "assigned_agency_id": A1, "assigned_responder_id": None,
        "station_id": "s1", "outcome": None, "casualties_injured": 0, "casualties_fatal": 0,
        "casualties_transported": 0, "sos_flagged": False, "submitted_via": "internet",
        "overlap_agencies": None, "report_text": "text " + i,
    }
    row.update(over)
    return row


def _plus(created_iso, minutes):
    return iso(datetime.fromisoformat(created_iso) + timedelta(minutes=minutes))


def _fixture():
    i1 = _incident("i1", hours=2, severity="critical", sos_flagged=True, assigned_responder_id="r1",
                   location_address="Sitio Uno, Larrazabal, Naval, Biliran", outcome="transported",
                   casualties_injured=2, casualties_transported=1, overlap_agencies=["injuries", "fire"])
    i1.update(dispatched_at=_plus(i1["created_at"], 3), accepted_at=_plus(i1["created_at"], 4),
              resolved_at=_plus(i1["created_at"], 60))
    i2 = _incident("i2", days=1, severity="high", incident_category="vehicular", assigned_responder_id="r1",
                   location_address="Caraycaray, Naval, Biliran", outcome="handled_on_scene")
    i2.update(dispatched_at=_plus(i2["created_at"], 12), accepted_at=_plus(i2["created_at"], 15),
              resolved_at=_plus(i2["created_at"], 90))
    i3 = _incident("i3", days=5, status="cancelled", incident_category="medical_trauma", location=None)
    i4 = _incident("i4", days=20, severity="low", location_address="1.5 km from San Roque, Biliran",
                   outcome="false_alarm", submitted_via="sos")
    i4.update(dispatched_at=_plus(i4["created_at"], 30), resolved_at=_plus(i4["created_at"], 45))
    i5 = _incident("i5", days=40, severity="high", location_address="Caraycaray, Naval, Biliran")
    i5.update(dispatched_at=_plus(i5["created_at"], 2), resolved_at=_plus(i5["created_at"], 20))
    i6 = _incident("i6", days=1, assigned_agency_id=A2, station_id="s3", severity="critical")
    i7 = _incident("i7", hours=0, days=0, status="received", severity="critical", station_id=None,
                   location_address="Poblacion, Naval, Biliran")
    i7["created_at"] = iso(NOW - timedelta(minutes=10))

    return {
        "agencies": [
            {"id": A1, "name": "BFP Naval Station", "agency_type": "BFP", "municipality": "Naval", "province": "Biliran",
             "region": "Region VIII", "contact_number": "(053) 500-9911", "email": None, "is_active": True},
            {"id": A2, "name": "PNP Naval Station", "agency_type": "PNP", "municipality": "Naval", "province": "Biliran",
             "region": "Region VIII", "contact_number": None, "email": None, "is_active": True},
            {"id": A3, "name": "BFP Almeria Station", "agency_type": "BFP", "municipality": "Almeria", "province": "Biliran",
             "region": "Region VIII", "contact_number": None, "email": None, "is_active": True},
        ],
        "barangays": [
            {"id": "b1", "name": "Caraycaray", "municipality": "Naval"},
            {"id": "b2", "name": "Larrazabal", "municipality": "Naval"},
            {"id": "b3", "name": "Poblacion", "municipality": "Naval"},
            {"id": "b4", "name": "Poblacion", "municipality": "Almeria"},
        ],
        "users": [
            {"id": "u1", "role": "resident", "barangay_id": "b1", "is_verified": True, "is_pwd": False, "date_of_birth": "1950-03-20", "created_at": iso(ago(days=3))},
            {"id": "u2", "role": "resident", "barangay_id": "b1", "is_verified": False, "is_pwd": True, "date_of_birth": "2019-03-21", "created_at": iso(ago(days=90))},
            {"id": "u3", "role": "resident", "barangay_id": "b2", "is_verified": True, "is_pwd": False, "date_of_birth": "1990-01-01", "created_at": iso(ago(days=10))},
            {"id": "u4", "role": "resident", "barangay_id": "b4", "is_verified": True, "is_pwd": False, "date_of_birth": "2020-01-01", "created_at": iso(ago(days=1))},
            {"id": "r1", "role": "responder", "agency_id": A1, "full_name": "Juan Cruz", "badge_id": "B-1",
             "approval_status": "approved", "availability": "on_duty", "location": {"coordinates": [124.4, 11.56]},
             "location_updated_at": iso(ago(minutes=5))},
            {"id": "r2", "role": "responder", "agency_id": A1, "full_name": "Ana Reyes", "badge_id": "B-2",
             "approval_status": "approved", "availability": "off_duty", "location": None, "location_updated_at": None},
            {"id": "r3", "role": "responder", "agency_id": A1, "full_name": "Pedro Diaz", "badge_id": "B-3",
             "approval_status": "pending", "availability": "off_duty", "location": None, "location_updated_at": None},
            {"id": "r4", "role": "responder", "agency_id": A3, "full_name": "Almeria Crew", "badge_id": "B-4",
             "approval_status": "approved", "availability": "on_duty", "location": None, "location_updated_at": None},
        ],
        "stations": [
            {"id": "s1", "name": "BFP Naval Main", "address": "Vicentillo St.", "agency_id": A1, "is_active": True,
             "location": {"coordinates": [124.39, 11.56]}},
            {"id": "s2", "name": "BFP Naval Annex", "address": None, "agency_id": A1, "is_active": True, "location": None},
            {"id": "s3", "name": "PNP Naval Station", "address": "Caneja St.", "agency_id": A2, "is_active": True,
             "location": {"coordinates": [124.39, 11.559]}},
        ],
        "incidents": [i1, i2, i3, i4, i5, i6, i7],
    }


@pytest.fixture
def db():
    fake = FakeDB(_fixture())
    with patch.object(svc, "get_supabase", return_value=fake):
        yield fake


def area(**kw):
    kw.setdefault("municipality", "Naval")
    kw.setdefault("days", 30)
    kw.setdefault("agency_id", A1)
    return svc.get_operational_area(now=NOW, **kw)


# ══════════════════════ pure helpers ═════════════════════════════════════

def test_summarise_shows_the_slow_tail_an_average_hides():
    # Nine 2-minute answers and one 40-minute answer.
    #   average = (9*2 + 40) / 10 = 5.8      median = 2.0
    #   p90: sorted, rank = (10-1)*0.9 = 8.1 -> 2 + (40-2)*0.1 = 5.8
    s = svc.summarise([2] * 9 + [40])
    assert (s["n"], s["avg"], s["p50"], s["p90"], s["max"]) == (10, 5.8, 2.0, 5.8, 40.0)


def test_summarise_ignores_none_and_handles_empty_and_single():
    assert svc.summarise([None, None]) == {"n": 0, "avg": None, "p50": None, "p90": None, "max": None}
    one = svc.summarise([7.5])
    assert (one["n"], one["avg"], one["p50"], one["p90"], one["max"]) == (1, 7.5, 7.5, 7.5, 7.5)


def test_negative_gap_is_a_data_error_not_a_response():
    assert svc._minutes_between("2026-03-20T04:10:00+00:00", "2026-03-20T04:00:00+00:00") is None
    assert svc._minutes_between("2026-03-20T04:00:00+00:00", "2026-03-20T04:05:30+00:00") == 5.5
    assert svc._minutes_between(None, "2026-03-20T04:05:30+00:00") is None


@pytest.mark.parametrize("raw,expected", [
    ("Brgy. San Roque", "san roque"),
    ("BARANGAY  Poblacion ", "poblacion"),
    ("Cañeja", "caneja"),
    ("  Larrazabal  ", "larrazabal"),
    ("", ""),
])
def test_normalise_place(raw, expected):
    assert svc.normalise_place(raw) == expected


def test_match_barangay_finds_the_barangay_part_of_a_geocoded_address():
    names = ["Caraycaray", "Larrazabal", "Poblacion"]
    ex = ["Naval", "Biliran"]
    assert svc.match_barangay("San Roque, Larrazabal, Naval, Biliran", names, ex) == "Larrazabal"
    assert svc.match_barangay("Brgy. Poblacion, Naval, Biliran", names, ex) == "Poblacion"


def test_match_barangay_is_whole_part_never_substring():
    names = ["Poblacion", "Naval Heights"]
    # "Poblacion Norte" is not "Poblacion"; "Naval Road" is not the barangay "Naval Heights".
    assert svc.match_barangay("Poblacion Norte, Naval, Biliran", names, ["Naval", "Biliran"]) is None
    assert svc.match_barangay("Naval Road, Naval, Biliran", names, ["Naval", "Biliran"]) is None


def test_match_barangay_never_answers_with_the_municipality_or_province():
    # A barangay that shares its name with the municipality must not swallow every address.
    assert svc.match_barangay("Somewhere, Naval, Biliran", ["Naval", "Biliran"], ["Naval", "Biliran"]) is None


def test_match_barangay_is_silent_when_the_address_names_none():
    assert svc.match_barangay("1.5 km from San Roque, Biliran", ["Larrazabal"], ["Biliran"]) is None
    assert svc.match_barangay(None, ["Larrazabal"]) is None
    assert svc.match_barangay("", ["Larrazabal"]) is None


# ── vulnerable residents ─────────────────────────────────────────────────

@pytest.mark.parametrize("dob,expected", [
    ("1950-03-20", 76),        # birthday is today: already 76
    ("1950-03-21", 75),        # birthday is tomorrow: still 75
    ("2019-03-21", 6),         # seven tomorrow
    ("2026-03-20", 0),         # born today
    ("2026-03-21", None),      # a date in the future is a data error
    ("not a date", None),
    ("", None),
    (None, None),
    ("1990-01-01T00:00:00", 36),   # a timestamp is read by its date
])
def test_age_on(dob, expected):
    assert svc.age_on(dob, NOW) == expected


def test_age_uses_the_philippine_date_not_utc():
    # 2026-03-19 17:00 UTC is already the 20th in the Philippines, so a March-20 birthday has arrived.
    just_after_midnight_ph = datetime(2026, 3, 19, 17, 0, tzinfo=timezone.utc)
    assert svc.age_on("2000-03-20", just_after_midnight_ph) == 26
    assert svc.age_on("2000-03-20", datetime(2026, 3, 19, 15, 0, tzinfo=timezone.utc)) == 25


def test_senior_and_child_thresholds_are_inclusive_and_exclusive_as_documented():
    def v(dob):
        return svc.vulnerability({"date_of_birth": dob, "is_pwd": False}, NOW)
    assert v("1966-03-20")["senior"] is True     # exactly 60 today
    assert v("1966-03-21")["senior"] is False    # 59 until tomorrow
    assert v("2014-03-21")["child"] is True      # 11 (twelve tomorrow)
    assert v("2014-03-20")["child"] is False     # exactly 12 today: not under 12
    assert v(None) == {"senior": False, "child": False, "pwd": False, "any": False}


def test_a_resident_in_two_groups_is_counted_once_as_vulnerable():
    u = {"date_of_birth": "2019-03-21", "is_pwd": True}       # a 6-year-old with a disability
    assert svc.vulnerability(u, NOW) == {"senior": False, "child": True, "pwd": True, "any": True}
    b = svc.build_barangays(
        [{"id": "b1", "name": "Caraycaray", "municipality": "Naval"}],
        [{"barangay_id": "b1", **u}, {"barangay_id": "b1", "date_of_birth": "1990-01-01", "is_pwd": False}],
        [], [], NOW,
    )["items"][0]
    assert (b["residents"], b["children"], b["pwd"], b["seniors"], b["vulnerable"]) == (2, 1, 1, 0, 1)


# ── repeat locations ─────────────────────────────────────────────────────

def _addr(text, sev="medium", cat="fire", at="2026-03-10T04:00:00+00:00"):
    return {"location_address": text, "severity": sev, "incident_category": cat, "created_at": at}


def test_hotspots_list_only_repeats_ranked_by_count_then_critical():
    rows = [
        _addr("San Roque, Larrazabal, Naval, Biliran", "critical"),
        _addr("san roque, larrazabal, naval, biliran", "critical", at="2026-03-12T04:00:00+00:00"),   # same place, other case
        _addr("San Roque, Larrazabal, Naval, Biliran", "low", "vehicular", "2026-03-15T04:00:00+00:00"),
        _addr("Caraycaray, Naval, Biliran", "high"),                                                    # once: not a pattern
        _addr("1.5 km from San Roque, Biliran"),
        _addr("1.5 km from San Roque, Biliran", "critical"),
        _addr(None),
        _addr(""),
    ]
    h = svc.build_hotspots(rows, ["Naval", "Biliran", "Region VIII"], ["Larrazabal", "Caraycaray"])
    assert [x["count"] for x in h] == [3, 2]
    first = h[0]
    assert first["place"] == "San Roque, Larrazabal"                # region parts stripped; the commonest spelling shown
    assert (first["critical"], first["top_category"], first["barangay"]) == (2, "fire", "Larrazabal")
    assert first["last_at"].startswith("2026-03-15")
    second = h[1]
    assert (second["place"], second["critical"], second["barangay"]) == ("1.5 km from San Roque", 1, None)


def test_hotspots_break_ties_by_critical_then_name():
    rows = [_addr("Zeta St., Naval", "low"), _addr("Zeta St., Naval", "low"),
            _addr("Alpha St., Naval", "low"), _addr("Alpha St., Naval", "low"),
            _addr("Mid St., Naval", "critical"), _addr("Mid St., Naval", "low")]
    h = svc.build_hotspots(rows, ["Naval"], [])
    assert [x["place"] for x in h] == ["Mid St.", "Alpha St.", "Zeta St."]      # 1 critical first, then A before Z


def test_hotspots_ignore_an_address_that_is_only_the_municipality_and_province():
    rows = [_addr("Naval, Biliran"), _addr("Naval, Biliran")]
    assert svc.build_hotspots(rows, ["Naval", "Biliran"], []) == []


def test_hotspots_are_capped():
    rows = [r for i in range(20) for r in (_addr(f"Street {i}, Naval"), _addr(f"Street {i}, Naval"))]
    assert len(svc.build_hotspots(rows, ["Naval"], [], limit=8)) == 8


# ── the previous period ──────────────────────────────────────────────────

def test_previous_period_measures_are_worked_out_the_same_way():
    t = "2026-02-01T00:00:00+00:00"
    prev = [
        {"status": "resolved", "severity": "critical", "created_at": t, "dispatched_at": "2026-02-01T00:04:00+00:00",
         "accepted_at": "2026-02-01T00:05:00+00:00", "resolved_at": "2026-02-01T01:00:00+00:00"},
        {"status": "resolved", "severity": "high", "created_at": t, "dispatched_at": "2026-02-01T00:12:00+00:00",
         "accepted_at": "2026-02-01T00:15:00+00:00", "resolved_at": "2026-02-01T02:00:00+00:00"},
        {"status": "cancelled", "severity": "low", "created_at": t},
    ]
    p = svc.build_previous(prev)
    assert p["incidents"] == 3 and p["critical"] == 1
    assert p["resolved_rate"] == 67                              # 2 resolved of 3 closed
    assert p["dispatch_avg"] == 8.0                              # (4 + 12) / 2
    assert p["ack_avg"] == 2.0                                   # (1 + 3) / 2
    assert p["resolution_avg"] == 90.0                           # (60 + 120) / 2
    assert p["dispatch_compliance"] == 50                        # critical 4<=5 on time, high 12>10 late


def test_previous_period_of_nothing_is_empty_not_an_error():
    p = svc.build_previous([])
    assert p["incidents"] == 0 and p["resolved_rate"] is None and p["dispatch_avg"] is None


# ── build_response ───────────────────────────────────────────────────────

def _row(sev, created, dispatched=None, accepted=None, resolved=None, status="resolved"):
    return {"severity": sev, "created_at": created, "dispatched_at": dispatched,
            "accepted_at": accepted, "resolved_at": resolved, "status": status}


def test_build_response_judges_against_the_dispatch_targets():
    t = "2026-03-01T00:00:00+00:00"
    rows = [
        _row("critical", t, "2026-03-01T00:04:00+00:00"),   # 4 min <= 5   on time
        _row("critical", t, "2026-03-01T00:06:00+00:00"),   # 6 min >  5   late
        _row("high", t, "2026-03-01T00:10:00+00:00"),        # 10 min <= 10 on time (boundary counts)
        _row("low", t, None, status="received"),             # still waiting: awaiting, not late
        _row("medium", t, "2026-03-01T00:45:00+00:00", status="cancelled"),  # cancelled: no obligation
    ]
    r = svc.build_response(rows)
    by = {x["severity"]: x for x in r["by_severity"]}
    assert (by["critical"]["on_time"], by["critical"]["late"], by["critical"]["dispatch_compliance"]) == (1, 1, 50)
    assert (by["high"]["on_time"], by["high"]["dispatch_compliance"]) == (1, 100)
    assert (by["low"]["awaiting"], by["low"]["dispatch_compliance"]) == (1, None)
    assert (by["medium"]["on_time"], by["medium"]["late"], by["medium"]["awaiting"]) == (0, 0, 0)
    # 2 on time of 3 decided = 67%
    assert r["dispatch_compliance"] == 67
    assert by["critical"]["dispatch_target_min"] == 5
    assert by["critical"]["ack_deadline_min"] == 1.0


def test_build_response_a_resolved_row_with_no_dispatch_time_is_not_a_queue_item():
    r = svc.build_response([_row("high", "2026-03-01T00:00:00+00:00", None, status="resolved")])
    assert {x["severity"]: x for x in r["by_severity"]}["high"]["awaiting"] == 0


def test_build_response_ack_is_judged_against_the_responder_deadline():
    t = "2026-03-01T00:00:00+00:00"
    rows = [
        _row("critical", t, "2026-03-01T00:01:00+00:00", "2026-03-01T00:01:30+00:00"),   # 0.5 min <= 1   ok
        _row("critical", t, "2026-03-01T00:01:00+00:00", "2026-03-01T00:03:00+00:00"),   # 2 min   >  1   late
        _row("medium", t, "2026-03-01T00:01:00+00:00", "2026-03-01T00:03:00+00:00"),     # 2 min  <= 3   ok
    ]
    by = {x["severity"]: x for x in svc.build_response(rows)["by_severity"]}
    assert by["critical"]["ack_compliance"] == 50
    assert by["medium"]["ack_compliance"] == 100


def test_build_response_resolution_only_counts_resolved_incidents():
    t = "2026-03-01T00:00:00+00:00"
    rows = [
        _row("high", t, resolved="2026-03-01T01:00:00+00:00", status="resolved"),   # 60
        _row("high", t, resolved="2026-03-01T03:00:00+00:00", status="cancelled"),  # excluded
    ]
    assert svc.build_response(rows)["resolution"]["n"] == 1
    assert svc.build_response(rows)["resolution"]["avg"] == 60.0


# ── trend / time patterns ────────────────────────────────────────────────

def test_trend_includes_the_quiet_days_and_uses_philippine_dates():
    # 2026-03-19 17:00 UTC is 2026-03-20 01:00 in the Philippines: it belongs to the 20th.
    rows = [
        {"created_at": "2026-03-19T17:00:00+00:00", "severity": "critical"},
        {"created_at": "2026-03-20T02:00:00+00:00", "severity": "low"},
        {"created_at": "2026-03-18T04:00:00+00:00", "severity": "high"},
    ]
    t = svc.build_trend(rows, 7, NOW)
    assert t["unit"] == "day"
    assert len(t["points"]) == 7                      # every day, even the empty ones
    by = {p["bucket"]: p for p in t["points"]}
    assert by["2026-03-20"] == {"bucket": "2026-03-20", "count": 2, "critical": 1, "high": 0, "serious": 1}
    assert by["2026-03-18"]["count"] == 1 and by["2026-03-18"]["high"] == 1 and by["2026-03-18"]["serious"] == 1
    assert by["2026-03-19"]["count"] == 0
    assert t["points"][0]["bucket"] == "2026-03-14" and t["points"][-1]["bucket"] == "2026-03-20"


def test_trend_tracks_critical_and_high_separately_in_the_same_bucket():
    rows = [
        {"created_at": "2026-03-20T02:00:00+00:00", "severity": "critical"},
        {"created_at": "2026-03-20T03:00:00+00:00", "severity": "high"},
        {"created_at": "2026-03-20T04:00:00+00:00", "severity": "high"},
        {"created_at": "2026-03-20T05:00:00+00:00", "severity": "medium"},
    ]
    t = svc.build_trend(rows, 7, NOW)
    by = {p["bucket"]: p for p in t["points"]}
    assert by["2026-03-20"] == {"bucket": "2026-03-20", "count": 4, "critical": 1, "high": 2, "serious": 3}


def test_trend_switches_unit_with_the_window():
    assert svc.build_trend([], 30, NOW)["unit"] == "day"
    week = svc.build_trend([], 90, NOW)
    assert week["unit"] == "week"
    assert all(datetime.fromisoformat(p["bucket"]).weekday() == 0 for p in week["points"])  # Mondays
    assert svc.build_trend([], 365, NOW)["unit"] == "month"


def test_trend_all_time_starts_at_the_first_report_month():
    rows = [{"created_at": "2025-11-20T04:00:00+00:00", "severity": "low"}]
    t = svc.build_trend(rows, 0, NOW)
    assert t["unit"] == "month"
    assert [p["bucket"] for p in t["points"]] == ["2025-11", "2025-12", "2026-01", "2026-02", "2026-03"]


def test_trend_over_a_chosen_range_covers_exactly_those_days():
    # 1-15 March: fifteen day buckets, ending on the 15th — not stretched to today (the 20th).
    rows = [
        {"created_at": "2026-02-28T16:00:00+00:00", "severity": "critical"},   # 1 March 00:00 PH: the first instant of the range
        {"created_at": "2026-02-28T15:59:59+00:00", "severity": "low"},        # 28 Feb 23:59:59 PH: one second outside it
        {"created_at": "2026-03-15T15:59:59+00:00", "severity": "low"},        # 15 March 23:59:59 PH: the last second inside
    ]
    t = svc.build_trend(rows, 15, NOW, date(2026, 3, 1), date(2026, 3, 15))
    assert t["unit"] == "day" and len(t["points"]) == 15
    assert t["points"][0]["bucket"] == "2026-03-01" and t["points"][-1]["bucket"] == "2026-03-15"
    by = {p["bucket"]: p for p in t["points"]}
    assert by["2026-03-01"] == {"bucket": "2026-03-01", "count": 1, "critical": 1, "high": 0, "serious": 1}
    assert by["2026-03-15"]["count"] == 1
    assert sum(p["count"] for p in t["points"]) == 2                            # the 28 Feb report is not in the range


@pytest.mark.parametrize("first,last,unit,points", [
    (date(2026, 1, 1), date(2026, 2, 14), "day", 45),                            # 45 days: still daily
    (date(2026, 1, 1), date(2026, 2, 15), "week", 7),                            # 46 days: weekly (Mon 29 Dec ... Mon 9 Feb)
    (date(2026, 1, 1), date(2026, 4, 30), "week", 18),                           # 120 days: still weekly
    (date(2026, 1, 1), date(2026, 5, 1), "month", 5),                            # 121 days: monthly (Jan..May)
])
def test_trend_over_a_chosen_range_picks_its_unit_from_the_length(first, last, unit, points):
    span = (last - first).days + 1
    t = svc.build_trend([], span, NOW, first, last)
    assert t["unit"] == unit and len(t["points"]) == points


def test_time_patterns_are_in_philippine_time():
    rows = [
        {"created_at": "2026-03-20T02:00:00+00:00"},   # Fri 10:00 PH
        {"created_at": "2026-03-20T02:30:00+00:00"},   # Fri 10:30 PH
        {"created_at": "2026-03-20T17:00:00+00:00"},   # Sat 01:00 PH (still Friday in UTC!)
    ]
    p = svc.build_time_patterns(rows)
    assert p["by_hour"][10] == 2 and p["by_hour"][1] == 1
    assert p["by_weekday"][4] == 2 and p["by_weekday"][5] == 1
    assert p["heatmap"][4][10] == 2 and p["heatmap"][5][1] == 1
    assert p["peak_hour"] == 10 and p["total"] == 3


def test_time_patterns_empty_has_no_peak():
    p = svc.build_time_patterns([])
    assert p["peak_hour"] is None and p["peak_weekday"] is None and p["total"] == 0


# ── mix / outcomes ───────────────────────────────────────────────────────

def test_mix_counts_signals_whether_stored_as_strings_or_objects():
    m = svc.build_mix([
        {"severity": "high", "incident_category": "fire", "status": "resolved", "overlap_agencies": ["injuries", "none"]},
        {"severity": None, "incident_category": None, "status": "received", "overlap_agencies": [{"flag": "fire"}]},
        {"severity": "high", "incident_category": "fire", "status": "resolved", "overlap_agencies": None},
    ])
    assert m["severity"] == {"high": 2, "untriaged": 1}
    assert m["categories"] == {"fire": 2, "other": 1}
    assert m["multi_agency_signals"] == {"injuries": 1, "fire": 1}       # "none" is not a signal
    assert m["channels"] == {"internet": 3}


def test_outcomes_sum_casualties_and_ignore_missing():
    o = svc.build_outcomes([
        {"outcome": "transported", "casualties_injured": 2, "casualties_fatal": 1, "casualties_transported": 1},
        {"outcome": "false_alarm", "casualties_injured": None},
        {"outcome": None},
    ])
    assert o["counts"] == {"transported": 1, "false_alarm": 1}
    assert o["recorded"] == 2
    assert o["casualties"] == {"injured": 2, "fatal": 1, "transported": 1}


# ── paging ───────────────────────────────────────────────────────────────

def test_fetch_all_pages_past_the_postgrest_row_ceiling():
    rows = [{"n": n} for n in range(2000)]
    fake = FakeDB({"t": rows})
    got = svc._fetch_all(lambda: fake.table("t").select("*").order("n"))
    assert len(got) == 2000 and got[0]["n"] == 0 and got[-1]["n"] == 1999


def test_fetch_all_stops_at_the_hard_cap(monkeypatch):
    monkeypatch.setattr(svc, "_MAX_ROWS", 1800)
    fake = FakeDB({"t": [{"n": n} for n in range(5000)]})
    assert len(svc._fetch_all(lambda: fake.table("t").select("*"))) == 1800


# ══════════════════════ the assembled payload ════════════════════════════

def test_agency_scope_only_counts_its_own_incidents(db):
    out = area()
    # window rows: i1 i2 i3 i4 i7 (i5 is 40 days old; i6 belongs to the PNP agency)
    assert out["kpis"]["incidents"] == 5
    assert out["kpis"]["previous_incidents"] == 1                 # i5, in days 30-60
    ids = {r["id"] for r in out["recent"]}
    assert "i6" not in ids and ids == {"i1", "i2", "i3", "i4", "i7"}


def test_kpis_match_the_hand_computed_figures(db):
    k = area()["kpis"]
    assert k["critical"] == 2                                     # i1, i7
    assert k["sos"] == 1                                          # i1
    assert (k["resolved"], k["cancelled"]) == (3, 1)              # i1 i2 i4 / i3
    assert k["resolved_rate"] == 75                               # 3 of 4 closed
    assert k["false_alarms"] == 1                                 # i4
    assert k["awaiting_dispatch"] == 1 and k["active_now"] == 1   # i7 only
    # dispatch minutes: i1=3, i2=12, i4=30 -> avg 15.0, median 12.0
    assert (k["dispatch"]["n"], k["dispatch"]["avg"], k["dispatch"]["p50"], k["dispatch"]["max"]) == (3, 15.0, 12.0, 30.0)
    # p90 of [3, 12, 30]: rank 1.8 -> 12 + 18*0.8 = 26.4
    assert k["dispatch"]["p90"] == 26.4
    # on time: i1 (3<=5), i4 (30<=60); late: i2 (12>10)  -> 2 of 3
    assert k["dispatch_compliance"] == 67
    # ack: i1 = 1 min, i2 = 3 min -> avg 2.0
    assert (k["ack"]["n"], k["ack"]["avg"]) == (2, 2.0)
    # resolution: i1=60, i2=90, i4=45 -> 65.0
    assert (k["resolution"]["n"], k["resolution"]["avg"]) == (3, 65.0)


def test_residents_are_only_the_areas_own_barangays(db):
    k = area()["kpis"]
    assert k["residents"] == 3                                    # u1 u2 u3; u4 lives in Almeria
    assert k["verified_residents"] == 2 and k["pwd_residents"] == 1
    # u1 is 76 (senior), u2 is 6 (child) and PWD, u3 is 36. u4 lives in Almeria.
    assert (k["senior_residents"], k["child_residents"]) == (1, 1)
    assert k["vulnerable_residents"] == 2                         # u1 and u2; u2 is in two groups but counted once
    assert k["new_residents"] == 2                                # u1 (3 days), u3 (10 days); u2 is 90 days old


def test_barangay_table_lists_every_barangay_and_attributes_by_address(db):
    b = area()["barangays"]
    by = {x["name"]: x for x in b["items"]}
    assert set(by) == {"Caraycaray", "Larrazabal", "Poblacion"}   # Almeria's Poblacion is not here
    assert by["Larrazabal"]["incidents"] == 1 and by["Larrazabal"]["critical"] == 1
    assert by["Caraycaray"]["incidents"] == 1 and by["Poblacion"]["incidents"] == 1
    assert by["Poblacion"]["active"] == 1                          # i7 is still received
    assert by["Caraycaray"]["residents"] == 2 and by["Caraycaray"]["pwd"] == 1
    assert (by["Caraycaray"]["seniors"], by["Caraycaray"]["children"], by["Caraycaray"]["vulnerable"]) == (1, 1, 2)
    assert (by["Larrazabal"]["seniors"], by["Larrazabal"]["children"], by["Larrazabal"]["vulnerable"]) == (0, 0, 0)
    assert by["Caraycaray"]["resident_share"] == 66.7              # 2 of 3
    assert b["matched_incidents"] == 3
    assert b["unlocated_incidents"] == 1                           # i3 has no address
    assert b["unmatched_incidents"] == 1                           # i4: a sitio and a province, no barangay
    assert b["empty_barangays"] == 1                               # Poblacion has no residents


def test_barangay_filter_narrows_the_figures_but_not_the_table(db):
    out = area(barangay="larrazabal")
    assert out["filters"]["barangay"] == "Larrazabal"
    assert out["kpis"]["incidents"] == 1
    assert out["kpis"]["residents"] == 1
    assert len(out["barangays"]["items"]) == 3                     # the table always lists them all
    assert [r["id"] for r in out["recent"]] == ["i1"]


def test_stations_show_incident_counts_only_for_the_admins_own_agency(db):
    st = area()["stations"]
    by = {s["id"]: s for s in st["items"]}
    assert by["s1"]["incidents"] == 4 and by["s1"]["is_own"]       # i1 i2 i3 i4
    assert by["s2"]["incidents"] == 0 and by["s2"]["lat"] is None
    assert by["s3"]["incidents"] is None and not by["s3"]["is_own"]   # someone else's data stays hidden
    assert by["s3"]["dispatch"] is None
    assert st["unassigned_incidents"] == 1                          # i7 has no station


def test_responders_are_the_own_agencys_only(db):
    r = area()["responders"]
    assert (r["approved"], r["on_duty"], r["off_duty"], r["pending"]) == (2, 1, 1, 1)
    assert [x["full_name"] for x in r["roster"]] == ["Juan Cruz", "Ana Reyes", "Pedro Diaz"]
    top = r["roster"][0]
    assert top["incidents"] == 2 and top["resolved"] == 2 and top["has_location"]
    assert top["ack"]["n"] == 2 and top["ack"]["avg"] == 2.0
    assert "Almeria Crew" not in [x["full_name"] for x in r["roster"]]


def test_agencies_present_show_incident_counts_only_for_the_scope(db):
    ag = {a["id"]: a for a in area()["agencies"]}
    assert set(ag) == {A1, A2}                                      # both agencies of Naval; not Almeria's
    assert ag[A1]["incidents"] == 5 and ag[A1]["is_own"]
    assert ag[A2]["incidents"] is None and not ag[A2]["is_own"]
    assert ag[A1]["stations"] == 2 and ag[A1]["mapped_stations"] == 1


def test_readiness_checks_are_derived_from_real_counts(db):
    checks = {c["key"]: c for c in area()["readiness"]}
    assert checks["stations"]["status"] == "warn" and "1 station" in checks["stations"]["title"]
    assert checks["responders"]["status"] == "ok" and "1 on duty" in checks["responders"]["title"]
    assert checks["approvals"]["status"] == "warn"
    assert checks["backlog"]["status"] == "warn" and "1 report" in checks["backlog"]["title"]   # i7: 10 min > 5 min target
    assert checks["adoption"]["status"] == "warn" and "1 of 3" in checks["adoption"]["title"]
    assert checks["contact"]["status"] == "warn" and "email" in checks["contact"]["title"]
    assert checks["locations"]["title"].startswith("80%")          # 4 of 5 carry coordinates
    assert checks["backlog"]["href"] == "/incidents" and checks["adoption"]["tab"] == "barangays"


def test_backlog_within_target_is_informational_not_a_warning(db):
    for row in db.tables["incidents"]:
        if row["id"] == "i7":
            row["created_at"] = iso(NOW - timedelta(minutes=2))     # inside the 5-minute critical target
    assert {c["key"]: c for c in area()["readiness"]}["backlog"]["status"] == "info"


def test_awaiting_dispatch_ignores_the_window(db):
    """A report from three months ago that nobody answered is the most urgent row, not old news."""
    db.tables["incidents"].append(_incident("i8", days=100, status="processing", severity="high"))
    out = area(days=7)
    assert out["kpis"]["awaiting_dispatch"] == 2                    # i7 and the old one
    assert out["kpis"]["incidents"] == 4                            # i1 i2 i3 i7 inside 7 days (i4 is 20 days old)


def test_trend_and_patterns_cover_the_window(db):
    out = area()
    pts = {p["bucket"]: p for p in out["trend"]["points"]}
    assert len(out["trend"]["points"]) == 30
    assert pts["2026-03-20"]["count"] == 2 and pts["2026-03-20"]["serious"] == 2     # i1, i7
    assert pts["2026-03-19"]["count"] == 1 and pts["2026-03-19"]["serious"] == 1     # i2 (high)
    assert sum(p["count"] for p in out["trend"]["points"]) == 5
    tp = out["time_patterns"]
    assert tp["by_hour"][12] == 3 and tp["peak_hour"] == 12          # i2, i3, i4 all at noon Philippine time
    assert tp["by_hour"][10] == 1 and tp["by_hour"][11] == 1         # i1 at 10:00, i7 at 11:50
    # i2 Thu 19th; i1 + i7 Fri 20th; i4 is 20 days back = Sat 28 Feb; i3 Sun 15th
    assert tp["by_weekday"][3] == 1 and tp["by_weekday"][4] == 2
    assert tp["by_weekday"][5] == 1 and tp["by_weekday"][6] == 1


def test_the_payload_carries_the_previous_period_for_comparison(db):
    prev = area()["kpis"]["previous"]
    # previous window (30-60 days ago) holds only i5: high, resolved, dispatched +2, resolved +20
    assert prev["incidents"] == 1 and prev["critical"] == 0
    assert prev["resolved_rate"] == 100
    assert prev["dispatch_avg"] == 2.0 and prev["resolution_avg"] == 20.0
    assert prev["ack_avg"] is None                               # i5 was never accepted


def test_the_payload_lists_repeat_locations(db):
    for row in db.tables["incidents"]:
        if row["id"] == "i5":
            row["created_at"] = iso(ago(days=6))                 # bring i5 (Caraycaray) inside the window
    h = area()["hotspots"]
    assert [(x["place"], x["count"]) for x in h] == [("Caraycaray", 2)]     # i2 and i5; Larrazabal and Poblacion appear once
    assert h[0]["barangay"] == "Caraycaray"


def test_all_time_has_no_previous_period(db):
    out = area(days=0)
    assert out["kpis"]["incidents"] == 6                            # adds i5
    assert out["kpis"]["previous_incidents"] is None and out["kpis"]["new_residents"] is None
    assert out["kpis"]["previous"] is None
    assert out["filters"]["since"] is None and out["trend"]["unit"] == "month"


def test_a_chosen_range_counts_only_reports_created_on_those_days(db):
    # 15-19 March: i2 (19th, 12:00 PH) and i3 (15th, 12:00 PH). i1 and i7 are the 20th, i4 is 28 Feb.
    out = area(date_from=date(2026, 3, 15), date_to=date(2026, 3, 19))
    assert out["kpis"]["incidents"] == 2
    assert {r["id"] for r in out["recent"]} == {"i2", "i3"}
    assert out["filters"]["days"] == 5                                            # its length, five whole days
    assert (out["filters"]["date_from"], out["filters"]["date_to"]) == ("2026-03-15", "2026-03-19")
    assert out["filters"]["since"] == "2026-03-15T00:00:00+08:00"
    assert out["filters"]["until"] == "2026-03-20T00:00:00+08:00"                 # exclusive: midnight ending the 19th
    k = out["kpis"]
    assert (k["resolved"], k["cancelled"]) == (1, 1) and k["resolved_rate"] == 50   # i2 resolved, i3 cancelled: 1 of 2 closed
    assert k["dispatch"]["avg"] == 12.0 and k["ack"]["avg"] == 3.0                 # i2 only
    assert k["critical"] == 0


def test_a_chosen_range_takes_its_days_in_philippine_time_not_utc(db):
    # 2026-03-19 16:00 UTC is exactly midnight starting the 20th in the Philippines.
    db.tables["incidents"] += [
        _incident("last_second", created_at="2026-03-19T15:59:59+00:00"),          # 19 March 23:59:59 PH
        _incident("first_second", created_at="2026-03-19T16:00:00+00:00"),         # 20 March 00:00:00 PH
    ]
    through_19th = {r["id"] for r in area(date_from=date(2026, 3, 19), date_to=date(2026, 3, 19))["recent"]}
    on_the_20th = {r["id"] for r in area(date_from=date(2026, 3, 20), date_to=date(2026, 3, 20))["recent"]}
    assert through_19th == {"i2", "last_second"}                                   # i2 is the 19th at noon
    assert on_the_20th == {"i1", "i7", "first_second"}


def test_a_chosen_range_is_compared_with_the_equally_long_range_before_it(db):
    # 1-20 March is twenty days, so the range before it is 9-28 February: it holds i4 (28 Feb) but not i5 (8 Feb).
    out = area(date_from=date(2026, 3, 1), date_to=date(2026, 3, 20))
    assert out["kpis"]["incidents"] == 4                                          # i1 i2 i3 i7
    assert out["kpis"]["previous_incidents"] == 1 and out["kpis"]["previous"]["incidents"] == 1
    # i4: low, resolved, dispatched +30, resolved +45
    assert out["kpis"]["previous"]["dispatch_avg"] == 30.0 and out["kpis"]["previous"]["resolution_avg"] == 45.0


def test_a_range_in_the_past_ignores_everything_newer_but_keeps_live_figures_live(db):
    out = area(date_from=date(2026, 2, 1), date_to=date(2026, 2, 10))
    assert out["kpis"]["incidents"] == 1 and {r["id"] for r in out["recent"]} == {"i5"}      # i5 was 8 Feb
    assert out["kpis"]["previous_incidents"] == 0                                 # 22-31 January: nothing
    pts = out["trend"]["points"]
    assert [p["bucket"] for p in pts][0] == "2026-02-01" and pts[-1]["bucket"] == "2026-02-10" and len(pts) == 10
    assert {p["bucket"]: p["count"] for p in pts}["2026-02-08"] == 1
    # "active now" and "awaiting dispatch" are the state of the queue today, whatever period is on screen
    assert out["kpis"]["awaiting_dispatch"] == 1 and out["kpis"]["active_now"] == 1            # i7


def test_a_chosen_range_that_ends_in_the_future_stops_at_today(db):
    out = area(date_from=date(2026, 3, 15), date_to=date(2026, 12, 31))
    assert out["filters"]["date_to"] == "2026-03-20" and out["filters"]["days"] == 6            # 15..20 March
    assert out["kpis"]["incidents"] == 4                                                        # i1 i2 i3 i7
    assert out["trend"]["points"][-1]["bucket"] == "2026-03-20"


def test_a_chosen_range_that_starts_after_it_ends_or_in_the_future_is_refused(db):
    with pytest.raises(ValueError):
        area(date_from=date(2026, 3, 10), date_to=date(2026, 3, 1))
    with pytest.raises(ValueError):
        area(date_from=date(2026, 3, 21), date_to=date(2026, 3, 25))                            # tomorrow onwards


def test_a_chosen_range_counts_new_residents_by_the_days_they_joined(db):
    # Naval residents joined: u1 on 17 March, u3 on 10 March, u2 in December. Both ends of the range are included.
    assert area(date_from=date(2026, 3, 10), date_to=date(2026, 3, 17))["kpis"]["new_residents"] == 2
    assert area(date_from=date(2026, 3, 11), date_to=date(2026, 3, 16))["kpis"]["new_residents"] == 0
    assert area(date_from=date(2026, 3, 11), date_to=date(2026, 3, 17))["kpis"]["new_residents"] == 1


def test_a_chosen_range_and_a_barangay_narrow_together_but_the_table_still_lists_everyone(db):
    out = area(date_from=date(2026, 3, 15), date_to=date(2026, 3, 19), barangay="Caraycaray")
    assert out["kpis"]["incidents"] == 1                                          # i2 (Caraycaray, the 19th); i3 has no address
    by = {b["name"]: b["incidents"] for b in out["barangays"]["items"]}
    assert by == {"Caraycaray": 1, "Larrazabal": 0, "Poblacion": 0}               # counts for the whole municipality in the range


def test_a_chosen_range_reaches_the_province_comparison(db):
    now_range = svc.get_operational_area(municipality="Naval", agency_type="BFP", now=NOW,
                                         date_from=date(2026, 3, 15), date_to=date(2026, 3, 19))
    comp = {c["municipality"]: c for c in now_range["comparison"]}
    assert comp["Naval"]["incidents"] == 2 and comp["Almeria"]["incidents"] == 0  # i2, i3 — and not the PNP i6
    past = svc.get_operational_area(municipality="Naval", agency_type="BFP", now=NOW,
                                    date_from=date(2026, 2, 1), date_to=date(2026, 2, 10))
    assert {c["municipality"]: c["incidents"] for c in past["comparison"]}["Naval"] == 1        # i5 only


def test_a_rolling_window_reports_no_fixed_dates(db):
    f = area()["filters"]
    assert f["date_from"] is None and f["date_to"] is None and f["until"] is None


def test_mix_and_outcomes_in_the_payload(db):
    out = area()
    assert out["mix"]["severity"] == {"critical": 2, "high": 1, "medium": 1, "low": 1}
    assert out["mix"]["categories"] == {"fire": 3, "vehicular": 1, "medical_trauma": 1}
    assert out["mix"]["channels"] == {"internet": 4, "sos": 1}
    assert out["mix"]["multi_agency_signals"] == {"injuries": 1, "fire": 1}
    assert out["outcomes"]["counts"] == {"transported": 1, "handled_on_scene": 1, "false_alarm": 1}
    assert out["outcomes"]["casualties"] == {"injured": 2, "fatal": 0, "transported": 1}


def test_map_payload_uses_the_shape_the_map_already_reads(db):
    m = area()["map"]
    assert {i["id"] for i in m["incidents"]} == {"i1", "i2", "i4", "i7"}          # i3 has no coordinates
    assert m["incidents_with_coordinates"] == 4
    assert m["coverage_polygons"] == []                                            # placeholder boxes are not drawn as fact
    assert {s["id"] for s in m["stations"]} == {"s1", "s3"}                        # s2 has no coordinates
    assert [r["full_name"] for r in m["responders"]] == ["Juan Cruz"]
    inc = next(i for i in m["incidents"] if i["id"] == "i1")
    assert inc["agency_type"] == "BFP" and inc["route"] is None and inc["sos_flagged"] is True


def test_provincial_scope_is_the_agency_type_and_adds_the_comparison(db):
    out = svc.get_operational_area(municipality="Naval", days=30, agency_type="BFP", now=NOW)
    assert out["kpis"]["incidents"] == 5                                            # BFP Naval only, not the PNP i6
    assert out["area"]["agency"] is None
    comp = {c["municipality"]: c for c in out["comparison"]}
    assert set(comp) == {"Naval", "Almeria"}
    assert comp["Naval"]["incidents"] == 5 and comp["Naval"]["critical"] == 2
    assert comp["Naval"]["barangays"] == 3 and comp["Naval"]["residents"] == 3
    assert comp["Naval"]["stations"] == 3 and comp["Naval"]["responders"] == 2 and comp["Naval"]["on_duty"] == 1
    assert comp["Almeria"]["residents"] == 1 and comp["Almeria"]["responders"] == 1 and comp["Almeria"]["incidents"] == 0


def test_agency_scope_has_no_comparison(db):
    assert "comparison" not in area()


def test_a_municipality_with_no_data_still_returns_a_complete_shape(db):
    out = svc.get_operational_area(municipality="Almeria", days=30, agency_id=A3, now=NOW)
    assert out["kpis"]["incidents"] == 0 and out["kpis"]["dispatch"]["avg"] is None
    assert out["kpis"]["resolved_rate"] is None
    assert len(out["trend"]["points"]) == 30 and sum(p["count"] for p in out["trend"]["points"]) == 0
    assert out["time_patterns"]["peak_hour"] is None
    assert out["recent"] == [] and out["map"]["incidents"] == []


def test_an_agency_with_no_row_returns_empty_not_an_error(db):
    out = svc.get_operational_area(municipality="Naval", days=30, agency_id="does-not-exist", now=NOW)
    assert out["kpis"]["incidents"] == 0 and out["responders"]["approved"] == 0


# ══════════════════════ the route ════════════════════════════════════════

def _profile(user_id, role, agency_id=None, agency_type=None):
    return {"id": user_id, "email": "t@example.com", "full_name": "T", "role": role, "approval_status": "not_required",
            "agency_id": agency_id, "agency_type": agency_type, "badge_id": None, "is_verified": True}


def _auth_db(user_id, role, agency_id=None, agency_type=None):
    user = MagicMock(); user.id = user_id
    got = MagicMock(); got.user = user
    profile = MagicMock(); profile.data = _profile(user_id, role, agency_id, agency_type)
    d = MagicMock()
    d.auth.get_user.return_value = got
    d.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return d


AUTH = {"Authorization": "Bearer token"}


def test_route_forbidden_for_resident():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("r", "resident")):
        assert client.get("/geographic/operational-area?municipality=Naval", headers=AUTH).status_code == 403


def test_route_agency_admin_is_locked_to_their_own_municipality_and_agency():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", A1)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"), \
         patch("app.routers.geographic.operational_area_service.get_operational_area", return_value={"stub": 1}) as get:
        resp = client.get("/geographic/operational-area?municipality=SomewhereElse&days=90", headers=AUTH)
    assert resp.status_code == 200, resp.text
    get.assert_called_once_with(municipality="Naval", days=90, barangay=None, agency_id=A1, agency_type=None,
                                date_from=None, date_to=None)


def test_route_provincial_admin_picks_a_municipality_and_is_scoped_to_their_type():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type="PNP")), \
         patch("app.routers.geographic.operational_area_service.get_operational_area", return_value={"stub": 1}) as get:
        resp = client.get("/geographic/operational-area?municipality=Almeria", headers=AUTH)
    assert resp.status_code == 200, resp.text
    get.assert_called_once_with(municipality="Almeria", days=30, barangay=None, agency_id=None, agency_type="PNP",
                                date_from=None, date_to=None)


def test_route_provincial_admin_must_name_a_municipality():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type="PNP")):
        assert client.get("/geographic/operational-area", headers=AUTH).status_code == 422
        assert client.get("/geographic/operational-area?municipality=%20%20", headers=AUTH).status_code == 422


def test_route_agency_admin_without_a_municipality_is_422():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", A1)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value=None):
        assert client.get("/geographic/operational-area", headers=AUTH).status_code == 422


def test_route_rejects_a_barangay_that_is_not_in_the_municipality():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", A1)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"), \
         patch("app.routers.geographic.operational_area_service.list_barangays", return_value=[{"id": "b", "name": "Larrazabal"}]), \
         patch("app.routers.geographic.operational_area_service.get_operational_area", return_value={"stub": 1}) as get:
        bad = client.get("/geographic/operational-area?barangay=Atlantis", headers=AUTH)
        good = client.get("/geographic/operational-area?barangay=%20larrazabal%20", headers=AUTH)
    assert bad.status_code == 422 and "Atlantis" in bad.json()["detail"]
    assert good.status_code == 200
    assert get.call_args.kwargs["barangay"] == " larrazabal "


@pytest.mark.parametrize("days", ["-1", "99999", "abc"])
def test_route_validates_the_window(days):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", A1)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"):
        assert client.get(f"/geographic/operational-area?days={days}", headers=AUTH).status_code == 422


def _agency_route(query):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", A1)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"), \
         patch("app.routers.geographic.operational_area_service.get_operational_area", return_value={"stub": 1}) as get:
        resp = client.get(f"/geographic/operational-area?{query}", headers=AUTH)
    return resp, get


def test_route_passes_a_chosen_range_to_the_service():
    resp, get = _agency_route("date_from=2026-03-01&date_to=2026-03-15")
    assert resp.status_code == 200, resp.text
    assert get.call_args.kwargs["date_from"] == date(2026, 3, 1) and get.call_args.kwargs["date_to"] == date(2026, 3, 15)


def test_route_a_single_day_is_a_valid_range():
    resp, get = _agency_route("date_from=2026-03-15&date_to=2026-03-15")
    assert resp.status_code == 200 and get.call_args.kwargs["date_from"] == get.call_args.kwargs["date_to"]


@pytest.mark.parametrize("query,why", [
    ("date_from=2026-03-01", "only a start"),
    ("date_to=2026-03-15", "only an end"),
    ("date_from=2026-03-15&date_to=2026-03-01", "start after end"),
    ("date_from=2999-01-01&date_to=2999-02-01", "starts in the future"),
    ("date_from=2000-01-01&date_to=2026-03-01", "longer than 3650 days"),
    ("date_from=soon&date_to=2026-03-01", "not a date"),
    ("date_from=2026-13-40&date_to=2026-03-01", "not a real date"),
])
def test_route_refuses_a_bad_range(query, why):
    resp, get = _agency_route(query)
    assert resp.status_code == 422, (why, resp.text)
    get.assert_not_called()


def test_route_clamps_an_end_date_in_the_future_to_today():
    before = datetime.now(svc.PH_TZ).date()
    resp, get = _agency_route("date_from=2026-03-01&date_to=2999-12-31")
    after = datetime.now(svc.PH_TZ).date()
    assert resp.status_code == 200, resp.text
    assert get.call_args.kwargs["date_to"] in {before, after}                      # a midnight rollover mid-test is allowed for


def test_route_a_range_wins_over_days():
    resp, get = _agency_route("days=7&date_from=2026-03-01&date_to=2026-03-15")
    assert resp.status_code == 200
    assert get.call_args.kwargs["date_from"] == date(2026, 3, 1)                  # the service ignores `days` when both ends are given


def test_route_days_zero_means_all_time():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", A1)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"), \
         patch("app.routers.geographic.operational_area_service.get_operational_area", return_value={"stub": 1}) as get:
        assert client.get("/geographic/operational-area?days=0", headers=AUTH).status_code == 200
    assert get.call_args.kwargs["days"] == 0
