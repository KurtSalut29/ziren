-- ============================================================
-- Migration 032: Incident Feedback — Resident spec Section 26
--
-- "After an incident has been resolved, the resident can optionally provide
-- feedback." Star rating (1-5) plus an optional comment, one row per
-- incident. The spec is explicit that feedback must never affect emergency
-- prioritization — this table has no relationship to rubric_service, the
-- severity model, or dispatch ordering, and nothing reads it during triage.
-- It exists purely for admin-side review (Reports & Export, System
-- Analytics), which is why writes are reporter-only and reads add
-- oversight for agency_admin/super_admin rather than everyone.
--
-- WHY ONE ROW PER INCIDENT, NOT PER RESIDENT
--
-- Only the reporter of an incident can ever rate it (enforced by the INSERT
-- policy joining back to incidents.reporter_id), so "one row per incident"
-- and "one row per reporter" are the same constraint here. A UNIQUE on
-- incident_id is simpler than a composite key that would never differ.
--
-- WHY NO UPDATE POLICY
--
-- Same reasoning as incident_notes (030): a rating is what the resident felt
-- at the time. Letting it be revised after the fact invites a rating being
-- edited under pressure rather than reflecting the original experience —
-- and there is no operational need for a correction path the way a
-- transcript has one.
--
-- Requires: migration 002 (incidents, users). Idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.incident_feedback (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id  UUID NOT NULL UNIQUE REFERENCES public.incidents(id) ON DELETE CASCADE,
    reporter_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    rating       SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment      TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.incident_feedback IS
    'Resident spec Section 26 — optional post-resolution rating. Read-only '
    'for admin review; never consulted by triage, rubric_service, or '
    'dispatch ordering.';

CREATE INDEX IF NOT EXISTS incident_feedback_reporter_idx
    ON public.incident_feedback (reporter_id, created_at);

GRANT ALL ON public.incident_feedback TO service_role;

ALTER TABLE public.incident_feedback ENABLE ROW LEVEL SECURITY;

-- Read: the reporter's own feedback, or any agency_admin/super_admin
-- (Reports & Export, System Analytics review) — matches the visibility
-- shape of incident_notes' oversight clause.
DROP POLICY IF EXISTS "incident_feedback: reporter and admin roles read" ON public.incident_feedback;
CREATE POLICY "incident_feedback: reporter and admin roles read"
    ON public.incident_feedback FOR SELECT
    USING (
        reporter_id = auth.uid()
        OR public.get_my_role() IN ('agency_admin', 'super_admin')
    );

-- Write: only the incident's own reporter, and only once the incident is
-- actually resolved — rating a response that has not finished is not what
-- this table is for, and the mobile UI never offers the option before then,
-- but the constraint is server-side because the UI is not the boundary.
DROP POLICY IF EXISTS "incident_feedback: reporter writes own resolved incident" ON public.incident_feedback;
CREATE POLICY "incident_feedback: reporter writes own resolved incident"
    ON public.incident_feedback FOR INSERT
    WITH CHECK (
        reporter_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_feedback.incident_id
              AND i.reporter_id = auth.uid()
              AND i.status = 'resolved'
        )
    );

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
WHERE n.nspname = 'public' AND c.relname = 'incident_feedback';
