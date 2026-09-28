-- ============================================================
-- Migration 040: Narrative reports become the full Incident Record Form
--
-- WHAT THIS ADDS
--
-- Migration 038 stored a narrative report as a page of prose plus a handful of
-- byline fields. The form an agency actually files (the police Incident Record
-- Form, and the BFP / MDRRMO equivalents) is much more than that: Item A the
-- reporting person, Item B every suspect, Item C every victim, Item D the
-- narrative, then the certification and the officers who signed it.
--
-- ONE JSONB COLUMN, NOT A COLUMN PER BOX
--
-- A report holds any number of suspects and victims, and each is a couple of
-- dozen boxes (names, birth date, address, education, occupation, height,
-- eye colour, ...). A column per box would be a schema nobody could keep in
-- step with the form, and a child table per person would buy nothing: these are
-- never queried across incidents, only read and printed as part of one report.
-- So the structured part lives in `details`, and the API (see
-- incident_narrative_service._clean_details) is the only writer, which is what
-- guarantees its shape. Everything that already had a column keeps it.
--
-- NOTHING ELSE CHANGES
--
-- Same row per incident, same draft/finalized lifecycle, same RLS policies (the
-- new column sits under them). The index is for the Narrative Reports library,
-- which lists newest-saved first.
--
-- Until this is applied the app keeps working: it saves what the table can hold
-- and tells the user the detailed sections were not stored.
--
-- Requires: migration 038. Idempotent. Adds one column and one index; touches
-- no existing data.
-- ============================================================

ALTER TABLE public.incident_narrative_reports
    ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.incident_narrative_reports.details IS
    'The Incident Record Form''s structured part: reporting person, suspects, '
    'victims, certification and station contacts. Written only through '
    'incident_narrative_service._clean_details; see migration 040''s header.';

CREATE INDEX IF NOT EXISTS incident_narrative_reports_updated_idx
    ON public.incident_narrative_reports (updated_at DESC);

-- ============================================================
-- Verification -- expect 1 row: column_name = details, data_type = jsonb.
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'incident_narrative_reports'
  AND column_name = 'details';
