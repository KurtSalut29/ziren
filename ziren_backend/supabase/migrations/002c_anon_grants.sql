-- ============================================================
-- Migration 002c: Grant anon access to public reference data
--
-- agencies and stations are public reference data needed during
-- Responder registration (before the user is authenticated).
-- ============================================================

GRANT SELECT ON public.agencies TO anon;
GRANT SELECT ON public.stations TO anon;

DROP POLICY IF EXISTS "agencies: public read" ON public.agencies;
CREATE POLICY "agencies: public read"
    ON public.agencies FOR SELECT
    TO anon, authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "stations: public read" ON public.stations;
CREATE POLICY "stations: public read"
    ON public.stations FOR SELECT
    TO anon, authenticated
    USING (TRUE);
