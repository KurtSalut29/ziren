-- ============================================================
-- Migration 011: Responder location field
--
-- Adds a PostGIS POINT column to public.users for Responders so
-- the Map view can render their last-known position.
--
-- Design notes:
--   - Only rows where role = 'responder' will ever have this set;
--     all other roles leave it NULL.
--   - Updated by the mobile app via PATCH /responder/location
--     (endpoint added in Phase 6C backend work).
--   - RLS: Responder can only update their own row (existing
--     "users: update own profile" policy). Agency Admin / Super
--     Admin can read via the service key — no new policy needed.
--
-- Run AFTER migration 010.
-- ============================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS location GEOMETRY(POINT, 4326);

CREATE INDEX IF NOT EXISTS users_responder_location_idx
    ON public.users USING GIST(location)
    WHERE role = 'responder';

COMMENT ON COLUMN public.users.location IS
    'Last-known GPS position for Responders (updated by mobile app). '
    'NULL for all non-Responder roles. EPSG:4326.';

-- Verification
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name  = 'location';
