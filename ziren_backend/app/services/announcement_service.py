"""
announcement_service - Provincial Admin broadcasts (spec Section 14), and the
safety alerts they became on 2026-10-01 (migration 043).

WHAT CHANGED, AND WHY

An announcement could only be aimed at a ROLE ("all residents") or one agency,
and it could say nothing but a title and a message. That is fine for "the app
is down at 2 a.m.". It is wrong for the things a province actually has to tell
people in a hurry:

  * An evacuation order is for two barangays of one town. Sent to the whole
    province, everybody else learns that these alerts are not for them - and
    ignores the next one, which is how a warning system stops working. So an
    announcement now has a PLACE: municipalities, and within one, barangays.
  * Once it was sent, nobody could tell who was safe and who was still waiting
    on a roof. So a safety alert can ASK: the resident answers "I am safe" or
    "I need help", the stations of their town are told the moment somebody
    needs help, and the dashboard lists who needs help, who is safe, and who
    has not answered - with a phone number to call.
  * A warning had no end. An "all clear" now ends the warning it answers, and
    reaches exactly the people the warning reached.
  * An evacuation order needs to say WHERE to go; a weather advisory, which
    signal. Each kind carries its own facts in `details`.

PLACE RULES (the part most likely to be asked about)

  * No place = the whole province, as before.
  * A resident is reached when their registered municipality is listed and -
    if barangays were picked for it - their barangay is one of them. A resident
    whose barangay is unknown is reached by any alert for their town: telling
    one person too many is cheaper than missing the one in the flood zone.
  * Station staff (agency admins, responders) are reached by any alert for the
    town their agency is in: a station covers its whole town.
  * A Provincial Admin is reached everywhere.

Before migration 043 is run, an announcement that uses none of the new fields
is still published the old way; one that does is refused with SchemaNotReady,
which names the migration.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Iterable
from uuid import uuid4

import structlog

from app.core.agency_names import provincial_office_name
from app.db.supabase_client import get_supabase
from app.services import audit_service, notification_service

log = structlog.get_logger()

_ALL_ROLES = ("provincial_admin", "agency_admin", "responder", "resident")

# ── Kinds ────────────────────────────────────────────────────────────────────

SAFETY_CATEGORIES = (
    "evacuation", "weather", "hazard", "road_closure", "missing_person", "all_clear", "emergency",
)
INFO_CATEGORIES = (
    "relief", "health", "drill", "utility",
    "service_interruption", "maintenance", "feature", "reminder", "general",
)
CATEGORIES = SAFETY_CATEGORIES + INFO_CATEGORIES

# What the table accepted before migration 043.
LEGACY_CATEGORIES = {"maintenance", "emergency", "service_interruption", "feature", "reminder", "general"}

# The kinds a resident can be asked to answer. A road closure or a missing
# person is not a question about the resident's own safety.
RESPONSE_CATEGORIES = {"evacuation", "weather", "hazard", "emergency"}

# Safety alerts are "important": the phone puts them on screen at once instead
# of leaving them in a list.
URGENT_CATEGORIES = set(SAFETY_CATEGORIES)

LABELS = {
    "evacuation": "Evacuation order",
    "weather": "Weather advisory",
    "hazard": "Hazard warning",
    "road_closure": "Road closure",
    "missing_person": "Missing person",
    "all_clear": "All clear",
    "emergency": "Emergency",
    "relief": "Relief distribution",
    "health": "Health advisory",
    "drill": "Drill",
    "utility": "Power / water interruption",
    "service_interruption": "Service interruption",
    "maintenance": "Maintenance",
    "feature": "New feature",
    "reminder": "Reminder",
    "general": "Announcement",
}

# Who issues which kind (2026-10-01, the user's call). In practice MDRRMO
# declares evacuations and weather/hazard warnings and runs relief; PNP handles
# missing persons. Left open, the PNP provincial office could order a
# province-wide evacuation the MDRRMO knew nothing about. Every kind not listed
# (road closure, emergency, all clear, ordinary notices) is open to all three.
KIND_OWNERS: dict[str, frozenset[str]] = {
    "evacuation": frozenset({"MDRRMO"}),
    "weather": frozenset({"MDRRMO"}),
    "hazard": frozenset({"MDRRMO"}),
    "relief": frozenset({"MDRRMO"}),
    "missing_person": frozenset({"PNP"}),
}


def may_issue(category: str, agency_type: str | None) -> bool:
    owners = KIND_OWNERS.get(category)
    return owners is None or (agency_type or "").upper() in owners


def _assert_may_issue(category: str, actor: dict) -> None:
    if not may_issue(category, actor.get("agency_type")):
        owners = " or the ".join(provincial_office_name(o) for o in sorted(KIND_OWNERS[category]))
        kind = LABELS.get(category, category).lower()
        article = "an" if kind[:1] in "aeiou" else "a"
        raise PermissionError(f"Only the {owners} issues {article} {kind}.")


def _assert_issuer(row: dict, actor: dict, doing: str) -> None:
    """Only the office that issued an alert ends it or takes it down - the BFP
    cannot call off an MDRRMO evacuation. An announcement from before 043 has
    no issuer on record, and any Provincial Admin may act on it."""
    issuer = (row.get("issuer_agency_type") or "").upper()
    if issuer and issuer != (actor.get("agency_type") or "").upper():
        raise PermissionError(f"Only the {provincial_office_name(issuer)}, which issued it, can {doing} it.")

MUNICIPALITIES = ("Almeria", "Biliran", "Cabucgayan", "Caibiran", "Culaba", "Kawayan", "Maripipi", "Naval")

RESPONSE_STATUSES = ("safe", "need_help")

_TITLE_MAX = 120
_BODY_MAX = 2000
_NOTE_MAX = 300
_MAX_BARANGAYS = 80
_NOTIFY_CHUNK = 500

# The facts each kind carries. ("str", max) | ("int", lo, hi) | ("enum", {...}) | ("centers",)
_DETAILS: dict[str, dict[str, tuple]] = {
    "weather": {
        "signal": ("int", 1, 5),
        "rainfall": ("enum", {"yellow", "orange", "red"}),
        "storm_name": ("str", 60),
    },
    "hazard": {
        "hazard": ("enum", {"flood", "landslide", "storm_surge", "earthquake", "tsunami", "volcanic", "fire", "other"}),
        "area": ("str", 200),
    },
    "evacuation": {
        "kind": ("enum", {"preemptive", "forced"}),
        "centers": ("centers",),
        "bring": ("str", 300),
    },
    "road_closure": {
        "road": ("str", 160),
        "alternate": ("str", 200),
        "reopens": ("str", 80),
    },
    "missing_person": {
        "name": ("str", 120),
        "age": ("int", 0, 120),
        "last_seen": ("str", 200),
        "description": ("str", 300),
        "contact": ("str", 80),
    },
    "relief": {"where": ("str", 160), "when": ("str", 120), "bring": ("str", 200)},
    "health": {"when": ("str", 120)},
    "drill": {"when": ("str", 120)},
    "utility": {"provider": ("str", 80), "when": ("str", 120)},
}

# What a kind is useless without.
_REQUIRED: dict[str, tuple[tuple[str, ...], str]] = {
    "hazard": (("hazard",), "Say which hazard this is."),
    "evacuation": (("centers",), "An evacuation order must say where to go: add at least one evacuation centre."),
    "road_closure": (("road",), "Say which road is closed."),
    "missing_person": (("name", "last_seen", "contact"), "A missing-person notice needs the name, where they were last seen and who to call."),
}


class SchemaNotReady(RuntimeError):
    """Migration 043 has not been run on this database."""

    def __init__(self, what: str = "This"):
        super().__init__(
            f"{what} needs migration 043_announcements_safety_alerts.sql, which has not been run on "
            "this database yet. Run it once in the Supabase SQL Editor."
        )


class AlertClosed(Exception):
    """The alert has ended or expired; it takes no more answers."""


# ── Small helpers ────────────────────────────────────────────────────────────

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_time(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _expired(row: dict, now: datetime) -> bool:
    until = _parse_time(row.get("expires_at"))
    return until is not None and until <= now


def _is_schema_error(exc: Exception) -> bool:
    text = str(exc).lower()
    return any(k in text for k in (
        "pgrst204", "pgrst205", "42703", "42p01", "schema cache", "does not exist",
        "announcements_category_check",
    ))


def canon_town(value: Any) -> str | None:
    """'naval ' -> 'Naval'. None for anything that is not one of the eight."""
    if not isinstance(value, str):
        return None
    wanted = value.strip().lower()
    return next((m for m in MUNICIPALITIES if m.lower() == wanted), None)


def _str_ids(values: Iterable[Any] | None) -> list[str]:
    out: list[str] = []
    for v in values or []:
        s = str(v).strip()
        if s and s not in out:
            out.append(s)
    return out


# ── Validation ───────────────────────────────────────────────────────────────

def _clean_details(category: str, raw: Any) -> dict:
    """Keep the facts this kind knows, each checked and trimmed; drop the rest."""
    spec = _DETAILS.get(category, {})
    raw = raw if isinstance(raw, dict) else {}
    out: dict[str, Any] = {}
    for key, rule in spec.items():
        value = raw.get(key)
        if value is None or value == "":
            continue
        kind = rule[0]
        if kind == "str":
            text = str(value).strip()[: rule[1]]
            if text:
                out[key] = text
        elif kind == "int":
            try:
                n = int(value)
            except (TypeError, ValueError):
                raise ValueError(f"{key} must be a whole number.")
            if not rule[1] <= n <= rule[2]:
                raise ValueError(f"{key} must be between {rule[1]} and {rule[2]}.")
            out[key] = n
        elif kind == "enum":
            text = str(value).strip().lower()
            if text not in rule[1]:
                raise ValueError(f"{key} must be one of: {', '.join(sorted(rule[1]))}.")
            out[key] = text
        elif kind == "centers":
            if not isinstance(value, list):
                raise ValueError("centers must be a list.")
            centers = []
            for c in value[:10]:
                if not isinstance(c, dict):
                    continue
                name = str(c.get("name") or "").strip()[:120]
                if not name:
                    continue
                center = {"name": name}
                place = str(c.get("place") or "").strip()[:160]
                if place:
                    center["place"] = place
                centers.append(center)
            if centers:
                out[key] = centers

    required = _REQUIRED.get(category)
    if required and not all(out.get(k) for k in required[0]):
        raise ValueError(required[1])
    if category == "weather" and not (out.get("signal") or out.get("rainfall")):
        raise ValueError("A weather advisory needs a wind signal or a rainfall warning.")
    return out


def _clean_municipalities(values: Iterable[Any] | None) -> list[str] | None:
    out: list[str] = []
    for v in values or []:
        town = canon_town(v)
        if town is None:
            raise ValueError(f"Unknown municipality: {v}. Expected one of {', '.join(MUNICIPALITIES)}.")
        if town not in out:
            out.append(town)
    return out or None


def _clean_barangays(db, ids: Iterable[Any] | None, towns: list[str] | None) -> tuple[list[dict] | None, list[str] | None]:
    """Look the picked barangays up in the reference table. Returns them as
    {id, name, municipality}, and the municipalities (derived from them when
    none were given)."""
    wanted = _str_ids(ids)
    if not wanted:
        return None, towns
    if len(wanted) > _MAX_BARANGAYS:
        raise ValueError(f"Pick at most {_MAX_BARANGAYS} barangays, or choose whole municipalities.")
    rows = db.table("barangays").select("id, name, municipality").in_("id", wanted).execute().data or []
    found = {str(r["id"]): r for r in rows}
    missing = [i for i in wanted if i not in found]
    if missing:
        raise ValueError("One of the picked barangays does not exist. Reload the page and pick again.")
    picked = [
        {"id": i, "name": found[i].get("name"), "municipality": canon_town(found[i].get("municipality")) or found[i].get("municipality")}
        for i in wanted
    ]
    if towns is None:
        towns = []
        for b in picked:
            if b["municipality"] not in towns:
                towns.append(b["municipality"])
    else:
        stray = [b["name"] for b in picked if b["municipality"] not in towns]
        if stray:
            raise ValueError(f"{', '.join(stray)} is not in the municipalities you picked.")
    return picked, towns


# ── Who an announcement reaches ──────────────────────────────────────────────

def _place(row: dict) -> tuple[set[str] | None, dict[str, set[str]]]:
    """(towns, {town: barangay ids}) in lower case. towns None = the whole province."""
    towns = row.get("target_municipalities") or None
    if not towns:
        return None, {}
    per: dict[str, set[str]] = {}
    for b in row.get("target_barangays") or []:
        if isinstance(b, dict) and b.get("id"):
            per.setdefault(str(b.get("municipality") or "").strip().lower(), set()).add(str(b["id"]))
    return {str(t).strip().lower() for t in towns}, per


def reaches_place(row: dict, *, role: str | None, town: str | None, barangay_id: Any = None) -> bool:
    towns, per = _place(row)
    if towns is None or role == "provincial_admin":
        return True
    if role == "resident" and barangay_id is not None:
        # Their barangay was picked by name - that settles it, whatever the
        # municipality column says.
        if any(str(barangay_id) in ids for ids in per.values()):
            return True
    t = (town or "").strip().lower()
    if not t or t not in towns:
        return False
    if role != "resident":
        return True  # a station covers its whole town
    picked = per.get(t)
    # No barangays picked for this town: all of it. Barangay unknown: include.
    return not picked or barangay_id is None or str(barangay_id) in picked


def reaches_role(row: dict, *, role: str | None, agency_id: Any = None) -> bool:
    target = row.get("target_type")
    if target == "all":
        return True
    if target == "agency":
        return agency_id is not None and str(row.get("target_agency_id")) == str(agency_id)
    return target == role


def _agency_towns(db) -> dict[str, str | None]:
    rows = db.table("agencies").select("id, municipality").execute().data or []
    return {str(r["id"]): r.get("municipality") for r in rows}


def _agency_town(db, agency_id: Any) -> str | None:
    if not agency_id:
        return None
    try:
        res = db.table("agencies").select("municipality").eq("id", str(agency_id)).maybe_single().execute()
    except Exception:
        return None
    data = getattr(res, "data", None) if res is not None else None
    return data.get("municipality") if isinstance(data, dict) else None


_RECIPIENT_COLUMNS = "id, role, agency_id, municipality_address, barangay_id"


def _recipients(db, row: dict, columns: str = _RECIPIENT_COLUMNS) -> list[dict]:
    """Every account this announcement reaches: by role (or agency), then by place."""
    target = row.get("target_type")
    query = db.table("users").select(columns)
    if target == "agency":
        query = query.eq("agency_id", str(row.get("target_agency_id")))
    elif target == "all":
        query = query.in_("role", list(_ALL_ROLES))
    else:
        query = query.eq("role", target)
    users = query.execute().data or []

    towns, _ = _place(row)
    if towns is None:
        return users
    staff = any(u.get("role") in ("agency_admin", "responder") for u in users)
    agency_town = _agency_towns(db) if staff else {}

    def town_of(u: dict) -> str | None:
        if u.get("role") == "resident":
            return u.get("municipality_address")
        return agency_town.get(str(u.get("agency_id") or ""))

    return [
        u for u in users
        if reaches_place(row, role=u.get("role"), town=town_of(u), barangay_id=u.get("barangay_id"))
    ]


def _reach(recipients: list[dict]) -> dict:
    counts = {role: 0 for role in _ALL_ROLES}
    for u in recipients:
        role = u.get("role")
        if role in counts:
            counts[role] += 1
    counts["total"] = len(recipients)
    return counts


def _place_of(db, user: dict) -> tuple[str | None, Any]:
    """(town, barangay_id) of the signed-in account. The auth dependency's row
    does not carry the address, so a resident's is read once, here."""
    role = user.get("role")
    if role == "resident":
        try:
            res = (
                db.table("users").select("municipality_address, barangay_id")
                .eq("id", str(user.get("id"))).maybe_single().execute()
            )
        except Exception:
            return None, None
        data = getattr(res, "data", None) if res is not None else None
        data = data if isinstance(data, dict) else {}
        return data.get("municipality_address"), data.get("barangay_id")
    if role in ("agency_admin", "responder"):
        return _agency_town(db, user.get("agency_id")), None
    return None, None


