"""
assist_request_service — cross-agency "please help on this incident"
requests: agency_admin to agency_admin, one incident at a time.

The receiving agency never gets access to the incident row itself — every
function here returns a narrow, live-projected snapshot (category, severity,
location text), never the full incidents row. See
docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
"""

from datetime import datetime, timezone

from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase
from app.services.notification_service import create_for_agency_role

_INCIDENT_COLS = "id, assigned_agency_id, status, incident_category, severity, location_address"


def _assert_owns_incident(db: Client, incident_id: str, actor: dict) -> dict:
    """
    Only the agency currently assigned to an incident may request assist on
    it — reuses the same assert_agency_scope every other incident-scoped
    write in this codebase uses. agency_admin only (this feature has no
    responder/resident branch — see the design spec's platform-scope call).
    """
    result = (
        db.table("incidents")
        .select(_INCIDENT_COLS)
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")
    incident = result.data
    assert_agency_scope(actor, str(incident.get("assigned_agency_id") or ""))
    return incident


def list_candidate_agencies(incident_id: str, actor: dict) -> list[dict]:
    """Other active agencies in the SAME municipality as this incident's own
    agency — never every agency platform-wide, so a request can't be aimed
    at a station nowhere near the incident."""
    db: Client = get_supabase()
    incident = _assert_owns_incident(db, incident_id, actor)

    own = (
        db.table("agencies")
        .select("id, municipality")
        .eq("id", incident["assigned_agency_id"])
        .maybe_single()
        .execute()
    )
    if own is None or not own.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="This incident's agency could not be found.")

    result = (
        db.table("agencies")
        .select("id, name, agency_type, contact_number, email")
        .eq("municipality", own.data["municipality"])
        .eq("is_active", True)
        .neq("id", incident["assigned_agency_id"])
        .execute()
    )
    return result.data or []


def _hydrate_request(db: Client, row: dict, actor: dict, requested_agency: dict | None = None) -> dict:
    """
    Attach display fields a raw incident_assist_requests row doesn't carry:
    both agencies' names, a narrow incident snapshot (never the full
    incidents row — see this module's docstring), and can_respond, computed
    here rather than left for the frontend because the dashboard's own
    session storage has no agency id to compare against client-side (see
    lib/hooks/useAuth.ts) — the server is the only place that knows it.
    """
    agencies: dict[str, dict] = {requested_agency["id"]: requested_agency} if requested_agency else {}
    missing = {row["requesting_agency_id"], row["requested_agency_id"]} - agencies.keys()
    if missing:
        fetched = db.table("agencies").select("id, name").in_("id", list(missing)).execute()
        agencies.update({a["id"]: a for a in (fetched.data or [])})

    incident = (
        db.table("incidents")
        .select("incident_category, severity, location_address, status")
        .eq("id", row["incident_id"])
        .maybe_single()
        .execute()
    )
    inc = incident.data if incident and incident.data else {}
    my_agency_id = str(actor.get("agency_id") or "")

    return {
        **row,
        "requesting_agency_name": agencies.get(row["requesting_agency_id"], {}).get("name"),
        "requested_agency_name": agencies.get(row["requested_agency_id"], {}).get("name"),
        "incident_category": inc.get("incident_category"),
        "severity": inc.get("severity"),
        "location_address": inc.get("location_address"),
        "incident_status": inc.get("status"),
        "can_respond": my_agency_id == row["requested_agency_id"] and row["status"] == "pending",
    }


