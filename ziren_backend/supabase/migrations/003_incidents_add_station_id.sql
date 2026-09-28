-- ============================================================
-- Migration 003: Add station_id to incidents table
--
-- Station selection is now manual (Resident-driven).
-- Every new incident submission must include a station_id.
-- Existing rows left NULL — they were submitted before this
-- field existed and cannot be back-filled.
-- ============================================================

ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS station_id UUID REFERENCES public.stations(id) ON DELETE SET NULL;

-- Index for agency-scoped queries (dispatcher sees incidents for their station)
CREATE INDEX IF NOT EXISTS incidents_station_idx ON public.incidents(station_id);

-- Comment for clarity
COMMENT ON COLUMN public.incidents.station_id IS
    'The station manually selected by the Resident at report time. '
    'Drives dispatch routing. Phase 9 validates this against actual GPS coverage area.';