# ── Publishing ───────────────────────────────────────────────────────────────

def _get_row(db, announcement_id: str) -> dict:
    try:
        res = db.table("announcements").select("*").eq("id", announcement_id).maybe_single().execute()
    except Exception as exc:
        if "22p02" in str(exc).lower() or "invalid input syntax" in str(exc).lower():
            raise LookupError("Announcement not found.")
        raise
    data = getattr(res, "data", None) if res is not None else None
    if not isinstance(data, dict):
        raise LookupError("Announcement not found.")
    return data


def _draft(
    db,
    actor: dict,
    *,
    title: str,
    body: str,
    category: str,
    target_type: str,
    target_agency_id: str | None,
    expires_at: str | None,
    details: dict | None,
    target_municipalities: list[str] | None,
    target_barangay_ids: list[str] | None,
    asks_response: bool,
    ends_announcement_id: str | None,
) -> dict:
    """Check everything, and return the row to insert (no id yet)."""
    if category not in CATEGORIES:
        raise ValueError(f"category must be one of: {', '.join(CATEGORIES)}")
    title = (title or "").strip()
    body = (body or "").strip()
    if not title or not body:
        raise ValueError("A title and a message are both needed.")
    if len(title) > _TITLE_MAX:
        raise ValueError(f"Keep the title under {_TITLE_MAX} characters.")
    if len(body) > _BODY_MAX:
        raise ValueError(f"Keep the message under {_BODY_MAX} characters.")

    expires = None
    if expires_at:
        when = _parse_time(expires_at)
        if when is None:
            raise ValueError("expires_at is not a date.")
        if when <= _now():
            raise ValueError("The end date is already past.")
        expires = when.isoformat()

    _assert_may_issue(category, actor)
    clean = _clean_details(category, details)

    if category == "all_clear":
        # An all clear answers ONE warning, and reaches exactly the people it
        # reached - whatever the form sent. Anything else would leave somebody
        # who was told to leave never told they can go home.
        if not ends_announcement_id:
            raise ValueError("Say which alert this all clear ends.")
        original = _get_row(db, str(ends_announcement_id))
        _assert_issuer(original, actor, "end")
        if not original.get("is_active"):
            raise ValueError("That alert has already ended.")
        if original.get("category") not in SAFETY_CATEGORIES or original.get("category") == "all_clear":
            raise ValueError("An all clear can only end a safety alert.")
        clean = {
            **clean,
            "ends_title": original.get("title"),
            "ends_category": original.get("category"),
        }
        return {
            "title": title, "body": body, "category": category,
            "target_type": original.get("target_type"),
            "target_agency_id": original.get("target_agency_id"),
            "target_municipalities": original.get("target_municipalities"),
            "target_barangays": original.get("target_barangays"),
            "asks_response": False,
            "details": clean,
            "ends_announcement_id": str(original["id"]),
            "created_by": actor.get("id"),
            "issuer_agency_type": actor.get("agency_type"),
            "expires_at": expires,
            "is_active": True,
        }
    if ends_announcement_id:
        raise ValueError("Only an all clear can end another alert.")

    if target_type == "agency" and not target_agency_id:
        raise ValueError("target_agency_id is required when target_type is 'agency'.")
    towns = _clean_municipalities(target_municipalities)
    barangays, towns = _clean_barangays(db, target_barangay_ids, towns)

    if asks_response:
        if category not in RESPONSE_CATEGORIES:
            raise ValueError(f"Only these can ask residents to answer: {', '.join(sorted(RESPONSE_CATEGORIES))}.")
        if target_type not in ("all", "resident"):
            raise ValueError("Only residents answer. Send it to residents (or everyone) to ask for answers.")

    return {
        "title": title, "body": body, "category": category,
        "target_type": target_type,
        "target_agency_id": target_agency_id if target_type == "agency" else None,
        "target_municipalities": towns,
        "target_barangays": barangays,
        "asks_response": bool(asks_response),
        "details": clean,
        "ends_announcement_id": None,
        "created_by": actor.get("id"),
        "issuer_agency_type": actor.get("agency_type"),
        "expires_at": expires,
        "is_active": True,
    }


