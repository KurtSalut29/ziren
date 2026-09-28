-- ============================================================
-- Migration 030: Incident Notes — Agency Admin spec Section 5
-- ("The Agency Admin should also be able to add operational notes.") and
-- Section 18 (Agency Communication).
--
-- WHY ONE TABLE COVERS BOTH SPEC SECTIONS
--
-- Section 18 asks for incident-specific communication between an
-- agency_admin and a responder ("Proceed to the eastern entrance." /
-- "Arrived at location."). Section 5 separately asks for operational notes
-- on an incident. Both are the same shape — an append-only, timestamped,
-- attributed thread tied to one incident — so one table serves both rather
-- than a chat table and a notes table holding identical columns.
--
-- WHAT SHIPS TODAY VS. WHAT DOES NOT
--
-- The dashboard side (agency_admin reading and writing) is fully wired by
-- this migration and the service/router code that follows it. The mobile
-- app has NO screen that reads or writes this table yet — ziren_mobile is
-- out of scope for this pass. Rather than withhold the feature until both
-- sides exist (the same reasoning migration 029 gives for shipping
-- clarification_note without a mobile surface for it), the RLS policies
-- below already allow a responder to read and write their own assigned
-- incident's notes, so the mobile half is pure UI work whenever it is
-- built — no backend or policy changes will be needed then.
--
-- WHY APPEND-ONLY, NO EDIT/DELETE
--
-- Same reasoning as dispatch_log (002): a note is evidence of what was
-- communicated and when. Letting it be edited after the fact would let a
-- record of "what was said" quietly become "what someone wishes had been
-- said". No UPDATE/DELETE policy is granted below.
--
-- Requires: migration 002 (incidents, users). Idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.incident_notes (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id  UUID NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
    author_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    -- Denormalized rather than joined at read time: a note outlives the
    -- possibility that its author's role later changes, and the thread
    -- should keep showing who spoke as what they were AT THE TIME.
    author_role  TEXT NOT NULL CHECK (author_role IN ('agency_admin', 'responder', 'super_admin')),
    body         TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — see header: notes are immutable once posted.
);

COMMENT ON TABLE public.incident_notes IS
    'Append-only, incident-scoped notes/communication (Agency Admin spec '
    'Sections 5 and 18). Dashboard side (agency_admin) is fully wired; the '
    'mobile side (responder) has policy support but no UI yet — see this '
    'migration''s header.';

CREATE INDEX IF NOT EXISTS incident_notes_incident_idx
    ON public.incident_notes (incident_id, created_at);

GRANT ALL ON public.incident_notes TO service_role;

ALTER TABLE public.incident_notes ENABLE ROW LEVEL SECURITY;

-- Read: the incident's own agency (admin or the assigned responder), or
-- any super_admin (oversight, matching every other dispatch-adjacent read).
DROP POLICY IF EXISTS "incident_notes: agency staff and assigned responder read" ON public.incident_notes;
CREATE POLICY "incident_notes: agency staff and assigned responder read"
    ON public.incident_notes FOR SELECT
    USING (
        public.get_my_role() = 'super_admin'
        OR EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_notes.incident_id
              AND (
                  (public.get_my_role() = 'agency_admin' AND i.assigned_agency_id = public.get_my_agency_id())
                  OR (public.get_my_role() = 'responder' AND i.assigned_responder_id = auth.uid())
              )
        )
    );

-- Write: same population as read, MINUS super_admin — oversight sees every
-- note, and writes none, the same split dispatch.py enforces in code
-- between _admin_read and _dispatcher.
DROP POLICY IF EXISTS "incident_notes: agency staff and assigned responder write" ON public.incident_notes;
CREATE POLICY "incident_notes: agency staff and assigned responder write"
    ON public.incident_notes FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_notes.incident_id
              AND (
                  (public.get_my_role() = 'agency_admin' AND i.assigned_agency_id = public.get_my_agency_id())
                  OR (public.get_my_role() = 'responder' AND i.assigned_responder_id = auth.uid())
              )
        )
    );

-- Realtime — so a note posted from the dashboard while a (future) mobile
-- screen is open arrives without a poll, the same reasoning migration 024
-- gives for responder_distress.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'incident_notes'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.incident_notes;
    END IF;
END $$;

-- ============================================================
-- Verification
--
-- Expect: 1 row, rowsecurity = t, service_role_can_read = t, policy_count = 2.
-- ============================================================
SELECT c.relname                                             AS table_name,
       c.relrowsecurity                                      AS rls_enabled,
       has_table_privilege('service_role', c.oid, 'SELECT')  AS service_role_can_read,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'incident_notes';
