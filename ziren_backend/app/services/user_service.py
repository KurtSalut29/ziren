"""
User profile service — GET and PATCH /users/me.

Security principles:
- user_id always comes from the authenticated JWT, never from the request body.
- Only non-sensitive fields can be updated by the user themselves.
- Role, approval_status, agency_id, badge_id are never touched here.
"""

from datetime import datetime, timezone

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.db.supabase_client import get_supabase
from app.models.user import UserProfile, UpdateProfileRequest
from app.services import audit_service

log = structlog.get_logger()

# All fields the user is allowed to read from their own profile row.
# agencies(agency_type) joins the agencies table so the dashboard can use
# the agency_type string (BFP/PNP/MDRRMO) directly without a second query.
# Every column here must also be declared on UserProfile, and -- the part that
# bites -- every column DECLARED on UserProfile must appear here. A field with
# a default that is never selected does not fail; it silently returns the
# default. verification_level did exactly that: declared as `int = 0`, never
# fetched, so the API reported every account as unverified no matter what an
# admin had set.
_PROFILE_SELECT = (
    "id, email, full_name, role, approval_status, agency_id, badge_id, "
    "is_verified, created_at, phone_number, barangay, barangay_id, "
    "municipality_address, purok_sitio, street_address, "
    "preferred_language, push_notifications_enabled, "
    # Warnings on record and any suspension, so the app can say so before the
    # resident fills in a report that would be refused.
    "sos_warning_count, sos_suspended_until, "
    "emergency_contact_name, emergency_contact_number, "
    # 012 -- residency + accessibility
    "verification_level, verification_method, verified_at, "
    "valid_id_type, valid_id_number, "
    "is_pwd, pwd_id_number, disability_types, accessibility_notes, "
    "preferred_contact_mode, "
    # 033 -- avatar_path is a storage key, never selected out raw to the
    # client; get_my_profile/update_my_profile exchange it for a signed
    # avatar_url before the row leaves this module. Migration 033 confirmed
    # applied 2026-09-13 (avatar_path updates are landing cleanly in the
    # logs), so this is back in the select.
    "avatar_path, "
    # 020 -- structured identity, consent, verification evidence
    "first_name, middle_name, last_name, name_suffix, date_of_birth, sex, "
    "terms_accepted_at, terms_version, privacy_version, consent_locale, "
    "residency_proof_type, liveness_method, "
    "rank_or_position, unit_assignment, date_joined, "
    # name and municipality alongside agency_type. A responder's profile
    # showed "a0000001-0000-0000-0000-000000000001" where their station
    # belongs, because agency_id was all this select carried and a crew
    # member cannot verify a UUID is theirs.
    #
    # Widened HERE rather than added as a second agencies(...) embed:
    # PostgREST refuses two embeds of one table in a single select with
    # 42712 'table name "users_agencies_1" specified more than once',
    # and maybe_single() reports that as a bare 204 "Missing response"
    # with the real cause nowhere in it.
    "agencies(agency_type, name, municipality, contact_number), "
    "barangays(name, municipality)"
)

# Fields the user is allowed to update.
# Anything NOT in this set must never appear in an update payload.
_ALLOWED_UPDATE_FIELDS = frozenset({
    "full_name",
    "phone_number",
    # Both, deliberately. barangay_id is the real one -- an FK into the
    # reference table, which is what dispatch routes on. barangay is the
    # free-text column it replaced in migration 012, still writable so that
    # pre-012 accounts can correct their address until they are migrated onto
    # the FK. New writes should always use barangay_id.
    "barangay",
    "barangay_id",
    "municipality_address",
    "preferred_language",
    "push_notifications_enabled",
    "emergency_contact_name",
    "emergency_contact_number",
    "avatar_path",
})