def _uses_new_fields(draft: dict) -> bool:
    return bool(
        draft["category"] not in LEGACY_CATEGORIES
        or draft.get("details")
        or draft.get("target_municipalities")
        or draft.get("target_barangays")
        or draft.get("asks_response")
        or draft.get("ends_announcement_id")
    )


_LEGACY_KEYS = ("id", "title", "body", "category", "target_type", "target_agency_id", "created_by", "expires_at", "is_active")


def _insert(db, draft: dict) -> dict:
    try:
        result = db.table("announcements").insert(draft).execute()
    except Exception as exc:
        if not _is_schema_error(exc):
            raise
        if _uses_new_fields(draft):
            raise SchemaNotReady("This announcement") from exc
        # The database predates 043, and nothing new was asked for: publish it
        # the way it always was.
        log.warning("announcement.legacy_insert", reason=str(exc)[:200])
        result = db.table("announcements").insert({k: draft.get(k) for k in _LEGACY_KEYS}).execute()
    if not result.data:
        raise RuntimeError("Failed to publish announcement.")
    return result.data[0]


def _notify_published(row: dict, recipients: list[dict]) -> None:
    category = row.get("category") or "general"
    urgent = category in URGENT_CATEGORIES
    label = LABELS.get(category, "Announcement")
    try:
        notification_service.create_for_users(
            [str(u["id"]) for u in recipients],
            type_="announcement.published",
            title=f"{label}: {row.get('title')}"[:200],
            body=(row.get("body") or "")[:200],
            link=f"/announcements?id={row.get('id')}",
            is_important=urgent,
            metadata={
                "announcement_id": str(row.get("id")),
                "category": category,
                # The announcement's own title: the notification title carries an
                # English "Evacuation order: " prefix the phone replaces with its
                # own words, and a prefix is not something to parse back out.
                "title": row.get("title"),
                "urgent": urgent,
                "asks_response": bool(row.get("asks_response")),
                "at": row.get("created_at"),
            },
        )
    except Exception:
        # The announcement is published and visible in every feed; a failed
        # fan-out must not undo it.
        log.error("announcement.notify_failed", announcement_id=row.get("id"), exc_info=True)


