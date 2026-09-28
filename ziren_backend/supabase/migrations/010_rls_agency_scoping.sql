-- ============================================================
-- Migration 010: Agency-scoped RLS hardening
--
-- Fixes four gaps left by migrations 002 and 007:
--
--   1. incidents SELECT/UPDATE — agency_admin could read/write
--      incidents belonging to any agency. Now scoped to
--      assigned_agency_id = get_my_agency_id().
--
--   2. dispatch_log SELECT/INSERT — agency_admin could read the
--      full cross-agency audit trail. Now scoped to
--      agency_id = get_my_agency_id().
--
--   3. stations INSERT/UPDATE — no write policy existed at all.
--      Now agency_admin can only write stations in their own agency.
--
--   4. rubric_configs / rubric_audit_log — rewrites the subquery-
--      based policies from migration 007 to use the
--      SECURITY DEFINER helpers (get_my_role, get_my_agency_id)
--      introduced in migration 001d. Same logic, no extra joins,
--      no recursion risk.
--
-- Decisions:
--   - agency_admin MAY write rubric_configs scoped to their own
--     agency_type. super_admin writes any agency_type.
--   - Rubric configs are per agency_type (BFP/PNP/MDRRMO), not
--     per agency_id. All BFP admins share one active BFP config.
--   - The SECURITY DEFINER helper get_my_agency_type() is created
--     here to resolve agency_type from the caller's agency_id
--     without a recursive public.users subquery.
--
-- Requires: migrations 001d, 002, 007, 008 already applied.
-- Run in Supabase SQL Editor.
-- ============================================================


-- ============================================================
-- 0. New SECURITY DEFINER helper: get_my_agency_type()
--
-- Resolves the agency_type ('BFP'|'PNP'|'MDRRMO') for the
-- currently authenticated user by joining users → agencies.
-- SECURITY DEFINER bypasses RLS so there is no recursion.
-- Returns NULL for super_admin (no agency) and unauthenticated.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_agency_type()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT a.agency_type
    FROM   public.users  u
    JOIN   public.agencies a ON a.id = u.agency_id
    WHERE  u.id = auth.uid();
$$;


-- ============================================================
-- 1. incidents — replace wide-open admin policies with scoped ones
-- ============================================================

-- Drop the two existing admin-wide policies from migration 002.
-- "incidents: resident reads own" covered all roles including admins
-- with a single unscoped OR branch — replaced below with two
-- separate, clearly scoped policies.
DROP POLICY IF EXISTS "incidents: resident reads own"   ON public.incidents;
DROP POLICY IF EXISTS "incidents: dispatcher updates"   ON public.incidents;

-- 1a. Residents read their own reports only
CREATE POLICY "incidents: resident reads own"
    ON public.incidents FOR SELECT
    USING (auth.uid() = reporter_id);

-- 1b. Responders read incidents assigned to them
--     (assigned_responder_id added in migration 008)
CREATE POLICY "incidents: responder reads assigned"
    ON public.incidents FOR SELECT
    USING (
        public.get_my_role() = 'responder'
        AND assigned_responder_id = auth.uid()
    );

-- 1c. Agency Admin reads incidents assigned to their agency only
CREATE POLICY "incidents: agency_admin reads own agency"
    ON public.incidents FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND assigned_agency_id = public.get_my_agency_id()
    );

-- 1d. Super Admin reads all incidents
CREATE POLICY "incidents: super_admin reads all"
    ON public.incidents FOR SELECT
    USING (public.get_my_role() = 'super_admin');

-- 1e. Agency Admin updates incidents in their agency only
--     (status changes, severity, dispatch routing)
CREATE POLICY "incidents: agency_admin updates own agency"
    ON public.incidents FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND assigned_agency_id = public.get_my_agency_id()
    );

-- 1f. Super Admin updates any incident
CREATE POLICY "incidents: super_admin updates all"
    ON public.incidents FOR UPDATE
    USING (public.get_my_role() = 'super_admin');

-- Note: INSERT policy ("incidents: resident inserts own") and the
-- responder UPDATE policy ("incidents: responder updates assigned",
-- added in migration 008) are left untouched.