def get_my_profile(user_id: str) -> UserProfile:
    """Fetch the full profile row for the authenticated user."""
    db: Client = get_supabase()

    # maybe_single, NOT single, and the difference is the whole bug below it.
    #
    # PostgREST's `single` asks the database to coerce the result to one JSON
    # object, and with zero rows that is an ERROR, not an empty result:
    #
    #   PGRST116 -- Cannot coerce the result to a single JSON object
    #
    # supabase-py raises that as an APIError, so the 404 underneath was DEAD
    # CODE. It could never run: the exception left this function before the
    # check, FastAPI turned it into a 500, and the app rendered that as
    # "Details below may be out of date" beside a Retry button — for a profile
    # that does not exist and never will until somebody creates the row. The
    # one message that would have explained it was the one the API could not
    # send.
    #
    # This is reachable for real accounts. Every user signed up before the
    # trigger in migration 013 has an auth record and no row here, and so does
    # anyone whose row is deleted while they hold a live session.
    #
    # maybe_single returns None rather than raising on an empty result — and
    # None itself, not a response with `data = None`, so the guard checks for
    # both.
    result = (
        db.table("users")
        .select(_PROFILE_SELECT)
        .eq("id", user_id)
        .maybe_single()
        .execute()
    )

    if result is None or not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "Your account exists but has no profile yet. "
                "Please contact an administrator."
            ),
        )

    # model_validate, NOT the constructor: the flattening of the agencies
    # and barangays joins lives in UserProfile.model_validate, and calling
    # UserProfile(**data) skips it entirely -- Pydantic then discards the
    # nested join dicts as unexpected keys, without complaining. That is
    # why barangay came back null with a perfectly good barangay_id beside
    # it, and why agency_type has been null from this endpoint all along.
    return UserProfile.model_validate(_with_avatar_url(result.data))


def update_my_profile(
    user_id: str,
    request: UpdateProfileRequest,
) -> UserProfile:
    """
    Update allowed profile fields for the authenticated user.
    Builds update payload from only the fields the user explicitly provided
    (excludes fields they left as None unless they intend to clear them).
    """
    db: Client = get_supabase()

    # Build update dict: only include fields explicitly set in the request
    # model_dump(exclude_unset=True) gives us only what was in the JSON body
    raw = request.model_dump(exclude_unset=True)

    # Extra safety: strip any fields not in the allowlist
    # (guards against future model fields accidentally slipping through)
    update_payload = {k: v for k, v in raw.items() if k in _ALLOWED_UPDATE_FIELDS}

    if not update_payload:
        # Nothing to update — just return the current profile
        return get_my_profile(user_id)

    try:
        result = (
            db.table("users")
            .update(update_payload)
            .eq("id", user_id)
            .execute()
        )
    except Exception as e:
        log.error("user.profile_update_failed", user_id=user_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update profile. Please try again.",
        )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found.",
        )

    log.info("user.profile_updated", user_id=user_id, fields=list(update_payload.keys()))

    # NOT UserProfile.model_validate(result.data[0]) — postgrest-py's update()
    # builder has no .select() to attach, so an UPDATE's response is always
    # the bare row: agency_id and barangay_id come back, but the agencies(...)
    # and barangays(...) embeds that _PROFILE_SELECT asks for on a GET do not,
    # because embeds only exist as a `select=` query param and there is no
    # method on SyncFilterRequestBuilder to add one after .update().
    #
    # That silently blanked Agency, Municipality, and the agency chip the
    # instant this response replaced the cached profile client-side — every
    # self-service save (name, phone, and now avatar) hit this, but it went
    # unnoticed until the avatar upload made the round trip fast and visible
    # enough to actually be looked at right after saving. Re-fetching costs
    # one extra query and guarantees this response has the exact same shape
    # GET /users/me does.
    return get_my_profile(user_id)


def _with_avatar_url(row: dict) -> dict:
    """Exchange the raw avatar_path for a short-lived signed URL in place.

    Only get_my_profile calls this now — update_my_profile re-fetches through
    it rather than building a UserProfile from an UPDATE's own bare response
    (see the comment there for why that used to blank the agency fields).
    """
    row = dict(row)
    # An hour, not the 5-minute default used for a one-time ID check: an
    # avatar sits in an Image widget for the life of the screen, sometimes
    # much longer if the profile tab stays in memory in the IndexedStack.
    row["avatar_url"] = _signed_url("avatars", row.get("avatar_path"), expires=3600)
    return row