def create_request(
    incident_id: str,
    requested_agency_id: str,
    message: str,
    overlap_flag: str | None,
    actor: dict,
) -> dict:
    if not message or not message.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="An opening message is required.")

    db: Client = get_supabase()
    incident = _assert_owns_incident(db, incident_id, actor)
    requesting_agency_id = incident["assigned_agency_id"]

    if requested_agency_id == requesting_agency_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot request assist from your own agency.")

    target = (
        db.table("agencies")
        .select("id, name, agency_type, municipality, is_active")
        .eq("id", requested_agency_id)
        .maybe_single()
        .execute()
    )
    if target is None or not target.data or not target.data["is_active"]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="That agency is not available to request assist from.")

    dup = (
        db.table("incident_assist_requests")
        .select("id")
        .eq("incident_id", incident_id)
        .eq("requested_agency_id", requested_agency_id)
        .eq("status", "pending")
        .execute()
    )
    if dup.data:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A pending request to this agency already exists for this incident.")

    inserted = (
        db.table("incident_assist_requests")
        .insert({
            "incident_id": incident_id,
            "requesting_agency_id": requesting_agency_id,
            "requested_agency_id": requested_agency_id,
            "overlap_flag": overlap_flag,
            "requested_by": str(actor["id"]),
        })
        .execute()
    )
    request_row = inserted.data[0]

    db.table("incident_assist_messages").insert({
        "request_id": request_row["id"],
        "sender_agency_id": requesting_agency_id,
        "sender_id": str(actor["id"]),
        "body": message.strip(),
    }).execute()

    create_for_agency_role(
        requested_agency_id, "agency_admin",
        type_="assist_request",
        title=f"Assist requested by {actor.get('full_name') or 'another agency'}",
        body=message.strip(),
        link=f"/geographic?tab=agencies&assist={request_row['id']}",
        is_important=True,
    )

    return _hydrate_request(db, request_row, actor, target.data)


def list_for_agency(actor: dict, scope: str | None) -> list[dict]:
    """
    scope='sent' -> requests my agency raised. scope='received' -> requests
    asking my agency for help. Ignored for provincial_admin, who has no
    single agency_id of their own (migration 034) and instead sees every
    request touching either side, scoped to their own agency_type — the
    same oversight shape incidents/dispatch_log already give that role
    (see migration 037).
    """
    db: Client = get_supabase()

    if actor.get("role") == "provincial_admin":
        agency_ids = [
            a["id"] for a in (
                db.table("agencies").select("id").eq("agency_type", actor.get("agency_type")).execute().data or []
            )
        ]
        if not agency_ids:
            return []
        ids_csv = ",".join(agency_ids)
        result = (
            db.table("incident_assist_requests")
            .select("*")
            .or_(f"requesting_agency_id.in.({ids_csv}),requested_agency_id.in.({ids_csv})")
            .order("created_at", desc=True)
            .execute()
        )
        my_agency_id = ""  # never matches a real agency id -> can_respond always False, correct for a read-only overseer
    else:
        if scope not in ("sent", "received"):
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="scope must be 'sent' or 'received'.")
        my_agency_id = str(actor.get("agency_id") or "")
        column = "requesting_agency_id" if scope == "sent" else "requested_agency_id"
        result = (
            db.table("incident_assist_requests")
            .select("*")
            .eq(column, my_agency_id)
            .order("created_at", desc=True)
            .execute()
        )

    rows = result.data or []
    if not rows:
        return []

    agency_ids = {r["requesting_agency_id"] for r in rows} | {r["requested_agency_id"] for r in rows}
    incident_ids = {r["incident_id"] for r in rows}
    agencies = {a["id"]: a for a in (db.table("agencies").select("id, name").in_("id", list(agency_ids)).execute().data or [])}
    incidents = {
        i["id"]: i for i in (
            db.table("incidents")
            .select("id, incident_category, severity, location_address, status")
            .in_("id", list(incident_ids))
            .execute().data or []
        )
    }

    return [
        {
            **r,
            "requesting_agency_name": agencies.get(r["requesting_agency_id"], {}).get("name"),
            "requested_agency_name": agencies.get(r["requested_agency_id"], {}).get("name"),
            "incident_category": incidents.get(r["incident_id"], {}).get("incident_category"),
            "severity": incidents.get(r["incident_id"], {}).get("severity"),
            "location_address": incidents.get(r["incident_id"], {}).get("location_address"),
            "incident_status": incidents.get(r["incident_id"], {}).get("status"),
            "can_respond": my_agency_id == r["requested_agency_id"] and r["status"] == "pending",
        }
        for r in rows
    ]


