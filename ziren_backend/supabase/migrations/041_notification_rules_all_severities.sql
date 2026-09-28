-- ============================================================
-- Migration 041: every severity alerts by default
--
-- agencies.notification_rules decides which NEW reports interrupt an Agency
-- Admin's console (useIncidentAlerts). Migration 009 defaulted it to
-- critical + high only, and ADD COLUMN ... DEFAULT wrote that value into every
-- existing agency row.
--
-- That silently made PNP the agency that never got alerted: its everyday
-- reports (theft, a fight, a missing person, "tulong po") score LOW or MEDIUM
-- on the triage model, while even a one-word "sunog" scores HIGH. BFP rang on
-- nearly every report; PNP on almost none.
--
-- 1. New agencies default to all four severities.
-- 2. Agencies still holding the untouched 009 default are moved to all four.
--    A row an admin actually changed in Settings -> Alerts is left alone.
--    (A row saved back as exactly critical+high is indistinguishable from an
--    untouched one; that admin can switch medium/low off again.)
--
-- Idempotent: safe to run twice.
-- ============================================================

ALTER TABLE public.agencies
    ALTER COLUMN notification_rules
    SET DEFAULT '{"critical": true, "high": true, "medium": true, "low": true}'::jsonb;

UPDATE public.agencies
SET notification_rules = '{"critical": true, "high": true, "medium": true, "low": true}'::jsonb
WHERE notification_rules IS NULL
   OR notification_rules = '{"critical": true, "high": true, "medium": false, "low": false}'::jsonb;

-- Check: every agency and what now interrupts it.
SELECT name, agency_type, notification_rules
FROM public.agencies
ORDER BY agency_type, name;