# ============================================================
# Resident identity verification
#
# Migration 012 added verification_level, 015 the ID scan, 020 the selfie --
# and until now nothing read any of them. Residents were uploading government
# IDs into a private bucket that no interface could open, which is the worst
# of both worlds: the privacy exposure of holding the documents, with none of
# the operational benefit of checking them.
#
# THE RULE THAT GOVERNS THIS WHOLE MODULE: verification_level is a trust
# signal shown to dispatchers. It is NEVER a permission. Nothing here may be
# reused to gate reporting.
# ============================================================

_VERIFICATION_SELECT = (
    "id, email, full_name, first_name, middle_name, last_name, name_suffix, "
    "date_of_birth, sex, phone_number, role, created_at, "
    "municipality_address, purok_sitio, street_address, "
    "verification_level, verification_method, verified_at, "
    "valid_id_type, valid_id_number, valid_id_image_path, "
    "selfie_image_path, liveness_method, liveness_asserted_at, "
    "residency_proof_type, is_pwd, pwd_id_number, "
    # 023: the pre-screen signals. Advisory, and rendered as such — see the
    # migration header. Listed here because _attach_review_flags reads
    # face_match_verdict and id_checks off the row, and anything the enrichment
    # reads has to be selected or it silently reads None.
    "face_match_score, face_match_verdict, face_match_checked_at, "
    "face_match_model, id_checks, id_number_source, "
    "sos_warning_count, "
    "barangays(name, municipality)"
)

# ── Review triage ─────────────────────────────────────────────

# How many ID numbers to load when looking for duplicates. Proportional to the
# resident population, not to anything unbounded, and only two short columns —
# but capped anyway so a province that grows past expectations degrades into
# "some duplicates not detected" rather than into a slow endpoint.
_DUP_SCAN_MAX = 5000

# When priority_only is set, how deep into the waiting list to look. The whole
# premise is that the priority set is small, so a wide scan returns few rows;
# the cap stops "show me what matters" from turning into a full table read.
_PRIORITY_SCAN_MAX = 500


def _normalise_id_number(raw: str | None) -> str | None:
    """
    Collapse an ID number to something comparable.

    Two people typing the same PhilSys number will not type it the same way —
    "1234-5678-9012", "1234 5678 9012" and "123456789012" are one number and
    three strings. Comparing them raw finds only the duplicates that were typed
    identically, which is the subset least likely to be deliberate.
    """
    if not raw:
        return None
    cleaned = "".join(ch for ch in raw if ch.isalnum()).upper()
    # A two-character "number" is a typo, not an identity. Treating it as one
    # would group every such account into one enormous false duplicate.
    return cleaned if len(cleaned) >= 4 else None


