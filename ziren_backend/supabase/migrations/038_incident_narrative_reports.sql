-- ============================================================
-- Migration 038: Incident Narrative Reports
--
-- WHAT THIS IS
--
-- Modelled on the police "Item D — Narrative of Incident" blotter form
-- (and its BFP/MDRRMO equivalents): once an incident is resolved, the
-- Agency Admin writes a full prose account of what actually happened —
-- the who/what/when/where/why/how as CONFIRMED after the fact, not the
-- resident's initial report or the crew's brief outcome tally
-- (incidents.outcome/outcome_notes, migration 024). Those two already
-- answer "was it handled" in a sentence; this is the citable document an
-- agency files, prints, or hands to another office.
--
-- ONE ROW PER INCIDENT, NOT DENORMALISED
--
-- Every fact the paper form also asks for that Ziren already has on the
-- incident (reporter, station, agency, timestamps) is read live through
-- the existing incidents/stations/agencies/users joins — the dashboard
-- already fetches all of it via GET /dispatch/queue/{id}. This table
-- holds only what does NOT already exist elsewhere: the narrative prose
-- itself, and the handful of fields a real report sometimes needs to
-- STATE DIFFERENTLY than the system's own record (e.g. the incident was
-- discovered earlier than it was reported, or the resident's registered
-- name differs from who a witness statement names) — see each column's
-- own comment.
--
-- DRAFT / FINALIZED, NO DELETE, EDITABLE AFTER FINALIZING
--
-- Unlike incident_notes (append-only, evidence of what was communicated
-- and when), a narrative report is a document being WRITTEN — an Agency
-- Admin drafts it over multiple sittings before it says what they mean.
-- `status` tracks that; `finalized_at`/`finalized_by` record the moment
-- it was signed off. Finalizing does not lock the row: a real report
-- still gets corrected after the fact, and the service layer's job is to
-- keep `updated_at`/`updated_by` honest, not to forbid the edit. No
-- DELETE policy — once written, a narrative report is retained the same
-- way dispatch_log is.
--
-- WHO
--
-- Agency Admin writes (own agency only — narrative reports are filed by
-- the agency that ran the incident, the same population that can Resolve
-- it — see dispatch.py's `_dispatcher`). Provincial Admin reads, same
-- oversight-only split as every other agency-scoped table since
-- migration 034 (see that migration's header and 037's for the pattern
-- this copies). No responder or resident access — this is an
-- agency-internal record, not part of the resident-facing thread.
--
-- Requires: migrations 002 (incidents, users), 034 (get_my_agency_type,
-- provincial_admin role). Idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.incident_narrative_reports (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id             UUID NOT NULL UNIQUE REFERENCES public.incidents(id) ON DELETE CASCADE,

    -- The account itself — free prose, the who/what/when/where/why/how as
    -- confirmed after the incident closed. Required: a report with no
    -- narrative is not a report.
    narrative               TEXT NOT NULL,

    -- Overrides of facts Ziren already has, for when the written record
    -- needs to state something the live data does not (or no longer can,
    -- e.g. the reporter's account was later deleted). NULL means "use the
    -- incident's own data" — the service fills these as defaults when the
    -- form first opens, but never forces a value into the row.
    reporting_person_name   TEXT,
    incident_occurred_at    TIMESTAMPTZ,
    place_of_incident       TEXT,

    -- Who wrote it up and who investigated, as this document should read
    -- when printed — independent of whichever admin account happened to
    -- be logged in when it was saved (created_by/updated_by, below, are
    -- that audit trail; these are the human-readable byline).
    prepared_by_name        TEXT,
    investigator_name       TEXT,

    -- The agency's own filing number (a PNP blotter entry number, a BFP
    -- incident report number, an MDRRMO log number) — free text because
    -- each agency's numbering is its own and Ziren does not assign one.
    -- Not incidents.record_number: that is Ziren's internal ZIR-#######
    -- id, already shown elsewhere on this same document.
    reference_no            TEXT,

    status                  TEXT NOT NULL DEFAULT 'draft'
                                 CHECK (status IN ('draft', 'finalized')),
    finalized_at            TIMESTAMPTZ,
    finalized_by            UUID REFERENCES public.users(id) ON DELETE SET NULL,

    created_by              UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    updated_by              UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.incident_narrative_reports IS
    'One prose narrative report per incident, written by the Agency Admin '
    'after resolution — modelled on the police blotter "Narrative of '
    'Incident" form. See this migration''s header.';

CREATE INDEX IF NOT EXISTS incident_narrative_reports_incident_idx
    ON public.incident_narrative_reports (incident_id);

GRANT ALL ON public.incident_narrative_reports TO service_role;

ALTER TABLE public.incident_narrative_reports ENABLE ROW LEVEL SECURITY;

-- Read: the incident's own agency_admin, or a provincial_admin of the same
-- agency_type (oversight) — identical population to every other
-- agency-scoped table's SELECT split since migration 034/037.
DROP POLICY IF EXISTS "incident_narrative_reports: agency_admin reads own agency" ON public.incident_narrative_reports;
CREATE POLICY "incident_narrative_reports: agency_admin reads own agency"
    ON public.incident_narrative_reports FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_narrative_reports.incident_id
              AND i.assigned_agency_id = public.get_my_agency_id()
        )
    );

DROP POLICY IF EXISTS "incident_narrative_reports: provincial_admin reads own agency_type" ON public.incident_narrative_reports;
CREATE POLICY "incident_narrative_reports: provincial_admin reads own agency_type"
    ON public.incident_narrative_reports FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_narrative_reports.incident_id
              AND i.assigned_agency_id IN (
                  SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
              )
        )
    );

-- Write: agency_admin only, own agency — a provincial_admin oversees, they
-- do not file a report on another station's behalf (same reasoning as
-- migration 037's header for incident_assist_requests).
DROP POLICY IF EXISTS "incident_narrative_reports: agency_admin inserts own agency" ON public.incident_narrative_reports;
CREATE POLICY "incident_narrative_reports: agency_admin inserts own agency"
    ON public.incident_narrative_reports FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_narrative_reports.incident_id
              AND i.assigned_agency_id = public.get_my_agency_id()
        )
    );

DROP POLICY IF EXISTS "incident_narrative_reports: agency_admin updates own agency" ON public.incident_narrative_reports;
CREATE POLICY "incident_narrative_reports: agency_admin updates own agency"
    ON public.incident_narrative_reports FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_narrative_reports.incident_id
              AND i.assigned_agency_id = public.get_my_agency_id()
        )
    )
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_narrative_reports.incident_id
              AND i.assigned_agency_id = public.get_my_agency_id()
        )
    );

-- ============================================================
-- Verification
--
-- Expect: 1 row, rowsecurity = t, service_role_can_read = t, policy_count = 4
-- (2x SELECT + INSERT + UPDATE, no DELETE — see this migration's header).
-- ============================================================
SELECT c.relname                                             AS table_name,
       c.relrowsecurity                                      AS rls_enabled,
       has_table_privilege('service_role', c.oid, 'SELECT')  AS service_role_can_read,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'incident_narrative_reports';
