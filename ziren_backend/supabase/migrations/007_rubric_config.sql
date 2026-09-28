-- ============================================================
-- Migration 007: Severity Rubric Engine — config tables
--
-- Creates:
--   rubric_configs   — one active versioned rule-set per agency
--   rubric_audit_log — append-only change log + fallback events
--
-- Architecture notes:
--   • rubric_configs is the authoritative runtime source for the
--     severity rubric engine (Phase 5). JSON seed files in
--     app/rubric_configs/ are the version-controlled bootstrap;
--     on first startup the engine loads those seeds into this table.
--   • Every write to rubric_configs (create, activate, deactivate)
--     produces a row in rubric_audit_log. This is also where the
--     engine logs fallback-to-seed events — not just console output.
--   • rubric_audit_log has no UPDATE or DELETE policy — immutable.
--
-- Run AFTER migration 006.
-- ============================================================

-- ============================================================
-- 1. rubric_configs table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rubric_configs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Which agency this config applies to
    agency_type     TEXT NOT NULL
                        CHECK (agency_type IN ('BFP', 'PNP', 'MDRRMO')),

    -- Semantic version string — bump when rules change
    version         TEXT NOT NULL,

    -- Full rule-set as JSONB (array of rule objects)
    -- Schema is validated by the application layer (Pydantic) before storage
    rules           JSONB NOT NULL,

    -- Only one config per agency_type can be is_active = TRUE at a time
    -- Enforced by partial unique index below
    is_active       BOOLEAN NOT NULL DEFAULT FALSE,

    -- Who created this version
    created_by      UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

    -- Who last activated this version (NULL until first activation)
    activated_by    UUID REFERENCES public.users(id) ON DELETE SET NULL,
    activated_at    TIMESTAMPTZ,

    -- Standard timestamps
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Only one active config per agency at a time
CREATE UNIQUE INDEX IF NOT EXISTS rubric_configs_one_active_per_agency
    ON public.rubric_configs(agency_type)
    WHERE is_active = TRUE;

-- Fast lookup by agency + active state
CREATE INDEX IF NOT EXISTS rubric_configs_agency_active_idx
    ON public.rubric_configs(agency_type, is_active);

CREATE TRIGGER rubric_configs_updated_at
    BEFORE UPDATE ON public.rubric_configs
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.rubric_configs IS
    'Versioned severity rubric rule-sets per agency (BFP/PNP/MDRRMO). '
    'Authoritative runtime source for the severity engine. '
    'JSON seed files in app/rubric_configs/ bootstrap this table on first deploy. '
    'Only one is_active=TRUE row per agency_type is permitted (enforced by partial unique index).';

COMMENT ON COLUMN public.rubric_configs.rules IS
    'JSONB array of rule objects. Each rule specifies signal conditions, '
    'a severity_contribution (critical/high/medium/low), a recommended_agency, '
    'and a provenance note. Schema is validated by Pydantic before storage — '
    'arbitrary code cannot be embedded here.';

-- ============================================================
-- 2. rubric_audit_log table (append-only)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rubric_audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- What kind of event this row records
    event_type      TEXT NOT NULL
                        CHECK (event_type IN (
                            'config_created',    -- new version uploaded
                            'config_activated',  -- a version set to is_active=TRUE
                            'config_deactivated',-- a version set to is_active=FALSE
                            'rule_updated',      -- a rule within a version changed
                            'fallback_to_seed'   -- engine fell back to JSON seed (DB miss)
                        )),

    agency_type     TEXT NOT NULL
                        CHECK (agency_type IN ('BFP', 'PNP', 'MDRRMO')),

    -- The config version involved (NULL for fallback_to_seed if no DB row exists yet)
    rubric_config_id UUID REFERENCES public.rubric_configs(id) ON DELETE SET NULL,
    config_version  TEXT,

    -- Rule-level granularity (NULL for config-level events like activation)
    rule_id         TEXT,

    -- JSONB snapshots for diffing — both NULL for activation/fallback events
    previous_value  JSONB,
    new_value       JSONB,

    -- Who triggered the event; NULL only for system-generated fallback events
    actor_id        UUID REFERENCES public.users(id) ON DELETE SET NULL,

    -- Human-readable note (required for fallback events — must say WHY)
    notes           TEXT,

    -- Immutable timestamp — no updated_at on this table
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — this table is append-only, rows are never modified
);

CREATE INDEX IF NOT EXISTS rubric_audit_log_agency_idx
    ON public.rubric_audit_log(agency_type);
