-- ============================================================
-- Migration 029: Agency Admin's Verification step (Agency Admin spec
-- Section 3) — Accept / Reject / Request Clarification
--
-- WHAT WAS MISSING
--
-- The spec's incident lifecycle is:
--
--     New Report -> Verification -> Accepted/Rejected -> Responder
--     Assignment -> Dispatch -> Response in Progress -> Resolved
--
-- The live schema had no "Verification" step at all: an incident went
-- straight from 'received' to whatever the agency_admin did via assign /
-- override / cancel, with no record of an agency having actually LOOKED at
-- the report and decided it was real before acting on it. There was also no
-- way to ask the reporter for more information — only accept-by-assigning or
-- reject-by-cancelling, both of which discard the "I looked at this and it
-- needs more detail" case entirely.
--
-- WHY status ISN'T TOUCHED
--
-- The existing IncidentStatus values (received, processing, dispatched,
-- resolved, cancelled — plus en_route/arrived via the DB CHECK constraint)
-- feed the dispatcher board's queue filter, the history page, every chart in
-- analytics_service and report_service, and the mobile app's own status
-- strip. Redefining what any of those five words mean would quietly change
-- every one of those surfaces. The same reasoning migration 024 gives for why
-- 'dispatched' kept its meaning applies here unchanged.
--
-- So the review decision is recorded ALONGSIDE status, in its own column,
-- the same pattern accepted_at/declined_at used for responder acceptance:
--
--   review_status = 'pending'                  -- default; nothing decided yet
--   review_status = 'accepted'                  -- agency looked, it's real
--   review_status = 'rejected'                  -- agency looked, it's not —
--                                                   status is ALSO set to
--                                                   'cancelled' (existing
--                                                   dispatcher-facing meaning
--                                                   is unchanged: a cancelled
--                                                   incident stops appearing
--                                                   in the queue)
--   review_status = 'clarification_requested'   -- agency needs more detail;
--                                                   status is untouched, the
--                                                   report stays in the queue
--
-- Accepting does not, by itself, move status off 'received' — an accepted
-- report is real but nobody has assigned a responder to it yet, which is
-- exactly what 'received' already means to every existing consumer.
--
-- WHAT THIS DOES NOT DO
--
-- There is no mobile-facing surface for clarification_note yet — the
-- resident's app does not read this column. Recording the request is still
-- worth shipping now (it is visible on the dashboard, and it is real data
-- for the eventual mobile surface); wiring a resident-facing notification is
-- separate follow-up work, not a reason to withhold the dashboard side.
--
-- Requires: migration 002 (incidents table). Idempotent.
-- ============================================================

ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS review_status          TEXT NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS reviewed_at             TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reviewed_by             UUID REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS rejection_reason        TEXT,
    ADD COLUMN IF NOT EXISTS clarification_note      TEXT,
    ADD COLUMN IF NOT EXISTS clarification_requested_at TIMESTAMPTZ;

ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_review_status_check;
ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_review_status_check CHECK (
        review_status IN ('pending', 'accepted', 'rejected', 'clarification_requested')
    );

COMMENT ON COLUMN public.incidents.review_status IS
    'The Agency Admin spec''s Verification step (Section 3), recorded '
    'alongside `status` rather than inside it — see this migration''s header '
    'for why `status`''s existing five/seven values are not redefined. '
    '''pending'' until an agency_admin makes a call.';

COMMENT ON COLUMN public.incidents.rejection_reason IS
    'Required when review_status is set to ''rejected'' — a rejection without '
    'a stated reason is unreviewable later and unaccountable now.';

COMMENT ON COLUMN public.incidents.clarification_note IS
    'What the agency needs the reporter to clarify. No mobile surface reads '
    'this yet — see this migration''s header.';

-- Hot query: "reports still awaiting a Verification decision" is the
-- Agency Admin's incoming-review queue and is small at any moment; indexing
-- every already-decided row would be paying to find what nobody asks for.
CREATE INDEX IF NOT EXISTS incidents_pending_review_idx
    ON public.incidents (created_at)
    WHERE review_status = 'pending';

-- Backfill: every incident that already has a status past 'received' was, by
-- construction, accepted by somebody before anyone could dispatch or resolve
-- it — the app just never recorded that as a distinct decision. Leaving these
-- rows at the new default of 'pending' would put the entire existing incident
-- history back in a fresh admin's Verification queue on the day this ships.
UPDATE public.incidents
SET review_status = 'accepted', reviewed_at = COALESCE(dispatched_at, created_at)
WHERE review_status = 'pending'
  AND status IN ('processing', 'dispatched', 'en_route', 'arrived', 'resolved');

-- A row already cancelled was, in every case that matters going forward,
-- either rejected or simply abandoned — 'rejected' is the closer of the two
-- and keeps a cancelled row out of the pending-review queue either way.
UPDATE public.incidents
SET review_status = 'rejected'
WHERE review_status = 'pending' AND status = 'cancelled';

-- No new GRANT needed: these are columns on public.incidents, which has
-- carried its service_role grant since migration 002. RLS is likewise
-- unchanged — the existing incidents policies gate by row (agency, reporter),
-- not by column, so a new column is visible under the same rules that
-- already govern the row it lives on.

-- ------------------------------------------------------------
-- dispatch_log gets the same three actions, so the Verification decision
-- lands in the SAME immutable audit trail every other dispatch action does,
-- instead of a parallel, harder-to-find log. suggested_severity/
-- chosen_severity/notes are already nullable columns (002), so a review
-- action can log with no severity chosen yet.
-- ------------------------------------------------------------
ALTER TABLE public.dispatch_log DROP CONSTRAINT IF EXISTS dispatch_log_action_check;
ALTER TABLE public.dispatch_log
    ADD CONSTRAINT dispatch_log_action_check CHECK (
        action IN (
            'dispatched', 'resolved', 'cancelled', 'reassigned',
            'accepted', 'rejected', 'clarification_requested'
        )
    );

-- ============================================================
-- Verification
--
-- Expect: 6 rows — every new column, review_status NOT NULL with a default,
-- the rest nullable.
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'incidents'
  AND column_name IN (
      'review_status', 'reviewed_at', 'reviewed_by',
      'rejection_reason', 'clarification_note', 'clarification_requested_at'
  )
ORDER BY column_name;
