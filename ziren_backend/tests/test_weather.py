"""
/weather and weather_service: heat index and rain grading on PAGASA's scales,
the reminder windows, the 5 km grid, the cache and its stale fallback.

Open-Meteo is never called: _fetch is replaced with a canned response.
"""

import time
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.core.dependencies import get_current_user
from app.main import app
from app.services import weather_service as ws

client = TestClient(app)
PH = timezone(timedelta(hours=8))
RESIDENT = {"id": "11111111-1111-4111-8111-111111111111", "role": "resident"}


@pytest.fixture(autouse=True)
def _clean():
    ws.clear_cache()
    yield
    ws.clear_cache()
    app.dependency_overrides.clear()


def _raw(overrides: dict[int, dict] | None = None) -> dict:
    """48 hours from 2026-10-06 00:00 local: 28 C, 70 %, dry, cloudy,
    90 % chance of rain (the usual Biliran afternoon number) for 0.0 mm."""
    hours = 48
    base = datetime(2026, 10, 6)
    h = {
        "time": [(base + timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M") for i in range(hours)],
        "temperature_2m": [28.0] * hours,
        "relative_humidity_2m": [70] * hours,
        "precipitation_probability": [90] * hours,
        "precipitation": [0.0] * hours,
        "weather_code": [3] * hours,
        "uv_index": [0.0] * hours,
        "wind_speed_10m": [10.0] * hours,
        "is_day": [1 if 6 <= i % 24 < 18 else 0 for i in range(hours)],
    }
    for i, fields in (overrides or {}).items():
        for k, v in fields.items():
            h[k][i] = v
    return {
        "utc_offset_seconds": 28800,
        "current": {"time": "2026-10-06T10:15", "temperature_2m": 28.0, "relative_humidity_2m": 70,
                    "precipitation": 0.0, "weather_code": 3, "wind_speed_10m": 10.0, "is_day": 1},
        "hourly": h,
        "daily": {"time": ["2026-10-06", "2026-10-07", "2026-10-08"], "weather_code": [95, 3, 61],
                  "temperature_2m_max": [31, 30, 29], "temperature_2m_min": [24, 24, 23],
                  "precipitation_sum": [12.0, 0.0, 4.0], "precipitation_probability_max": [100, 60, 80],
                  "uv_index_max": [9, 8, 7]},
    }


NOW = datetime(2026, 10, 6, 10, 20, tzinfo=PH)


# ── Grading ───────────────────────────────────────────────────────────────


def test_heat_index_matches_the_noaa_table():
    # NOAA's published chart: 86 F / 75 % -> 97 F, 96 F / 65 % -> 121 F.
    assert ws.heat_index_c(30.0, 75) == pytest.approx(36.1, abs=0.6)
    assert ws.heat_index_c(35.6, 65) == pytest.approx(49.4, abs=0.8)
    # Cool air just feels like itself.
    assert ws.heat_index_c(24.0, 60) == pytest.approx(24.0, abs=1.0)
    assert ws.heat_index_c(None, 60) is None


@pytest.mark.parametrize("hi,level", [
    (26.9, "none"), (27.0, "caution"), (32.9, "caution"), (33.0, "extreme_caution"),
    (41.9, "extreme_caution"), (42.0, "danger"), (51.9, "danger"), (52.0, "extreme_danger"),
])
def test_heat_levels_follow_pagasa(hi, level):
    assert ws.heat_level(hi) == level


@pytest.mark.parametrize("mm,level", [
    (0.0, "none"), (0.2, "none"), (0.3, "light"), (2.5, "moderate"), (7.5, "heavy"),
    (15.0, "intense"), (30.0, "torrential"), (None, "none"),
])
def test_rain_levels_follow_pagasa(mm, level):
    assert ws.rain_level(mm) == level


@pytest.mark.parametrize("code,cond", [
    (0, "clear"), (2, "partly_cloudy"), (3, "cloudy"), (45, "fog"), (53, "drizzle"),
    (63, "rain"), (80, "rain"), (65, "heavy_rain"), (82, "heavy_rain"), (95, "thunderstorm"), (None, "cloudy"),
])
def test_conditions(code, cond):
    assert ws.condition(code) == cond


# ── Shaping ───────────────────────────────────────────────────────────────


def test_hours_start_at_the_current_hour_in_manila_time():
    out = ws.shape(_raw(), now=NOW)
    assert out["hours"][0]["time"] == "2026-10-06T10:00:00+08:00"
    assert len(out["hours"]) == ws.HOURS_SHOWN
    assert out["current"]["time"] == "2026-10-06T10:15:00+08:00"
    assert [d["date"] for d in out["days"]] == ["2026-10-06", "2026-10-07", "2026-10-08"]


def test_a_high_chance_of_rain_with_no_rain_is_not_rain():
    out = ws.shape(_raw(), now=NOW)
    assert all(h["rain_level"] == "none" for h in out["hours"])
    assert out["watch"] == []
    assert out["outlook"]["rain_starts_at"] is None


def test_rain_windows_bridge_one_dry_hour():
    raw = _raw({14: {"precipitation": 3.0}, 15: {"precipitation": 9.0}, 17: {"precipitation": 2.6},
                21: {"precipitation": 4.0}})
    out = ws.shape(raw, now=NOW)
    rain = [w for w in out["watch"] if w["kind"] == "rain"]
    assert len(rain) == 2
    assert rain[0]["starts_at"] == "2026-10-06T14:00:00+08:00"
    assert rain[0]["ends_at"] == "2026-10-06T18:00:00+08:00"
    assert rain[0]["level"] == "heavy"
    assert rain[0]["peak_at"] == "2026-10-06T15:00:00+08:00"
    assert rain[1]["starts_at"] == "2026-10-06T21:00:00+08:00"
    assert out["outlook"]["rain_starts_at"] == "2026-10-06T14:00:00+08:00"
    assert out["outlook"]["rain_level"] == "heavy"


def test_light_rain_is_in_the_outlook_but_not_a_reminder():
    out = ws.shape(_raw({13: {"precipitation": 1.0, "weather_code": 51}}), now=NOW)
    assert out["watch"] == []
    assert out["outlook"]["rain_starts_at"] == "2026-10-06T13:00:00+08:00"
    assert out["outlook"]["rain_level"] == "light"


def test_thunderstorm_needs_a_real_chance():
    raw = _raw({16: {"weather_code": 95, "precipitation_probability": 80},
                19: {"weather_code": 95, "precipitation_probability": 20}})
    out = ws.shape(raw, now=NOW)
    thunder = [w for w in out["watch"] if w["kind"] == "thunderstorm"]
    assert [w["starts_at"] for w in thunder] == ["2026-10-06T16:00:00+08:00"]
    assert out["outlook"]["thunder_at"] == "2026-10-06T16:00:00+08:00"


def test_heat_reminder_only_from_danger_level():
    # 34 C at 70 % is about 47 C heat index: danger. 31 C at 70 % is extreme caution.
    raw = _raw({12: {"temperature_2m": 34.0}, 13: {"temperature_2m": 34.0}, 11: {"temperature_2m": 31.0}})
    out = ws.shape(raw, now=NOW)
    heat = [w for w in out["watch"] if w["kind"] == "heat"]
    assert len(heat) == 1
    assert heat[0]["starts_at"] == "2026-10-06T12:00:00+08:00"
    assert heat[0]["ends_at"] == "2026-10-06T14:00:00+08:00"
    assert heat[0]["level"] == "danger"
    assert out["outlook"]["heat_level"] == "danger"
    assert out["hours"][1]["heat_level"] == "extreme_caution"


def test_past_hours_are_never_windows():
    out = ws.shape(_raw({8: {"precipitation": 20.0}}), now=NOW)
    assert out["watch"] == []


# ── Grid ──────────────────────────────────────────────────────────────────


def test_points_snap_to_the_grid():
    assert ws.snap(11.5617, 124.3966) == (11.55, 124.4)
    assert ws.snap(11.574, 124.374) == (11.55, 124.35)
    assert ws.snap(None, None) == ws.snap(ws.DEFAULT_LAT, ws.DEFAULT_LNG)


def test_outside_the_philippines_is_refused():
    with pytest.raises(ws.OutsideCoverage):
        ws.snap(35.68, 139.69)


# ── Endpoint ──────────────────────────────────────────────────────────────


def _signed_in():
    app.dependency_overrides[get_current_user] = lambda: RESIDENT


def test_endpoint_sends_only_the_grid_cell_and_caches(monkeypatch):
    _signed_in()
    calls = []

    def fake_fetch(lat, lng):
        calls.append((lat, lng))
        return _raw()

    monkeypatch.setattr(ws, "_fetch", fake_fetch)
    r1 = client.get("/weather/", params={"lat": 11.5617, "lng": 124.3966})
    r2 = client.get("/weather/", params={"lat": 11.5599, "lng": 124.4012})  # same cell
    assert r1.status_code == 200 and r2.status_code == 200
    assert calls == [(11.55, 124.4)]
    body = r1.json()
    assert body["place"] == {"lat": 11.55, "lng": 124.4}
    assert body["source"] == "Open-Meteo"
    assert body["stale"] is False
    assert {"current", "hours", "days", "outlook", "watch", "fetched_at"} <= body.keys()


def test_endpoint_serves_the_last_forecast_when_open_meteo_is_down(monkeypatch):
    _signed_in()
    key = ws.snap(None, None)
    ws._cache[key] = (time.monotonic() - ws.CACHE_TTL_S - 5, time.time() - 1900, _raw())

    def down(lat, lng):
        raise RuntimeError("connect timeout")

    monkeypatch.setattr(ws, "_fetch", down)
    r = client.get("/weather/")
    assert r.status_code == 200
    assert r.json()["stale"] is True


def test_endpoint_503_when_nothing_to_serve(monkeypatch):
    _signed_in()

    def down(lat, lng):
        raise RuntimeError("connect timeout")

    monkeypatch.setattr(ws, "_fetch", down)
    r = client.get("/weather/")
    assert r.status_code == 503


def test_endpoint_refuses_points_abroad(monkeypatch):
    _signed_in()
    monkeypatch.setattr(ws, "_fetch", lambda lat, lng: _raw())
    r = client.get("/weather/", params={"lat": 35.68, "lng": 139.69})
    assert r.status_code == 422


def test_endpoint_needs_a_signed_in_account():
    r = client.get("/weather/")
    assert r.status_code in (401, 403)
