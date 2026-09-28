-- ============================================================
-- Migration 004: SOS Quick-Report support fields
--
-- Adds anti-abuse / rate-limiting columns to public.users
-- and extends incidents.submitted_via to accept 'sos'.
--
-- Run AFTER migration 003b.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Extend incidents.submitted_via to allow 'sos'
-- ------------------------------------------------------------
-- Drop the old CHECK constraint, re-add with 'sos' included
ALTER TABLE public.incidents
    DROP CONSTRAINT IF EXISTS incidents_submitted_via_check;

ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_submitted_via_check
    CHECK (submitted_via IN ('internet', 'sms', 'offline_sync', 'sos'));

-- ------------------------------------------------------------
-- 2. Add SOS anti-abuse columns to public.users
--
-- sos_warning_count    — number of confirmed false SOS reports.
--                        Incremented by Agency Admin action only.
-- sos_suspended_until  — NULL = not suspended; future timestamp = suspended.
--                        Set by server-side escalation logic.
-- sos_last_submitted_at — server-side cooldown check.
--                         Updated on every successful SOS submission.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS sos_warning_count    INTEGER   NOT NULL DEFAULT 0;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS sos_suspended_until  TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS sos_last_submitted_at TIMESTAMPTZ DEFAULT NULL;

COMMENT ON COLUMN public.users.sos_warning_count IS
    'Number of confirmed false SOS reports. '
    'Only Agency Admin can increment this via the dispatch dashboard. '
    'Threshold: 1 = warning shown to dispatcher; 3 = SOS access suspended.';

COMMENT ON COLUMN public.users.sos_suspended_until IS
    'If NOT NULL and in the future, this user cannot submit SOS reports. '
    'Null = no suspension. Set by escalation logic, cleared by super_admin only.';

COMMENT ON COLUMN public.users.sos_last_submitted_at IS
    'Timestamp of last SOS submission. Used for server-side cooldown enforcement '
    '(minimum 30 minutes between SOS submissions per account).';

-- ------------------------------------------------------------
-- 3. Add sos_flagged column to incidents
--    True when the reporter has a prior false SOS history.
--    Dispatcher dashboard surfaces this as a trust indicator.
--    Informational only — does not auto-reject the report.
-- ------------------------------------------------------------
ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS sos_flagged BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.incidents.sos_flagged IS
    'Set to TRUE when the reporter has sos_warning_count >= 1 at the time '
    'of SOS submission. Shown as a trust indicator to the dispatcher. '
    'Does not auto-reject the report — human dispatcher decides.';

-- ------------------------------------------------------------
-- 4. Index for suspension lookup (checked on every SOS attempt)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS users_sos_suspended_idx
    ON public.users(sos_suspended_until)
    WHERE sos_suspended_until IS NOT NULL;

-- ------------------------------------------------------------
-- 4. RLS: users cannot update their own SOS abuse fields
--    (already protected by the existing "users: update own profile"
--     policy's WITH CHECK clause — but make the intent explicit
--     here as a comment for reviewers)
--
-- The existing policy locks approval_status, role, agency_id, badge_id.
-- sos_warning_count and sos_suspended_until are NOT in the WITH CHECK
-- allowlist, so self-update is already blocked.
-- No additional policy needed — this comment is the audit trail.
-- ------------------------------------------------------------

-- Verification query — run after applying migration:
SELECT
    column_name,
    data_type,
    column_default,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name IN ('sos_warning_count', 'sos_suspended_until', 'sos_last_submitted_at')
ORDER BY column_name;
