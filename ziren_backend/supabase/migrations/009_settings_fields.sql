-- ============================================================
-- Migration 009: Settings fields — Phase 6A.5
--
-- Adds:
--   agencies.notification_rules  — JSONB: per-severity alert config
--                                  { critical: bool, high: bool, medium: bool, low: bool }
--   agencies.email               — contact email for the agency
--
-- notification_rules is owned by the agency and editable by its Agency Admin.
-- Super Admin can edit any agency's notification_rules.
-- The rubric engine does NOT read this column — it is dispatcher/alert config only.
--
-- Run AFTER migration 008.
-- ============================================================

-- ── 1. Add notification_rules JSONB column ────────────────────────────────────
ALTER TABLE public.agencies
    ADD COLUMN IF NOT EXISTS notification_rules JSONB
        DEFAULT '{"critical": true, "high": true, "medium": false, "low": false}'::jsonb;

-- ── 2. Add email column ───────────────────────────────────────────────────────
ALTER TABLE public.agencies
    ADD COLUMN IF NOT EXISTS email TEXT;

-- ── 3. Verification ──────────────────────────────────────────────────────────
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'agencies'
  AND column_name IN ('notification_rules', 'email');
