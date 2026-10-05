"""
Weather for the resident app: Ziren's "it will rain at 3 PM, bring an
umbrella" on Home, and the phone reminder an hour before heavy rain or
danger-level heat.

WHERE THE DATA COMES FROM

Open-Meteo (https://open-meteo.com): free, no API key, hourly forecasts from
the national weather models. The phone never calls it directly. It asks this
service, which:

  * snaps the resident's position to a ~5 km grid before it leaves Ziren, so
    no outside company is told where a resident is standing;
  * keeps each grid cell's forecast for 30 minutes, so a town opening the app
    at the same time costs one upstream call, not hundreds;
  * keeps serving the last good forecast (marked stale) for a few hours if
    Open-Meteo is unreachable, rather than going blank.

This is a forecast, not a warning. Official rainfall and heat warnings come
from PAGASA, and Ziren's own safety alerts come from the MDRRMO through
announcements. The app says so under the forecast.

WHAT IS DECIDED HERE

Every judgement about the weather is made here, once, so the app only has to
put it into words:

  * heat index from temperature and humidity (the NOAA formula PAGASA uses),
    graded with PAGASA's four heat-index classes;
  * rain graded by the AMOUNT forecast for the hour, on PAGASA's rainfall
    intensity scale. Not by the chance of rain: in Biliran the models give
    90-100 % almost every afternoon, often for 0.0 mm, and a reminder driven
    by that would fire every day and be ignored by the second week;
  * "watch" windows: the stretches of the next 24 hours worth reminding a
    resident about (moderate rain or worse, thunderstorms, danger-level heat).
"""

from __future__ import annotations

import logging
import math
import threading
import time
from datetime import datetime, timedelta, timezone

import httpx

logger = logging.getLogger(__name__)

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

# Naval, the provincial capital. Used when the phone has no location fix yet
# (permission refused, GPS still warming up).
DEFAULT_LAT = 11.5617
DEFAULT_LNG = 124.3966

# A rough box around the Philippines. The endpoint is not a free weather proxy
# for the rest of the world.
PH_BOUNDS = (4.0, 116.0, 21.5, 127.5)  # south, west, north, east

GRID_DEG = 0.05          # ~5.5 km at Biliran's latitude
CACHE_TTL_S = 30 * 60
STALE_LIMIT_S = 6 * 60 * 60
HOURS_SHOWN = 24
OUTLOOK_HOURS = 12
DAYS_SHOWN = 3

THUNDER_CODES = frozenset({95, 96, 99})

# PAGASA rainfall intensity, mm per hour. "heavy" is where PAGASA's yellow
# rainfall warning starts, "intense" orange, "torrential" red.
RAIN_LEVELS = (
    ("torrential", 30.0),
    ("intense", 15.0),
    ("heavy", 7.5),
    ("moderate", 2.5),
    ("light", 0.3),
)
RAIN_ORDER = ("none", "light", "moderate", "heavy", "intense", "torrential")

# PAGASA heat index classes, degrees Celsius.
HEAT_LEVELS = (
    ("extreme_danger", 52.0),
    ("danger", 42.0),
    ("extreme_caution", 33.0),
    ("caution", 27.0),
)
HEAT_ORDER = ("none", "caution", "extreme_caution", "danger", "extreme_danger")

# A thunderstorm hour only counts when the model gives it at least this chance.
THUNDER_MIN_CHANCE = 40


class WeatherUnavailable(Exception):
    """Open-Meteo could not be reached and there is no recent copy to serve."""


class OutsideCoverage(ValueError):
    """The point is outside the Philippines."""


# ── Grading ───────────────────────────────────────────────────────────────