def preview_audience(actor: dict, **fields) -> dict:
    """How many accounts a draft would reach, by role - without publishing it."""
    db = get_supabase()
    draft = _draft(db, actor, **fields)
    recipients = [u for u in _recipients(db, draft) if str(u.get("id")) != str(actor.get("id"))]
    return _reach(recipients)


def publish(
    actor: dict,
    *,
    title: str,
    body: str,
    category: str,
    target_type: str,
    target_agency_id: str | None = None,
    expires_at: str | None = None,
    details: dict | None = None,
    target_municipalities: list[str] | None = None,
    target_barangay_ids: list[str] | None = None,
    asks_response: bool = False,
    ends_announcement_id: str | None = None,
) -> dict:
    db = get_supabase()
    draft = _draft(
        db, actor,
        title=title, body=body, category=category, target_type=target_type,
        target_agency_id=target_agency_id, expires_at=expires_at, details=details,
        target_municipalities=target_municipalities, target_barangay_ids=target_barangay_ids,
        asks_response=asks_response, ends_announcement_id=ends_announcement_id,
    )
    # The id is chosen here so the audit row, written first, can name it (#6).
    draft["id"] = str(uuid4())
    summary = {
        "category": draft["category"],
        "target_type": draft["target_type"],
        "municipalities": draft.get("target_municipalities"),
        "barangays": [b["name"] for b in draft.get("target_barangays") or []],
        "asks_response": draft.get("asks_response"),
        "ends": draft.get("ends_announcement_id"),
    }
    with audit_service.action(
        actor=actor,
        action="announcement.published",
        target_type="announcement",
        target_id=draft["id"],
        target_label=draft.get("title"),
        new=summary,
    ) as entry:
        row = _insert(db, draft)

        if draft.get("ends_announcement_id"):
            db.table("announcements").update({
                "is_active": False,
                "ended_at": _now().isoformat(),
                "ended_by_announcement_id": str(row["id"]),
            }).eq("id", draft["ends_announcement_id"]).execute()

        # Who it reaches is worked out from what was STORED, so the fan-out and
        # the feeds can never disagree about the audience.
        stored = {**draft, **row}
        recipients = [u for u in _recipients(db, stored) if str(u.get("id")) != str(actor.get("id"))]
        _notify_published(stored, recipients)
        reach = _reach(recipients)
        entry.new = {**summary, "reach": reach}

    return {**stored, "reach": reach}