def _load_request_as_party(db: Client, request_id: str, actor: dict) -> dict:
    result = db.table("incident_assist_requests").select("*").eq("id", request_id).maybe_single().execute()
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Assist request not found.")
    row = result.data
    my_agency_id = str(actor.get("agency_id") or "")
    if actor.get("role") != "agency_admin" or my_agency_id not in (row["requesting_agency_id"], row["requested_agency_id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not a party to this assist request.")
    return row


def _load_request_for_read(db: Client, request_id: str, actor: dict) -> dict:
    """
    Like _load_request_as_party, but also admits a provincial_admin whose
    agency_type matches either side — read-only oversight, same scope as
    list_for_agency's provincial_admin branch. Used by get_thread only;
    post_message/set_status keep the stricter agency_admin-only party
    check, since neither action is open to provincial_admin (see the
    design spec's Global Constraints and migration 037's header).
    """
    result = db.table("incident_assist_requests").select("*").eq("id", request_id).maybe_single().execute()
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Assist request not found.")
    row = result.data

    if actor.get("role") == "agency_admin":
        my_agency_id = str(actor.get("agency_id") or "")
        if my_agency_id in (row["requesting_agency_id"], row["requested_agency_id"]):
            return row
    elif actor.get("role") == "provincial_admin":
        agencies = (
            db.table("agencies")
            .select("id, agency_type")
            .in_("id", [row["requesting_agency_id"], row["requested_agency_id"]])
            .execute()
        )
        types = {a["id"]: a["agency_type"] for a in (agencies.data or [])}
        my_type = actor.get("agency_type")
        if my_type in (types.get(row["requesting_agency_id"]), types.get(row["requested_agency_id"])):
            return row

    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not a party to this assist request.")


def get_thread(request_id: str, actor: dict) -> dict:
    db: Client = get_supabase()
    request_row = _load_request_for_read(db, request_id, actor)
    my_agency_id = str(actor.get("agency_id") or "")

    messages = (
        db.table("incident_assist_messages")
        .select("id, request_id, sender_agency_id, sender_id, body, created_at, users(full_name)")
        .eq("request_id", request_id)
        .order("created_at", desc=False)
        .execute()
    )
    flattened = [
        {
            **{k: v for k, v in m.items() if k != "users"},
            "sender_name": (m.get("users") or {}).get("full_name"),
            "mine": m["sender_agency_id"] == my_agency_id,
        }
        for m in (messages.data or [])
    ]
    return {"request": _hydrate_request(db, request_row, actor), "messages": flattened}


def post_message(request_id: str, body: str, actor: dict) -> dict:
    if not body or not body.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Message cannot be empty.")

    db: Client = get_supabase()
    request_row = _load_request_as_party(db, request_id, actor)

    incident = db.table("incidents").select("status").eq("id", request_row["incident_id"]).maybe_single().execute()
    if incident and incident.data and incident.data.get("status") in ("resolved", "cancelled"):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This incident is closed; the thread is read-only.")

    my_agency_id = str(actor.get("agency_id") or "")
    inserted = db.table("incident_assist_messages").insert({
        "request_id": request_id,
        "sender_agency_id": my_agency_id,
        "sender_id": str(actor["id"]),
        "body": body.strip(),
    }).execute()
    row = inserted.data[0]

    # No notification here — only the OPENING message notifies (see
    # create_request). A bell entry per reply would spam the feed during an
    # active exchange; an open thread panel's own polling is how replies
    # are seen, same as any chat you have open.
    return {**row, "sender_name": actor.get("full_name"), "mine": True}


def set_status(request_id: str, new_status: str, actor: dict) -> dict:
    if new_status not in ("acknowledged", "declined"):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="status must be 'acknowledged' or 'declined'.")

    db: Client = get_supabase()
    request_row = _load_request_as_party(db, request_id, actor)

    my_agency_id = str(actor.get("agency_id") or "")
    if my_agency_id != request_row["requested_agency_id"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the requested agency can respond to this request.")
    if request_row["status"] != "pending":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"This request was already {request_row['status']}.")

    updated = (
        db.table("incident_assist_requests")
        .update({
            "status": new_status,
            "responded_by": str(actor["id"]),
            "responded_at": datetime.now(timezone.utc).isoformat(),
        })
        .eq("id", request_id)
        .execute()
    )
    row = updated.data[0]

    create_for_agency_role(
        row["requesting_agency_id"], "agency_admin",
        type_="assist_response",
        title=f"Assist request {new_status}",
        body=f"Your request was {new_status} by {actor.get('full_name') or 'the other agency'}.",
        link=f"/geographic?tab=agencies&assist={row['id']}",
        is_important=True,
    )
    return _hydrate_request(db, row, actor)
