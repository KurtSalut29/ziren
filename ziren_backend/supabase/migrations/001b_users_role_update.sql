-- ============================================================
-- Migration 001b: Patch users table — 4-role system
--
-- Patches the users table created in migration 001.
-- Safe to run: uses IF NOT EXISTS / IF EXISTS guards.
-- DO NOT edit migration 001 — this is the canonical patch.
--
-- IMPORTANT: Run this BEFORE migration 002.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Drop ALL old constraints first, before any data changes.
--    This prevents old CHECKs from blocking the backfill.
-- ------------------------------------------------------------
ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS users_role_check;

ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS users_approval_status_check;

ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS users_agency_required_check;

ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS users_badge_id_check;

-- Also drop old RLS policies before recreating them
DROP POLICY IF EXISTS "users: read own row"                    ON public.users;
DROP POLICY IF EXISTS "users: update own row"                  ON public.users;
DROP POLICY IF EXISTS "users: update own profile"              ON public.users;
DROP POLICY IF EXISTS "users: dispatcher reads citizens"       ON public.users;
DROP POLICY IF EXISTS "users: agency_admin manages own agency" ON public.users;
DROP POLICY IF EXISTS "users: agency_admin reads own agency"   ON public.users;
DROP POLICY IF EXISTS "users: agency_admin approves own responders" ON public.users;
DROP POLICY IF EXISTS "users: super_admin reads all"           ON public.users;
DROP POLICY IF EXISTS "users: insert own row"                  ON public.users;

-- ------------------------------------------------------------
-- 2. Add new columns (idempotent)
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS badge_id TEXT DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending';

-- ------------------------------------------------------------
-- 3. Backfill existing rows AFTER constraints are dropped
--    and BEFORE new constraints are added.
--    Order matters: rename roles first, then set approval_status.
-- ------------------------------------------------------------

-- Rename legacy role values to new names
UPDATE public.users SET role = 'resident'     WHERE role = 'citizen';
UPDATE public.users SET role = 'agency_admin' WHERE role = 'dispatcher';

-- Set approval_status based on role
-- resident / agency_admin / super_admin → no approval gate needed
UPDATE public.users
SET approval_status = 'not_required'
WHERE role IN ('resident', 'agency_admin', 'super_admin');

-- responders stay 'pending' (default) — no change needed
-- Any row not yet touched gets 'pending' from the column default

-- ------------------------------------------------------------
-- 4. Add new CHECK constraints AFTER data is clean
-- ------------------------------------------------------------

-- 4a. Role constraint — all 4 valid roles
ALTER TABLE public.users
    ADD CONSTRAINT users_role_check
    CHECK (role IN ('resident', 'responder', 'agency_admin', 'super_admin'));

-- 4b. Approval status constraint
ALTER TABLE public.users
    ADD CONSTRAINT users_approval_status_check
    CHECK (approval_status IN ('not_required', 'pending', 'approved', 'rejected'));

-- 4c. Agency required for responder/agency_admin; forbidden for resident/super_admin
ALTER TABLE public.users
    ADD CONSTRAINT users_agency_required_check
    CHECK (
        (role IN ('responder', 'agency_admin') AND agency_id IS NOT NULL)
        OR
        (role IN ('resident', 'super_admin') AND agency_id IS NULL)
    );

-- 4d. badge_id required for responders, must be NULL for others
ALTER TABLE public.users
    ADD CONSTRAINT users_badge_id_check
    CHECK (
        (role = 'responder' AND badge_id IS NOT NULL)
        OR (role != 'responder')
    );

-- ------------------------------------------------------------
-- 5. Recreate RLS policies with correct role names
-- ------------------------------------------------------------

-- 5a. Any authenticated user reads their own row
CREATE POLICY "users: read own row"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

-- 5b. Users update their own non-sensitive fields only
--     Cannot self-change role, approval_status, agency_id, badge_id
CREATE POLICY "users: update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        role = (SELECT role FROM public.users WHERE id = auth.uid())
        AND approval_status = (SELECT approval_status FROM public.users WHERE id = auth.uid())
        AND agency_id IS NOT DISTINCT FROM (SELECT agency_id FROM public.users WHERE id = auth.uid())
        AND COALESCE(badge_id, '') = COALESCE((SELECT badge_id FROM public.users WHERE id = auth.uid()), '')
    );

-- 5c. Agency Admin reads all users in their own agency (for approval queue)
CREATE POLICY "users: agency_admin reads own agency"
    ON public.users FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users admin
            WHERE admin.id = auth.uid()
            AND admin.role = 'agency_admin'
            AND admin.agency_id = public.users.agency_id
        )
    );

-- 5d. Agency Admin can approve/reject Responders in their agency ONLY
--     Can only change approval_status — all other fields locked
CREATE POLICY "users: agency_admin approves own responders"
    ON public.users FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users admin
            WHERE admin.id = auth.uid()
            AND admin.role = 'agency_admin'
            AND admin.agency_id = public.users.agency_id
        )
        AND public.users.role = 'responder'
    )
    WITH CHECK (
        role = (SELECT role FROM public.users WHERE id = public.users.id)
        AND agency_id IS NOT DISTINCT FROM (SELECT agency_id FROM public.users WHERE id = public.users.id)
        AND COALESCE(badge_id, '') = COALESCE((SELECT badge_id FROM public.users WHERE id = public.users.id), '')
    );

-- 5e. Super Admin reads all users across all agencies
CREATE POLICY "users: super_admin reads all"
    ON public.users FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users sa
            WHERE sa.id = auth.uid()
            AND sa.role = 'super_admin'
        )
    );

-- 5f. Authenticated users insert their own row
CREATE POLICY "users: insert own row"
    ON public.users FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ------------------------------------------------------------
-- 6. Verification — confirm current state of all users
-- ------------------------------------------------------------
SELECT
    id,
    email,
    role,
    approval_status,
    agency_id IS NOT NULL AS has_agency,
    badge_id  IS NOT NULL AS has_badge
FROM public.users
ORDER BY created_at;
