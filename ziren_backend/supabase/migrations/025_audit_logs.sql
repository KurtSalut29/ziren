-- ============================================================
-- Migration 025: audit_logs — general-purpose admin action trail
--
-- Superset of rubric_audit_log (migration 007), which stays as-is for the
-- rubric engine's own fallback-to-seed events. This table is the general
-- "who changed what" record the Super Admin's Audit Logs module reads,
-- written by audit_service.record() from any router, not only rubric.py.
--
-- GRANT is in this same migration (not a follow-up), unlike rubric_configs/
-- rubric_audit_log which needed 018 as a bugfix afterwards -- see that
-- migration's header for exactly the 42501 failure this avoids repeating:
-- creating a table grants nothing to service_role by itself.
--
-- Run AFTER migration 024.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id       UUID REFERENCES public.users(id) ON DELETE SET NULL,
    actor_role     TEXT,
    actor_name     TEXT,
    action         TEXT NOT NULL,
    target_type    TEXT NOT NULL,
    target_id      TEXT,
    target_label   TEXT,
    previous_value JSONB,
    new_value      JSONB,
    metadata       JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS audit_logs_created_idx ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_actor_idx   ON public.audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS audit_logs_target_idx  ON public.audit_logs(target_type, target_id);
CREATE INDEX IF NOT EXISTS audit_logs_action_idx  ON public.audit_logs(action);

COMMENT ON TABLE public.audit_logs IS
    'Append-only trail of administrative actions across the whole app. '
    'Written exclusively by app.services.audit_service.record() -- never '
    'updated or deleted. actor_id is NULL only for system-generated rows.';

-- ============================================================
-- Row Level Security
-- ============================================================
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_logs: super_admin reads all"
    ON public.audit_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'super_admin'
        )
    );

-- Inserts happen via the backend's service-role client, never a user JWT --
-- audit_service.record() always writes as service_role. No INSERT policy
-- for authenticated users is needed or granted.
-- No UPDATE or DELETE policy anywhere -- immutable, append-only.

-- ============================================================
-- service_role grant -- in THIS migration, not a follow-up. See header.
-- ============================================================
GRANT ALL ON public.audit_logs TO service_role;

-- ============================================================
-- Verification -- run after applying.
-- ============================================================
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'audit_logs';

SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'audit_logs'
GROUP BY table_name, grantee;