# ── Reading ──────────────────────────────────────────────────────────────────

def _attach_my_responses(db, rows: list[dict], user_id: str) -> None:
    ids = [str(r["id"]) for r in rows if r.get("asks_response")]
    if not ids:
        return
    try:
        answers = (
            db.table("announcement_responses")
            .select("announcement_id, status, note, responded_at, handled_at")
            .eq("user_id", str(user_id)).in_("announcement_id", ids).execute().data or []
        )
    except Exception:
        return
    mine = {str(a["announcement_id"]): a for a in answers}
    for r in rows:
        if r.get("asks_response"):
            r["my_response"] = mine.get(str(r["id"]))


def _attach_counts(db, rows: list[dict], town: str | None = None) -> None:
    """How many answered safe / need help, on each alert that asks. For a
    station, only the residents of its own town are counted."""
    ids = [str(r["id"]) for r in rows if r.get("asks_response")]
    if not ids:
        return
    try:
        answers = (
            db.table("announcement_responses")
            .select("announcement_id, user_id, status, handled_at")
            .in_("announcement_id", ids).execute().data or []
        )
    except Exception:
        return
    if town:
        people = _str_ids(a.get("user_id") for a in answers)
        home = {}
        if people:
            home = {
                str(u["id"]): u.get("municipality_address")
                for u in db.table("users").select("id, municipality_address").in_("id", people).execute().data or []
            }
        answers = [a for a in answers if (home.get(str(a.get("user_id"))) or "").strip().lower() == town.lower()]
    counts: dict[str, dict[str, int]] = {}
    for a in answers:
        c = counts.setdefault(str(a["announcement_id"]), {"safe": 0, "need_help": 0, "need_help_open": 0})
        if a.get("status") == "safe":
            c["safe"] += 1
        elif a.get("status") == "need_help":
            c["need_help"] += 1
            if not a.get("handled_at"):
                c["need_help_open"] += 1
    for r in rows:
        if r.get("asks_response"):
            c = counts.get(str(r["id"]), {"safe": 0, "need_help": 0, "need_help_open": 0})
            # How many were asked - so a card can say "44 of 57 answered", and
            # the ones who have not are a number, not a guess.
            c["audience"] = _resident_audience(db, r, town)
            r["response_counts"] = c


def _resident_audience(db, row: dict, town: str | None) -> int | None:
    try:
        people = _recipients(db, row)
    except Exception:
        return None
    t = (town or "").strip().lower()
    return sum(
        1 for u in people
        if u.get("role") == "resident" and (not t or (u.get("municipality_address") or "").strip().lower() == t)
    )