def _attach_review_flags(db: Client, rows: list[dict]) -> None:
    """
    Mark each waiting submission with why a human should — or need not — look.

    THE PROBLEM THIS EXISTS FOR

    The queue is oldest-first and otherwise undifferentiated, so a thousand
    waiting residents are a thousand identical-looking jobs. Reviewing them
    exhaustively is eight hours of looking at photographs, and the great
    majority of that work changes nothing: verification is metadata a
    dispatcher reads, never a permission (migration 012 is explicit that an
    unverified resident can report an emergency exactly like a verified one).

    So the queue should not be a list of everyone. It should be able to answer
    "which of these actually matters", and these are the signals for that:

      duplicate_id_count  Another account is using the same ID number. This is
                          the fraud case verification exists to catch, and
                          nothing in this system looked for it — the column was
                          stored and never compared. A human squinting at two
                          photographs cannot see it at all.
      report_count        This resident has actually filed incidents. Their
                          identity is the one a dispatcher will read; the
                          accounts that never report are the ones where a
                          decision changes nothing.
      sos_warning_count   This account has already misused the SOS button.
      missing_evidence    No ID photo or no selfie, so the one comparison this
                          page exists for cannot be made. Not review work at
                          all — it needs the resident to re-upload.
      face_mismatch       The automatic ID/selfie comparison disagreed, or
                          found no face on the card. This is the check the page
                          exists for, now done before a human opens the row.
      id_unreadable       The photographed card produced almost no text, or an
                          expiry already in the past.

    THE TWO NEW FLAGS ARE PRE-SCREENS, NOT VERDICTS. They are computed on the
    handset by a model that has never been validated on Philippine ID cards
    re-photographed under a phone flash, and the expected failure is a FALSE
    mismatch: an ID photograph fifteen years old, or taken before an illness,
    scores badly and is approved in four seconds by anyone who looks. So they
    move a row up the queue and change nothing else. Nothing in this file, and
    nothing downstream of it, may raise verification_level from them — see
    migration 023.

    Every lookup here is bounded by the page being enriched except the
    duplicate scan, which is capped.
    """
    if not rows:
        return

    ids = [r["id"] for r in rows]

    # ── Which of these residents has actually reported anything ──
    # Bounded by the page: .in_() over the ids we already hold.
    reported: dict[str, int] = {}
    try:
        inc = (
            db.table("incidents")
            .select("reporter_id")
            .in_("reporter_id", ids)
            .execute()
            .data
            or []
        )
        for row in inc:
            rid = str(row.get("reporter_id") or "")
            if rid:
                reported[rid] = reported.get(rid, 0) + 1
    except Exception:
        # A failure here must not take the queue down with it. The flags are an
        # aid to prioritising; the list of people waiting is the actual job.
        log.warning("verification.report_count_failed", exc_info=True)

    # ── Duplicate ID numbers, across every resident ──────────────
    dup_counts: dict[str, int] = {}
    try:
        all_ids = (
            db.table("users")
            .select("id, valid_id_number")
            .eq("role", "resident")
            .not_.is_("valid_id_number", "null")
            .limit(_DUP_SCAN_MAX)
            .execute()
            .data
            or []
        )
        for row in all_ids:
            key = _normalise_id_number(row.get("valid_id_number"))
            if key:
                dup_counts[key] = dup_counts.get(key, 0) + 1
    except Exception:
        log.warning("verification.duplicate_scan_failed", exc_info=True)

    for row in rows:
        key = _normalise_id_number(row.get("valid_id_number"))
        # Minus one: the row is counting itself.
        duplicates = max(0, dup_counts.get(key, 0) - 1) if key else 0
        reports = reported.get(str(row["id"]), 0)
        sos = int(row.get("sos_warning_count") or 0)
        missing = not row.get("valid_id_image_path") or not row.get("selfie_image_path")

        verdict = row.get("face_match_verdict")
        # 'uncertain' and 'unavailable' are NOT flags. Both mean "a human
        # decides", which is what this queue is for — flagging them would mark
        # every submission on a deployment without the model installed, and a
        # flag that fires on everything is one nobody reads.
        face_mismatch = verdict in ("no_match", "no_face_on_id")

        checks = row.get("id_checks") or {}
        # `is False` and `is True`, not truthiness. These keys are absent on
        # rows registered before migration 023 and on cards that print no
        # expiry, and a missing key must not read as "the check failed".
        id_unreadable = (
            checks.get("readable") is False
            or checks.get("expired") is True
            or checks.get("face_found") is False
        )

        row["review_flags"] = {
            "duplicate_id_count": duplicates,
            "report_count": reports,
            "sos_warning_count": sos,
            "missing_evidence": missing,
            "face_mismatch": face_mismatch,
            "id_unreadable": id_unreadable,
            # Missing evidence is deliberately NOT a reason to review: there is
            # nothing to look at. It is its own bucket, surfaced separately on
            # the page so those rows can be chased rather than opened.
            "needs_review": bool(
                duplicates or reports or sos or face_mismatch or id_unreadable
            ),
        }


