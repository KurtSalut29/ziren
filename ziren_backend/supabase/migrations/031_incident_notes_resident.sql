-- ============================================================
-- Migration 031: Incident Notes — Resident side
--
-- Migration 030 shipped incident_notes for agency_admin/responder/
-- super_admin, and deliberately left the resident half unbuilt (its header:
-- "ziren_mobile is out of scope for this pass"). This is that pass —
-- Resident spec Section 14 ("Add Information to an Existing Report") and
-- Section 16 ("Incident-Specific Communication") are the same request from
-- the resident's side of the same thread: let the reporter add a follow-up
-- ("3 people still inside") without filing a second incident, and let them
-- see whatever the agency writes back.
--
-- One table still covers all three roles' use of it — see 030's header for
-- why a single append-only thread beats a notes table plus a chat table.
--
-- WHY THE RESIDENT CANNOT SEE agency_admin/responder AUTHORED NOTES
--
-- Not true — they can. A resident who owns the incident sees the WHOLE
-- thread, same as an agency_admin sees the whole thread for their agency's
-- incident. What is scoped is WHICH incident's thread you can see at all,
-- not which authors within it — an agency's operational shorthand
-- ("proceed to eastern entrance") is fine for the reporter to read; it is
-- the reporter's own emergency.
--
-- Requires: migration 030. Idempotent.
-- ============================================================

-- The CHECK constraint has no direct "ADD VALUE" — drop and recreate.
ALTER TABLE public.incident_notes DROP CONSTRAINT IF EXISTS incident_notes_author_role_check;
ALTER TABLE public.incident_notes
    ADD CONSTRAINT incident_notes_author_role_check
    CHECK (author_role IN ('agency_admin', 'responder', 'super_admin', 'resident'));

COMMENT ON TABLE public.incident_notes IS
    'Append-only, incident-scoped notes/communication (Agency Admin spec '
    'Sections 5 and 18; Resident spec Sections 14 and 16). Reporter, the '
    'assigned agency/responder, and super_admin (oversight, read-only) all '
    'share one thread per incident.';

-- Read: resident who filed the incident, in addition to 030's existing
-- agency-staff/responder/super_admin clause.
DROP POLICY IF EXISTS "incident_notes: agency staff and assigned responder read" ON public.incident_notes;
CREATE POLICY "incident_notes: reporter, agency staff, responder, super_admin read"
    ON public.incident_notes FOR SELECT
    USING (
        public.get_my_role() = 'super_admin'
        OR EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_notes.incident_id
              AND (
                  (public.get_my_role() = 'agency_admin' AND i.assigned_agency_id = public.get_my_agency_id())
                  OR (public.get_my_role() = 'responder' AND i.assigned_responder_id = auth.uid())
                  OR (public.get_my_role() = 'resident' AND i.reporter_id = auth.uid())
              )
        )
    );

-- Write: same population, still minus super_admin (oversight, not a seat in
-- the conversation — unchanged from 030).
DROP POLICY IF EXISTS "incident_notes: agency staff and assigned responder write" ON public.incident_notes;
CREATE POLICY "incident_notes: reporter, agency staff, responder write"
    ON public.incident_notes FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_notes.incident_id
              AND (
                  (public.get_my_role() = 'agency_admin' AND i.assigned_agency_id = public.get_my_agency_id())
                  OR (public.get_my_role() = 'responder' AND i.assigned_responder_id = auth.uid())
                  OR (public.get_my_role() = 'resident' AND i.reporter_id = auth.uid())
              )
        )
    );

-- ============================================================
-- Verification
--
-- Expect: 1 row, rowsecurity = t, policy_count = 2, and the CHECK
-- constraint's definition contains 'resident'.
-- ============================================================
SELECT c.relname                                             AS table_name,
       c.relrowsecurity                                      AS rls_enabled,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'incident_notes';

SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.incident_notes'::regclass AND conname = 'incident_notes_author_role_check';
