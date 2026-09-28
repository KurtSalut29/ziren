"""
operational_area_service — everything the Operational Area screen shows, in one
payload.

Agency Admin's "Operational Area" (Agency Admin spec Section 16) and Provincial
Admin's "Geographic Overview" (spec Section 8) are the same screen over the
same data: a municipality, what is registered there, what is happening there,
and how well it is being answered. The Agency Admin's view is locked to their
own agency's municipality and their own agency's incidents; the Provincial
Admin picks any municipality and sees incidents of their own agency_type.
Scoping is decided by the caller (the router) and arrives here as `agency_id`
or `agency_type` — this module never widens it.

TWO FACTS ABOUT THE SCHEMA SHAPE MOST OF THE DESIGN (they are why some figures
are attributions and not measurements, and the payload says so):

  1. An incident has no barangay. It has coordinates and a free-text address
     that the reporter's phone reverse-geocoded, e.g. "San Roque, Larrazabal,
     Naval, Biliran". A barangay is therefore ATTRIBUTED by finding a barangay's
     name among the address's comma-separated parts. That is right when the
     address names one and silent when it does not ("1.5 km from San Roque,
     Biliran" names a sitio and a province, not a barangay) — those incidents
     are counted as `unmatched`, never guessed at and never dropped from the
     totals. Barangays have no coordinates in the schema, so nearest-barangay
     assignment is not available either.

  2. A responder's or station's place is its AGENCY's municipality. Residents are
     the only rows that carry a real barangay_id.

Aggregation happens in Python over fetched rows rather than in a Postgres
function, for the reason geographic_service and analytics_service give: one
province's row counts are small, and Python is simpler to write, test and read.
Fetches are PAGED, though (`_fetch_all`) — PostgREST silently caps a response at
1,000 rows, and a count that quietly stops at 1,000 is worse than a slow one.

The functions below the fetch layer are PURE (rows in, figures out) so every
figure has a test that states the expected number by hand.
"""

from __future__ import annotations

import re
import unicodedata
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Callable, Iterable

from app.db.supabase_client import get_supabase
from app.services import responder_ack
from app.services.report_service import _DEFAULT_TARGET_MINUTES, _DISPATCH_TARGET_MINUTES

#: The Philippines has no daylight saving, so a fixed offset is exact and needs
#: no tz database (which Windows Python does not ship).
PH_TZ = timezone(timedelta(hours=8))

ACTIVE_STATUSES = ("received", "processing", "dispatched", "en_route", "arrived")
AWAITING_DISPATCH = ("received", "processing")
SEVERITIES = ("critical", "high", "medium", "low")

#: Rows requested per PostgREST page. Below its 1,000-row ceiling.
_PAGE = 900
#: A hard stop on paging, so a runaway table can never hang a request.
_MAX_ROWS = 20_000
#: The map draws at most this many incident pins; the figures use every row.
_MAP_INCIDENT_CAP = 500

_INCIDENT_COLS = (
    "id, record_number, status, severity, incident_category, created_at, dispatched_at, "
    "accepted_at, resolved_at, location, location_address, assigned_agency_id, "
    "assigned_responder_id, station_id, outcome, casualties_injured, casualties_fatal, "
    "casualties_transported, sos_flagged, submitted_via, overlap_agencies, report_text"
)


# ── Time helpers ────────────────────────────────────────────────────────

