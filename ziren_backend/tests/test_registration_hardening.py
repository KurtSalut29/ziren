"""
Regression tests for registration hardening (residency + role allow-list).

Background — the defect these guard against:

Week 1 blocked privileged self-registration at POST /auth/register with a
Pydantic validator. That fix is real, but it guards a door the mobile client
never opens. ziren_mobile registers by calling Supabase Auth directly:

    _client.auth.signUp(data: {'role': role, ...})

and the anon key that call requires ships inside the app binary. The
`handle_new_auth_user` trigger then copied `raw_user_meta_data->>'role'`
straight into public.users.role with no allow-list — so the same escalation
the validator rejects at the API boundary was still reachable by anyone who
could read the key out of the APK.

The trigger is the only chokepoint shared by BOTH registration paths, which
is why the allow-list belongs there (migration 013).

These are source-level assertions, in the same spirit as
test_station_resolution.py: the defect lives in SQL and in RLS policy text,
neither of which a MagicMock database can reproduce.
"""

import re
from pathlib import Path

import pytest

MIGRATIONS = Path(__file__).resolve().parents[1] / "supabase" / "migrations"


def _sql(name: str) -> str:
    path = MIGRATIONS / name
    assert path.exists(), f"Missing migration: {name}"
    return path.read_text(encoding="utf-8")


# ── Trigger must enforce a role allow-list ────────────────────────────────────

def test_auth_trigger_has_role_allow_list():
    """
    The trigger must restrict self-assigned roles to resident/responder.
    Without this, signUp(data:{'role':'super_admin'}) provisions a Super Admin.
    """
    src = _sql("013_harden_auth_trigger.sql")

    assert "IN ('resident', 'responder')" in src, (
        "handle_new_auth_user must allow-list the client-supplied role. "
        "A plain COALESCE of raw_user_meta_data->>'role' lets the mobile "
        "client self-assign super_admin."
    )


def test_auth_trigger_does_not_trust_raw_role():
    """
    Guard the specific broken shape: assigning the metadata role directly to
    the column with only a COALESCE default and no membership test.
    """
    src = _sql("013_harden_auth_trigger.sql")

    # The requested role may be READ into a variable, but the value inserted
    # must come from the validated variable, not the raw JSON expression.
    body = src[src.index("CREATE OR REPLACE FUNCTION"):]
    insert_stmt = body[body.index("INSERT INTO public.users"):]

    assert "raw_user_meta_data->>'role'" not in insert_stmt, (
        "The INSERT must use the validated role variable, never the raw "
        "metadata expression."
    )


def test_privileged_roles_are_not_self_assignable():
    """Neither privileged role may appear in the trigger's allow-list."""
    src = _sql("013_harden_auth_trigger.sql")
    allow_list = re.search(r"IN \('resident', 'responder'\)", src)
    assert allow_list, "Allow-list not found."

    # They may appear in comments/verification queries, but not as an
    # accepted value in the branch that assigns v_role.
    assign_branch = src[allow_list.start():src.index("v_approval_status :=")]
    for role in ("agency_admin", "super_admin"):
        assert role not in assign_branch, (
            f"'{role}' must not be reachable through the trigger's role "
            f"assignment branch."
        )


# ── Trust signals must be frozen against self-update ──────────────────────────

def test_rls_freezes_verification_level():
    """
    verification_level is shown to dispatchers as reporter credibility. If the
    'update own profile' policy does not pin it, a resident can PATCH their own
    row and appear as a confirmed resident.
    """
    src = _sql("012_residency_and_accessibility.sql")

    policy_start = src.index('CREATE POLICY "users: update own profile"')
    policy = src[policy_start:src.index(");", policy_start)]

    for column in ("verification_level", "verification_method", "verified_at"):
        assert column in policy, (
            f"'{column}' must be frozen in the WITH CHECK of "
            f"'users: update own profile' — it is a system-assigned trust "
            f"signal, not user-editable profile data."
        )