-- ============================================================
-- 2. dispatch_log — add agency scoping
-- ============================================================

-- Drop the unscoped policies from migration 002.
DROP POLICY IF EXISTS "dispatch_log: admin reads"    ON public.dispatch_log;
DROP POLICY IF EXISTS "dispatch_log: admin inserts"  ON public.dispatch_log;

-- 2a. Agency Admin reads only their agency's dispatch log
CREATE POLICY "dispatch_log: agency_admin reads own agency"
    ON public.dispatch_log FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND agency_id = public.get_my_agency_id()
    );

-- 2b. Super Admin reads the full cross-agency log
CREATE POLICY "dispatch_log: super_admin reads all"
    ON public.dispatch_log FOR SELECT
    USING (public.get_my_role() = 'super_admin');

-- 2c. Agency Admin inserts log entries for their own agency
--     dispatcher_id must be the authenticated user (no spoofing)
CREATE POLICY "dispatch_log: agency_admin inserts own agency"
    ON public.dispatch_log FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND agency_id = public.get_my_agency_id()
        AND dispatcher_id = auth.uid()
    );

-- 2d. Super Admin inserts log entries for any agency
CREATE POLICY "dispatch_log: super_admin inserts any"
    ON public.dispatch_log FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'super_admin'
        AND dispatcher_id = auth.uid()
    );

-- No UPDATE or DELETE — dispatch_log is immutable append-only.


-- ============================================================
-- 3. stations — add scoped write policies
-- ============================================================

-- Read is already public (migrations 002c / stations: public read).
-- No write policy existed — adding now.

-- 3a. Agency Admin can insert stations for their own agency
CREATE POLICY "stations: agency_admin inserts own agency"
    ON public.stations FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND agency_id = public.get_my_agency_id()
    );

-- 3b. Agency Admin can update stations for their own agency
CREATE POLICY "stations: agency_admin updates own agency"
    ON public.stations FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND agency_id = public.get_my_agency_id()
    );

-- 3c. Super Admin can insert/update stations for any agency
CREATE POLICY "stations: super_admin inserts any"
    ON public.stations FOR INSERT
    WITH CHECK (public.get_my_role() = 'super_admin');

CREATE POLICY "stations: super_admin updates any"
    ON public.stations FOR UPDATE
    USING (public.get_my_role() = 'super_admin');

-- Grant authenticated users INSERT/UPDATE on stations
-- (SELECT is already granted; INSERT/UPDATE were missing)
GRANT INSERT, UPDATE ON public.stations TO authenticated;


-- ============================================================
-- 4. rubric_configs — rewrite migration 007 policies using
--    SECURITY DEFINER helpers (eliminates subquery joins,
--    consistent with how users/incidents policies work)
-- ============================================================

-- Drop the six policies written in migration 007
DROP POLICY IF EXISTS "rubric_configs: agency_admin reads own"    ON public.rubric_configs;
DROP POLICY IF EXISTS "rubric_configs: agency_admin inserts own"  ON public.rubric_configs;
DROP POLICY IF EXISTS "rubric_configs: agency_admin updates own"  ON public.rubric_configs;
DROP POLICY IF EXISTS "rubric_configs: super_admin reads all"     ON public.rubric_configs;
DROP POLICY IF EXISTS "rubric_configs: super_admin inserts any"   ON public.rubric_configs;
DROP POLICY IF EXISTS "rubric_configs: super_admin updates any"   ON public.rubric_configs;

-- 4a. Agency Admin reads configs for their own agency_type only
CREATE POLICY "rubric_configs: agency_admin reads own"
    ON public.rubric_configs FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND agency_type = public.get_my_agency_type()
    );

-- 4b. Agency Admin inserts new config versions for their agency_type
--     created_by must be the authenticated user
CREATE POLICY "rubric_configs: agency_admin inserts own"
    ON public.rubric_configs FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND agency_type = public.get_my_agency_type()
        AND created_by = auth.uid()
    );

