"""
Who should be told about a new incident - and how loudly.

THE RULE THIS CHANGES

Until 2026-09-25 a responder heard about an incident only when a dispatcher
assigned it to them. The dispatcher's console was the one place a new report
announced itself, and every second the dispatcher spent reading it, choosing a
crew and pressing Dispatch was a second nobody was moving. The rule is now:

  * The agency that owns the nearest station of the right type is told at once
    (unchanged: incident_service routes the report and notifies its admins), and
  * the responders ON DUTY and NEAR the incident are told at the same moment, by
    this module, without waiting to be assigned.

The dispatcher is still the dispatcher of record. Telling a responder is not
assigning them: nothing here writes `assigned_responder_id`, and a responder who
answers "I can respond" is giving the dispatcher a fact (who is close, who is
ready, how long they would take), not taking the call. See "What this never
does".

HOW "NEAR" IS MEASURED

By `app.core.geo.geodesic_m` - Vincenty's inverse formula on the WGS-84 ellipsoid,
accurate to half a millimetre - never by a straight subtraction or a spherical
approximation. A responder's position is only trusted while it is FRESH (the app
pings every two minutes; older than `Policy.fix_max_age_s` it is treated as
unknown), because a stale dot is exactly how the wrong crew is called: a
responder parked at the scene and one whose phone died forty minutes ago look
identical on a map.

WHO IS TOLD (the policy)

Severity sets how far the net is cast and how many people are woken:

    severity   radius   at most (free units told)
    critical   15 km    8
    high       10 km    5      <- an unscored report is treated as HIGH:
    medium      6 km    3         never under-alert what nobody has judged
    low         4 km    2

and each responder is in exactly one AVAILABILITY STATE, derived from what is
already assigned to them: free, committed (dispatched, not yet moving), en route,
or on scene.

THE HARD CASE: A BUSY RESPONDER, A NEW INCIDENT, NEAR THEM BOTH

A crew already driving to one call is also the nearest crew to a second. What is
the right thing to do? The answer this module implements, and the reasoning:

  1. FREE units in range get the full alert (level `alarm`). Nearest first, up to
     the cap. They are the ones who can actually go.

  2. A BUSY unit is NOT alarmed just because it is close. Waking a crew mid-call
     to tell them about every new report near them is noise at the worst time,
     and a system that pulls people between calls whenever a new dot appears
     abandons the first emergency for the second. It is told only when it
     matters, and quietly (level `advisory`: no looping alarm, no sound of its
     own, plainly labelled), in two cases:
        a. ESCALATION - the new incident is strictly more severe than the worst
           thing the unit is already committed to. A person with a low-priority
           call in hand would want to know a critical one is on their doorstep.
        b. NO FREE UNIT - nobody free is in range. Better to ask a busy crew that
           is close than to leave the incident unanswered; and only crews that
           are committed or en route (a crew on scene with a patient on the
           ground is never asked to consider leaving).
     A busy unit that is neither stays visible to the dispatcher (state and
     current call on the panel) and gets nothing.

  3. THE SYSTEM NEVER REASSIGNS. This is the same rule migration 024 states for
     declined calls - "the system never silently reassigns a life-safety call; it
     makes the silence impossible to miss" - applied to a new one. A busy
     responder keeps every call they hold. If they can also take the new one they
     say so (`can_respond`) and the dispatcher, who can see who is where and who
     is busy with what, decides. Dispatching a busy crew is possible (the queue
     holds several), but the dispatcher does it knowing what it costs.

  4. NOBODY IS LEFT UNTOLD. If no free unit is in range and no busy unit qualifies,
     the net widens rather than going quiet: the nearest few free units beyond
     the radius are told (flagged out of range), and every on-duty unit with no
     usable position is told (flagged location unknown). A missing GPS fix must
     never silence a call; the worst outcome of the fallback is a crew hearing
     about something that is too far away, which they can dismiss in a second.

WHAT THIS NEVER DOES

It never assigns, reassigns, accepts or declines anything, never changes an
incident's status, never touches a responder's queue. It reads positions and
assignments, and writes only notifications (the audit trail of who was told,
when, how far away, in what state) - which is also what lets an auditor ask
afterwards "who knew, and how quickly".
"""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

