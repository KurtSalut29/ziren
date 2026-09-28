-- ============================================================
-- Migration 005: PostGIS coverage-check RPC function
--                + Resident profile columns
--
-- Run AFTER migration 004.
-- ============================================================

-- ------------------------------------------------------------
-- 1. PostGIS helper function: check_station_coverage
--
-- Called via Supabase RPC from the FastAPI backend.
-- Returns whether a GPS point falls within the coverage_area
-- polygon of the agency that owns a given station.
--
-- Parameters:
--   p_station_id UUID   — the station the Resident selected
--   p_lat        FLOAT  — Resident GPS latitude
--   p_lng        FLOAT  — Resident GPS longitude
--
-- Returns table row:
--   within_coverage BOOLEAN
--   station_name    TEXT
--   agency_type     TEXT
--   municipality    TEXT
--   distance_km     FLOAT   — Haversine distance station→reporter (km)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_station_coverage(
    p_station_id UUID,
    p_lat        DOUBLE PRECISION,
    p_lng        DOUBLE PRECISION
)
RETURNS TABLE (
    within_coverage BOOLEAN,
    station_name    TEXT,
    agency_type     TEXT,
    municipality    TEXT,
    distance_km     DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER   -- runs with definer's rights so RLS on agencies is bypassed
AS $$
DECLARE
    v_reporter_point GEOMETRY;
BEGIN
    -- Build a PostGIS point from the reporter's GPS coordinates
    v_reporter_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);

    RETURN QUERY
    SELECT
        -- TRUE if the reporter's point is within the agency's coverage polygon
        CASE
            WHEN a.coverage_area IS NOT NULL
            THEN ST_Within(v_reporter_point, a.coverage_area)
            ELSE TRUE   -- no polygon defined → treat as in-coverage (fail-open)
        END                          AS within_coverage,

        s.name::TEXT                 AS station_name,
        a.agency_type::TEXT          AS agency_type,
        a.municipality::TEXT         AS municipality,

        -- Distance in km between reporter and station point (null if no station location)
        CASE
            WHEN s.location IS NOT NULL
            THEN ROUND(
                ST_Distance(
                    v_reporter_point::GEOGRAPHY,
                    s.location::GEOGRAPHY
                ) / 1000.0,
                2
            )
            ELSE NULL
        END                          AS distance_km

    FROM public.stations  s
    JOIN public.agencies  a ON a.id = s.agency_id
    WHERE s.id = p_station_id
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.check_station_coverage IS
    'Phase 9 — returns coverage mismatch info for a station + GPS coordinate pair. '
    'Fail-open: if coverage_area is NULL, within_coverage = TRUE. '
    'Called by the FastAPI backend via Supabase RPC.';

-- ------------------------------------------------------------
-- 2. Resident profile columns (Phase 10.5)
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS phone_number              TEXT    DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS barangay                  TEXT    DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS municipality_address      TEXT    DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS preferred_language        TEXT    DEFAULT 'Filipino'
        CHECK (preferred_language IN ('Filipino', 'English', 'Bisaya', 'Waray'));

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS push_notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS emergency_contact_name    TEXT    DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS emergency_contact_number  TEXT    DEFAULT NULL;

COMMENT ON COLUMN public.users.phone_number IS
    'Resident''s mobile number for SMS fallback contact. Never logged in plain text.';
COMMENT ON COLUMN public.users.push_notifications_enabled IS
    'Whether the user has enabled push/Realtime status notifications.';
COMMENT ON COLUMN public.users.emergency_contact_name IS
    'Name of the Resident''s emergency contact person.';
COMMENT ON COLUMN public.users.emergency_contact_number IS
    'Phone number of the emergency contact. Never exposed in incident reports.';

-- ------------------------------------------------------------
-- 3. Verification queries
-- ------------------------------------------------------------
-- Confirm function was created:
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name   = 'check_station_coverage';

-- Confirm new user columns:
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name  IN (
      'phone_number', 'barangay', 'municipality_address',
      'preferred_language', 'push_notifications_enabled',
      'emergency_contact_name', 'emergency_contact_number'
  )
ORDER BY column_name;