def test_registered_by_is_frozen():
    """
    registered_by records assisted registration. A user must not be able to
    claim someone else registered them, or to erase that they were assisted.
    """
    src = _sql("012_residency_and_accessibility.sql")
    policy_start = src.index('CREATE POLICY "users: update own profile"')
    policy = src[policy_start:src.index(");", policy_start)]

    assert "registered_by" in policy


# ── Verification must never gate reporting ────────────────────────────────────

def test_verification_level_defaults_to_zero():
    """
    A brand-new account starts at level 0 and must still be able to report.
    A non-zero default would imply verification is a precondition.
    """
    src = _sql("012_residency_and_accessibility.sql")

    assert "verification_level SMALLINT NOT NULL DEFAULT 0" in src, (
        "verification_level must default to 0. An unverified resident in an "
        "emergency must be able to file a report."
    )


def test_incident_submission_does_not_check_verification_level():
    """
    The safety-critical invariant: no code path in incident submission may
    branch on verification_level. Blocking an unverified user from reporting
    an emergency would be a safety defect, not a security feature.
    """
    from app.services import incident_service
    import inspect

    src = inspect.getsource(incident_service)
    assert "verification_level" not in src, (
        "incident_service must not read verification_level. Tiered trust is "
        "dispatcher-facing metadata and must never gate submission."
    )


# ── Accessibility data must reach the responding crew ─────────────────────────

def test_responder_incident_detail_includes_accessibility_fields():
    """
    The accessibility profile is only useful if it arrives with the incident.
    A crew that does not know the reporter is deaf will attempt a voice
    callback and lose minutes.
    """
    from app.services import responder_service
    import inspect

    src = inspect.getsource(responder_service.get_incident_detail)

    for field in ("is_pwd", "disability_types", "accessibility_notes",
                  "preferred_contact_mode"):
        assert field in src, (
            f"Responder incident detail must select '{field}' so the crew "
            f"knows how to assist before arrival."
        )


# ── Barangay reference data ───────────────────────────────────────────────────

def test_barangays_readable_by_anon():
    """
    The registration form loads the barangay list before the user has a
    session, so anon must hold SELECT.
    """
    src = _sql("012_residency_and_accessibility.sql")

    assert "GRANT SELECT ON public.barangays TO anon" in src
    assert "TO anon, authenticated" in src


def test_all_eight_biliran_municipalities_are_seeded():
    """Every municipality must be present or its residents cannot register."""
    src = _sql("012_residency_and_accessibility.sql")

    for municipality in ("Naval", "Almeria", "Biliran", "Cabucgayan",
                         "Caibiran", "Culaba", "Kawayan", "Maripipi"):
        assert f"('{municipality}', " in src, (
            f"No barangays seeded for {municipality}. Residents of that "
            f"municipality would be unable to complete registration."
        )


# ── Valid ID gives non-PWD residents a route to verification ──────────────────

def test_every_resident_has_a_path_to_level_two():
    """
    Originally only `pwd_id_number` existed, so a resident who is not a PWD had
    no way to reach verification_level 2 while a PWD resident did. Verification
    must not be reachable by one group only.
    """
    src = _sql("012_residency_and_accessibility.sql")

    assert "valid_id_type" in src and "valid_id_number" in src, (
        "Residents need a general valid-ID field, not just pwd_id_number, or "
        "non-PWD residents can never be verified."
    )


def test_lgu_issued_ids_are_accepted():
    """
    LGU-issued IDs are the operationally useful ones: the issuing LGU only
    issues to its own residents, so they prove Biliran residency.
    """
    src = _sql("012_residency_and_accessibility.sql")

    for id_type in ("barangay_id", "voters_id", "pwd_id", "senior_citizen_id"):
        assert f"'{id_type}'" in src