CREATE INDEX IF NOT EXISTS rubric_audit_log_actor_idx
    ON public.rubric_audit_log(actor_id);
CREATE INDEX IF NOT EXISTS rubric_audit_log_created_idx
    ON public.rubric_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS rubric_audit_log_event_type_idx
    ON public.rubric_audit_log(event_type);

COMMENT ON TABLE public.rubric_audit_log IS
    'Append-only audit trail for all rubric config changes and engine fallback events. '
    'event_type=fallback_to_seed is written by the engine (not a human) when it cannot '
    'load a config from the DB and falls back to the bundled JSON seed file. '
    'This is NOT only a console warning — every fallback is a persistent audit record. '
    'actor_id is NULL for system-generated events (fallbacks). '
    'No UPDATE or DELETE policy — rows are immutable once written.';

-- ============================================================
-- 3. Row Level Security — rubric_configs
-- ============================================================
ALTER TABLE public.rubric_configs ENABLE ROW LEVEL SECURITY;

-- agency_admin: read only their own agency's configs
CREATE POLICY "rubric_configs: agency_admin reads own"
    ON public.rubric_configs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            JOIN public.agencies a ON a.id = u.agency_id
            WHERE u.id = auth.uid()
              AND u.role = 'agency_admin'
              AND a.agency_type = public.rubric_configs.agency_type
        )
    );

-- agency_admin: insert new versions scoped to their own agency only
CREATE POLICY "rubric_configs: agency_admin inserts own"
    ON public.rubric_configs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            JOIN public.agencies a ON a.id = u.agency_id
            WHERE u.id = auth.uid()
              AND u.role = 'agency_admin'
              AND a.agency_type = public.rubric_configs.agency_type
        )
        AND created_by = auth.uid()
    );

-- agency_admin: update (activate/deactivate) only their own agency's configs
CREATE POLICY "rubric_configs: agency_admin updates own"
    ON public.rubric_configs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            JOIN public.agencies a ON a.id = u.agency_id
            WHERE u.id = auth.uid()
              AND u.role = 'agency_admin'
              AND a.agency_type = public.rubric_configs.agency_type
        )
    );

-- super_admin: full read across all agencies
CREATE POLICY "rubric_configs: super_admin reads all"
    ON public.rubric_configs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role = 'super_admin'
        )
    );

-- super_admin: insert for any agency
CREATE POLICY "rubric_configs: super_admin inserts any"
    ON public.rubric_configs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role = 'super_admin'
        )
        AND created_by = auth.uid()
    );

-- super_admin: update any agency's configs
CREATE POLICY "rubric_configs: super_admin updates any"
    ON public.rubric_configs FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role = 'super_admin'
        )
    );

-- Nobody deletes rubric configs — deactivate via is_active=FALSE instead
-- (No DELETE policy = DELETE denied for all)

-- ============================================================
-- 4. Row Level Security — rubric_audit_log
-- ============================================================
ALTER TABLE public.rubric_audit_log ENABLE ROW LEVEL SECURITY;

-- agency_admin: reads audit log for their own agency only
CREATE POLICY "rubric_audit_log: agency_admin reads own"
    ON public.rubric_audit_log FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            JOIN public.agencies a ON a.id = u.agency_id
            WHERE u.id = auth.uid()
              AND u.role = 'agency_admin'
              AND a.agency_type = public.rubric_audit_log.agency_type
        )
    );

-- super_admin: reads all audit log entries
CREATE POLICY "rubric_audit_log: super_admin reads all"
    ON public.rubric_audit_log FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role = 'super_admin'
        )
    );

-- Insert is allowed for agency_admin / super_admin AND for the service role
-- (the engine inserts fallback_to_seed rows using the service key, not a user JWT)
CREATE POLICY "rubric_audit_log: admin inserts"
    ON public.rubric_audit_log FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
              AND u.role IN ('agency_admin', 'super_admin')
        )
        -- actor_id must match the authenticated user when a human is inserting
        -- (actor_id = NULL is only valid for system/service-role inserts)
        AND (actor_id = auth.uid() OR actor_id IS NULL)
    );

-- NO UPDATE or DELETE policy on rubric_audit_log — immutable append-only
-- Residents and Responders cannot read or write this table

-- ============================================================
-- 5. Verification queries — run after applying migration
-- ============================================================
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('rubric_configs', 'rubric_audit_log');

SELECT
    schemaname,
    tablename,
    policyname,
    cmd
FROM pg_policies
WHERE tablename IN ('rubric_configs', 'rubric_audit_log')
ORDER BY tablename, policyname;