def heat_index_c(temp_c: float | None, humidity: float | None) -> float | None:
    """
    The heat index ("feels like") for a temperature and relative humidity,
    using the NOAA Rothfusz regression with its two adjustments. This is the
    formula PAGASA's heat index bulletins are based on.

    Below about 27 C the regression is not valid and the air simply feels like
    its temperature, which is what NOAA's simple formula returns there.
    """
    if temp_c is None or humidity is None:
        return temp_c
    t = temp_c * 9 / 5 + 32
    rh = max(0.0, min(100.0, float(humidity)))
    simple = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + rh * 0.094)
    if (simple + t) / 2 < 80:
        hi = simple
    else:
        hi = (
            -42.379
            + 2.04901523 * t
            + 10.14333127 * rh
            - 0.22475541 * t * rh
            - 0.00683783 * t * t
            - 0.05481717 * rh * rh
            + 0.00122874 * t * t * rh
            + 0.00085282 * t * rh * rh
            - 0.00000199 * t * t * rh * rh
        )
        if rh < 13 and 80 <= t <= 112:
            hi -= ((13 - rh) / 4) * math.sqrt((17 - abs(t - 95)) / 17)
        elif rh > 85 and 80 <= t <= 87:
            hi += ((rh - 85) / 10) * ((87 - t) / 5)
    return round((hi - 32) * 5 / 9, 1)


def heat_level(heat_index: float | None) -> str:
    if heat_index is None:
        return "none"
    for level, floor in HEAT_LEVELS:
        if heat_index >= floor:
            return level
    return "none"


def rain_level(precip_mm: float | None) -> str:
    if not precip_mm:
        return "none"
    for level, floor in RAIN_LEVELS:
        if precip_mm >= floor:
            return level
    return "none"


def condition(code: int | None) -> str:
    """WMO weather code -> the handful of conditions the app has words and
    icons for. Snow codes cannot happen here; they read as cloudy."""
    if code is None:
        return "cloudy"
    if code == 0:
        return "clear"
    if code == 1:
        return "mostly_clear"
    if code == 2:
        return "partly_cloudy"
    if code in (45, 48):
        return "fog"
    if 51 <= code <= 57:
        return "drizzle"
    if code in (65, 67, 82):
        return "heavy_rain"
    if 61 <= code <= 67 or code in (80, 81):
        return "rain"
    if code in THUNDER_CODES:
        return "thunderstorm"
    return "cloudy"


def _at_least(level: str, floor: str, order: tuple[str, ...]) -> bool:
    return order.index(level) >= order.index(floor)


def _max_level(levels, order: tuple[str, ...]) -> str:
    best = "none"
    for level in levels:
        if order.index(level) > order.index(best):
            best = level
    return best


# ── Shaping Open-Meteo's answer ───────────────────────────────────────────


def _local_iso(naive: str, offset_s: int) -> str:
    """'2026-10-06T15:00' + 28800 -> '2026-10-06T15:00:00+08:00'."""
    tz = timezone(timedelta(seconds=offset_s))
    return datetime.fromisoformat(naive).replace(tzinfo=tz).isoformat()


def _pick(series: dict, key: str, i: int):
    values = series.get(key) or []
    return values[i] if i < len(values) else None


def _hour(hourly: dict, i: int, offset_s: int) -> dict:
    temp = _pick(hourly, "temperature_2m", i)
    humidity = _pick(hourly, "relative_humidity_2m", i)
    precip = _pick(hourly, "precipitation", i)
    code = _pick(hourly, "weather_code", i)
    hi = heat_index_c(temp, humidity)
    return {
        "time": _local_iso(hourly["time"][i], offset_s),
        "temperature_c": temp,
        "heat_index_c": hi,
        "humidity": humidity,
        "rain_chance": _pick(hourly, "precipitation_probability", i),
        "precip_mm": precip,
        "weather_code": code,
        "condition": condition(code),
        "uv_index": _pick(hourly, "uv_index", i),
        "wind_kmh": _pick(hourly, "wind_speed_10m", i),
        "is_day": bool(_pick(hourly, "is_day", i)),
        "rain_level": rain_level(precip),
        "heat_level": heat_level(hi),
    }


def _is_thunder(hour: dict) -> bool:
    chance = hour.get("rain_chance")
    return hour.get("weather_code") in THUNDER_CODES and (chance is None or chance >= THUNDER_MIN_CHANCE)