def _agency_admin_municipality(current_user: dict) -> str | None:
    """The one municipality an agency_admin may verify residents in — their
    own station's, the same lock geographic_service.agency_municipality
    already applies to an Agency Admin's Operational Area. Returns None for
    any other role (provincial_admin sees every municipality; residents and
    responders never call this endpoint at all)."""
    if current_user.get("role") != "agency_admin":
        return None
    from app.services.geographic_service import agency_municipality
    return agency_municipality(str(current_user.get("agency_id") or ""))


def list_verification_queue(
    *,
    municipality: str | None = None,
    include_decided: bool = False,
    limit: int = 50,
    priority_only: bool = False,
    current_user: dict | None = None,
) -> list[dict]:
    """
    Residents awaiting an identity decision, oldest first.

    Oldest first is deliberate and the opposite of most listings here: this is
    a queue of people waiting, not a feed of recent activity. Newest-first
    would let the earliest applicant starve.

    SCOPED TO ONE MUNICIPALITY FOR AN AGENCY ADMIN. A station verifies the
    identity of the people IT serves — Naval's queue is Naval residents, never
    Kawayan's or Almeria's. `municipality` is therefore not a free client
    choice for this role: an agency_admin's own station locks it, silently
    overriding whatever the request asked for, the same way Operational Area
    already locks their municipality. A provincial_admin has no such lock and
    may filter (or not) across the whole province.
    """
    db: Client = get_supabase()

    if current_user is not None:
        own_muni = _agency_admin_municipality(current_user)
        if own_muni is not None:
            municipality = own_muni

    query = db.table("users").select(_VERIFICATION_SELECT).eq("role", "resident")

    if not include_decided:
        # Something to actually look at. An account that skipped verification
        # entirely has nothing for an admin to decide and must not clog the
        # queue -- it is not a pending request, it is simply unverified.
        query = query.eq("verification_level", 0).not_.is_(
            "valid_id_image_path", "null"
        )

    if municipality:
        query = query.eq("municipality_address", municipality)

    # A wider scan when filtering to priority, because the filter is applied
    # after enrichment and most rows will fall out of it. Fetching `limit` rows
    # and then filtering would return a near-empty page and read as "nothing
    # needs review" when it means "nothing in the oldest fifty".
    scan = _PRIORITY_SCAN_MAX if priority_only else limit
    result = query.order("created_at", desc=False).limit(scan).execute()
    rows = result.data or []

    for row in rows:
        barangay = row.pop("barangays", None)
        row["barangay"] = barangay.get("name") if isinstance(barangay, dict) else None

    _attach_review_flags(db, rows)

    if priority_only:
        rows = [r for r in rows if r["review_flags"]["needs_review"]]

    return rows[:limit]


def _assert_verification_scope(row: dict, current_user: dict | None) -> None:
    """Raise 403 if an agency_admin is reaching outside their own municipality.
    Same lock as list_verification_queue's filter, enforced again here so a
    direct GET/decide on a known user_id cannot bypass it — see that
    function's docstring for why the lock exists."""
    if current_user is None:
        return
    own_muni = _agency_admin_municipality(current_user)
    if own_muni is None:
        return
    if (row.get("municipality_address") or None) != own_muni:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only verify residents of your own municipality.",
        )