def _parse_dt(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _minutes_between(start: Any, end: Any) -> float | None:
    a, b = _parse_dt(start), _parse_dt(end)
    if not a or not b:
        return None
    minutes = (b - a).total_seconds() / 60
    # A negative gap is a data error (clock skew, a hand-edited row), not a
    # response that happened before the report. Dropping it keeps one bad row
    # from dragging an average below zero.
    return minutes if minutes >= 0 else None


def _local(value: Any) -> datetime | None:
    """A timestamp in Philippine time — what a dispatcher means by "the evening"."""
    parsed = _parse_dt(value)
    return parsed.astimezone(PH_TZ) if parsed else None


def _percentile(sorted_values: list[float], pct: float) -> float:
    """Linear-interpolated percentile of an already-sorted, non-empty list."""
    if len(sorted_values) == 1:
        return sorted_values[0]
    rank = (len(sorted_values) - 1) * pct
    lo = int(rank)
    hi = min(lo + 1, len(sorted_values) - 1)
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (rank - lo)


def summarise(values: Iterable[float | None]) -> dict[str, Any]:
    """
    n / average / median / 90th percentile / worst, in minutes, one decimal.

    The 90th percentile is here because an average hides the slow tail that a
    dispatcher is judged on: nine reports answered in 2 minutes and one in 40
    average 5.8 minutes, which describes neither.
    """
    vals = sorted(v for v in values if v is not None)
    if not vals:
        return {"n": 0, "avg": None, "p50": None, "p90": None, "max": None}
    return {
        "n": len(vals),
        "avg": round(sum(vals) / len(vals), 1),
        "p50": round(_percentile(vals, 0.5), 1),
        "p90": round(_percentile(vals, 0.9), 1),
        "max": round(vals[-1], 1),
    }


# ── Vulnerable residents ────────────────────────────────────────────────

#: The groups an evacuation or outreach plan counts first. Ages, not labels a
#: resident chose: date of birth is on the account, PWD status is the flag the
#: registration form already carries.
SENIOR_FROM = 60
CHILD_UNDER = 12


def age_on(dob: Any, today: datetime) -> int | None:
    """Whole years old on `today`'s Philippine date, or None (missing, unparsable, in the future)."""
    if not dob:
        return None
    try:
        born = datetime.fromisoformat(str(dob)[:10]).date()
    except ValueError:
        return None
    now = today.astimezone(PH_TZ).date()
    years = now.year - born.year - ((now.month, now.day) < (born.month, born.day))
    return years if years >= 0 else None


def vulnerability(user: dict, today: datetime) -> dict[str, bool]:
    age = age_on(user.get("date_of_birth"), today)
    senior = age is not None and age >= SENIOR_FROM
    child = age is not None and age < CHILD_UNDER
    pwd = bool(user.get("is_pwd"))
    return {"senior": senior, "child": child, "pwd": pwd, "any": senior or child or pwd}


# ── Barangay attribution ────────────────────────────────────────────────

_PREFIX_RE = re.compile(r"^(?:brgy|barangay|bgy|brg)\.?\s+", re.IGNORECASE)


def normalise_place(text: str) -> str:
    """Lower-case, accent-free, prefix-free ('Brgy. San Roque' -> 'san roque')."""
    folded = unicodedata.normalize("NFKD", text or "")
    folded = "".join(c for c in folded if not unicodedata.combining(c)).strip().lower()
    folded = re.sub(r"\s+", " ", folded)
    return _PREFIX_RE.sub("", folded).strip()


def match_barangay(
    address: str | None,
    barangay_names: Iterable[str],
    exclude: Iterable[str] = (),
) -> str | None:
    """
    The barangay an address names, or None.

    Matches whole comma-separated parts, not substrings: "Poblacion" must not
    match "Poblacion Norte" by prefix, and a street called "Naval Road" must
    not match a barangay called "Naval". `exclude` lists names that are never a
    barangay answer here (the municipality and province themselves).
    """
    if not address:
        return None
    by_norm = {normalise_place(n): n for n in barangay_names}
    skip = {normalise_place(x) for x in exclude}
    for part in address.split(","):
        key = normalise_place(part)
        if key and key not in skip and key in by_norm:
            return by_norm[key]
    return None


# ── Fetch layer ─────────────────────────────────────────────────────────

def _fetch_all(build: Callable[[], Any]) -> list[dict[str, Any]]:
    """
    Every row of a query, paged. `build` returns a FRESH query each call —
    PostgREST builders are mutated by .range(), so one builder cannot be reused.
    """
    rows: list[dict[str, Any]] = []
    start = 0
    while start < _MAX_ROWS:
        page = build().range(start, start + _PAGE - 1).execute().data or []
        rows.extend(page)
        if len(page) < _PAGE:
            break
        start += _PAGE
    return rows


def _coords(loc: Any) -> tuple[float, float] | None:
    """(lat, lng) from a PostgREST GeoJSON point, or None."""
    if not isinstance(loc, dict):
        return None
    c = loc.get("coordinates")
    if not c or len(c) < 2:
        return None
    try:
        return float(c[1]), float(c[0])
    except (TypeError, ValueError):
        return None


def _parallel(*tasks: Callable[[], Any]) -> list[Any]:
    """
    Run independent fetches at once. Each is a network round trip to Supabase of
    a few hundred milliseconds, and the screen needs about ten of them; run one
    after another they made the page take 2.6 s, run together it takes the
    slowest one. Results come back in the order the tasks were given.
    """
    with ThreadPoolExecutor(max_workers=min(len(tasks), 8)) as pool:
        futures = [pool.submit(t) for t in tasks]
        return [f.result() for f in futures]


# ── Pure aggregation ────────────────────────────────────────────────────

def _bucket_plan(
    days: int,
    first_seen: datetime | None,
    now: datetime,
    first_day: date | None = None,
    last_day: date | None = None,
) -> tuple[str, list[str]]:
    """
    ('day'|'week'|'month', every bucket key in order). Empty buckets are
    INCLUDED: a chart that skips the quiet days draws a straight line between
    two busy ones and reads as continuous activity.

    `first_day`/`last_day` (Philippine calendar days) lay the chart out over
    exactly the range a reader picked; without them the window is "the last
    `days` days, ending today" (or, for 0, everything since the first report).
    """
    end = last_day or now.astimezone(PH_TZ).date()
    if first_day is not None:
        start = first_day
        span = (end - start).days + 1
        unit = "day" if span <= 45 else "week" if span <= 120 else "month"
    elif days == 0:
        start = (first_seen.astimezone(PH_TZ).date() if first_seen else end).replace(day=1)
        unit = "month"
    else:
        start = end - timedelta(days=days - 1)
        unit = "day" if days <= 45 else "week" if days <= 120 else "month"

    keys: list[str] = []
    if unit == "day":
        d = start
        while d <= end:
            keys.append(d.isoformat())
            d += timedelta(days=1)
    elif unit == "week":
        d = start - timedelta(days=start.weekday())  # the Monday of the first week
        while d <= end:
            keys.append(d.isoformat())
            d += timedelta(days=7)
    else:
        y, m = start.year, start.month
        while (y, m) <= (end.year, end.month):
            keys.append(f"{y:04d}-{m:02d}")
            m += 1
            if m == 13:
                y, m = y + 1, 1
    return unit, keys


def _bucket_of(dt: datetime, unit: str) -> str:
    d = dt.astimezone(PH_TZ).date()
    if unit == "day":
        return d.isoformat()
    if unit == "week":
        return (d - timedelta(days=d.weekday())).isoformat()
    return f"{d.year:04d}-{d.month:02d}"


def build_trend(
    rows: list[dict],
    days: int,
    now: datetime,
    first_day: date | None = None,
    last_day: date | None = None,
) -> dict[str, Any]:
    firsts = [t for t in (_parse_dt(r.get("created_at")) for r in rows) if t]
    unit, keys = _bucket_plan(days, min(firsts) if firsts else None, now, first_day, last_day)
    total: Counter[str] = Counter()
    critical: Counter[str] = Counter()
    high: Counter[str] = Counter()
    for r in rows:
        created = _parse_dt(r.get("created_at"))
        if not created:
            continue
        key = _bucket_of(created, unit)
        total[key] += 1
        if r.get("severity") == "critical":
            critical[key] += 1
        elif r.get("severity") == "high":
            high[key] += 1
    return {
        "unit": unit,
        "points": [
            {
                "bucket": k,
                "count": total.get(k, 0),
                "critical": critical.get(k, 0),
                "high": high.get(k, 0),
                # Kept alongside critical/high, not replaced by them, so this
                # stays a backward-compatible addition to the payload.
                "serious": critical.get(k, 0) + high.get(k, 0),
            }
            for k in keys
        ],
    }


def build_time_patterns(rows: list[dict]) -> dict[str, Any]:
    """When reports arrive, in Philippine time: hour of day and day of week."""
    grid = [[0] * 24 for _ in range(7)]  # Monday=0 .. Sunday=6
    for r in rows:
        local = _local(r.get("created_at"))
        if local:
            grid[local.weekday()][local.hour] += 1
    by_hour = [sum(grid[d][h] for d in range(7)) for h in range(24)]
    by_weekday = [sum(row) for row in grid]
    total = sum(by_hour)
    peak_hour = max(range(24), key=lambda h: by_hour[h]) if total else None
    peak_day = max(range(7), key=lambda d: by_weekday[d]) if total else None
    return {
        "heatmap": grid,
        "by_hour": by_hour,
        "by_weekday": by_weekday,
        "peak_hour": peak_hour,
        "peak_weekday": peak_day,
        "total": total,
    }


def build_response(rows: list[dict]) -> dict[str, Any]:
    """
    How quickly the area is being answered, overall and per severity, judged
    against the SAME dispatch targets Reports & Export uses (report_service) and
    the SAME acknowledgement deadlines the responder clock uses (responder_ack) —
    so this screen never disagrees with a report an admin exports.

    A report still awaiting dispatch is counted as `awaiting`, not as a miss:
    it has not been decided either way, and folding it into "late" would make
    today's queue look like a finished failure.
    """
    dispatch_all: list[float | None] = []
    ack_all: list[float | None] = []
    resolve_all: list[float | None] = []
    on_time_all = late_all = 0
    per: dict[str, dict[str, Any]] = {}

    for sev in (*SEVERITIES, "untriaged"):
        per[sev] = {"n": 0, "dispatch": [], "ack": [], "resolve": [], "on_time": 0, "late": 0,
                    "awaiting": 0, "ack_on_time": 0, "ack_late": 0}

    for r in rows:
        sev = r.get("severity") if r.get("severity") in SEVERITIES else "untriaged"
        b = per[sev]
        b["n"] += 1
        dispatch = _minutes_between(r.get("created_at"), r.get("dispatched_at"))
        ack = _minutes_between(r.get("dispatched_at"), r.get("accepted_at"))
        resolve = _minutes_between(r.get("created_at"), r.get("resolved_at")) if r.get("status") == "resolved" else None

        target = _DISPATCH_TARGET_MINUTES.get(sev, _DEFAULT_TARGET_MINUTES)
        if r.get("status") == "cancelled":
            pass  # a cancelled report was never a dispatch obligation
        elif dispatch is None:
            # Undispatched AND still waiting. A row with no dispatch time that is
            # already resolved is a data gap, not a queue.
            if r.get("status") in AWAITING_DISPATCH:
                b["awaiting"] += 1
        elif dispatch <= target:
            b["on_time"] += 1
            on_time_all += 1
        else:
            b["late"] += 1
            late_all += 1

        if ack is not None:
            deadline_min = responder_ack.deadline_seconds(None if sev == "untriaged" else sev) / 60
            b["ack_on_time" if ack <= deadline_min else "ack_late"] += 1

        b["dispatch"].append(dispatch)
        b["ack"].append(ack)
        b["resolve"].append(resolve)
        dispatch_all.append(dispatch)
        ack_all.append(ack)
        resolve_all.append(resolve)

    def rate(good: int, bad: int) -> int | None:
        return round(good / (good + bad) * 100) if (good + bad) else None

    by_severity = []
    for sev in (*SEVERITIES, "untriaged"):
        b = per[sev]
        by_severity.append({
            "severity": sev,
            "n": b["n"],
            "dispatch": summarise(b["dispatch"]),
            "dispatch_target_min": _DISPATCH_TARGET_MINUTES.get(sev, _DEFAULT_TARGET_MINUTES),
            "on_time": b["on_time"], "late": b["late"], "awaiting": b["awaiting"],
            "dispatch_compliance": rate(b["on_time"], b["late"]),
            "ack": summarise(b["ack"]),
            "ack_deadline_min": round(responder_ack.deadline_seconds(None if sev == "untriaged" else sev) / 60, 1),
            "ack_compliance": rate(b["ack_on_time"], b["ack_late"]),
            "resolution": summarise(b["resolve"]),
        })

    return {
        "dispatch": summarise(dispatch_all),
        "ack": summarise(ack_all),
        "resolution": summarise(resolve_all),
        "dispatch_compliance": rate(on_time_all, late_all),
        "by_severity": by_severity,
    }


def build_outcomes(rows: list[dict]) -> dict[str, Any]:
    outcomes = Counter(r["outcome"] for r in rows if r.get("outcome"))
    return {
        "counts": dict(outcomes),
        "recorded": sum(outcomes.values()),
        "casualties": {
            "injured": sum(int(r.get("casualties_injured") or 0) for r in rows),
            "fatal": sum(int(r.get("casualties_fatal") or 0) for r in rows),
            "transported": sum(int(r.get("casualties_transported") or 0) for r in rows),
        },
    }


def build_mix(rows: list[dict]) -> dict[str, Any]:
    flags: Counter[str] = Counter()
    for r in rows:
        for f in (r.get("overlap_agencies") or []):
            name = f if isinstance(f, str) else (f or {}).get("flag")
            if name and name != "none":
                flags[name] += 1
    return {
        "severity": dict(Counter(r.get("severity") or "untriaged" for r in rows)),
        "categories": dict(Counter(r.get("incident_category") or "other" for r in rows)),
        "status": dict(Counter(r.get("status") or "unknown" for r in rows)),
        "channels": dict(Counter(r.get("submitted_via") or "internet" for r in rows)),
        "multi_agency_signals": dict(flags),
    }


def build_barangays(
    barangays: list[dict],
    residents: list[dict],
    rows: list[dict],
    exclude_names: Iterable[str],
    now: datetime | None = None,
) -> dict[str, Any]:
    """
    One row per barangay of the municipality — INCLUDING those with nothing
    registered and nothing reported, because an empty barangay is the finding.
    """
    names = [b["name"] for b in barangays]
    today = now or datetime.now(timezone.utc)
    zero = {"residents": 0, "verified": 0, "pwd": 0, "seniors": 0, "children": 0, "vulnerable": 0}
    by_resident: dict[str, dict[str, int]] = defaultdict(lambda: dict(zero))
    for u in residents:
        slot = by_resident[u.get("barangay_id")]
        v = vulnerability(u, today)
        slot["residents"] += 1
        slot["verified"] += 1 if u.get("is_verified") else 0
        slot["pwd"] += 1 if v["pwd"] else 0
        slot["seniors"] += 1 if v["senior"] else 0
        slot["children"] += 1 if v["child"] else 0
        slot["vulnerable"] += 1 if v["any"] else 0

    per_incident: dict[str, list[dict]] = defaultdict(list)
    unmatched = unlocated = 0
    for r in rows:
        if not r.get("location_address"):
            unlocated += 1
            continue
        hit = match_barangay(r["location_address"], names, exclude_names)
        if hit is None:
            unmatched += 1
        else:
            per_incident[hit].append(r)

    total_residents = sum(v["residents"] for v in by_resident.values()) or 0
    matched_total = sum(len(v) for v in per_incident.values())
    out = []
    for b in sorted(barangays, key=lambda x: x["name"]):
        res = by_resident.get(b["id"], zero)
        inc = per_incident.get(b["name"], [])
        last = max((t for t in (_parse_dt(i.get("created_at")) for i in inc) if t), default=None)
        out.append({
            "id": b["id"],
            "name": b["name"],
            "residents": res["residents"],
            "verified": res["verified"],
            "pwd": res["pwd"],
            "seniors": res["seniors"],
            "children": res["children"],
            "vulnerable": res["vulnerable"],
            "resident_share": round(res["residents"] / total_residents * 100, 1) if total_residents else 0.0,
            "incidents": len(inc),
            "critical": sum(1 for i in inc if i.get("severity") == "critical"),
            "active": sum(1 for i in inc if i.get("status") in ACTIVE_STATUSES),
            "incident_share": round(len(inc) / matched_total * 100, 1) if matched_total else 0.0,
            "last_incident_at": last.isoformat() if last else None,
        })
    return {
        "items": out,
        "matched_incidents": matched_total,
        "unmatched_incidents": unmatched,
        "unlocated_incidents": unlocated,
        "empty_barangays": sum(1 for b in out if b["residents"] == 0),
    }


def build_hotspots(
    rows: list[dict],
    exclude_names: Iterable[str],
    barangay_names: Iterable[str],
    limit: int = 8,
) -> list[dict[str, Any]]:
    """
    PLACES that keep appearing: the same address (municipality, province and
    region stripped, case and accents ignored) named by two or more reports.

    A barangay count is too coarse to act on — "seven fires in Larrazabal" does
    not say which street to put a hydrant on; "four fires at San Roque" does.
    Only repeats are listed, because a place that appeared once is an incident,
    not a pattern. The address is whatever the reporter's phone looked up, so this
    is text matching and says so; two spellings of one place are two places.
    """
    skip = {normalise_place(x) for x in exclude_names}
    names = list(barangay_names)
    groups: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        addr = r.get("location_address")
        if not addr:
            continue
        kept = [p.strip() for p in addr.split(",") if p.strip() and normalise_place(p) not in skip]
        if not kept:
            continue
        groups[normalise_place(", ".join(kept))].append({**r, "_place": ", ".join(kept)})

    out = []
    for members in groups.values():
        if len(members) < 2:
            continue
        display = Counter(m["_place"] for m in members).most_common(1)[0][0]
        last = max((t for t in (_parse_dt(m.get("created_at")) for m in members) if t), default=None)
        cats = Counter(m.get("incident_category") or "other" for m in members)
        out.append({
            "place": display,
            "barangay": match_barangay(members[0].get("location_address"), names, exclude_names),
            "count": len(members),
            "critical": sum(1 for m in members if m.get("severity") == "critical"),
            "top_category": cats.most_common(1)[0][0],
            "last_at": last.isoformat() if last else None,
        })
    out.sort(key=lambda h: (-h["count"], -h["critical"], h["place"].lower()))
    return out[:limit]


def build_previous(prev_rows: list[dict]) -> dict[str, Any]:
    """The same headline measures for the period BEFORE the one on screen, so a figure can say better or worse."""
    resp = build_response(prev_rows)
    resolved = sum(1 for r in prev_rows if r.get("status") == "resolved")
    closed = resolved + sum(1 for r in prev_rows if r.get("status") == "cancelled")
    return {
        "incidents": len(prev_rows),
        "critical": sum(1 for r in prev_rows if r.get("severity") == "critical"),
        "resolved_rate": round(resolved / closed * 100) if closed else None,
        "dispatch_avg": resp["dispatch"]["avg"],
        "ack_avg": resp["ack"]["avg"],
        "resolution_avg": resp["resolution"]["avg"],
        "dispatch_compliance": resp["dispatch_compliance"],
    }


def build_stations(
    stations: list[dict],
    agencies_by_id: dict[str, dict],
    scope_ids: set[str],
    rows: list[dict],
) -> dict[str, Any]:
    by_station: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        if r.get("station_id"):
            by_station[r["station_id"]].append(r)

    items = []
    for s in stations:
        ag = agencies_by_id.get(s.get("agency_id"), {})
        mine = by_station.get(s["id"], [])
        pos = _coords(s.get("location"))
        last = max((t for t in (_parse_dt(i.get("created_at")) for i in mine) if t), default=None)
        items.append({
            "id": s["id"],
            "name": s.get("name"),
            "address": s.get("address"),
            "agency_id": s.get("agency_id"),
            "agency_name": ag.get("name"),
            "agency_type": ag.get("agency_type"),
            "is_active": bool(s.get("is_active", True)),
            "is_own": s.get("agency_id") in scope_ids,
            "lat": pos[0] if pos else None,
            "lng": pos[1] if pos else None,
            "incidents": len(mine) if s.get("agency_id") in scope_ids else None,
            "dispatch": summarise(_minutes_between(i.get("created_at"), i.get("dispatched_at")) for i in mine)
            if s.get("agency_id") in scope_ids else None,
            "last_incident_at": last.isoformat() if last else None,
        })
    return {
        "items": items,
        "unassigned_incidents": sum(1 for r in rows if not r.get("station_id")),
    }


def build_responders(responders: list[dict], rows: list[dict], agencies_by_id: dict[str, dict]) -> dict[str, Any]:
    approved = [u for u in responders if u.get("approval_status") == "approved"]
    by_resp: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        if r.get("assigned_responder_id"):
            by_resp[r["assigned_responder_id"]].append(r)

    roster = []
    for u in responders:
        mine = by_resp.get(u["id"], [])
        roster.append({
            "id": u["id"],
            "full_name": u.get("full_name"),
            "badge_id": u.get("badge_id"),
            "agency_type": agencies_by_id.get(u.get("agency_id"), {}).get("agency_type"),
            "approval_status": u.get("approval_status"),
            "availability": u.get("availability"),
            "has_location": _coords(u.get("location")) is not None,
            "location_updated_at": u.get("location_updated_at"),
            "incidents": len(mine),
            "resolved": sum(1 for i in mine if i.get("status") == "resolved"),
            "ack": summarise(_minutes_between(i.get("dispatched_at"), i.get("accepted_at")) for i in mine),
        })
    roster.sort(key=lambda x: (x["approval_status"] != "approved", x["availability"] != "on_duty",
                               -x["incidents"], (x["full_name"] or "").lower()))
    return {
        "approved": len(approved),
        "on_duty": sum(1 for u in approved if u.get("availability") == "on_duty"),
        "off_duty": sum(1 for u in approved if u.get("availability") != "on_duty"),
        "pending": sum(1 for u in responders if u.get("approval_status") == "pending"),
        "roster": roster,
    }


def build_readiness(
    *,
    scope_agencies: list[dict],
    stations_out: dict[str, Any],
    responders_out: dict[str, Any],
    barangays_out: dict[str, Any],
    barangay_count: int,
    awaiting_rows: list[dict],
    now: datetime,
    window_rows: list[dict],
) -> list[dict[str, str]]:
    """
    Plain checks the reader can act on. Every one is derived from a real row
    count — none is a score, because a single "readiness 82%" would have to
    invent weights, and an invented number is worse than none in a dispatch room.
    """
    checks: list[dict[str, str]] = []

    def add(key: str, status: str, title: str, detail: str, **extra: str) -> None:
        checks.append({"key": key, "status": status, "title": title, "detail": detail, **extra})

    own_stations = [s for s in stations_out["items"] if s["is_own"] and s["is_active"]]
    unmapped = [s for s in own_stations if s["lat"] is None]
    if not own_stations:
        add("stations", "warn", "No active station on file",
            "Reports cannot be routed to a nearest station until one is added.", href="/agencies")
    elif unmapped:
        add("stations", "warn", f"{len(unmapped)} station{'s' if len(unmapped) != 1 else ''} without coordinates",
            "A station with no coordinates cannot be pinned on the map or picked as the nearest.", href="/agencies")
    else:
        add("stations", "ok", "Every station is on the map",
            f"{len(own_stations)} active station{'s' if len(own_stations) != 1 else ''} with coordinates.")

    if responders_out["approved"] == 0:
        add("responders", "warn", "No approved responders",
            "Nobody can accept a dispatch until a responder is approved.", href="/responders")
    elif responders_out["on_duty"] == 0:
        add("responders", "warn", "Nobody is on duty",
            f"{responders_out['approved']} approved, all off duty — a new report would wait for someone to go on duty.",
            href="/responders")
    else:
        add("responders", "ok", f"{responders_out['on_duty']} on duty now",
            f"Of {responders_out['approved']} approved responders.")

    if responders_out["pending"]:
        add("approvals", "warn", f"{responders_out['pending']} responder{'s' if responders_out['pending'] != 1 else ''} awaiting approval",
            "They cannot receive dispatches until an admin approves them.", href="/responders")

    overdue = 0
    for r in awaiting_rows:
        created = _parse_dt(r.get("created_at"))
        if not created:
            continue
        sev = r.get("severity") if r.get("severity") in SEVERITIES else "untriaged"
        limit = _DISPATCH_TARGET_MINUTES.get(sev, _DEFAULT_TARGET_MINUTES)
        if (now - created).total_seconds() / 60 > limit:
            overdue += 1
    if overdue:
        add("backlog", "warn", f"{overdue} report{'s' if overdue != 1 else ''} past the dispatch target",
            "Still waiting for a dispatcher, longer than the target for its severity.", href="/incidents")
    elif awaiting_rows:
        add("backlog", "info", f"{len(awaiting_rows)} report{'s' if len(awaiting_rows) != 1 else ''} awaiting dispatch",
            "Within target for now.", href="/incidents")
    else:
        add("backlog", "ok", "Nothing waiting for dispatch", "Every report has been dispatched or closed.")

    if barangay_count:
        empty = barangays_out["empty_barangays"]
        if empty:
            add("adoption", "warn", f"{empty} of {barangay_count} barangays have no registered residents",
                "Nobody there can file a report through the app. Worth a registration drive.", tab="barangays")
        else:
            add("adoption", "ok", "Every barangay has registered residents", f"{barangay_count} barangays covered.")

    missing = [k for k in ("contact_number", "email") if not any(a.get(k) for a in scope_agencies)]
    if missing:
        label = " and ".join("contact number" if k == "contact_number" else "email" for k in missing)
        add("contact", "warn", f"Agency {label} not on file",
            "Residents and other agencies have nothing to reach you with.", href="/settings?tab=agency")
    else:
        add("contact", "ok", "Agency contact details are on file", "Residents and other agencies can reach you.")

    located = sum(1 for r in window_rows if _coords(r.get("location")))
    if window_rows:
        pct = round(located / len(window_rows) * 100)
        add("locations", "ok" if pct >= 90 else "info", f"{pct}% of reports carry coordinates",
            "The rest have an address only and cannot be pinned on the map.")
    return checks


def build_recent(rows: list[dict], names: list[str], exclude: Iterable[str], limit: int = 8) -> list[dict]:
    latest = sorted(rows, key=lambda r: r.get("created_at") or "", reverse=True)[:limit]
    return [{
        "id": r["id"],
        "record_number": r.get("record_number"),
        "category": r.get("incident_category"),
        "severity": r.get("severity"),
        "status": r.get("status"),
        "address": r.get("location_address"),
        "barangay": match_barangay(r.get("location_address"), names, exclude),
        "created_at": r.get("created_at"),
        "sos_flagged": bool(r.get("sos_flagged")),
    } for r in latest]


# ── Assembly ────────────────────────────────────────────────────────────

def list_barangays(municipality: str) -> list[dict[str, Any]]:
    db = get_supabase()
    return (
        db.table("barangays").select("id, name, municipality").eq("municipality", municipality)
        .order("name").execute().data or []
    )


def get_operational_area(
    *,
    municipality: str,
    days: int = 30,
    barangay: str | None = None,
    agency_id: str | None = None,
    agency_type: str | None = None,
    now: datetime | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
) -> dict[str, Any]:
    """
    `agency_id` (Agency Admin) or `agency_type` (Provincial Admin) scopes every
    INCIDENT and RESPONDER figure. Registered residents, stations and the list
    of agencies present are informational for every admin role — who else has a
    presence here — and were never agency-scoped.

    The period is one of two things:
      - a rolling look-back: `days` = the last N days up to now, 0 = all time; or
      - a chosen range: `date_from`..`date_to`, BOTH INCLUDED, as Philippine
        calendar days ("1 to 15 March" is fifteen whole days, midnight to
        midnight local time). When both are given, `days` is ignored.
    A chosen range is compared with the range of the same length immediately
    before it, exactly as a rolling window is. An end date after today is
    clamped to today — nothing can have been reported tomorrow.
    """
    now = now or datetime.now(timezone.utc)
    db = get_supabase()

    # ── Area: agencies present and barangays ────────────────────────────
    agencies, barangays = _parallel(
        lambda: (db.table("agencies")
                 .select("id, name, agency_type, municipality, province, region, contact_number, email, is_active")
                 .eq("municipality", municipality).execute().data or []),
        lambda: list_barangays(municipality),
    )
    agencies_by_id = {a["id"]: a for a in agencies}
    if agency_id:
        scope_agencies = [a for a in agencies if a["id"] == agency_id]
    else:
        scope_agencies = [a for a in agencies if a.get("agency_type") == agency_type]
    scope_ids = {a["id"] for a in scope_agencies}

    barangay_names = [b["name"] for b in barangays]
    selected = None
    if barangay:
        selected = next((b for b in barangays if normalise_place(b["name"]) == normalise_place(barangay)), None)
    province = next((a.get("province") for a in agencies if a.get("province")), None)
    region = next((a.get("region") for a in agencies if a.get("region")), None)
    exclude = [municipality, province or "", region or ""]

    # ── Windows: [since, until) and the equally long one before it ──────
    custom = date_from is not None and date_to is not None
    until: datetime | None = None                 # None = "up to now"
    if custom:
        date_to = min(date_to, now.astimezone(PH_TZ).date())
        if date_from > date_to:
            raise ValueError("date_from is after date_to, or in the future.")
        since = datetime.combine(date_from, time.min, tzinfo=PH_TZ)
        until = datetime.combine(date_to + timedelta(days=1), time.min, tzinfo=PH_TZ)
        days = (date_to - date_from).days + 1
        prev_since = since - (until - since)
    else:
        since = None if days == 0 else now - timedelta(days=days)
        prev_since = None if days == 0 else now - timedelta(days=days * 2)

    # ── Rows (independent fetches, run together) ────────────────────────
    scope_list = sorted(scope_ids)
    fetch_since = prev_since.astimezone(timezone.utc).isoformat() if prev_since else None
    barangay_ids = [b["id"] for b in barangays]

    def _incident_query():
        q = db.table("incidents").select(_INCIDENT_COLS).in_("assigned_agency_id", scope_list)
        if fetch_since:
            q = q.gte("created_at", fetch_since)
        if until:
            # A chosen range can end in the past; without this the newer reports
            # would be fetched and then mistaken for the "previous" period.
            q = q.lt("created_at", until.astimezone(timezone.utc).isoformat())
        return q.order("created_at", desc=True)

    def _awaiting():
        # Awaiting-dispatch is a live question, not a windowed one: a report from
        # last month that is still unanswered is the most urgent row on the screen.
        return (db.table("incidents").select("id, severity, created_at, status")
                .in_("assigned_agency_id", scope_list).in_("status", list(AWAITING_DISPATCH)).execute().data or [])

    def _active_count():
        return (db.table("incidents").select("id", count="exact")
                .in_("assigned_agency_id", scope_list).in_("status", list(ACTIVE_STATUSES)).execute().count or 0)

    def _residents():
        return _fetch_all(
            lambda: db.table("users").select("id, barangay_id, is_verified, is_pwd, date_of_birth, created_at")
            .eq("role", "resident").in_("barangay_id", barangay_ids)
        )

    def _stations():
        return (db.table("stations").select("id, name, address, location, agency_id, is_active")
                .in_("agency_id", list(agencies_by_id)).execute().data or [])

    def _responders():
        return (db.table("users")
                .select("id, full_name, badge_id, availability, approval_status, location, location_updated_at, agency_id")
                .eq("role", "responder").in_("agency_id", scope_list).execute().data or [])

    def _none(empty):
        return lambda: empty

    all_rows, awaiting_rows, active_now, residents_all, station_rows, responder_rows = _parallel(
        (lambda: _fetch_all(_incident_query)) if scope_list else _none([]),
        _awaiting if scope_list else _none([]),
        _active_count if scope_list else _none(0),
        _residents if barangays else _none([]),
        _stations if agencies_by_id else _none([]),
        _responders if scope_list else _none([]),
    )

    def _in_window(r: dict) -> bool:
        if since is None:
            return True
        t = _parse_dt(r.get("created_at"))
        return bool(t and t >= since and (until is None or t < until))

    def _in_previous(r: dict) -> bool:
        t = _parse_dt(r.get("created_at"))
        return bool(t and prev_since is not None and since is not None and prev_since <= t < since)

    def _matches_barangay(r: dict) -> bool:
        if selected is None:
            return True
        return match_barangay(r.get("location_address"), barangay_names, exclude) == selected["name"]

    area_rows = [r for r in all_rows if _in_window(r)]                       # whole municipality
    rows = [r for r in area_rows if _matches_barangay(r)]                    # narrowed to the barangay, if any
    prev_rows = [r for r in all_rows if _in_previous(r) and _matches_barangay(r)] if since else []
    residents = [u for u in residents_all if selected is None or u.get("barangay_id") == selected["id"]]

    # ── Figures ─────────────────────────────────────────────────────────
    barangays_out = build_barangays(barangays, residents_all, area_rows, exclude, now)
    stations_out = build_stations(station_rows, agencies_by_id, scope_ids, area_rows)
    responders_out = build_responders(responder_rows, area_rows, agencies_by_id)
    response = build_response(rows)

    total = len(rows)
    prev_total = len(prev_rows) if since else None
    closed = sum(1 for r in rows if r.get("status") in ("resolved", "cancelled"))
    resolved = sum(1 for r in rows if r.get("status") == "resolved")
    mix = build_mix(rows)
    new_residents = None
    if since:
        new_residents = 0
        for u in residents:
            joined = _parse_dt(u.get("created_at"))
            if joined and joined >= since and (until is None or joined < until):
                new_residents += 1

    kpis = {
        "incidents": total,
        "previous_incidents": prev_total,
        "active_now": active_now,
        "awaiting_dispatch": len(awaiting_rows),
        "critical": sum(1 for r in rows if r.get("severity") == "critical"),
        "sos": sum(1 for r in rows if r.get("sos_flagged")),
        "resolved": resolved,
        "cancelled": sum(1 for r in rows if r.get("status") == "cancelled"),
        "resolved_rate": round(resolved / closed * 100) if closed else None,
        "false_alarms": sum(1 for r in rows if r.get("outcome") == "false_alarm"),
        "dispatch": response["dispatch"],
        "ack": response["ack"],
        "resolution": response["resolution"],
        "dispatch_compliance": response["dispatch_compliance"],
        "residents": len(residents),
        "verified_residents": sum(1 for u in residents if u.get("is_verified")),
        "pwd_residents": sum(1 for u in residents if u.get("is_pwd")),
        "senior_residents": sum(1 for u in residents if vulnerability(u, now)["senior"]),
        "child_residents": sum(1 for u in residents if vulnerability(u, now)["child"]),
        "vulnerable_residents": sum(1 for u in residents if vulnerability(u, now)["any"]),
        "new_residents": new_residents,
        # None for "all time": there is no earlier period to be better or worse than.
        "previous": build_previous(prev_rows) if since else None,
    }

    # Map payload, in the shape ZirenMap already consumes (MapData).
    agency_type_by_id = {a["id"]: a.get("agency_type") for a in agencies}
    map_incidents = []
    for r in rows:
        pos = _coords(r.get("location"))
        if not pos:
            continue
        map_incidents.append({
            "id": r["id"], "lat": pos[0], "lng": pos[1], "severity": r.get("severity"),
            "status": r.get("status"), "sos_flagged": bool(r.get("sos_flagged")),
            "agency_type": agency_type_by_id.get(r.get("assigned_agency_id")),
            "agency_id": r.get("assigned_agency_id"),
            "report_text": (r.get("report_text") or "")[:120],
            "created_at": r.get("created_at"), "resolved_at": r.get("resolved_at"), "route": None,
        })
    map_incidents = map_incidents[:_MAP_INCIDENT_CAP]
    map_stations = [
        {"id": s["id"], "name": s["name"], "address": s["address"], "agency_type": s["agency_type"],
         "agency_name": s["agency_name"], "municipality": municipality, "lat": s["lat"], "lng": s["lng"]}
        for s in stations_out["items"] if s["lat"] is not None and s["is_active"]
    ]
    map_responders = []
    for u in responder_rows:
        pos = _coords(u.get("location"))
        if u.get("approval_status") == "approved" and u.get("availability") == "on_duty":
            map_responders.append({
                "id": u["id"], "full_name": u.get("full_name"), "badge_id": u.get("badge_id"),
                "availability": "on_duty", "agency_type": agency_type_by_id.get(u.get("agency_id")),
                "lat": pos[0] if pos else None, "lng": pos[1] if pos else None,
            })

    agencies_out = []
    for a in sorted(agencies, key=lambda x: (x.get("agency_type") or "", x.get("name") or "")):
        agencies_out.append({
            "id": a["id"], "name": a["name"], "agency_type": a.get("agency_type"),
            "contact_number": a.get("contact_number"), "email": a.get("email"),
            "is_active": bool(a.get("is_active", True)), "is_own": a["id"] in scope_ids,
            "stations": sum(1 for s in stations_out["items"] if s["agency_id"] == a["id"]),
            "mapped_stations": sum(1 for s in stations_out["items"] if s["agency_id"] == a["id"] and s["lat"] is not None),
            "incidents": sum(1 for r in area_rows if r.get("assigned_agency_id") == a["id"]) if a["id"] in scope_ids else None,
        })

    readiness = build_readiness(
        scope_agencies=scope_agencies, stations_out=stations_out, responders_out=responders_out,
        barangays_out=barangays_out, barangay_count=len(barangays), awaiting_rows=awaiting_rows,
        now=now, window_rows=rows,
    )

    out: dict[str, Any] = {
        "generated_at": now.isoformat(),
        "area": {
            "municipality": municipality, "province": province, "region": region,
            "barangay_count": len(barangays),
            "barangays": barangay_names,
            "agency": ({"id": scope_agencies[0]["id"], "name": scope_agencies[0]["name"],
                        "agency_type": scope_agencies[0].get("agency_type"),
                        "contact_number": scope_agencies[0].get("contact_number"),
                        "email": scope_agencies[0].get("email")} if agency_id and scope_agencies else None),
        },
        "filters": {"days": days, "barangay": selected["name"] if selected else None,
                    "since": since.isoformat() if since else None,
                    "until": until.isoformat() if until else None,
                    # Present only for a chosen range; a rolling window has no fixed dates.
                    "date_from": date_from.isoformat() if custom else None,
                    "date_to": date_to.isoformat() if custom else None},
        "kpis": kpis,
        "trend": build_trend(rows, days, now, date_from if custom else None, date_to if custom else None),
        "mix": mix,
        "time_patterns": build_time_patterns(rows),
        "response": response,
        "outcomes": build_outcomes(rows),
        "barangays": barangays_out,
        "hotspots": build_hotspots(rows, exclude, barangay_names),
        "stations": stations_out,
        "responders": responders_out,
        "agencies": agencies_out,
        "readiness": readiness,
        "recent": build_recent(rows, barangay_names, exclude),
        "map": {"incidents": map_incidents, "coverage_polygons": [], "responders": map_responders,
                "stations": map_stations, "incidents_shown": len(map_incidents),
                "incidents_with_coordinates": sum(1 for r in rows if _coords(r.get("location")))},
    }
    if agency_type and not agency_id:
        out["comparison"] = build_comparison(agency_type, days, now, since, until)
    return out


def build_comparison(
    agency_type: str,
    days: int,
    now: datetime,
    since: datetime | None,
    until: datetime | None = None,
) -> list[dict[str, Any]]:
    """
    Every municipality side by side, for the Provincial Admin: where the people,
    the stations and the incidents are, and where they are not. Incidents are
    scoped to the admin's own agency_type, as everywhere else.
    """
    db = get_supabase()

    agencies, barangays, residents, stations, responders = _parallel(
        lambda: db.table("agencies").select("id, name, agency_type, municipality").execute().data or [],
        lambda: db.table("barangays").select("id, municipality").execute().data or [],
        lambda: _fetch_all(lambda: db.table("users").select("id, barangay_id").eq("role", "resident")),
        lambda: db.table("stations").select("id, agency_id, is_active").eq("is_active", True).execute().data or [],
        lambda: (db.table("users").select("id, agency_id, availability, approval_status")
                 .eq("role", "responder").execute().data or []),
    )
    muni_of = {a["id"]: a["municipality"] for a in agencies}
    type_ids = [a["id"] for a in agencies if a.get("agency_type") == agency_type]
    barangay_muni = {b["id"]: b["municipality"] for b in barangays}
    residents_by = Counter(barangay_muni.get(u.get("barangay_id")) for u in residents)
    stations_by = Counter(muni_of.get(s["agency_id"]) for s in stations)

    resp_by: Counter[str] = Counter()
    duty_by: Counter[str] = Counter()
    for u in responders:
        if u.get("approval_status") != "approved" or u.get("agency_id") not in type_ids:
            continue
        m = muni_of.get(u["agency_id"])
        resp_by[m] += 1
        duty_by[m] += 1 if u.get("availability") == "on_duty" else 0

    def _incident_query():
        query = (db.table("incidents").select("id, severity, status, assigned_agency_id, created_at")
                 .in_("assigned_agency_id", type_ids))
        if since:
            query = query.gte("created_at", since.astimezone(timezone.utc).isoformat())
        if until:
            query = query.lt("created_at", until.astimezone(timezone.utc).isoformat())
        return query

    inc = _fetch_all(_incident_query) if type_ids else []
    inc_by = Counter(muni_of.get(r["assigned_agency_id"]) for r in inc)
    crit_by = Counter(muni_of.get(r["assigned_agency_id"]) for r in inc if r.get("severity") == "critical")
    active_by = Counter(muni_of.get(r["assigned_agency_id"]) for r in inc if r.get("status") in ACTIVE_STATUSES)
    n_barangays = Counter(b["municipality"] for b in barangays)

    out = []
    for m in sorted(set(n_barangays) | set(muni_of.values())):
        out.append({
            "municipality": m, "barangays": n_barangays.get(m, 0), "residents": residents_by.get(m, 0),
            "stations": stations_by.get(m, 0), "responders": resp_by.get(m, 0), "on_duty": duty_by.get(m, 0),
            "incidents": inc_by.get(m, 0), "critical": crit_by.get(m, 0), "active": active_by.get(m, 0),
        })
    return out