-- 4c. Agency Admin activates/deactivates configs for their agency_type
CREATE POLICY "rubric_configs: agency_admin updates own"
    ON public.rubric_configs FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND agency_type = public.get_my_agency_type()
    );

-- 4d. Super Admin reads all configs across all agency types
CREATE POLICY "rubric_configs: super_admin reads all"
    ON public.rubric_configs FOR SELECT
    USING (public.get_my_role() = 'super_admin');

-- 4e. Super Admin inserts configs for any agency type
CREATE POLICY "rubric_configs: super_admin inserts any"
    ON public.rubric_configs FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'super_admin'
        AND created_by = auth.uid()
    );

-- 4f. Super Admin updates any agency's configs
CREATE POLICY "rubric_configs: super_admin updates any"
    ON public.rubric_configs FOR UPDATE
    USING (public.get_my_role() = 'super_admin');

-- No DELETE policy on rubric_configs — deactivate via is_active=FALSE.


-- ============================================================
-- 5. rubric_audit_log — same rewrite as rubric_configs
-- ============================================================

DROP POLICY IF EXISTS "rubric_audit_log: agency_admin reads own"  ON public.rubric_audit_log;
DROP POLICY IF EXISTS "rubric_audit_log: super_admin reads all"   ON public.rubric_audit_log;
DROP POLICY IF EXISTS "rubric_audit_log: admin inserts"           ON public.rubric_audit_log;

-- 5a. Agency Admin reads audit entries for their agency_type only
CREATE POLICY "rubric_audit_log: agency_admin reads own"
    ON public.rubric_audit_log FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND agency_type = public.get_my_agency_type()
    );

-- 5b. Super Admin reads all audit entries
CREATE POLICY "rubric_audit_log: super_admin reads all"
    ON public.rubric_audit_log FOR SELECT
    USING (public.get_my_role() = 'super_admin');

-- 5c. Agency Admin and Super Admin can insert audit entries.
--     actor_id must match auth.uid() for human actions;
--     actor_id = NULL is reserved for service-role engine events
--     (fallback_to_seed), which bypass RLS entirely via the service key.
CREATE POLICY "rubric_audit_log: admin inserts"
    ON public.rubric_audit_log FOR INSERT
    WITH CHECK (
        public.get_my_role() IN ('agency_admin', 'super_admin')
        AND (actor_id = auth.uid() OR actor_id IS NULL)
    );

-- No UPDATE or DELETE — rubric_audit_log is immutable.


-- ============================================================
-- 6. agencies — rewrite migration 002 admin update policy to
--    use SECURITY DEFINER helpers (the original used a subquery
--    on public.users which is recursion-prone)
-- ============================================================

DROP POLICY IF EXISTS "agencies: admin updates own agency"  ON public.agencies;
DROP POLICY IF EXISTS "agencies: authenticated read"        ON public.agencies;

-- Keep the public read from migration 002c intact; just re-add
-- the authenticated read in case 002c hasn't been applied yet.
-- The "agencies: public read" policy from 002c covers anon+authenticated,
-- so this is a no-op if 002c ran — safe to leave.
CREATE POLICY "agencies: authenticated read"
    ON public.agencies FOR SELECT
    TO authenticated
    USING (TRUE);

-- Agency Admin updates only their own agency record
CREATE POLICY "agencies: agency_admin updates own"
    ON public.agencies FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND id = public.get_my_agency_id()
    );

-- Super Admin updates any agency record
CREATE POLICY "agencies: super_admin updates any"
    ON public.agencies FOR UPDATE
    USING (public.get_my_role() = 'super_admin');


-- ============================================================
-- 7. Verification
-- ============================================================

-- Confirm all expected policies now exist
SELECT
    tablename,
    policyname,
    cmd,
    qual
FROM pg_policies
WHERE tablename IN (
    'incidents', 'dispatch_log', 'stations',
    'rubric_configs', 'rubric_audit_log', 'agencies'
)
ORDER BY tablename, policyname;

-- Confirm the new helper function exists
SELECT
    proname,
    prosecdef  -- should be TRUE (SECURITY DEFINER)
FROM pg_proc
WHERE proname = 'get_my_agency_type'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