import structlog
from fastapi import HTTPException, status

from app.core import geo
from app.db.supabase_client import get_supabase
from app.services import notification_service

log = structlog.get_logger()


# =============================================================================
# Vocabulary
# =============================================================================

#: Notification types written by this module.
TYPE_NEARBY = "incident.nearby"                    # a responder was told (audit)
TYPE_ANSWER = "incident.nearby_answer"             # a responder answered (audit)
TYPE_RESPONSE = "incident.responder_response"      # what the agency's admins are shown

ANSWERS = ("can_respond", "unavailable")

#: Statuses that mean "this responder is committed to it".
_ACTIVE_STATUSES = ("dispatched", "en_route", "arrived")
#: Statuses of an incident nobody has been sent to yet.
_OPEN_STATUSES = ("received", "processing")
#: An undispatched report older than this is no longer a live "nearby" alert.
_MAX_INCIDENT_AGE = timedelta(hours=12)

_SEVERITY_RANK = {"critical": 0, "high": 1, "medium": 2, "low": 3}
UNTRIAGED_RANK = 1  # an unscored report is treated as HIGH

_STATE_ORDER = {"free": 0, "committed": 1, "en_route": 2, "on_scene": 3}
_LEVEL_ORDER = {"alarm": 0, "advisory": 1, "none": 2}


def severity_rank(severity: str | None) -> int:
    """0 = critical ... 3 = low. Anything unscored ranks as HIGH."""
    return _SEVERITY_RANK.get((severity or "").strip().lower(), UNTRIAGED_RANK)


@dataclass(frozen=True)
class Policy:
    """The numbers behind the rule above. One place, so tuning is one edit."""

    #: A responder position older than this is treated as unknown.
    fix_max_age_s: int = 10 * 60
    #: Radius by severity rank (critical, high, medium, low), kilometres.
    radius_km: tuple[float, float, float, float] = (15.0, 10.0, 6.0, 4.0)
    #: Most FREE units told at alarm level, by severity rank.
    max_alarm: tuple[int, int, int, int] = (8, 5, 3, 2)
    #: Most busy units given an advisory.
    max_advisory: int = 3
    #: When nobody is in range: how many of the nearest free units beyond it to tell.
    fallback_nearest: int = 3


DEFAULT_POLICY = Policy()


# =============================================================================
# The pure core - no database, no clock. Everything below is testable with dicts.
# =============================================================================

@dataclass
class Scene:
    """The incident, as the ranking needs it."""

    id: str
    severity: str | None
    lat: float | None
    lng: float | None


@dataclass
class Unit:
    """A responder, as the ranking needs them."""

    id: str
    full_name: str | None = None
    badge_id: str | None = None
    lat: float | None = None
    lng: float | None = None
    #: Seconds since the position was reported; None when it is not known.
    fix_age_s: int | None = None
    #: What is already assigned to them: dicts with id, status, severity, category, address.
    calls: list[dict] = field(default_factory=list)


@dataclass
class Assessment:
    """One responder measured against one incident."""

    responder_id: str
    full_name: str | None
    badge_id: str | None
    state: str                      # free | committed | en_route | on_scene
    calls: list[dict]
    distance_m: float | None
    eta_min: int | None
    direction: str | None           # compass point from the responder TO the incident
    fix_age_s: int | None
    located: bool                   # a fresh, valid position was used
    in_range: bool
    level: str = "none"             # alarm | advisory | none
    reason: str = "out_of_range"
    rank: int | None = None         # 1-based among those who will be told
    #: The position the distance was measured from (None unless `located`). Shown
    #: to dispatchers only, as /map/data already does, so the console can draw and
    #: route to it.
    lat: float | None = None
    lng: float | None = None

    @property
    def distance_km(self) -> float | None:
        return None if self.distance_m is None else round(self.distance_m / 1000.0, 2)

    def call_summaries(self) -> list[dict]:
        return [
            {
                "incident_id": c.get("id"),
                "status": c.get("status"),
                "severity": c.get("severity"),
                "category": c.get("category"),
                "address": c.get("address"),
            }
            for c in self.calls
        ]

    def to_dict(self) -> dict:
        return {
            "responder_id": self.responder_id,
            "full_name": self.full_name,
            "badge_id": self.badge_id,
            "state": self.state,
            "distance_m": None if self.distance_m is None else round(self.distance_m),
            "distance_km": self.distance_km,
            "eta_min": self.eta_min,
            "direction": self.direction,
            "fix_age_s": self.fix_age_s,
            "located": self.located,
            "latitude": None if self.lat is None else round(self.lat, 6),
            "longitude": None if self.lng is None else round(self.lng, 6),
            "level": self.level,
            "reason": self.reason,
            "rank": self.rank,
            "current_calls": self.call_summaries(),
        }