def get_verification_detail(user_id: str, *, current_user: dict | None = None) -> dict:
    """One resident's submission, with short-lived signed URLs for the images.

    The URLs expire in five minutes and are generated per request. They are
    never stored, never returned to the resident themselves, and never reach a
    responder -- see the storage policies in migrations 015 and 020.
    """
    db: Client = get_supabase()

    result = (
        db.table("users")
        .select(_VERIFICATION_SELECT)
        .eq("id", user_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Resident not found.",
        )

    row = result.data
    _assert_verification_scope(row, current_user)
    barangay = row.pop("barangays", None)
    row["barangay"] = barangay.get("name") if isinstance(barangay, dict) else None

    row["id_image_url"] = _signed_url("resident-ids", row.get("valid_id_image_path"))
    row["selfie_url"] = _signed_url("resident-ids", row.get("selfie_image_path"))
    row["last_review"] = _last_review(db, user_id)

    # The reviewer's actual job is comparing the typed name to the card, so
    # spell out what to compare rather than making them assemble it.
    row["name_on_file"] = " ".join(
        p for p in [
            row.get("first_name"),
            row.get("middle_name"),
            row.get("last_name"),
            row.get("name_suffix"),
        ] if p
    ) or row.get("full_name")

    return row


_REVIEW_COLUMNS = (
    "verification_decision, verification_reviewed_by, "
    "verification_reviewed_by_name, verification_reviewed_at"
)


def _last_review(db: Client, user_id: str) -> dict | None:
    """Who made the latest identity decision on this resident, and what it was.

    Evaluator finding #7. Read on its own so a database without migration 044
    (no such columns yet) still shows the rest of the review screen.
    """
    try:
        res = db.table("users").select(_REVIEW_COLUMNS).eq("id", user_id).maybe_single().execute()
    except Exception:
        return None
    row = res.data if res is not None and isinstance(res.data, dict) else None
    if not row or not row.get("verification_decision"):
        return None
    return {
        "decision": row.get("verification_decision"),
        "reviewed_by": row.get("verification_reviewed_by"),
        "reviewed_by_name": row.get("verification_reviewed_by_name"),
        "reviewed_at": row.get("verification_reviewed_at"),
    }


def _signed_url(bucket: str, path: str | None, expires: int = 300) -> str | None:
    if not path:
        return None
    try:
        signed = get_supabase().storage.from_(bucket).create_signed_url(path, expires)
        return signed.get("signedURL") or signed.get("signedUrl")
    except Exception:
        # A missing object must not 500 the whole review screen -- the admin
        # still needs to see the typed data and the other image.
        return None


def decide_verification(
    user_id: str,
    *,
    approve: bool,
    method: str | None,
    reviewer_id: str,
    purge_images: bool = True,
    current_user: dict | None = None,
) -> dict:
    """
    Record an identity decision.

    Approving sets verification_level to 2. Rejecting returns it to 0 rather
    than inventing a "rejected" state: the tier is a confidence signal, and a
    rejected submission means we are back to not knowing, which is exactly
    what 0 means.

    [purge_images] honours the retention rule migration 015 states plainly --
    the scan exists to be checked once, and keeping it afterwards is the
    failure mode. The row keeps valid_id_type and valid_id_number as the audit
    trail of what was checked.
    """
    db: Client = get_supabase()

    current = (
        db.table("users")
        .select("id, role, full_name, valid_id_image_path, selfie_image_path, municipality_address")
        .eq("id", user_id)
        .single()
        .execute()
    )
    if not current.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Resident not found."
        )
    if current.data.get("role") != "resident":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only resident accounts are verified this way. "
                   "Responders are approved via /agency/responders.",
        )
    _assert_verification_scope(current.data, current_user)

    now = datetime.now(timezone.utc).isoformat()
    reviewer_name = (current_user or {}).get("full_name")
    payload: dict = {
        "verification_level": 2 if approve else 0,
        "verification_method": method if approve else None,
        "verified_at": now if approve else None,
    }
    # Finding #7: the decision used to keep no trace of who made it. Stored on
    # the resident (latest decision) and in the audit log (every decision).
    review = {
        "verification_decision": "approved" if approve else "rejected",
        "verification_reviewed_by": reviewer_id,
        "verification_reviewed_by_name": reviewer_name,
        "verification_reviewed_at": now,
    }

    if purge_images:
        for bucket, key in (
            ("resident-ids", "valid_id_image_path"),
            ("resident-ids", "selfie_image_path"),
        ):
            path = current.data.get(key)
            if not path:
                continue
            try:
                db.storage.from_(bucket).remove([path])
            except Exception:
                # Failing to delete the object must not block the decision.
                # The column is cleared regardless, and migration 015's
                # retention query will surface anything left behind.
                pass
            payload[key] = None

    reviewer = current_user or {"id": reviewer_id}
    with audit_service.action(
        actor=reviewer,
        action="verification.approved" if approve else "verification.rejected",
        target_type="user",
        target_id=user_id,
        target_label=current.data.get("full_name"),
        new={"verification_level": payload["verification_level"], "method": payload["verification_method"],
             "images_purged": purge_images},
    ):
        try:
            updated = db.table("users").update({**payload, **review}).eq("id", user_id).execute()
        except Exception as exc:
            if not _missing_review_columns(exc):
                raise
            # Migration 044 not applied: the decision still stands and the audit
            # row above names the reviewer; only the copy on the resident waits.
            log.warning("verification.review_columns_missing", user_id=user_id)
            updated = db.table("users").update(payload).eq("id", user_id).execute()
        if not updated.data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Could not record the decision.",
            )

    return {
        "id": user_id,
        "verification_level": payload["verification_level"],
        "verification_method": payload["verification_method"],
        "verified_at": payload["verified_at"],
        "images_purged": purge_images,
        "reviewed_by": reviewer_id,
        "reviewed_by_name": reviewer_name,
        "reviewed_at": now,
        "decision": review["verification_decision"],
    }


