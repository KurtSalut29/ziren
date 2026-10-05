"""
weather_alerts: the backend-sent "heavy rain in about an hour" push.

Why it exists (the phone-side alarm was swallowed by Transsion's battery
manager on the user's Infinix) is in the module docstring.
"""

from datetime import datetime, timedelta, timezone

import pytest

from app.services import push_service, weather_alerts as wa

PH = timezone(timedelta(hours=8))


def iso(hour: int, day: int = 6, minute: int = 0) -> str:
    return datetime(2026, 10, day, hour, minute, tzinfo=PH).isoformat()


def at(hour: int, minute: int = 0, day: int = 6) -> datetime:
    return datetime(2026, 10, day, hour, minute, tzinfo=PH)


def win(kind, level, start, end, day=6, peak=5.0):
    return {"kind": kind, "level": level, "starts_at": iso(start, day), "ends_at": iso(end, day),
            "peak_at": iso(start, day), "peak": peak}


@pytest.fixture(autouse=True)
def _clean():
    wa.reset()
    yield
    wa.reset()


# ── Planning ──────────────────────────────────────────────────────────────


def test_overlapping_storm_and_rain_are_one_reminder_worded_as_the_storm():
    p = wa.plans([win("thunderstorm", "moderate", 15, 17), win("rain", "heavy", 16, 18)])
    assert len(p) == 1
    assert p[0]["slot"] == "rain"
    assert p[0]["thunder"] is True
    assert p[0]["level"] == "heavy"
    assert p[0]["send_at"] == at(14)
    assert p[0]["ends_at"] == iso(18)


def test_night_only_heavy_rain_is_sent():
    assert wa.plans([win("rain", "moderate", 2, 3, day=7), win("thunderstorm", "light", 4, 5, day=7)]) == []
    p = wa.plans([win("rain", "moderate", 2, 3, day=7), win("rain", "intense", 4, 6, day=7)])
    assert [x["starts_at"] for x in p] == [iso(4, 7)]


def test_heat_has_its_own_slot():
    p = wa.plans([win("heat", "danger", 12, 15, peak=45.2), win("rain", "moderate", 16, 17)])
    assert {x["slot"] for x in p} == {"rain", "heat"}
    heat = next(x for x in p if x["slot"] == "heat")
    assert heat["send_at"] == at(11)
    assert heat["peak"] == 45.2


# ── When it is sent ───────────────────────────────────────────────────────


def test_sent_in_the_tick_after_its_time_and_only_once():
    watch = [win("rain", "heavy", 15, 17)]
    assert wa.due("Naval", watch, at(13, 50)) == []          # too early
    assert len(wa.due("Naval", watch, at(14, 5))) == 1       # due
    assert wa.due("Naval", watch, at(14, 12)) == []          # already sent
    # Another town is its own reminder.
    assert len(wa.due("Almeria", watch, at(14, 5))) == 1


def test_a_missed_moment_is_not_sent_late():
    watch = [win("rain", "heavy", 15, 17)]
    assert wa.due("Naval", watch, at(14, 20)) == []  # "in about an hour" would be wrong now


def test_a_forecast_nudging_the_start_does_not_send_again():
    assert len(wa.due("Naval", [win("rain", "heavy", 15, 17)], at(14, 5))) == 1
    # Next tick the model says 15:00 -> 15:00 still, or the spell moved to start
    # at 16:00 and last till 18:00: still the same spell, not a new reminder.
    assert wa.due("Naval", [win("rain", "heavy", 16, 18)], at(15, 5)) == []
    # After the spell, a new one is a new reminder.
    assert len(wa.due("Naval", [win("rain", "heavy", 20, 21)], at(19, 5))) == 1


# ── Who gets it ───────────────────────────────────────────────────────────


@pytest.mark.parametrize("address,town", [
    ("Naval", "Naval"),
    ("Naval, Biliran", "Naval"),
    ("MUNICIPALITY OF CAIBIRAN", "Caibiran"),
    ("Biliran", "Biliran"),
    ("Biliran, Biliran", "Biliran"),
    ("Kawayan, Biliran Province", "Kawayan"),
    ("Tacloban City", None),
    (None, None),
])
def test_town_of_address(address, town):
    assert wa._town_of(address) == town


def test_run_once_pushes_data_only_to_the_towns_residents(monkeypatch):
    now = at(14, 3)

    def fake_forecast(lat, lng, now=None):
        rainy = (lat, lng) == wa.TOWNS["Caibiran"]
        return {"watch": [win("thunderstorm", "heavy", 15, 16)] if rainy else []}

    sent = []
    monkeypatch.setattr(wa.ws, "forecast", fake_forecast)
    monkeypatch.setattr(wa, "residents_by_town", lambda: {"Caibiran": ["r1", "r2"], "Naval": ["r3"]})
    monkeypatch.setattr(push_service, "send_data_to_users",
                        lambda ids, data, ttl_seconds: sent.append((ids, data, ttl_seconds)))

    assert wa.run_once(now) == 1
    assert len(sent) == 1
    ids, data, ttl = sent[0]
    assert ids == ["r1", "r2"]
    assert data["ziren_weather"] == "rain"
    assert data["thunder"] == "1"
    assert data["level"] == "heavy"
    assert data["town"] == "Caibiran"
    assert data["starts_at"] == iso(15)
    # Lives only until the storm starts.
    assert ttl == 57 * 60
    assert all(isinstance(v, str) for v in data.values())

    # Next tick: nothing new.
    assert wa.run_once(at(14, 13)) == 0


def test_run_once_skips_the_resident_query_when_nothing_is_due(monkeypatch):
    monkeypatch.setattr(wa.ws, "forecast", lambda lat, lng, now=None: {"watch": []})

    def boom():
        raise AssertionError("queried users for nothing")

    monkeypatch.setattr(wa, "residents_by_town", boom)
    assert wa.run_once(at(9)) == 0


def test_a_town_whose_forecast_fails_does_not_stop_the_others(monkeypatch):
    def flaky(lat, lng, now=None):
        if (lat, lng) == wa.TOWNS["Naval"]:
            raise wa.ws.WeatherUnavailable("down")
        return {"watch": [win("rain", "heavy", 15, 16)]}

    sent = []
    monkeypatch.setattr(wa.ws, "forecast", flaky)
    monkeypatch.setattr(wa, "residents_by_town", lambda: {t: [t] for t in wa.TOWNS})
    monkeypatch.setattr(push_service, "send_data_to_users", lambda ids, data, ttl_seconds: sent.append(ids))
    assert wa.run_once(at(14, 1)) == len(wa.TOWNS) - 1
    assert ["Naval"] not in sent


def test_data_push_is_data_only_high_priority_with_ttl():
    msg = push_service._message("tok", "", None, {"ziren_weather": "rain"}, True, None, True, 3420)
    assert "notification" not in msg
    assert msg["android"] == {"priority": "HIGH", "ttl": "3420s"}


def test_scheduler_does_not_start_without_fcm(monkeypatch):
    monkeypatch.setattr(push_service, "enabled", lambda: False)
    assert wa.start() is False