def unit_state(calls: Iterable[dict]) -> str:
    """The most restrictive thing a unit is doing: on scene, then en route, then
    committed (dispatched, not yet moving), else free."""
    statuses = {c.get("status") for c in calls}
    if "arrived" in statuses:
        return "on_scene"
    if "en_route" in statuses:
        return "en_route"
    if "dispatched" in statuses:
        return "committed"
    return "free"


def _worst_rank(calls: Iterable[dict]) -> int | None:
    """The most severe thing already assigned (lowest rank number), or None."""
    ranks = [severity_rank(c.get("severity")) for c in calls]
    return min(ranks) if ranks else None


def _by_distance(a: Assessment):
    # Located units first, nearest first; ties broken by name so the order is stable.
    return (a.distance_m is None, a.distance_m or 0.0, (a.full_name or ""), a.responder_id)


def assess(scene: Scene, units: Iterable[Unit], policy: Policy = DEFAULT_POLICY) -> list[Assessment]:
    """Measure every unit against the incident and decide who is told, and how.

    Returns ALL units, most-relevant first: alarm, then advisory, then the rest,
    each group by state then distance. The dispatcher's panel shows everyone; only
    those whose `level` is not "none" are notified.
    """
    inc_rank = severity_rank(scene.severity)
    radius_km = policy.radius_km[inc_rank]
    scene_located = geo.valid_coordinates(scene.lat, scene.lng)

    rows: list[Assessment] = []
    for u in units:
        calls = list(u.calls)
        state = unit_state(calls)
        located = bool(
            scene_located
            and geo.valid_coordinates(u.lat, u.lng)
            and u.fix_age_s is not None
            and u.fix_age_s <= policy.fix_max_age_s
        )
        d_m = eta = direction = None
        if located:
            d_m = geo.geodesic_m(u.lat, u.lng, scene.lat, scene.lng)  # type: ignore[arg-type]
            eta = geo.estimate_eta_minutes(d_m / 1000.0)
            direction = geo.compass_point(
                geo.initial_bearing_deg(u.lat, u.lng, scene.lat, scene.lng)  # type: ignore[arg-type]
            )
        in_range = located and d_m is not None and d_m / 1000.0 <= radius_km

        if not scene_located:
            reason = "incident_not_located"
        elif not located:
            reason = "not_located"
        elif not in_range:
            reason = "out_of_range"
        else:
            reason = "busy"

        rows.append(Assessment(
            responder_id=u.id, full_name=u.full_name, badge_id=u.badge_id,
            state=state, calls=calls, distance_m=d_m, eta_min=eta, direction=direction,
            fix_age_s=u.fix_age_s, located=located, in_range=in_range,
            level="none", reason=reason,
            lat=u.lat if located else None, lng=u.lng if located else None,
        ))

    free = [a for a in rows if a.state == "free"]
    busy = [a for a in rows if a.state != "free"]

    # 1. Free units in range: the ones who can actually go. Nearest first, capped.
    free_in = sorted((a for a in free if a.in_range), key=_by_distance)
    cap = policy.max_alarm[inc_rank]
    for i, a in enumerate(free_in):
        a.level, a.reason = ("alarm", "nearest") if i < cap else ("none", "beyond_cap")

    # 2. Busy units in range: quietly, and only when it matters.
    advisories: list[Assessment] = []
    for a in sorted((b for b in busy if b.in_range), key=_by_distance):
        worst = _worst_rank(a.calls)
        if worst is not None and inc_rank < worst:
            a.level, a.reason = "advisory", "escalation"
            advisories.append(a)
        elif a.state in ("committed", "en_route") and not free_in:
            a.level, a.reason = "advisory", "no_free_unit"
            advisories.append(a)
        else:
            a.reason = "busy"
    for a in advisories[policy.max_advisory:]:
        a.level, a.reason = "none", "beyond_cap"

    # 3. Nobody untold: if no FREE unit in range was alarmed, widen the net instead of
    # going quiet. A busy unit's quiet advisory does not count as coverage - it is a
    # courtesy to them, not somebody who can go.
    covered = any(a.level == "alarm" for a in rows if a.in_range)
    if not covered:
        wide_level = "alarm" if inc_rank <= UNTRIAGED_RANK else "advisory"
        beyond = sorted((a for a in free if a.located and not a.in_range), key=_by_distance)
        for a in beyond[: policy.fallback_nearest]:
            a.level, a.reason = wide_level, "nobody_in_range"
        for a in free:
            if not a.located:
                a.level = wide_level
                a.reason = "location_unknown" if scene_located else "incident_not_located"

    # Order for display, then number those who will be told.
    rows.sort(key=lambda a: (
        _LEVEL_ORDER[a.level], _STATE_ORDER[a.state], _by_distance(a),
    ))
    n = 0
    for a in rows:
        if a.level != "none":
            n += 1
            a.rank = n
    return rows