def _missing_review_columns(exc: Exception) -> bool:
    text = str(exc)
    return "verification_review" in text or "verification_decision" in text


# Batch ceiling. One HTTP request should not be able to sit in a loop for
# minutes: each decision is its own read, write and two storage deletes, so a
# thousand-row batch would hold a worker open long past any sane timeout and
# leave the caller unable to tell what had been committed when it died.
BULK_DECIDE_MAX = 200


def decide_verification_bulk(
    user_ids: list[str],
    *,
    approve: bool,
    method: str | None,
    reviewer_id: str,
    purge_images: bool = True,
    current_user: dict | None = None,
) -> dict:
    """
    Record the SAME decision for several residents.

    WHAT THIS IS FOR, AND WHAT IT IS NOT FOR

    A queue of a thousand waiting residents cannot be worked one modal at a
    time, so this exists. But a bulk approve is only honest when one sentence
    is true of every account in the batch, and `method` is where that sentence
    is recorded — it is required on approval and validated against the same
    list the single-decision route uses.

    "These forty all passed phone OTP" is such a sentence, and phone_otp is a
    real method that needed no human. "I examined a thousand government IDs" is
    not, and choosing government_id for a batch nobody opened writes that claim
    into every one of those rows and into the audit trail behind them. The API
    cannot tell the difference; the reviewer can.

    Rejection needs no method — the single route does not take one either,
    because "we are back to not knowing" is the same state however you arrived.

    Not a transaction. Each decision commits on its own, so a failure partway
    through leaves the ones before it decided. That is deliberate: the
    alternative is discarding good decisions because the nine-hundredth row
    had a bad id, and each row here is an independent fact about a different
    person, not a step in one operation. The caller is told exactly which ones
    failed and why.
    """
    if not user_ids:
        return {"decided": 0, "failed": []}

    if len(user_ids) > BULK_DECIDE_MAX:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Too many at once. {BULK_DECIDE_MAX} is the maximum per "
                   f"request; {len(user_ids)} were sent.",
        )

    # De-duplicate but keep the order the reviewer sent, so the failure list
    # reads in the same order as the list they were looking at.
    seen: set[str] = set()
    ordered = [u for u in user_ids if not (u in seen or seen.add(u))]

    decided = 0
    failed: list[dict] = []

    for uid in ordered:
        try:
            decide_verification(
                uid,
                approve=approve,
                method=method,
                reviewer_id=reviewer_id,
                purge_images=purge_images,
                current_user=current_user,
            )
            decided += 1
        except HTTPException as exc:
            failed.append({"id": uid, "reason": str(exc.detail)})
        except Exception as exc:  # noqa: BLE001 - one bad row must not stop the batch
            log.warning("verification.bulk_row_failed", user_id=uid, exc_info=True)
            failed.append({"id": uid, "reason": str(exc) or "Unknown error"})

    log.info(
        "admin.verification_bulk_decided",
        approve=approve,
        method=method,
        requested=len(ordered),
        decided=decided,
        failed=len(failed),
        acting_admin_id=reviewer_id,
    )

    return {"decided": decided, "failed": failed}