def list_for_user(user: dict) -> list[dict]:
    """
    What a resident, responder or Provincial Admin (mine_only) should see:
    active, not expired, aimed at their role (or agency), and at their place.
    A resident also gets their own answer on each alert that asks for one.

    (Expired announcements used to be returned: the docstring said "not
    expired" but nothing checked expires_at.)
    """
    db = get_supabase()
    now = _now()
    rows = (
        db.table("announcements").select("*")
        .eq("is_active", True).order("created_at", desc=True).execute().data or []
    )
    role = user.get("role")
    agency_id = str(user.get("agency_id")) if user.get("agency_id") else None

    place: tuple[str | None, Any] | None = None
    out = []
    for r in rows:
        if _expired(r, now) or not reaches_role(r, role=role, agency_id=agency_id):
            continue
        if _place(r)[0] is not None:
            if place is None:
                place = _place_of(db, user)
            if not reaches_place(r, role=role, town=place[0], barangay_id=place[1]):
                continue
        out.append(r)
    if role == "resident":
        _attach_my_responses(db, out, str(user.get("id")))
    return out


_RECENTLY_ENDED_DAYS = 7


def _visible_to_station(row: dict, *, agency_id: str | None, town: str | None) -> bool:
    if row.get("target_type") == "agency":
        return agency_id is not None and str(row.get("target_agency_id")) == agency_id
    towns, _ = _place(row)
    return towns is None or (town or "").strip().lower() in towns


def list_for_station(user: dict) -> list[dict]:
    """
    An Agency Admin's view: everything announced to their town - not only what
    was addressed to agency admins. An evacuation order sent to the residents of
    Naval is the Naval stations' business: they are the ones who go and get the
    people who answer "I need help". `for_you` marks what was addressed to them.

    Alerts that ended in the last week stay listed (marked ended), so a station
    can still work through the answers after the all clear.
    """
    db = get_supabase()
    now = _now()
    agency_id = str(user.get("agency_id")) if user.get("agency_id") else None
    town = _agency_town(db, agency_id)
    rows = db.table("announcements").select("*").order("created_at", desc=True).limit(200).execute().data or []
    out = []
    for r in rows:
        if not _visible_to_station(r, agency_id=agency_id, town=town):
            continue
        if r.get("is_active") and not _expired(r, now):
            pass
        else:
            ended = _parse_time(r.get("ended_at")) or _parse_time(r.get("expires_at"))
            if ended is None or (now - ended).days >= _RECENTLY_ENDED_DAYS:
                continue
        r["for_you"] = reaches_role(r, role="agency_admin", agency_id=agency_id)
        out.append(r)
    _attach_counts(db, out, town=town)
    return out


def list_all(include_inactive: bool = True) -> list[dict]:
    """Provincial Admin's own management list — every announcement, active or not."""
    db = get_supabase()
    query = db.table("announcements").select("*").order("created_at", desc=True)
    if not include_inactive:
        query = query.eq("is_active", True)
    rows = query.execute().data or []
    _attach_counts(db, rows)
    return rows


def get_one(announcement_id: str, user: dict) -> dict:
    """One announcement, for whoever it reached - still readable after it ended,
    so a notification opened late can say "this has ended" instead of failing.
    Not found and not yours are the same 404."""
    db = get_supabase()
    row = _get_row(db, announcement_id)
    role = user.get("role")
    agency_id = str(user.get("agency_id")) if user.get("agency_id") else None
    if role == "agency_admin":
        if not _visible_to_station(row, agency_id=agency_id, town=_agency_town(db, agency_id)):
            raise LookupError("Announcement not found.")
    elif role != "provincial_admin":
        town, barangay_id = _place_of(db, user)
        if not (reaches_role(row, role=role, agency_id=agency_id)
                and reaches_place(row, role=role, town=town, barangay_id=barangay_id)):
            raise LookupError("Announcement not found.")
    row["is_open"] = bool(row.get("is_active")) and not _expired(row, _now())
    if row.get("ended_by_announcement_id"):
        try:
            row["ended_by"] = _get_row(db, str(row["ended_by_announcement_id"]))
        except LookupError:
            row["ended_by"] = None
    if role == "resident":
        _attach_my_responses(db, [row], str(user.get("id")))
    return row


# ── Answers ──────────────────────────────────────────────────────────────────

def respond(
    announcement_id: str,
    user: dict,
    *,
    status: str,
    note: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
) -> dict:
    """A resident answers a safety alert: "safe" or "need_help". Answering again
    replaces the answer. A fresh "need help" tells the stations of their town
    and whoever issued the alert, at once."""
    if user.get("role") != "resident":
        raise PermissionError("Only residents answer safety alerts.")
    if status not in RESPONSE_STATUSES:
        raise ValueError(f"status must be one of: {', '.join(RESPONSE_STATUSES)}")
    note = (note or "").strip()[:_NOTE_MAX] or None
    if (latitude is None) != (longitude is None):
        raise ValueError("Send both latitude and longitude, or neither.")
    if latitude is not None and not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise ValueError("That location is not on the map.")

    db = get_supabase()
    row = _get_row(db, announcement_id)
    user_id = str(user.get("id"))
    town, barangay_id = _place_of(db, user)
    if not (reaches_role(row, role="resident") and reaches_place(row, role="resident", town=town, barangay_id=barangay_id)):
        raise LookupError("Announcement not found.")
    if not row.get("asks_response"):
        raise ValueError("This announcement does not ask for an answer.")
    if not row.get("is_active") or _expired(row, _now()):
        raise AlertClosed("This alert has ended. If you still need help, call a hotline.")

    now = _now().isoformat()
    try:
        existing = (
            db.table("announcement_responses").select("*")
            .eq("announcement_id", announcement_id).eq("user_id", user_id)
            .maybe_single().execute()
        )
    except Exception as exc:
        if _is_schema_error(exc):
            raise SchemaNotReady("Answering an alert") from exc
        raise
    before = getattr(existing, "data", None) if existing is not None else None
    before = before if isinstance(before, dict) else None

    fields: dict[str, Any] = {
        "status": status, "note": note, "latitude": latitude, "longitude": longitude, "responded_at": now,
    }
    if before is None or before.get("status") != status:
        fields["handled_at"] = None
        fields["handled_by"] = None
    if before is None:
        saved = db.table("announcement_responses").insert(
            {"announcement_id": announcement_id, "user_id": user_id, **fields}
        ).execute().data
    else:
        saved = (
            db.table("announcement_responses").update(fields)
            .eq("announcement_id", announcement_id).eq("user_id", user_id).execute().data
        )
    answer = (saved or [{}])[0] or {"announcement_id": announcement_id, "user_id": user_id, **fields}

    fresh_call = status == "need_help" and (
        before is None or before.get("status") != "need_help" or (note and note != before.get("note"))
    )
    if fresh_call:
        _alert_help(db, row, user_id, town=town, note=note)
    return answer


