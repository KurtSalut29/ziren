-- ============================================================
-- Migration 037: Provincial Admin oversight read on assist requests
--
-- Migration 036 (cross-agency assist requests) gave read access to
-- "party agencies and super_admin" -- but migration 034 had already
-- replaced super_admin with provincial_admin province-wide, weeks
-- earlier in this same migration sequence. That clause has been dead
-- since the day 036 was written: users_role_check (034) does not allow
-- the value 'super_admin' at all, so `get_my_role() = 'super_admin'`
-- can never be true. The practical effect was the one this migration
-- fixes -- provincial_admin had NO visibility into assist requests,
-- unlike every other agency-scoped table (incidents, incident_notes,
-- dispatch_log), which all give provincial_admin oversight read across
-- every station of their own agency_type. See migration 034's header
-- for that pattern and get_my_agency_type().
--
-- READ ONLY. The design spec's Global Constraints (see
-- docs/superpowers/plans/2026-09-20-cross-agency-assist-requests.md)
-- explicitly excluded provincial_admin write access -- a provincial
-- admin oversees, they do not act on a specific station's behalf. Only
-- the two SELECT policies are replaced; INSERT/UPDATE stay agency_admin
-- only, untouched.
--
-- SCOPE: "own agency_type on EITHER side" -- a BFP provincial admin
-- sees a BFP station's requests whether that station asked for help or
-- was asked for it, mirroring how they already see every BFP station's
-- incidents regardless of direction of the dispatch.
--
-- Run AFTER migration 036.
-- ============================================================

-- ── incident_assist_requests ─────────────────────────────────────────

DROP POLICY IF EXISTS "incident_assist_requests: party agencies and super_admin read" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: party agencies read"
    ON public.incident_assist_requests FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND (
            requesting_agency_id = public.get_my_agency_id()
            OR requested_agency_id = public.get_my_agency_id()
        )
    );

DROP POLICY IF EXISTS "incident_assist_requests: provincial_admin reads own scope" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: provincial_admin reads own scope"
    ON public.incident_assist_requests FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND (
            requesting_agency_id IN (SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type())
            OR requested_agency_id IN (SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type())
        )
    );

-- ── incident_assist_messages ─────────────────────────────────────────

DROP POLICY IF EXISTS "incident_assist_messages: party agencies and super_admin read" ON public.incident_assist_messages;
CREATE POLICY "incident_assist_messages: party agencies read"
    ON public.incident_assist_messages FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND EXISTS (
            SELECT 1 FROM public.incident_assist_requests r
            WHERE r.id = incident_assist_messages.request_id
              AND (
                  r.requesting_agency_id = public.get_my_agency_id()
                  OR r.requested_agency_id = public.get_my_agency_id()
              )
        )
    );

DROP POLICY IF EXISTS "incident_assist_messages: provincial_admin reads own scope" ON public.incident_assist_messages;
CREATE POLICY "incident_assist_messages: provincial_admin reads own scope"
    ON public.incident_assist_messages FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND EXISTS (
            SELECT 1 FROM public.incident_assist_requests r
            WHERE r.id = incident_assist_messages.request_id
              AND (
                  r.requesting_agency_id IN (SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type())
                  OR r.requested_agency_id IN (SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type())
              )
        )
    );

-- ============================================================
-- Verification
--
-- Expect: policy_count = 4 for incident_assist_requests
-- (2x SELECT + INSERT + UPDATE), policy_count = 3 for
-- incident_assist_messages (2x SELECT + INSERT).
-- ============================================================
SELECT c.relname AS table_name,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('incident_assist_requests', 'incident_assist_messages')
ORDER BY c.relname;
