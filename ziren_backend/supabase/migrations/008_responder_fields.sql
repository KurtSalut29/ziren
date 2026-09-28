-- ============================================================
-- Migration 008: Responder fields
--
-- Adds:
--   users.availability  — on_duty / off_duty toggle for Responders
--   incidents.assigned_responder_id  — FK to the Responder assigned by dispatcher
--   incidents.en_route status value  — extends the status CHECK
--   incidents.arrived  status value  — extends the status CHECK
--
-- Run AFTER migration 007.
-- ============================================================

-- ── 1. Add availability column to users ──────────────────────────────────────
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS availability TEXT DEFAULT 'off_duty'
        CHECK (availability IN ('on_duty', 'off_duty'));

-- ── 2. Add assigned_responder_id to incidents ─────────────────────────────────
ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS assigned_responder_id UUID
        REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS incidents_responder_idx
    ON public.incidents(assigned_responder_id);

-- ── 3. Extend status CHECK to include en_route / arrived ─────────────────────
-- Drop and recreate the check constraint (Postgres does not support ADD VALUE
-- to a CHECK inline — must drop + recreate).
ALTER TABLE public.incidents
    DROP CONSTRAINT IF EXISTS incidents_status_check;

ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_status_check
    CHECK (status IN ('received', 'processing', 'dispatched',
                      'en_route', 'arrived', 'resolved', 'cancelled'));

-- ── 4. RLS for assigned_responder_id visibility ───────────────────────────────
-- Responders should be able to read their own assigned incidents.
-- The existing "incidents: resident reads own" policy covers:
--   auth.uid() = reporter_id OR role IN (responder, agency_admin, super_admin)
-- which already grants responders SELECT on all incidents.
-- The service layer (get_my_queue) adds the assigned_responder_id filter,
-- so no additional RLS policy is needed here — the service enforces scope.

-- Responders can update status on incidents assigned to them.
-- This is a new UPDATE policy: only affects the status column via the
-- service layer; RLS just gates the UPDATE permission.
DROP POLICY IF EXISTS "incidents: responder updates assigned" ON public.incidents;

CREATE POLICY "incidents: responder updates assigned"
    ON public.incidents FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role = 'responder'
            AND u.approval_status = 'approved'
        )
        AND assigned_responder_id = auth.uid()
    );

-- ── 5. Verification ──────────────────────────────────────────────────────────
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name = 'availability';

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'incidents'
  AND column_name = 'assigned_responder_id';
