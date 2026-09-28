-- ============================================================
-- Migration 018: service_role grants for the rubric tables
--
-- Fixes a 500 on every rubric endpoint.
--
-- rubric_configs and rubric_audit_log were created in migration 007 with RLS
-- policies but WITHOUT table-level GRANTs to service_role. RLS and GRANTs are
-- independent checks: service_role bypasses RLS, but it still needs the
-- underlying privilege, so every read failed with
--
--   42501  permission denied for table rubric_configs
--   42501  permission denied for table rubric_audit_log
--
-- Symptom: an Agency Admin opening Rubric Config got "Internal server error",
-- and GET /rubric/{agency_type}/configs and /audit-log both 500'd. The rubric
-- engine itself kept working because it silently falls back to the bundled
-- seed file when no active config can be read — which is exactly why this went
-- unnoticed: severity scoring appeared fine while the configuration UI was
-- entirely inaccessible.
--
-- This is the same omission migration 017 corrected for barangays and
-- access_requests. Same remedy, same reasoning: creating a table does not
-- grant anything to service_role.
--
-- Run AFTER migration 017.
-- ============================================================

GRANT ALL ON public.rubric_configs   TO service_role;
GRANT ALL ON public.rubric_audit_log TO service_role;

-- ------------------------------------------------------------
-- Verification — expect service_role to appear for BOTH tables
-- with INSERT/SELECT/UPDATE/DELETE present.
-- ------------------------------------------------------------
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('rubric_configs', 'rubric_audit_log')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;
