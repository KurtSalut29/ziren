-- ============================================================
-- Migration 027: system_config — key/value store for System Governance's
-- Account Policies and Notification Policies (spec Section 11).
--
-- Incident Configuration and Severity Configuration need no table of their
-- own: incident categories/statuses are read live from the IncidentCategory/
-- IncidentStatus enums in app/models/incident.py (so this can never drift
-- from what the code actually enforces), and severity is the existing
-- rubric_configs table (migration 007) — this table only holds the two
-- policy groups that don't already have a home.
--
-- GRANT is in this same migration — see migration 025's header for the
-- 42501 failure this pattern avoids repeating.
--
-- Run AFTER migration 026.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.system_config (
    key         TEXT PRIMARY KEY,
    value       JSONB NOT NULL,
    description TEXT,
    updated_by  UUID REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.system_config IS
    'Key/value store for System Governance policy groups (account_policies, '
    'notification_policies). Every write is also recorded in audit_logs via '
    'audit_service.record() for Configuration History.';

ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "system_config: super_admin reads all"
    ON public.system_config FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'super_admin'
        )
    );

-- Writes happen via the backend's service-role client only (governance.py
-- always runs behind require_super_admin at the application layer before
-- ever reaching a table call) — no INSERT/UPDATE policy for authenticated
-- users is needed or granted.

GRANT ALL ON public.system_config TO service_role;

-- Seed rows — ON CONFLICT DO NOTHING so re-running this file is safe and
-- never clobbers a value a Super Admin has already changed.
INSERT INTO public.system_config (key, value, description) VALUES
    ('account_policies', '{"require_id_verification": true, "auto_suspend_after_inactive_days": null}',
     'Account verification and suspension policy defaults.'),
    ('notification_policies', '{"system_alerts": true, "admin_notifications": true, "incident_alerts": true}',
     'Which categories of system-wide notification are enabled.')
ON CONFLICT (key) DO NOTHING;

-- Verification -- run after applying.
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'system_config';

SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'system_config'
GROUP BY table_name, grantee;

SELECT key, value FROM public.system_config ORDER BY key;