def test_no_id_image_column_exists():
    """
    Only type and number are stored. An ID photo is sensitive personal
    information under RA 10173 and would make this system a far larger breach
    target for no operational gain.
    """
    src = _sql("012_residency_and_accessibility.sql")

    for banned in ("id_image", "id_photo", "id_scan", "valid_id_url"):
        assert banned not in src, (
            f"'{banned}' must not exist — ID images are not collected."
        )


def test_valid_id_is_optional():
    """An ID must never be required to register or to report."""
    src = _sql("012_residency_and_accessibility.sql")

    id_block = src[src.index("valid_id_type"):src.index("valid_id_number") + 200]
    assert "NOT NULL" not in id_block, (
        "valid_id_type/valid_id_number must be nullable. Requiring an ID "
        "would exclude the residents most likely to need this app."
    )


def test_valid_id_type_validator_rejects_unknown():
    """The API must reject an ID type outside the known set."""
    from app.models.user import UpdateProfileRequest

    ok = UpdateProfileRequest(valid_id_type="barangay_id", valid_id_number="X-1")
    assert ok.valid_id_type == "barangay_id"

    with pytest.raises(Exception):
        UpdateProfileRequest(valid_id_type="library_card")


# ── Accessibility is resident-only ────────────────────────────────────────────

def test_responder_registration_omits_accessibility_fields():
    """
    The accessibility profile describes how a crew should assist the person
    reporting; it does not apply to the crew themselves. The registration
    screen must not send it for a responder.
    """
    screen = (
        Path(__file__).resolve().parents[2]
        / "ziren_mobile" / "lib" / "features" / "auth" / "presentation"
        / "register_screen.dart"
    )
    if not screen.exists():
        pytest.skip("ziren_mobile not present in this checkout")

    src = screen.read_text(encoding="utf-8")

    # Registration is a stepped flow, and the optional ID/accessibility step
    # is the last one. Responders get a shorter flow that never reaches it.
    assert "_isResponder ? 2 : 3" in src, (
        "Responders must skip the optional resident step entirely."
    )
    # And the submitted values are neutralised for a responder regardless of
    # any state left behind by toggling the role selector before switching.
    assert "isPwd: _isResponder ? false : _isPwd" in src, (
        "A responder must never submit is_pwd=true, even if the resident form "
        "was filled in before switching roles."
    )


# ── Responder agency resolution ───────────────────────────────────────────────

def test_mobile_does_not_hardcode_naval_agency():
    """
    _resolveAgencyId used to pin municipality to 'Naval', stranding every
    responder outside the capital in an agency their own admin could not see.
    """
    repo = (
        Path(__file__).resolve().parents[2]
        / "ziren_mobile" / "lib" / "features" / "auth" / "data"
        / "auth_repository.dart"
    )
    if not repo.exists():
        pytest.skip("ziren_mobile not present in this checkout")

    src = repo.read_text(encoding="utf-8")
    resolve = src[src.index("Future<String?> _resolveAgencyId"):]
    resolve = resolve[:resolve.index("\n  }")]

    assert "'Naval'" not in resolve, (
        "_resolveAgencyId must resolve the agency from the responder's own "
        "municipality, not a hardcoded 'Naval'."
    )
    assert ".eq('municipality', municipality)" in resolve


def test_agency_admin_can_release_misassigned_responder():
    """
    Migration 014 must stop pinning agency_id in the agency-admin WITH CHECK,
    otherwise responders stranded by the Naval default can never be moved.
    """
    src = _sql("014_responder_agency_reassignment.sql")

    policy_start = src.index(
        'CREATE POLICY "users: agency_admin approves own responders"'
    )
    policy = src[policy_start:]
    with_check = policy[policy.index("WITH CHECK"):]

    assert "agency_id IS NOT NULL" in with_check, (
        "The admin must be able to hand a responder to another agency, but "
        "never to NULL."
    )
    assert "agency_id IS NOT DISTINCT FROM" not in with_check, (
        "Pinning agency_id in WITH CHECK is exactly what trapped responders "
        "in Naval."
    )
