-- ============================================================
-- Migration 002b: Grant table permissions to Supabase roles
--
-- RLS policies control row-level access.
-- GRANT controls table-level access.
-- Both are required — RLS alone is not enough.
-- ============================================================

GRANT SELECT, INSERT, UPDATE ON public.users         TO authenticated;
GRANT SELECT, UPDATE         ON public.agencies      TO authenticated;
GRANT SELECT                 ON public.stations      TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.incidents     TO authenticated;
GRANT SELECT, INSERT         ON public.dispatch_log  TO authenticated;

GRANT ALL ON public.users        TO service_role;
GRANT ALL ON public.agencies     TO service_role;
GRANT ALL ON public.stations     TO service_role;
GRANT ALL ON public.incidents    TO service_role;
GRANT ALL ON public.dispatch_log TO service_role;
