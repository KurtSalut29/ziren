"""
The weather reminder push: "heavy rain in about an hour" on a resident's
phone, sent by the backend.

WHY THE BACKEND SENDS IT

The first version scheduled the reminder on the phone (an Android alarm). On
the user's Infinix it never arrived: Transsion's battery manager ("Usf_Hiber")
freezes a closed app about five seconds after it leaves the screen and takes
over its alarms (logcat: `proxy alarm (uid=..., pkgName=com.ziren.app)`). The
alarm fired and was swallowed. Infinix, Tecno and itel phones are everywhere
in Biliran. What does get through is a high-priority FCM message, the same
path the responder alarm uses. So the backend watches the forecast and pushes.

That also covers the resident who has not opened the app for days, which a
phone-side alarm never could.

HOW

Every TICK_S, for each of Biliran's eight towns (the poblacion's coordinates):

  * read the forecast through weather_service (cached, so 8 calls per 30 min);
  * pick the reminders due now (`due`): a window of moderate-or-worse rain or
    a thunderstorm, or danger-level heat, starting in about an hour;
  * push a data-only message to every resident registered in that town.

The phone draws the notification in its own language, and drops it if the
resident turned weather reminders off (see the app's
lib/features/weather/data/weather_reminders.dart). The backend does not need
to know the switch.

The message lives only until the weather it warns about starts (FCM ttl), so
a phone that was off never wakes up to an old "rain in an hour".

What was sent is remembered in memory. A restart in the middle of a window
can send that window once more, which is better than a table for this.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime, timedelta, timezone

from app.db.supabase_client import get_supabase
from app.services import push_service, weather_service as ws

log = logging.getLogger(__name__)

# The poblacion of each town (from the app's offline map data,
# assets/map/places.json). Weather is graded on a ~5 km grid, so the town
# centre stands in for the whole municipality.
TOWNS: dict[str, tuple[float, float]] = {
    "Naval": (11.561792, 124.396525),
    "Almeria": (11.620281, 124.381666),
    "Kawayan": (11.679949, 124.357021),
    "Culaba": (11.655594, 124.540619),
    "Caibiran": (11.572319, 124.581335),
    "Cabucgayan": (11.472954, 124.574999),
    "Biliran": (11.466571, 124.474095),
    "Maripipi": (11.776525, 124.348594),
}

TICK_S = 10 * 60
LEAD = timedelta(hours=1)

# A reminder is sent in the tick that lands within this long after its time.
# Longer than a tick, so a slow tick never skips one; short enough that "in
# about an hour" is still true when it arrives.
SEND_WINDOW = timedelta(minutes=15)

RAIN_ORDER = ws.RAIN_ORDER


def _parse(t: str) -> datetime:
    return datetime.fromisoformat(t)


def plans(watch: list[dict]) -> list[dict]:
    """
    The next rain reminder and the next heat reminder a forecast calls for,
    with the time each should go out. Same rules as the app's
    WeatherReminderPlan:

      * overlapping rain and thunderstorm windows are one reminder, worded as
        the thunderstorm, at the worse of the two rain levels;
      * at night (10 PM to 6 AM, Manila) only heavy rain or worse is sent. That
        is when rivers rise; a 3 AM shower does not need to wake anyone.
    """
    out: list[dict] = []
    wet = sorted((w for w in watch if w["kind"] != "heat"), key=lambda w: w["starts_at"])
    for w in wet:
        start, end = _parse(w["starts_at"]), _parse(w["ends_at"])
        together = [
            o for o in wet
            if _parse(o["starts_at"]) < end and start < _parse(o["ends_at"])
        ]
        level = max((o["level"] for o in together), key=RAIN_ORDER.index)
        send_at = start - LEAD
        night = send_at.hour >= 22 or send_at.hour < 6
        if night and RAIN_ORDER.index(level) < RAIN_ORDER.index("heavy"):
            continue
        out.append({
            "slot": "rain",
            "send_at": send_at,
            "starts_at": w["starts_at"],
            "ends_at": max((o["ends_at"] for o in together), key=_parse),
            "thunder": any(o["kind"] == "thunderstorm" for o in together),
            "level": level,
        })
        break
    for w in watch:
        if w["kind"] != "heat":
            continue
        out.append({
            "slot": "heat",
            "send_at": _parse(w["starts_at"]) - LEAD,
            "starts_at": w["starts_at"],
            "ends_at": w["ends_at"],
            "thunder": False,
            "level": w["level"],
            "peak": w.get("peak"),
        })
        break
    return out


# (town, slot) -> the end of the last window a reminder went out for.
_sent: dict[tuple[str, str], datetime] = {}
_sent_lock = threading.Lock()


def due(town: str, watch: list[dict], now: datetime) -> list[dict]:
    """The reminders to send for this town now, marked as sent."""
    out = []
    with _sent_lock:
        for p in plans(watch):
            if not (p["send_at"] <= now < p["send_at"] + SEND_WINDOW):
                continue
            last_end = _sent.get((town, p["slot"]))
            # One reminder per spell: a forecast that nudges the start time
            # between ticks does not send it again.
            if last_end is not None and now < last_end:
                continue
            _sent[(town, p["slot"])] = _parse(p["ends_at"])
            out.append(p)
    return out


def reset() -> None:
    with _sent_lock:
        _sent.clear()


def _town_of(address: str | None) -> str | None:
    """`users.municipality_address` -> one of TOWNS. Free text in older rows
    ("Naval, Biliran", "MUNICIPALITY OF NAVAL"), so matched by name."""
    if not address:
        return None
    low = address.lower()
    # "Biliran" is also the province name, so it is only the town when no
    # other town is named.
    for town in TOWNS:
        if town != "Biliran" and town.lower() in low:
            return town
    return "Biliran" if "biliran" in low else None


def residents_by_town() -> dict[str, list[str]]:
    db = get_supabase()
    out: dict[str, list[str]] = {}
    start, page = 0, 1000
    while True:
        rows = (
            db.table("users").select("id, municipality_address")
            .eq("role", "resident").range(start, start + page - 1).execute().data or []
        )
        for r in rows:
            town = _town_of(r.get("municipality_address"))
            if town:
                out.setdefault(town, []).append(str(r["id"]))
        if len(rows) < page:
            return out
        start += page


def message_data(town: str, p: dict) -> dict:
    return {
        "ziren_weather": p["slot"],
        "level": p["level"],
        "thunder": "1" if p["thunder"] else "0",
        "starts_at": p["starts_at"],
        "ends_at": p["ends_at"],
        "town": town,
        **({"peak": str(p["peak"])} if p.get("peak") is not None else {}),
    }


def run_once(now: datetime | None = None) -> int:
    """One tick. Returns how many town reminders were sent."""
    now = now or datetime.now(timezone.utc)
    todo: list[tuple[str, dict]] = []
    for town, (lat, lng) in TOWNS.items():
        try:
            f = ws.forecast(lat, lng, now=now)
        except Exception as e:
            log.warning("[weather_alerts] no forecast for %s: %s", town, e)
            continue
        todo.extend((town, p) for p in due(town, f.get("watch") or [], now))
    if not todo:
        return 0
    people = residents_by_town()
    for town, p in todo:
        ids = people.get(town) or []
        ttl = max(60, int((_parse(p["starts_at"]) - now).total_seconds()))
        log.info("[weather_alerts] %s %s (%s) for %s: %d residents", p["slot"], p["level"], p["starts_at"], town, len(ids))
        push_service.send_data_to_users(ids, data=message_data(town, p), ttl_seconds=ttl)
    return len(todo)


_thread: threading.Thread | None = None
_stop = threading.Event()


def start() -> bool:
    """Run the ticks in a daemon thread. No-op without FCM configured (tests,
    local runs without the key) or when already running."""
    global _thread
    if _thread is not None or not push_service.enabled():
        return False
    _stop.clear()

    def loop() -> None:
        # First tick a minute after startup, then every TICK_S.
        wait = 60
        while not _stop.wait(wait):
            wait = TICK_S
            try:
                run_once()
            except Exception:
                log.exception("[weather_alerts] tick failed")

    _thread = threading.Thread(target=loop, name="weather-alerts", daemon=True)
    _thread.start()
    return True


def stop() -> None:
    global _thread
    _stop.set()
    _thread = None
