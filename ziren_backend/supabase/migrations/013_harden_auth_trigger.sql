-- ============================================================
-- Migration 013: Harden handle_new_auth_user against role injection
--
-- SECURITY FIX — privilege escalation, second path.
--
-- Week 1 closed this hole in the FastAPI layer by rejecting
-- role='agency_admin'/'super_admin' at POST /auth/register. That fix is
-- real but it guards a door the mobile client never uses.
--
-- ziren_mobile registers by calling Supabase Auth directly:
--
--     _client.auth.signUp(
--       email: ..., password: ...,
--       data: {'full_name': ..., 'role': role, 'agency_id': ..., ...},
--     )
--
-- The anon key that call needs is shipped inside the app binary. The
-- trigger then did:
--
--     v_role := COALESCE(NULLIF(NEW.raw_user_meta_data->>'role',''),'resident');
--
-- with no allow-list, copying whatever the client sent into
-- public.users.role. So anyone able to read the anon key out of the APK
-- could sign up as 'super_admin' and receive cross-agency access to every
-- incident in the province. The Pydantic validator cannot see this path
-- because no request ever reaches FastAPI.
--
-- Fix: the trigger is the last common chokepoint for BOTH registration
-- paths, so the allow-list belongs here. Only 'resident' and 'responder'
-- may be self-assigned. Anything else is forced to 'resident' rather than
-- raising, because raising inside an auth trigger would leave an
-- auth.users row with no profile row (which is how the existing orphaned
-- rows were probably created).
--
-- Privileged accounts are provisioned deliberately:
--   agency_admin -> POST /users/super/agency-admins (Super Admin only)
--   super_admin  -> out-of-band, service key
--
-- Run AFTER migration 012.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_requested_role  TEXT;
    v_role            TEXT;
    v_approval_status TEXT;
BEGIN
    v_requested_role := NULLIF(NEW.raw_user_meta_data->>'role', '');

    -- Allow-list. Self-registration may only ever produce these two roles.
    IF v_requested_role IN ('resident', 'responder') THEN
        v_role := v_requested_role;
    ELSE
        v_role := 'resident';

        -- Anything other than an absent role is an escalation attempt worth
        -- seeing in the Postgres log. Absent role is the normal default case.
        IF v_requested_role IS NOT NULL THEN
            RAISE WARNING
                'handle_new_auth_user: rejected self-assigned role % for auth user % (forced to resident)',
                v_requested_role, NEW.id;
        END IF;
    END IF;

    v_approval_status := CASE
        WHEN v_role = 'responder' THEN 'pending'
        ELSE 'not_required'
    END;

    INSERT INTO public.users (
        id, email, full_name, role, approval_status, agency_id, badge_id
    )
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        v_role,
        v_approval_status,
        -- agency_id is only meaningful for a responder. Ignoring it for
        -- residents stops a resident row from being bound to an agency.
        CASE
            WHEN v_role = 'responder'
             AND NEW.raw_user_meta_data->>'agency_id' IS NOT NULL
             AND NEW.raw_user_meta_data->>'agency_id' NOT IN ('null', '')
            THEN (NEW.raw_user_meta_data->>'agency_id')::UUID
            ELSE NULL
        END,
        CASE
            WHEN v_role = 'responder'
            THEN NULLIF(NEW.raw_user_meta_data->>'badge_id', '')
            ELSE NULL
        END
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS
    'Creates the public.users profile row for a new auth.users row. '
    'Enforces the resident/responder allow-list on client-supplied role — '
    'this is the only chokepoint shared by BOTH the FastAPI and the direct '
    'Supabase (mobile) registration paths. Do not remove the allow-list.';

-- ------------------------------------------------------------
-- Verification — confirm the allow-list is present in the deployed body
-- ------------------------------------------------------------
SELECT
    p.proname,
    (pg_get_functiondef(p.oid) LIKE '%''resident'', ''responder''%')
        AS has_role_allow_list
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'handle_new_auth_user';

-- Any existing privileged account NOT created deliberately will show here.
-- Review before deleting — a legitimate Super Admin may be in this list.
SELECT id, email, role, is_verified, created_at
FROM public.users
WHERE role IN ('agency_admin', 'super_admin')
ORDER BY created_at;
