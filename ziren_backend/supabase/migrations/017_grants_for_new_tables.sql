-- ============================================================
-- Migration 017: Grants for the tables added in 012 and 016
--
-- Fixes: "Could not submit your request right now. Please try again shortly."
--
-- Both new tables were created with RLS policies but no GRANTs for
-- service_role. RLS and GRANT are separate gates in Postgres — a policy that
-- permits a row is irrelevant if the role has no table privilege at all — so
-- every call from the FastAPI backend failed with:
--
--   42501: permission denied for table access_requests
--
-- The backend connects as service_role (see app/db/supabase_client.py), which
-- is exactly the role both migrations forgot. 002b_grant_permissions.sql sets
-- the pattern for every earlier table:
--
--   GRANT ALL ON <table> TO service_role;
--
-- and 012/016 simply did not follow it. Worth noting the failure mode: the
-- surfaced error said "try again shortly", which was wrong — a missing GRANT
-- is permanent, and no amount of retrying would have fixed it. That message
-- has been corrected alongside this migration.
--
-- Idempotent. Run AFTER 016.
-- ============================================================

-- Backend runs as service_role and bypasses RLS by design.
GRANT ALL ON public.barangays       TO service_role;
GRANT ALL ON public.access_requests TO service_role;

-- Reference data: the registration form reads this before the user has a
-- session, so anon needs SELECT (012 granted this, restated here so a fresh
-- database gets the full picture from one file).
GRANT SELECT ON public.barangays TO anon, authenticated;

-- access_requests is deliberately NOT granted to anon or authenticated.
-- Submissions go through the rate-limited API; direct writes would let anyone
-- flood the table, and direct reads would expose which officials have applied.

-- ------------------------------------------------------------
-- Verification — should list service_role for both tables
-- ------------------------------------------------------------
SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('barangays', 'access_requests')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;