def summarize(assessments: Iterable[Assessment]) -> dict:
    """The counts a panel header wants."""
    rows = list(assessments)
    return {
        "on_duty": len(rows),
        "free": sum(1 for a in rows if a.state == "free"),
        "busy": sum(1 for a in rows if a.state != "free"),
        "in_range": sum(1 for a in rows if a.in_range),
        "notified": sum(1 for a in rows if a.level != "none"),
        "alarm": sum(1 for a in rows if a.level == "alarm"),
        "advisory": sum(1 for a in rows if a.level == "advisory"),
    }


# =============================================================================
# Reading the database
# =============================================================================

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_ts(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _fix_age_s(updated_at: Any, now: datetime) -> int | None:
    ts = _parse_ts(updated_at)
    return None if ts is None else max(0, int((now - ts).total_seconds()))


def _call_dict(row: dict) -> dict:
    return {
        "id": row.get("id"),
        "status": row.get("status"),
        "severity": row.get("severity"),
        "category": row.get("incident_category"),
        "address": row.get("location_address"),
    }


def load_units(db, agency_id: str, *, now: datetime | None = None) -> list[Unit]:
    """Every approved, on-duty responder of one agency, with their position and
    what they are already committed to."""
    now = now or _now()
    users = (
        db.table("users")
        .select("id, full_name, badge_id, location, location_updated_at")
        .eq("role", "responder")
        .eq("agency_id", agency_id)
        .eq("approval_status", "approved")
        .eq("availability", "on_duty")
        .execute()
        .data
        or []
    )
    ids = [u["id"] for u in users]
    calls_by: dict[str, list[dict]] = {}
    if ids:
        for row in (
            db.table("incidents")
            .select("id, status, severity, incident_category, location_address, assigned_responder_id")
            .in_("assigned_responder_id", ids)
            .in_("status", list(_ACTIVE_STATUSES))
            .execute()
            .data
            or []
        ):
            calls_by.setdefault(str(row["assigned_responder_id"]), []).append(_call_dict(row))

    units: list[Unit] = []
    for u in users:
        lat, lng = geo.parse_point(u.get("location"))
        units.append(Unit(
            id=str(u["id"]), full_name=u.get("full_name"), badge_id=u.get("badge_id"),
            lat=lat, lng=lng, fix_age_s=_fix_age_s(u.get("location_updated_at"), now),
            calls=calls_by.get(str(u["id"]), []),
        ))
    return units


def scene_from_row(row: dict, *, lat: float | None = None, lng: float | None = None) -> Scene:
    """An incident row as a Scene. Explicit coordinates win over the row's own
    geometry - the write path knows them exactly and the returned column may be
    shaped differently."""
    if lat is None or lng is None:
        lat, lng = geo.parse_point(row.get("location"))
    return Scene(id=str(row["id"]), severity=row.get("severity"), lat=lat, lng=lng)


def rank_for_incident(
    db, incident_row: dict, *, lat: float | None = None, lng: float | None = None,
    now: datetime | None = None, policy: Policy = DEFAULT_POLICY,
) -> list[Assessment]:
    """Every on-duty responder of the incident's agency, measured against it."""
    agency_id = incident_row.get("assigned_agency_id")
    if not agency_id:
        return []
    now = now or _now()
    return assess(
        scene_from_row(incident_row, lat=lat, lng=lng),
        load_units(db, str(agency_id), now=now),
        policy,
    )


# =============================================================================
# 1. Telling the responders - at the moment a report lands
# =============================================================================

def _place(row: dict) -> str:
    return (row.get("location_address") or "Location not provided")[:120]


def _title_for(severity: str | None) -> str:
    return "New incident near you" if not severity else f"New {severity.upper()} incident near you"


def _body_for(row: dict, a: Assessment) -> str:
    where = _place(row)
    if a.distance_km is None:
        return f"{where} - your position is not known, so distance could not be measured"
    return f"{where} - {a.distance_km:.1f} km {a.direction or ''}, about {a.eta_min} min".replace("  ", " ")


def _audit_row(row: dict, a: Assessment, at: str) -> dict:
    """One `incident.nearby` notification, for one responder."""
    severity = row.get("severity")
    return {
        "recipient_id": a.responder_id,
        "type": TYPE_NEARBY,
        "title": _title_for(severity),
        "body": _body_for(row, a),
        "link": None,
        "is_important": a.level == "alarm" and severity_rank(severity) <= 1,
        "metadata": {
            "incident_id": str(row["id"]),
            "level": a.level,
            "reason": a.reason,
            "state": a.state,
            "distance_m": None if a.distance_m is None else round(a.distance_m),
            "eta_min": a.eta_min,
            "at": at,
        },
    }


def notify_nearby(
    db, incident_row: dict, *, lat: float | None = None, lng: float | None = None,
    now: datetime | None = None, policy: Policy = DEFAULT_POLICY,
) -> list[Assessment]:
    """Tell the responders near a NEW incident, and record who was told.

    Called from the write path the moment the report is saved. Never raises: the
    report is already stored and the agency's admins already told, and a failure
    here (a slow query, an unreadable position) must cost the resident nothing.

    What "told" means: a row in `notifications` (the audit trail), and the
    responder's phone, which asks GET /responder/nearby every few seconds while
    on duty, will surface the same incident with its own live measurement.
    """
    try:
        now = now or _now()
        assessed = rank_for_incident(db, incident_row, lat=lat, lng=lng, now=now, policy=policy)
        told = [a for a in assessed if a.level != "none"]
        if told:
            at = now.isoformat()
            db.table("notifications").insert([_audit_row(incident_row, a, at) for a in told]).execute()
            for a in told:
                _remember(str(incident_row["id"]), a.responder_id)
        log.info(
            "incident.nearby_notified",
            incident_id=str(incident_row.get("id")),
            severity=incident_row.get("severity"),
            **summarize(assessed),
        )
        return told
    except Exception:
        log.error("incident.nearby_notify_failed", incident_id=incident_row.get("id"), exc_info=True)
        return []


# ── remembering who has been recorded, without asking the database every poll ──

_RECORDED: "OrderedDict[tuple[str, str], bool]" = OrderedDict()
_RECORDED_MAX = 5000


def _remember(incident_id: str, responder_id: str) -> None:
    _RECORDED[(incident_id, responder_id)] = True
    _RECORDED.move_to_end((incident_id, responder_id))
    while len(_RECORDED) > _RECORDED_MAX:
        _RECORDED.popitem(last=False)


def clear_memory() -> None:
    """Forget who has been recorded. For tests."""
    _RECORDED.clear()


def _already_told(db, incident_id: str, responder_id: str) -> bool:
    if (incident_id, responder_id) in _RECORDED:
        return True
    rows = (
        db.table("notifications")
        .select("id")
        .eq("recipient_id", responder_id)
        .eq("type", TYPE_NEARBY)
        .eq("metadata->>incident_id", incident_id)
        .limit(1)
        .execute()
        .data
        or []
    )
    if rows:
        _remember(incident_id, responder_id)
    return bool(rows)


# =============================================================================
# 2. The responder's own view: what is near ME, right now
# =============================================================================

def _my_position(unit: Unit | None, lat: float | None, lng: float | None):
    """The position to measure from: the phone's own fresh reading if it sent
    one, else the last reported position. Returns (lat, lng, fix_age_s, source)."""
    if lat is not None and lng is not None and geo.valid_coordinates(lat, lng):
        return float(lat), float(lng), 0, "device"
    if unit is not None and unit.lat is not None:
        return unit.lat, unit.lng, unit.fix_age_s, "last_reported"
    return None, None, None, "none"


def nearby_for_responder(
    db, responder: dict, *, lat: float | None = None, lng: float | None = None,
    now: datetime | None = None, policy: Policy = DEFAULT_POLICY,
) -> dict:
    """Undispatched incidents near this responder that they should know about.

    Measured live, from the phone's own position when it sends one (a responder
    who has driven three kilometres since the last two-minute ping is not where
    the last ping says), otherwise from the last reported position. The same
    `assess` decides everything, so what a responder is told and what the
    dispatcher's panel shows can never disagree.
    """
    now = now or _now()
    me = str(responder["id"])

    profile = (
        db.table("users")
        .select("id, agency_id, availability, approval_status")
        .eq("id", me)
        .maybe_single()
        .execute()
    )
    prow = (profile.data if profile is not None else None) or {}
    agency_id = prow.get("agency_id") or responder.get("agency_id")
    if prow.get("availability") != "on_duty" or not agency_id:
        return {"on_duty": False, "position": "none", "items": []}

    units = load_units(db, str(agency_id), now=now)
    mine = next((u for u in units if u.id == me), None)
    my_lat, my_lng, my_age, source = _my_position(mine, lat, lng)
    if mine is None:
        # On duty but not in the list (approval race): measure them as a bare unit.
        mine = Unit(id=me)
        units.append(mine)
    mine.lat, mine.lng, mine.fix_age_s = my_lat, my_lng, my_age

    cutoff = (now - _MAX_INCIDENT_AGE).isoformat()
    incidents = (
        db.table("incidents")
        .select(
            "id, record_number, status, severity, incident_category, report_text, "
            "location_address, location, created_at, sos_flagged, assigned_responder_id, declined_by"
        )
        .eq("assigned_agency_id", str(agency_id))
        .in_("status", list(_OPEN_STATUSES))
        .is_("assigned_responder_id", "null")
        .gte("created_at", cutoff)
        .execute()
        .data
        or []
    )

    answers = _my_answers(db, me, now)
    items: list[dict] = []
    for inc in incidents:
        # A responder who handed this incident back (migration 024) is not woken
        # for it again the moment it returns to the pool - they said they cannot go.
        if str(inc.get("declined_by")) == me:
            continue
        scene = scene_from_row(inc)
        assessed = assess(scene, units, policy)
        mine_a = next((a for a in assessed if a.responder_id == me), None)
        if mine_a is None or mine_a.level == "none":
            continue
        items.append({
            "incident_id": str(inc["id"]),
            "record_number": inc.get("record_number"),
            "severity": inc.get("severity"),
            "category": inc.get("incident_category"),
            "report_text": (inc.get("report_text") or "")[:240],
            "location_address": inc.get("location_address"),
            "latitude": scene.lat,
            "longitude": scene.lng,
            "created_at": inc.get("created_at"),
            "sos_flagged": bool(inc.get("sos_flagged")),
            "distance_m": None if mine_a.distance_m is None else round(mine_a.distance_m),
            "distance_km": mine_a.distance_km,
            "eta_min": mine_a.eta_min,
            "direction": mine_a.direction,
            "level": mine_a.level,
            "reason": mine_a.reason,
            "rank": mine_a.rank,
            "units_free_in_range": sum(1 for a in assessed if a.state == "free" and a.in_range),
            "you": {"state": mine_a.state, "current_calls": mine_a.call_summaries()},
            "answered": answers.get(str(inc["id"])),
        })
        _record_surfaced(db, inc, mine_a, now)

    items.sort(key=lambda i: (
        _LEVEL_ORDER[i["level"]], severity_rank(i["severity"]),
        i["distance_m"] is None, i["distance_m"] or 0,
    ))
    return {"on_duty": True, "position": source, "items": items}


def _record_surfaced(db, incident_row: dict, a: Assessment, now: datetime) -> None:
    """A responder who moved into range (or came on duty) after the report landed
    was not in the creation-time fan-out. Record the first time they are shown it,
    so 'who was told, and when' is complete. Best effort, never raises."""
    try:
        iid = str(incident_row["id"])
        if _already_told(db, iid, a.responder_id):
            return
        db.table("notifications").insert([_audit_row(incident_row, a, now.isoformat())]).execute()
        _remember(iid, a.responder_id)
    except Exception:
        log.warning("proximity.record_surfaced_failed", exc_info=True)


def _my_answers(db, responder_id: str, now: datetime) -> dict[str, str]:
    """incident id -> this responder's latest answer, from the last 12 hours."""
    rows = (
        db.table("notifications")
        .select("metadata, created_at")
        .eq("recipient_id", responder_id)
        .eq("type", TYPE_ANSWER)
        .gte("created_at", (now - _MAX_INCIDENT_AGE).isoformat())
        .order("created_at", desc=False)
        .execute()
        .data
        or []
    )
    out: dict[str, str] = {}
    for r in rows:
        meta = r.get("metadata") or {}
        if meta.get("incident_id") and meta.get("answer") in ANSWERS:
            out[str(meta["incident_id"])] = meta["answer"]
    return out


# =============================================================================
# 3. The responder answers
# =============================================================================

def answer_nearby(
    db, responder: dict, incident_id: str, answer: str, *,
    lat: float | None = None, lng: float | None = None,
    now: datetime | None = None, policy: Policy = DEFAULT_POLICY,
) -> dict:
    """The responder's reply to "an incident is near you".

    `can_respond` tells the agency's admins who is ready and how long they would
    take; `unavailable` is recorded and shown on the panel without ringing anyone's
    bell. NEITHER ASSIGNS ANYTHING - the dispatcher decides. Replies are recorded,
    not deduplicated: the latest wins, and the history is the audit trail.
    """
    if answer not in ANSWERS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"answer must be one of: {', '.join(ANSWERS)}.",
        )
    now = now or _now()
    me = str(responder["id"])

    inc = (
        db.table("incidents")
        .select(
            "id, record_number, status, severity, incident_category, report_text, "
            "location_address, location, assigned_agency_id, assigned_responder_id"
        )
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    row = inc.data if inc is not None else None
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    profile = (
        db.table("users")
        .select("id, full_name, agency_id, availability")
        .eq("id", me)
        .maybe_single()
        .execute()
    )
    prow = (profile.data if profile is not None else None) or {}
    agency_id = prow.get("agency_id") or responder.get("agency_id")
    if str(row.get("assigned_agency_id")) != str(agency_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This incident belongs to another agency.")
    if prow.get("availability") != "on_duty":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Go on duty before answering.")
    if row.get("status") not in _OPEN_STATUSES or row.get("assigned_responder_id"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A responder has already been assigned to this incident.",
        )

    # Measure them the way the alert did, so what the admin reads matches what
    # the responder saw.
    units = load_units(db, str(agency_id), now=now)
    mine = next((u for u in units if u.id == me), None) or Unit(id=me)
    my_lat, my_lng, my_age, _ = _my_position(mine, lat, lng)
    mine.lat, mine.lng, mine.fix_age_s = my_lat, my_lng, my_age
    if not any(u.id == me for u in units):
        units.append(mine)
    a = next(x for x in assess(scene_from_row(row), units, policy) if x.responder_id == me)

    at = now.isoformat()
    meta = {
        "incident_id": str(incident_id),
        "answer": answer,
        "state": a.state,
        "distance_m": None if a.distance_m is None else round(a.distance_m),
        "eta_min": a.eta_min,
        "at": at,
    }
    db.table("notifications").insert({
        "recipient_id": me,
        "type": TYPE_ANSWER,
        "title": "You can respond" if answer == "can_respond" else "You are not available",
        "body": _place(row),
        "link": None,
        "is_important": False,
        "metadata": meta,
    }).execute()

    if answer == "can_respond":
        name = prow.get("full_name") or "A responder"
        status_word = {
            "free": "free", "committed": "already dispatched to another call",
            "en_route": "en route to another call", "on_scene": "on scene at another call",
        }[a.state]
        where = _place(row)
        dist = (
            f"{a.distance_km:.1f} km {a.direction or ''}, about {a.eta_min} min"
            if a.distance_km is not None else "position not known"
        ).replace("  ", " ")
        try:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_=TYPE_RESPONSE,
                title=f"{name} can respond",
                body=f"{where} - {dist} - {status_word}",
                link=f"/incidents/{incident_id}",
                is_important=severity_rank(row.get("severity")) <= 1,
                metadata={"incident_id": str(incident_id), "responder_id": me, **meta},
            )
        except Exception:
            log.error("proximity.answer_notify_failed", incident_id=incident_id, exc_info=True)

    log.info("incident.nearby_answered", incident_id=incident_id, responder_id=me, answer=answer, state=a.state)
    return {"incident_id": str(incident_id), "answer": answer, "recorded_at": at}


# =============================================================================
# 4. The dispatcher's view: who is near THIS incident
# =============================================================================

def _rows_for_incident(db, type_: str, incident_id: str) -> list[dict]:
    return (
        db.table("notifications")
        .select("recipient_id, metadata, created_at")
        .eq("type", type_)
        .eq("metadata->>incident_id", incident_id)
        .order("created_at", desc=False)
        .execute()
        .data
        or []
    )


def nearby_for_admin(
    db, incident_row: dict, *, now: datetime | None = None, policy: Policy = DEFAULT_POLICY,
) -> dict:
    """Everyone on duty in the incident's agency, ranked by how well they fit it,
    with who has been told and who has answered. What the dispatcher decides from."""
    now = now or _now()
    incident_id = str(incident_row["id"])
    assessed = rank_for_incident(db, incident_row, now=now, policy=policy)

    told_at: dict[str, str] = {}
    for r in _rows_for_incident(db, TYPE_NEARBY, incident_id):
        told_at.setdefault(str(r["recipient_id"]), r.get("created_at"))
    answered: dict[str, dict] = {}
    for r in _rows_for_incident(db, TYPE_ANSWER, incident_id):
        meta = r.get("metadata") or {}
        answered[str(r["recipient_id"])] = {"answer": meta.get("answer"), "at": meta.get("at") or r.get("created_at")}

    off_duty = 0
    agency_id = incident_row.get("assigned_agency_id")
    if agency_id:
        roster = (
            db.table("users")
            .select("id, availability")
            .eq("role", "responder")
            .eq("agency_id", str(agency_id))
            .eq("approval_status", "approved")
            .execute()
            .data
            or []
        )
        off_duty = sum(1 for r in roster if r.get("availability") != "on_duty")

    items = []
    for a in assessed:
        d = a.to_dict()
        d["notified_at"] = told_at.get(a.responder_id)
        ans = answered.get(a.responder_id)
        d["answer"] = ans["answer"] if ans else None
        d["answered_at"] = ans["at"] if ans else None
        items.append(d)

    return {
        "incident_id": incident_id,
        "summary": {**summarize(assessed), "off_duty": off_duty},
        "policy": {
            "radius_km": policy.radius_km[severity_rank(incident_row.get("severity"))],
            "fix_max_age_s": policy.fix_max_age_s,
        },
        "responders": items,
    }


def station_distance_km(incident_row: dict) -> float | None:
    """How far the incident is from the station it was routed to (or None)."""
    st = incident_row.get("stations") or {}
    s_lat, s_lng = geo.parse_point(st.get("location"))
    i_lat, i_lng = geo.parse_point(incident_row.get("location"))
    if s_lat is None or i_lat is None:
        return None
    return round(geo.geodesic_km(s_lat, s_lng, i_lat, i_lng), 2)
