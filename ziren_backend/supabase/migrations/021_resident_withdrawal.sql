-- ============================================================
-- Migration 021: a resident can withdraw their own report
--
-- Residents had no way to take back a report. The only cancel path was
-- dispatcher-side (POST /dispatch/queue/{id}/cancel), which writes to
-- dispatch_log and requires a dispatcher identity and an agency. A resident
-- who tapped submit by mistake, or whose neighbour turned out to be fine, had
-- to leave a false report sitting in the queue for somebody to triage.
--
-- Why the withdrawal is recorded HERE and not in dispatch_log
-- -----------------------------------------------------------
-- dispatch_log.agency_id is NOT NULL REFERENCES agencies(id), and
-- dispatch_log.dispatcher_id is NOT NULL REFERENCES users(id). A resident
-- withdrawal has no agency at all — it happens before dispatch, by definition
-- (see the status guard in incident_service.withdraw_incident). Forcing a row
-- in would mean inventing an agency_id and filing a resident under
-- `dispatcher_id`, which would corrupt the one table whose value is that every
-- row is a dispatcher action. So the withdrawal lives on the incident.
--
-- Soft, not hard
-- --------------
-- status moves to 'cancelled' and the row stays. Two reasons, both operational
-- rather than sentimental: an emergency report is an audit record, and
-- /dispatch/queue already excludes cancelled incidents — so a withdrawal
-- disappears from the dispatcher's working queue without deleting the evidence
-- that a report was made. A dispatcher reading history still sees it, marked.
--
-- No new GRANT
-- ------------
-- These are columns on public.incidents, which already carries its
-- service_role grant from migration 002. The failure that 017 and 018 exist to
-- fix applies to new TABLES; adding a column to an existing table inherits the
-- table's privileges. No RLS change either: withdrawal is performed by the
-- backend as service_role, which bypasses RLS, and ownership is enforced in
-- incident_service against the authenticated token rather than in a policy.
--
-- Requires: migration 002 already applied. Idempotent.
-- Run in Supabase SQL Editor AFTER 020.
-- ============================================================

ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS withdrawn_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS withdrawn_reason TEXT;

COMMENT ON COLUMN public.incidents.withdrawn_at IS
    'Set when the reporter withdrew this report themselves. NULL for incidents '
    'cancelled by a dispatcher — those are recorded in dispatch_log instead.';

COMMENT ON COLUMN public.incidents.withdrawn_reason IS
    'Optional free text from the reporter. May be NULL: a resident is not '
    'required to justify taking back their own report.';

-- Withdrawn reports are read together (history views, false-report review) and
-- are a small fraction of the table, so a partial index is the cheap shape.
CREATE INDEX IF NOT EXISTS incidents_withdrawn_idx
    ON public.incidents (withdrawn_at DESC)
    WHERE withdrawn_at IS NOT NULL;

-- ------------------------------------------------------------
-- Verification — expect two rows, both nullable ('YES'), types
-- timestamp with time zone and text. A zero-row result means the
-- ALTER did not run.
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'incidents'
  AND column_name IN ('withdrawn_at', 'withdrawn_reason')
ORDER BY column_name;
