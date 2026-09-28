-- ============================================================
-- Migration 036: Cross-agency assist requests
--
-- Lets the agency currently handling an incident ask another agency
-- present in the same municipality for help — see
-- docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md
-- for the full design and why it is shaped this way.
--
-- TWO TABLES, MATCHING THE incidents/incident_notes SPLIT
--
-- incident_assist_requests is the mutable envelope (status changes over
-- time, same as incidents.status). incident_assist_messages is an
-- append-only log (never edited/deleted), same reasoning as migration
-- 030's incident_notes: a message is evidence of what was said and when.
--
-- THE RECEIVING AGENCY NEVER GETS INCIDENT ACCESS
--
-- incidents RLS is completely untouched by this migration. The
-- application layer (assist_request_service.py) projects a narrow,
-- live snapshot (category/severity/location) into API responses —
-- these two tables never copy incident columns, and the receiving
-- agency's RLS grant here is scoped to THESE tables only.
--
-- NO sender_role COLUMN on incident_assist_messages, unlike
-- incident_notes.author_role — every writer here is an agency_admin by
-- construction of the INSERT policy below (super_admin is read-only
-- oversight, mobile/responder is out of scope), so there is no role
-- variability for a denormalized column to preserve.
--
-- NOT added to the supabase_realtime publication. The design spec
-- chose fast polling over giving the dashboard its first-ever direct
-- Supabase Realtime subscription — nothing will subscribe to this
-- table, so publishing it would be pure overhead.
--
-- Requires: migrations 002 (incidents, users), 001d (get_my_role,
-- get_my_agency_id helpers). Idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.incident_assist_requests (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id           UUID NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
    requesting_agency_id  UUID NOT NULL REFERENCES public.agencies(id),
    requested_agency_id   UUID NOT NULL REFERENCES public.agencies(id),
    overlap_flag          TEXT,
    status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'acknowledged', 'declined')),
    requested_by          UUID NOT NULL REFERENCES public.users(id),
    responded_by          UUID REFERENCES public.users(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at          TIMESTAMPTZ,
    CONSTRAINT incident_assist_requests_distinct_agencies
        CHECK (requested_agency_id <> requesting_agency_id)
);

COMMENT ON TABLE public.incident_assist_requests IS
    'One row per "please help on this incident" request between two agencies. '
    'status is the only mutable field. See migration 036''s header.';

CREATE INDEX IF NOT EXISTS incident_assist_requests_incident_idx
    ON public.incident_assist_requests (incident_id);
CREATE INDEX IF NOT EXISTS incident_assist_requests_requesting_idx
    ON public.incident_assist_requests (requesting_agency_id, status);
CREATE INDEX IF NOT EXISTS incident_assist_requests_requested_idx
    ON public.incident_assist_requests (requested_agency_id, status);

CREATE TABLE IF NOT EXISTS public.incident_assist_messages (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id        UUID NOT NULL REFERENCES public.incident_assist_requests(id) ON DELETE CASCADE,
    sender_agency_id  UUID NOT NULL REFERENCES public.agencies(id),
    sender_id         UUID NOT NULL REFERENCES public.users(id),
    body              TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- append-only — no updated_at, no UPDATE/DELETE policy below.
);

COMMENT ON TABLE public.incident_assist_messages IS
    'Append-only chat scoped to one incident_assist_requests row. See migration 036''s header.';

CREATE INDEX IF NOT EXISTS incident_assist_messages_request_idx
    ON public.incident_assist_messages (request_id, created_at);

GRANT ALL ON public.incident_assist_requests TO service_role;
GRANT ALL ON public.incident_assist_messages TO service_role;

ALTER TABLE public.incident_assist_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incident_assist_messages ENABLE ROW LEVEL SECURITY;

-- ── incident_assist_requests policies ───────────────────────────────

DROP POLICY IF EXISTS "incident_assist_requests: party agencies and super_admin read" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: party agencies and super_admin read"
    ON public.incident_assist_requests FOR SELECT
    USING (
        public.get_my_role() = 'super_admin'
        OR (
            public.get_my_role() = 'agency_admin'
            AND (
                requesting_agency_id = public.get_my_agency_id()
                OR requested_agency_id = public.get_my_agency_id()
            )
        )
    );

DROP POLICY IF EXISTS "incident_assist_requests: requester inserts" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: requester inserts"
    ON public.incident_assist_requests FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND requesting_agency_id = public.get_my_agency_id()
        AND requested_by = auth.uid()
    );

-- Status transitions only, only by the agency being asked. No DELETE.
DROP POLICY IF EXISTS "incident_assist_requests: requested agency responds" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: requested agency responds"
    ON public.incident_assist_requests FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND requested_agency_id = public.get_my_agency_id()
    );

-- ── incident_assist_messages policies ───────────────────────────────

DROP POLICY IF EXISTS "incident_assist_messages: party agencies and super_admin read" ON public.incident_assist_messages;
CREATE POLICY "incident_assist_messages: party agencies and super_admin read"
    ON public.incident_assist_messages FOR SELECT
    USING (
        public.get_my_role() = 'super_admin'
        OR (
            public.get_my_role() = 'agency_admin'
            AND EXISTS (
                SELECT 1 FROM public.incident_assist_requests r
                WHERE r.id = incident_assist_messages.request_id
                  AND (
                      r.requesting_agency_id = public.get_my_agency_id()
                      OR r.requested_agency_id = public.get_my_agency_id()
                  )
            )
        )
    );

DROP POLICY IF EXISTS "incident_assist_messages: party agencies write" ON public.incident_assist_messages;
CREATE POLICY "incident_assist_messages: party agencies write"
    ON public.incident_assist_messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid()
        AND public.get_my_role() = 'agency_admin'
        AND sender_agency_id = public.get_my_agency_id()
        AND EXISTS (
            SELECT 1 FROM public.incident_assist_requests r
            WHERE r.id = incident_assist_messages.request_id
              AND (
                  r.requesting_agency_id = public.get_my_agency_id()
                  OR r.requested_agency_id = public.get_my_agency_id()
              )
        )
    );

-- ============================================================
-- Verification
--
-- Expect: 2 rows, rowsecurity = t for both, service_role_can_read = t for
-- both, policy_count = 3 for incident_assist_requests (SELECT/INSERT/UPDATE),
-- policy_count = 2 for incident_assist_messages (SELECT/INSERT).
-- ============================================================
SELECT c.relname                                             AS table_name,
       c.relrowsecurity                                      AS rls_enabled,
       has_table_privilege('service_role', c.oid, 'SELECT')  AS service_role_can_read,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('incident_assist_requests', 'incident_assist_messages')
ORDER BY c.relname;