def _alert_help(db, row: dict, resident_id: str, *, town: str | None, note: str | None) -> None:
    """Tell the stations of the resident's town, and whoever issued the alert,
    that this person needs help. Never raises: the answer is saved either way,
    and it is listed on the dashboard."""
    try:
        person = (
            db.table("users").select("full_name, phone_number, barangay_id")
            .eq("id", resident_id).maybe_single().execute()
        )
        person = person.data if person is not None and isinstance(person.data, dict) else {}
        barangay = _barangay_name(db, person.get("barangay_id"))

        recipients: list[str] = []
        home = canon_town(town)
        if home:
            agencies = db.table("agencies").select("id").eq("municipality", home).execute().data or []
            agency_ids = _str_ids(a.get("id") for a in agencies)
            if agency_ids:
                admins = (
                    db.table("users").select("id").eq("role", "agency_admin")
                    .in_("agency_id", agency_ids).execute().data or []
                )
                recipients = _str_ids(a.get("id") for a in admins)
        if row.get("created_by") and str(row["created_by"]) not in recipients:
            recipients.append(str(row["created_by"]))

        where = ", ".join(p for p in (f"Brgy. {barangay}" if barangay else None, home) if p)
        name = person.get("full_name") or "A resident"
        body = f"{row.get('title')}" + (f" · {where}" if where else "") + (f" — “{note}”" if note else "")
        notification_service.create_for_users(
            recipients,
            type_="announcement.help_requested",
            title=f"Needs help: {name}"[:200],
            body=body[:240],
            link=f"/announcements?responses={row.get('id')}",
            is_important=True,
            metadata={"announcement_id": str(row.get("id")), "user_id": resident_id},
        )
    except Exception:
        log.error("announcement.help_alert_failed", announcement_id=row.get("id"), exc_info=True)


def _barangay_name(db, barangay_id: Any) -> str | None:
    if not barangay_id:
        return None
    try:
        res = db.table("barangays").select("name").eq("id", str(barangay_id)).maybe_single().execute()
    except Exception:
        return None
    data = getattr(res, "data", None) if res is not None else None
    return data.get("name") if isinstance(data, dict) else None


_PEOPLE_COLUMNS = "id, role, agency_id, full_name, phone_number, municipality_address, barangay_id, barangay"

_ORDER = {"need_help": 0, "no_answer": 1, "safe": 2}


def responses(announcement_id: str, actor: dict) -> dict:
    """
    The answer board for one alert: who needs help (open first, longest
    waiting on top), who has not answered, who is safe. A Provincial Admin sees
    the whole audience; an Agency Admin sees the residents of their own town.
    """
    role = actor.get("role")
    if role not in ("provincial_admin", "agency_admin"):
        raise PermissionError("Only administrators see the answers.")
    db = get_supabase()
    row = _get_row(db, announcement_id)
    town: str | None = None
    if role == "agency_admin":
        agency_id = str(actor.get("agency_id")) if actor.get("agency_id") else None
        town = _agency_town(db, agency_id)
        if not _visible_to_station(row, agency_id=agency_id, town=town):
            raise LookupError("Announcement not found.")
    if not row.get("asks_response"):
        raise ValueError("This announcement did not ask residents to answer.")

    def in_scope(u: dict) -> bool:
        return town is None or (u.get("municipality_address") or "").strip().lower() == (town or "").lower()

    audience = [u for u in _recipients(db, row, _PEOPLE_COLUMNS) if u.get("role") == "resident" and in_scope(u)]
    try:
        answers = (
            db.table("announcement_responses").select("*")
            .eq("announcement_id", announcement_id).execute().data or []
        )
    except Exception as exc:
        if _is_schema_error(exc):
            raise SchemaNotReady("The answer board") from exc
        raise
    by_user = {str(a["user_id"]): a for a in answers}

    # Someone who answered and has since moved out of the audience is still
    # listed: their "I need help" does not stop mattering.
    known = {str(u["id"]) for u in audience}
    extra = [uid for uid in by_user if uid not in known]
    if extra:
        more = db.table("users").select(_PEOPLE_COLUMNS).in_("id", extra).execute().data or []
        audience += [u for u in more if in_scope(u)]

    names = {}
    brgy_ids = _str_ids(u.get("barangay_id") for u in audience)
    if brgy_ids:
        names = {
            str(b["id"]): b.get("name")
            for b in db.table("barangays").select("id, name").in_("id", brgy_ids).execute().data or []
        }
    handlers = _str_ids(a.get("handled_by") for a in answers)
    handler_names = {}
    if handlers:
        handler_names = {
            str(u["id"]): u.get("full_name")
            for u in db.table("users").select("id, full_name").in_("id", handlers).execute().data or []
        }

    items = []
    for u in audience:
        a = by_user.get(str(u["id"]))
        items.append({
            "user_id": str(u["id"]),
            "full_name": u.get("full_name"),
            "phone_number": u.get("phone_number"),
            "barangay": names.get(str(u.get("barangay_id"))) or u.get("barangay"),
            "municipality": u.get("municipality_address"),
            "status": a.get("status") if a else "no_answer",
            "note": a.get("note") if a else None,
            "latitude": a.get("latitude") if a else None,
            "longitude": a.get("longitude") if a else None,
            "responded_at": a.get("responded_at") if a else None,
            "handled_at": a.get("handled_at") if a else None,
            "handled_by_name": handler_names.get(str(a.get("handled_by"))) if a and a.get("handled_by") else None,
        })

    def key(i: dict):
        open_first = 0 if (i["status"] == "need_help" and not i["handled_at"]) else 1
        when = i["responded_at"] or ""
        # Longest-waiting call on top; safe answers newest first.
        return (_ORDER[i["status"]], open_first, when if i["status"] == "need_help" else "", (i["full_name"] or "").lower())

    items.sort(key=key)
    tally = {
        "audience": len(items),
        "safe": sum(1 for i in items if i["status"] == "safe"),
        "need_help": sum(1 for i in items if i["status"] == "need_help"),
        "need_help_open": sum(1 for i in items if i["status"] == "need_help" and not i["handled_at"]),
        "no_answer": sum(1 for i in items if i["status"] == "no_answer"),
    }
    return {
        "announcement": {k: row.get(k) for k in (
            "id", "title", "category", "created_at", "is_active", "target_municipalities", "target_barangays",
        )},
        "scope": town or "province",
        "tally": tally,
        "items": items,
    }


