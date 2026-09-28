-- ============================================================
-- Migration 035: Incident record numbers
--
-- Incident History became Incident Records — a table where each incident is a
-- citable record. A record needs a number a person can read out, write on a
-- form and search by. Until now an incident's only identity was its UUID,
-- which is neither.
--
-- FORMAT   ZIR-2026-000123
--   ZIR   fixed prefix (this system), so a number is recognisable on paper.
--   2026  year the incident was FILED, in Philippine time — an incident filed
--         at 00:30 on 1 January belongs to the new year even though it is
--         still 31 December in UTC.
--   000123 one global sequence, zero-padded to six digits (grows past six
--         rather than wrapping — the CHECK allows six or more).
--
-- WHY NO AGENCY PREFIX (BFP-2026-…)
--   An incident's agency is not known when it is filed, and routing can move
--   it afterwards. A prefix baked into an official record would then be wrong
--   for good. The agency is its own column on the table instead.
--
-- WHY A TRIGGER, NOT APPLICATION CODE
--   Incidents are created by more than one path (resident report, SOS, SMS
--   inbound). Numbering in Python would mean every path has to remember, and
--   the one that forgot would create records with no number. The database is
--   the one place every insert passes through.
--   The function is SECURITY DEFINER so the insert works for whichever role
--   performs it without that role being granted the sequence directly.
--
-- IMMUTABLE ONCE ASSIGNED
--   A record number that can be edited is not an identifier. A second trigger
--   refuses to change or clear it.
--
-- BACKFILL
--   Existing incidents are numbered in filing order (created_at, then id) so
--   the sequence reads chronologically. The loop, not a single UPDATE, is what
--   guarantees that order: nextval() inside an UPDATE ... FROM is evaluated in
--   whatever order the planner scans.
--   The backfill would otherwise stamp EVERY existing incident "updated just
--   now" through the incidents_updated_at trigger and destroy that signal for
--   the whole history, so that trigger is paused for the duration and
--   restored in the same transaction.
--
-- Requires: migration 002 (incidents, incidents_updated_at). Idempotent.
-- Run in Supabase SQL Editor AFTER 034.
-- ============================================================

BEGIN;

CREATE SEQUENCE IF NOT EXISTS public.incident_record_seq;

ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS record_number TEXT;

-- One place that knows the format, used by the trigger and the backfill alike.
CREATE OR REPLACE FUNCTION public.next_incident_record_number(filed_at TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 'ZIR-'
        || to_char(COALESCE(filed_at, now()) AT TIME ZONE 'Asia/Manila', 'YYYY')
        || '-'
        || lpad(nextval('public.incident_record_seq')::text, 6, '0');
$$;

CREATE OR REPLACE FUNCTION public.assign_incident_record_number()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.record_number IS NULL THEN
        NEW.record_number := public.next_incident_record_number(NEW.created_at);
    END IF;
    RETURN NEW;
END;
$$;

-- Functions are executable by PUBLIC by default, and Supabase exposes public
-- functions over RPC. Left open, any signed-in user could call this
-- SECURITY DEFINER function directly and burn sequence numbers, leaving gaps
-- in the record series. Only the database itself (via the trigger, which runs
-- as the function's owner) and the backend need it.
REVOKE ALL ON FUNCTION public.next_incident_record_number(TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_incident_record_number(TIMESTAMPTZ) TO service_role;

DROP TRIGGER IF EXISTS incidents_assign_record_number ON public.incidents;
CREATE TRIGGER incidents_assign_record_number
    BEFORE INSERT ON public.incidents
    FOR EACH ROW EXECUTE FUNCTION public.assign_incident_record_number();

-- Backfill, oldest first. Only rows with no number yet, so a re-run is a no-op.
ALTER TABLE public.incidents DISABLE TRIGGER incidents_updated_at;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT id, created_at
        FROM   public.incidents
        WHERE  record_number IS NULL
        ORDER  BY created_at, id
    LOOP
        UPDATE public.incidents
        SET    record_number = public.next_incident_record_number(r.created_at)
        WHERE  id = r.id;
    END LOOP;
END;
$$;

ALTER TABLE public.incidents ENABLE TRIGGER incidents_updated_at;

-- Only now that every row has one.
ALTER TABLE public.incidents
    ALTER COLUMN record_number SET NOT NULL;

ALTER TABLE public.incidents
    DROP CONSTRAINT IF EXISTS incidents_record_number_format_check;
ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_record_number_format_check
    CHECK (record_number ~ '^ZIR-[0-9]{4}-[0-9]{6,}$');

-- Unique, and it is also the index the record_no lookup (LIKE 'ZIR-2026-0001%')
-- runs against. text_pattern_ops lets a prefix match use the index under a
-- non-C collation, which a plain unique index would not.
CREATE UNIQUE INDEX IF NOT EXISTS incidents_record_number_key
    ON public.incidents (record_number text_pattern_ops);

-- Guard, created AFTER the backfill so the backfill's own UPDATEs (NULL -> value)
-- are the one change it would have to allow anyway.
CREATE OR REPLACE FUNCTION public.protect_incident_record_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.record_number IS NOT NULL
       AND NEW.record_number IS DISTINCT FROM OLD.record_number THEN
        RAISE EXCEPTION 'incidents.record_number is assigned once and cannot be changed'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS incidents_protect_record_number ON public.incidents;
CREATE TRIGGER incidents_protect_record_number
    BEFORE UPDATE ON public.incidents
    FOR EACH ROW EXECUTE FUNCTION public.protect_incident_record_number();

-- No new table, so no table GRANT: incidents already carries service_role's
-- privileges and a new column inherits them. The sequence is the new object.
GRANT USAGE, SELECT ON SEQUENCE public.incident_record_seq TO service_role;

COMMENT ON COLUMN public.incidents.record_number IS
    'Citable record number, ZIR-YYYY-NNNNNN, assigned once by trigger at insert '
    '(migration 035). YYYY is the filing year in Asia/Manila. Immutable.';

COMMIT;

-- ============================================================
-- Verification
--
-- Expect one row where:
--   incidents       = numbered        (nothing left without a number)
--   distinct_numbers = incidents      (no duplicates)
--   first_number    ends in 000001 or the lowest sequence value, and belongs
--                   to the OLDEST incident
--   triggers        = 3               (updated_at, assign, protect)
--   updated_at_untouched = t          (no row was stamped by the backfill:
--                   nothing was modified in the last 5 minutes that was not
--                   already recent before this ran — if this reads f on a
--                   busy database, judge by the oldest rows instead)
-- ============================================================
SELECT
    count(*)                                                AS incidents,
    count(record_number)                                    AS numbered,
    count(DISTINCT record_number)                           AS distinct_numbers,
    (SELECT record_number FROM public.incidents ORDER BY created_at, id LIMIT 1) AS first_number,
    (SELECT count(*) FROM pg_trigger
      WHERE tgrelid = 'public.incidents'::regclass
        AND tgname IN ('incidents_updated_at',
                       'incidents_assign_record_number',
                       'incidents_protect_record_number')
        AND NOT tgisinternal)                               AS triggers,
    (SELECT max(updated_at) FROM (
        SELECT updated_at FROM public.incidents ORDER BY created_at, id LIMIT 1
     ) oldest) < now() - interval '5 minutes'               AS updated_at_untouched
FROM public.incidents;