def _watch(hours: list[dict]) -> list[dict]:
    """
    The windows of the next 24 hours worth a reminder, earliest first.

    One window per run of qualifying hours, with a single quiet hour bridged
    (rain at 2, dry at 3, rain at 4 is one spell, not two reminders).
    `ends_at` is the end of the last qualifying hour.
    """
    kinds = {
        "thunderstorm": (_is_thunder, lambda h: h.get("precip_mm") or 0.0),
        "rain": (lambda h: _at_least(h["rain_level"], "moderate", RAIN_ORDER), lambda h: h.get("precip_mm") or 0.0),
        "heat": (lambda h: _at_least(h["heat_level"], "danger", HEAT_ORDER), lambda h: h.get("heat_index_c") or 0.0),
    }
    windows: list[dict] = []
    for kind, (qualifies, peak_of) in kinds.items():
        run: list[dict] = []
        gap = 0
        for hour in hours:
            if qualifies(hour):
                run.append(hour)
                gap = 0
                continue
            if run:
                gap += 1
                if gap > 1:
                    windows.append(_window(kind, run, peak_of))
                    run, gap = [], 0
        if run:
            windows.append(_window(kind, run, peak_of))
    windows.sort(key=lambda w: w["starts_at"])
    return windows


def _window(kind: str, run: list[dict], peak_of) -> dict:
    peak_hour = max(run, key=peak_of)
    end = datetime.fromisoformat(run[-1]["time"]) + timedelta(hours=1)
    if kind == "heat":
        level = _max_level((h["heat_level"] for h in run), HEAT_ORDER)
    else:
        level = _max_level((h["rain_level"] for h in run), RAIN_ORDER)
    return {
        "kind": kind,
        "level": level,
        "starts_at": run[0]["time"],
        "ends_at": end.isoformat(),
        "peak_at": peak_hour["time"],
        "peak": peak_of(peak_hour),
    }


def _outlook(hours: list[dict]) -> dict:
    """The next 12 hours in one line each: what Ziren's tips are built from."""
    ahead = hours[:OUTLOOK_HOURS]
    if not ahead:
        return {}
    hottest = max(ahead, key=lambda h: h.get("heat_index_c") or -99)
    first_rain = next((h for h in ahead if _at_least(h["rain_level"], "light", RAIN_ORDER)), None)
    first_thunder = next((h for h in ahead if _is_thunder(h)), None)
    return {
        "heat_index_max_c": hottest.get("heat_index_c"),
        "heat_peak_at": hottest["time"],
        "heat_level": hottest["heat_level"],
        "rain_level": _max_level((h["rain_level"] for h in ahead), RAIN_ORDER),
        "rain_starts_at": first_rain["time"] if first_rain else None,
        "rain_mm": round(sum((h.get("precip_mm") or 0.0) for h in ahead), 1),
        "thunder_at": first_thunder["time"] if first_thunder else None,
        "uv_max": max(((h.get("uv_index") or 0.0) for h in ahead), default=0.0),
        "wind_max_kmh": max(((h.get("wind_kmh") or 0.0) for h in ahead), default=0.0),
    }


def shape(raw: dict, *, now: datetime | None = None) -> dict:
    """Open-Meteo's response -> the payload the app reads (see module doc)."""
    offset_s = int(raw.get("utc_offset_seconds") or 0)
    tz = timezone(timedelta(seconds=offset_s))
    now_local = (now or datetime.now(timezone.utc)).astimezone(tz)

    hourly = raw.get("hourly") or {}
    times = hourly.get("time") or []
    # The hour we are in now, then forward. An hour stays "current" until it ends.
    start = next(
        (i for i, t in enumerate(times)
         if datetime.fromisoformat(t).replace(tzinfo=tz) + timedelta(hours=1) > now_local),
        len(times),
    )
    hours = [_hour(hourly, i, offset_s) for i in range(start, min(start + HOURS_SHOWN, len(times)))]

    cur = raw.get("current") or {}
    cur_hi = heat_index_c(cur.get("temperature_2m"), cur.get("relative_humidity_2m"))
    current = {
        "time": _local_iso(cur["time"], offset_s) if cur.get("time") else None,
        "temperature_c": cur.get("temperature_2m"),
        "heat_index_c": cur_hi,
        "humidity": cur.get("relative_humidity_2m"),
        "precip_mm": cur.get("precipitation"),
        "weather_code": cur.get("weather_code"),
        "condition": condition(cur.get("weather_code")),
        "wind_kmh": cur.get("wind_speed_10m"),
        "is_day": bool(cur.get("is_day")),
        "rain_level": rain_level(cur.get("precipitation")),
        "heat_level": heat_level(cur_hi),
    }

    daily = raw.get("daily") or {}
    today = now_local.date().isoformat()
    days = []
    for i, date in enumerate(daily.get("time") or []):
        if date < today:
            continue
        code = _pick(daily, "weather_code", i)
        days.append({
            "date": date,
            "weather_code": code,
            "condition": condition(code),
            "temp_max_c": _pick(daily, "temperature_2m_max", i),
            "temp_min_c": _pick(daily, "temperature_2m_min", i),
            "rain_mm": _pick(daily, "precipitation_sum", i),
            "rain_chance": _pick(daily, "precipitation_probability_max", i),
            "uv_max": _pick(daily, "uv_index_max", i),
        })
        if len(days) == DAYS_SHOWN:
            break

    return {
        "current": current,
        "hours": hours,
        "days": days,
        "outlook": _outlook(hours),
        "watch": _watch(hours),
    }


