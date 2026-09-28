-- ============================================================
-- Migration 016: Agency Admin access requests
--
-- Fixes a flow that has been broken since the Week 1 security fix.
--
-- The dashboard's "Request Access" page posted to POST /auth/register with
-- role='agency_admin'. That endpoint now rejects privileged roles (see
-- RegisterRequest.block_privileged_self_registration), so every submission
-- fails with:
--
--   "Self-registration as 'agency_admin' is not permitted."
--
-- The validator is right and stays. The page was the thing in the wrong: it
-- promised the reader "a Super Admin will review your request" while actually
-- attempting to mint a privileged account on the spot.
--
-- This table is what the page should always have written to. A request is not
-- an account — it carries no password, grants nothing, and is inert until a
-- Super Admin acts on it through the existing provisioning endpoint
-- (POST /users/super/agency-admins), which sends the Supabase invite that
-- lands on /accept-invite.
--
-- Run AFTER migration 015.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.access_requests (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name     TEXT NOT NULL,
    email         TEXT NOT NULL,
    position      TEXT,
    agency_id     UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,

    status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected')),

    -- Set when a Super Admin acts on the request.
    reviewed_by   UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_at   TIMESTAMPTZ,
    review_note   TEXT,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One open request per email. A second submission while the first is still
-- pending is a duplicate, not a new request — but a rejected applicant may
-- legitimately reapply, so the constraint only covers pending rows.
CREATE UNIQUE INDEX IF NOT EXISTS access_requests_one_pending_per_email
    ON public.access_requests (lower(email))
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS access_requests_status_idx
    ON public.access_requests(status, created_at DESC);

COMMENT ON TABLE public.access_requests IS
    'Pending Agency Admin access requests from the dashboard. Holds no '
    'password and grants no access. A Super Admin approves one by calling '
    'POST /users/super/agency-admins, which creates the account and sends the '
    'invite email.';

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
ALTER TABLE public.access_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "access_requests: super_admin reads"   ON public.access_requests;
DROP POLICY IF EXISTS "access_requests: super_admin updates" ON public.access_requests;

-- Deliberately no INSERT policy for anon. Submissions go through the API on
-- the service key, which rate-limits them; letting the public write straight
-- into this table would hand anyone an unbounded insert.
CREATE POLICY "access_requests: super_admin reads"
    ON public.access_requests FOR SELECT
    USING (public.get_my_role() = 'super_admin');

CREATE POLICY "access_requests: super_admin updates"
    ON public.access_requests FOR UPDATE
    USING (public.get_my_role() = 'super_admin')
    WITH CHECK (public.get_my_role() = 'super_admin');

-- The API writes these rows as service_role. RLS policies alone are not
-- enough — without a table GRANT every insert fails with 42501.
GRANT ALL ON public.access_requests TO service_role;

-- ------------------------------------------------------------
-- Verification
-- ------------------------------------------------------------
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'access_requests'
ORDER BY ordinal_position;

SELECT status, COUNT(*) FROM public.access_requests GROUP BY status;