def mark_reached(announcement_id: str, resident_id: str, actor: dict, *, reached: bool = True) -> dict:
    """A station has reached someone who asked for help (or takes that back).
    The resident is told their call was received, so they are not left
    wondering whether anyone saw it."""
    role = actor.get("role")
    if role not in ("provincial_admin", "agency_admin"):
        raise PermissionError("Only administrators mark help as reached.")
    db = get_supabase()
    row = _get_row(db, announcement_id)
    try:
        res = (
            db.table("announcement_responses").select("*")
            .eq("announcement_id", announcement_id).eq("user_id", resident_id)
            .maybe_single().execute()
        )
    except Exception as exc:
        if _is_schema_error(exc):
            raise SchemaNotReady("The answer board") from exc
        raise
    answer = getattr(res, "data", None) if res is not None else None
    if not isinstance(answer, dict) or answer.get("status") != "need_help":
        raise LookupError("This resident has not asked for help on this alert.")

    agency_name = None
    if role == "agency_admin":
        agency_id = str(actor.get("agency_id")) if actor.get("agency_id") else None
        town = _agency_town(db, agency_id)
        home = (
            db.table("users").select("municipality_address").eq("id", resident_id).maybe_single().execute()
        )
        home_town = (home.data or {}).get("municipality_address") if home is not None and isinstance(home.data, dict) else None
        if (home_town or "").strip().lower() != (town or "").strip().lower():
            raise PermissionError("This resident is outside your municipality.")
        try:
            ag = db.table("agencies").select("name").eq("id", agency_id).maybe_single().execute()
            agency_name = ag.data.get("name") if ag is not None and isinstance(ag.data, dict) else None
        except Exception:
            agency_name = None

    now = _now().isoformat()
    fields = {"handled_at": now if reached else None, "handled_by": actor.get("id") if reached else None}
    with audit_service.action(
        actor=actor,
        action="announcement.help_reached" if reached else "announcement.help_reopened",
        target_type="announcement",
        target_id=str(announcement_id),
        target_label=row.get("title"),
        new={"resident_id": resident_id},
    ):
        db.table("announcement_responses").update(fields).eq("announcement_id", announcement_id).eq("user_id", resident_id).execute()

    if reached:
        by = agency_name or (provincial_office_name(actor.get("agency_type")) if actor.get("agency_type") else "The station")
        try:
            notification_service.create_for_user(
                resident_id,
                type_="announcement.help_acknowledged",
                title="Your call for help was received",
                body=f"{by} has your request and is responding. Stay where it is safe; call a hotline if it gets worse.",
                link=f"/announcements?id={announcement_id}",
                is_important=True,
                metadata={
                    "announcement_id": str(announcement_id),
                    "category": row.get("category"),
                    "title": row.get("title"),
                    "station": by,
                    "at": now,
                },
            )
        except Exception:
            log.error("announcement.ack_notify_failed", announcement_id=announcement_id, exc_info=True)
    return {**answer, **fields}


# ── Ending ───────────────────────────────────────────────────────────────────

def deactivate(announcement_id: str, actor: dict) -> dict:
    db = get_supabase()
    check = db.table("announcements").select("*").eq("id", announcement_id).single().execute()
    if not check.data:
        raise ValueError("Announcement not found.")
    _assert_issuer(check.data, actor, "take down")

    with audit_service.action(
        actor=actor,
        action="announcement.deactivated",
        target_type="announcement",
        target_id=announcement_id,
        target_label=check.data.get("title"),
    ):
        result = (
            db.table("announcements")
            .update({"is_active": False})
            .eq("id", announcement_id)
            .execute()
        )
        if not result.data:
            raise RuntimeError("Failed to deactivate announcement.")

    return result.data[0]