# ── Fetching and caching ──────────────────────────────────────────────────


def snap(lat: float | None, lng: float | None) -> tuple[float, float]:
    """The grid cell a point falls in. No point -> Naval."""
    if lat is None or lng is None:
        lat, lng = DEFAULT_LAT, DEFAULT_LNG
    south, west, north, east = PH_BOUNDS
    if not (south <= lat <= north and west <= lng <= east):
        raise OutsideCoverage("Weather is only available inside the Philippines.")
    return (round(round(lat / GRID_DEG) * GRID_DEG, 2), round(round(lng / GRID_DEG) * GRID_DEG, 2))


_cache: dict[tuple[float, float], tuple[float, float, dict]] = {}  # key -> (monotonic, wall, raw)
_locks: dict[tuple[float, float], threading.Lock] = {}
_locks_guard = threading.Lock()


def _lock_for(key: tuple[float, float]) -> threading.Lock:
    with _locks_guard:
        return _locks.setdefault(key, threading.Lock())


def clear_cache() -> None:
    _cache.clear()


def _fetch(lat: float, lng: float) -> dict:
    params = {
        "latitude": lat,
        "longitude": lng,
        "current": "temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,is_day",
        "hourly": "temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,"
                  "weather_code,uv_index,wind_speed_10m,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,"
                 "precipitation_probability_max,uv_index_max",
        "timezone": "Asia/Manila",
        "forecast_days": DAYS_SHOWN,
        "wind_speed_unit": "kmh",
    }
    r = httpx.get(FORECAST_URL, params=params, timeout=8.0)
    r.raise_for_status()
    raw = r.json()
    if not (raw.get("hourly") or {}).get("time"):
        raise ValueError("Open-Meteo returned no hourly forecast")
    return raw


def forecast(lat: float | None, lng: float | None, *, now: datetime | None = None) -> dict:
    """
    The shaped forecast for the grid cell around (lat, lng).

    Raises OutsideCoverage for a point outside the Philippines, and
    WeatherUnavailable when Open-Meteo is down and nothing recent is cached.
    """
    key = snap(lat, lng)
    with _lock_for(key):
        cached = _cache.get(key)
        stale = False
        if cached and time.monotonic() - cached[0] < CACHE_TTL_S:
            _, fetched_wall, raw = cached
        else:
            try:
                raw = _fetch(*key)
                fetched_wall = time.time()
                _cache[key] = (time.monotonic(), fetched_wall, raw)
            except Exception as e:  # network, HTTP status, bad JSON
                logger.warning("[weather] Open-Meteo fetch failed for %s: %s", key, e)
                if cached and time.monotonic() - cached[0] < STALE_LIMIT_S:
                    _, fetched_wall, raw = cached
                    stale = True
                else:
                    raise WeatherUnavailable("The weather forecast is not available right now.") from e

    payload = shape(raw, now=now)
    payload.update({
        "place": {"lat": key[0], "lng": key[1]},
        "source": "Open-Meteo",
        "fetched_at": datetime.fromtimestamp(fetched_wall, timezone.utc).isoformat(),
        "stale": stale,
    })
    return payload
