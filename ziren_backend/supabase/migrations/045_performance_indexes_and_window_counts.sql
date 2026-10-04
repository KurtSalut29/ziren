-- 045: query performance for growing data
--
-- Run once in the Supabase SQL Editor. Safe to re-run (IF NOT EXISTS /
-- CREATE OR REPLACE). Answers the ISO / white-box evaluator's findings of
-- 2026-10-05:
--
--   #16 Operational Area statistics, #17 the map endpoint and #18 Incident
--       Records all filter incidents by agency and time. The existing indexes
--       cover each column on its own; these composite ones match the way the
--       queries actually filter (agency, then newest first; or agency and
--       status), so a deep page of history or a year-long window stops
--       reading the whole table.
--
--   #18 Incident Records' summary tiles ran five more queries on every page
--       (three counts, then two row fetches for the response-time average and
--       the station tally). Those two fetches had no range, so PostgREST's
--       default row cap of 1,000 applied: on a window with more incidents the
--       average and the tally were computed from an arbitrary first thousand
--       and were silently wrong. incident_window_counts() returns all six
--       figures from one query over the whole filtered window. The backend
--       falls back to its old path when this function does not exist yet.

-- =============================================================================
-- 1. Indexes shaped like the queries
-- =============================================================================

CREATE INDEX IF NOT EXISTS incidents_agency_created_idx
    ON public.incidents (assigned_agency_id, created_at DESC);

CREATE INDEX IF NOT EXISTS incidents_agency_status_idx
    ON public.incidents (assigned_agency_id, status);

CREATE INDEX IF NOT EXISTS incidents_status_created_idx
    ON public.incidents (status, created_at DESC);

CREATE INDEX IF NOT EXISTS incidents_responder_status_idx
    ON public.incidents (assigned_responder_id, status)
    WHERE assigned_responder_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS notifications_recipient_created_idx
    ON public.notifications (recipient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS incident_notes_incident_created_idx
    ON public.incident_notes (incident_id, created_at);

-- =============================================================================
-- 2. Incident Records' summary in one query
-- =============================================================================

CREATE OR REPLACE FUNCTION public.incident_window_counts(
    p_since          TIMESTAMPTZ DEFAULT NULL,
    p_until          TIMESTAMPTZ DEFAULT NULL,
    p_status         TEXT        DEFAULT NULL,   -- a status, or 'open' = not resolved/cancelled
    p_severity       TEXT        DEFAULT NULL,
    p_category       TEXT        DEFAULT NULL,
    p_station_id     UUID        DEFAULT NULL,
    p_record_prefix  TEXT        DEFAULT NULL,
    p_agency_ids     UUID[]      DEFAULT NULL    -- NULL = no agency filter
)
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    WITH w AS (
        SELECT i.status, i.severity, i.station_id, i.created_at, i.dispatched_at
        FROM public.incidents i
        WHERE (p_since IS NULL OR i.created_at >= p_since)
          AND (p_until IS NULL OR i.created_at <  p_until)
          AND (
                p_status IS NULL
             OR (p_status = 'open' AND i.status NOT IN ('resolved', 'cancelled'))
             OR (p_status <> 'open' AND i.status = p_status)
          )
          AND (p_severity      IS NULL OR i.severity = p_severity)
          AND (p_category      IS NULL OR i.incident_category = p_category)
          AND (p_station_id    IS NULL OR i.station_id = p_station_id)
          AND (p_record_prefix IS NULL OR i.record_number LIKE p_record_prefix || '%')
          AND (p_agency_ids    IS NULL OR i.assigned_agency_id = ANY (p_agency_ids))
    )
    SELECT json_build_object(
        'total',                   count(*),
        'critical',                count(*) FILTER (WHERE severity = 'critical'),
        'resolved',                count(*) FILTER (WHERE status = 'resolved'),
        'cancelled',               count(*) FILTER (WHERE status = 'cancelled'),
        'avg_response_minutes',    round((avg(EXTRACT(EPOCH FROM (dispatched_at - created_at)) / 60.0)
                                          FILTER (WHERE dispatched_at IS NOT NULL))::numeric, 1),
        'stations_with_incidents', count(DISTINCT station_id)
    )
    FROM w;
$$;

COMMENT ON FUNCTION public.incident_window_counts IS
    'Incident Records summary tiles over the whole filtered window in one query '
    '(migration 045). Called by the backend with the service key; the caller''s '
    'agency scope is passed in p_agency_ids.';

REVOKE ALL ON FUNCTION public.incident_window_counts(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, UUID, TEXT, UUID[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.incident_window_counts(TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, UUID, TEXT, UUID[]) TO service_role;

-- =============================================================================
-- Verification -- expect six index rows and one function row.
-- =============================================================================
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN ('incidents_agency_created_idx', 'incidents_agency_status_idx',
                    'incidents_status_created_idx', 'incidents_responder_status_idx',
                    'notifications_recipient_created_idx', 'incident_notes_incident_created_idx')
ORDER BY 1;

SELECT proname FROM pg_proc WHERE proname = 'incident_window_counts';
