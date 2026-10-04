-- 044: accountability and audit integrity
--
-- Run once in the Supabase SQL Editor. Safe to re-run: every statement is
-- idempotent (IF NOT EXISTS / DROP ... IF EXISTS / CREATE OR REPLACE).
--
-- Answers the ISO / white-box evaluator's findings of 2026-10-05:
--
--   #6  "An important action can succeed even when its audit record fails."
--       audit_logs gains an outcome. The backend now writes the row FIRST, as
--       'pending', and refuses the action if that write fails; it then marks
--       the row 'succeeded' or 'failed'. A row left 'pending' is an action
--       that was attempted and never confirmed -- still a record of who.
--
--   #7  "Resident verification records do not show which admin approved or
--       rejected the resident." users gains the reviewer, the decision, when,
--       and the reviewer's name as it was at the time.
--
--   #8  "A finalized narrative report can be edited without keeping the
--       previous version." incident_narrative_report_versions keeps the full
--       previous report every time a finalized one is changed, with who
--       changed it, which fields, and the reason they gave.
--
--   #9  "Audit records themselves could potentially be modified or deleted."
--       audit_logs, rubric_audit_log and the new versions table become
--       append-only at the database: a trigger refuses UPDATE, DELETE and
--       TRUNCATE for every role, the service role included (triggers are not
--       bypassed by RLS bypass). dispatch_log refuses UPDATE and TRUNCATE, and
--       DELETE except for the demo data seed_demo_data.py --clean removes.
--
--   #29 "Keep a permanent actor ID in audit records." audit_logs.actor_id and
--       rubric_audit_log.actor_id were foreign keys ON DELETE SET NULL: deleting
--       an account erased who had acted. The constraints are dropped; the ids
--       stay as plain uuids beside the name and role recorded at the time.
--
-- RETENTION
-- Audit rows are kept indefinitely. A deliberate purge (say, rows older than
-- the retention period the offices adopt) is possible only from the SQL
-- Editor, in one transaction:
--     BEGIN;
--     SET LOCAL ziren.log_purge = 'on';
--     DELETE FROM public.audit_logs WHERE created_at < now() - interval '5 years';
--     COMMIT;
-- The setting cannot be reached through the API (PostgREST exposes no SET),
-- so the backend's service key cannot purge, and the purge itself shows in the
-- Supabase SQL Editor history.

-- =============================================================================
-- 1. audit_logs: outcome, completion, permanent actor
-- =============================================================================

ALTER TABLE public.audit_logs
    ADD COLUMN IF NOT EXISTS outcome      TEXT NOT NULL DEFAULT 'succeeded',
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS error        TEXT;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'audit_logs_outcome_check' AND conrelid = 'public.audit_logs'::regclass
    ) THEN
        ALTER TABLE public.audit_logs
            ADD CONSTRAINT audit_logs_outcome_check
            CHECK (outcome IN ('pending', 'succeeded', 'failed'));
    END IF;
END $$;

COMMENT ON COLUMN public.audit_logs.outcome IS
    'pending = written before the action ran; succeeded / failed = what happened. '
    'Rows written before migration 044 default to succeeded (they were only ever '
    'written after a successful action).';

ALTER TABLE public.audit_logs       DROP CONSTRAINT IF EXISTS audit_logs_actor_id_fkey;
ALTER TABLE public.rubric_audit_log DROP CONSTRAINT IF EXISTS rubric_audit_log_actor_id_fkey;

COMMENT ON COLUMN public.audit_logs.actor_id IS
    'The acting account''s id, kept even if the account is later deleted (no foreign '
    'key on purpose -- see migration 044). actor_name and actor_role are as they were '
    'at the time of the action.';

CREATE INDEX IF NOT EXISTS audit_logs_pending_idx
    ON public.audit_logs (created_at) WHERE outcome = 'pending';

-- =============================================================================
-- 2. Append-only enforcement
-- =============================================================================

-- audit_logs: the one permitted change is completing a pending row --
-- pending -> succeeded/failed, filling completed_at / error / new_value /
-- metadata. Everything that says who did what to which record stays as written.
CREATE OR REPLACE FUNCTION public.audit_logs_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('ziren.log_purge', true) = 'on' THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'audit_logs is append-only: rows cannot be deleted'
            USING ERRCODE = '42501';
    END IF;

    IF OLD.outcome = 'pending'
       AND NEW.outcome IN ('succeeded', 'failed')
       AND NEW.id             = OLD.id
       AND NEW.actor_id       IS NOT DISTINCT FROM OLD.actor_id
       AND NEW.actor_role     IS NOT DISTINCT FROM OLD.actor_role
       AND NEW.actor_name     IS NOT DISTINCT FROM OLD.actor_name
       AND NEW.action         =  OLD.action
       AND NEW.target_type    =  OLD.target_type
       AND NEW.target_id      IS NOT DISTINCT FROM OLD.target_id
       AND NEW.target_label   IS NOT DISTINCT FROM OLD.target_label
       AND NEW.previous_value IS NOT DISTINCT FROM OLD.previous_value
       AND NEW.agency_type    IS NOT DISTINCT FROM OLD.agency_type
       AND NEW.created_at     =  OLD.created_at
    THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'audit_logs is append-only: rows cannot be changed'
        USING ERRCODE = '42501';
END;
$$;

-- For tables with no permitted change at all.
CREATE OR REPLACE FUNCTION public.log_table_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('ziren.log_purge', true) = 'on' THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    RAISE EXCEPTION '% is append-only: rows cannot be changed or removed (%)', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '42501';
END;
$$;

-- dispatch_log: no edits ever; deletes only of the seeded demo data, whose
-- incidents are all filed by @seed.ziren.test accounts (seed_demo_data.py).
CREATE OR REPLACE FUNCTION public.dispatch_log_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('ziren.log_purge', true) = 'on' THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP = 'DELETE' AND EXISTS (
        SELECT 1
        FROM public.incidents i
        JOIN public.users u ON u.id = i.reporter_id
        WHERE i.id = OLD.incident_id
          AND u.email LIKE '%@seed.ziren.test'
    ) THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'dispatch_log is append-only: rows cannot be changed or removed (%)', TG_OP
        USING ERRCODE = '42501';
END;
$$;

CREATE OR REPLACE FUNCTION public.log_table_no_truncate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('ziren.log_purge', true) = 'on' THEN
        RETURN NULL;
    END IF;
    RAISE EXCEPTION '% is append-only: it cannot be truncated', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS audit_logs_append_only ON public.audit_logs;
CREATE TRIGGER audit_logs_append_only
    BEFORE UPDATE OR DELETE ON public.audit_logs
    FOR EACH ROW EXECUTE FUNCTION public.audit_logs_append_only();

DROP TRIGGER IF EXISTS audit_logs_no_truncate ON public.audit_logs;
CREATE TRIGGER audit_logs_no_truncate
    BEFORE TRUNCATE ON public.audit_logs
    FOR EACH STATEMENT EXECUTE FUNCTION public.log_table_no_truncate();

DROP TRIGGER IF EXISTS rubric_audit_log_append_only ON public.rubric_audit_log;
CREATE TRIGGER rubric_audit_log_append_only
    BEFORE UPDATE OR DELETE ON public.rubric_audit_log
    FOR EACH ROW EXECUTE FUNCTION public.log_table_append_only();

DROP TRIGGER IF EXISTS rubric_audit_log_no_truncate ON public.rubric_audit_log;
CREATE TRIGGER rubric_audit_log_no_truncate
    BEFORE TRUNCATE ON public.rubric_audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION public.log_table_no_truncate();

DROP TRIGGER IF EXISTS dispatch_log_append_only ON public.dispatch_log;
CREATE TRIGGER dispatch_log_append_only
    BEFORE UPDATE OR DELETE ON public.dispatch_log
    FOR EACH ROW EXECUTE FUNCTION public.dispatch_log_append_only();

DROP TRIGGER IF EXISTS dispatch_log_no_truncate ON public.dispatch_log;
CREATE TRIGGER dispatch_log_no_truncate
    BEFORE TRUNCATE ON public.dispatch_log
    FOR EACH STATEMENT EXECUTE FUNCTION public.log_table_no_truncate();

-- Nobody signs in to change these through the API either.
REVOKE UPDATE, DELETE, TRUNCATE ON public.audit_logs       FROM anon, authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON public.rubric_audit_log FROM anon, authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON public.dispatch_log     FROM anon, authenticated;

-- =============================================================================
-- 3. Who decided a resident's verification (#7)
-- =============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS verification_decision         TEXT,
    ADD COLUMN IF NOT EXISTS verification_reviewed_by      UUID,
    ADD COLUMN IF NOT EXISTS verification_reviewed_by_name TEXT,
    ADD COLUMN IF NOT EXISTS verification_reviewed_at      TIMESTAMPTZ;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'users_verification_decision_check' AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_verification_decision_check
            CHECK (verification_decision IS NULL OR verification_decision IN ('approved', 'rejected'));
    END IF;
END $$;

COMMENT ON COLUMN public.users.verification_reviewed_by IS
    'The admin who made the latest identity decision on this resident. No foreign key '
    'on purpose (migration 044): the record of who decided must outlive their account.';
COMMENT ON COLUMN public.users.verification_reviewed_by_name IS
    'That admin''s name at the time of the decision.';

-- A resident updates their own row through the API (the "users: update own
-- profile" policy). These four columns are not in that policy's freeze list,
-- and recreating that long policy for them risks loosening it; a trigger is
-- the narrower guard. auth.uid() is NULL for the backend's service key, so the
-- backend -- the only legitimate writer -- is unaffected.
CREATE OR REPLACE FUNCTION public.users_guard_verification_review()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND auth.uid() = OLD.id AND (
           NEW.verification_decision         IS DISTINCT FROM OLD.verification_decision
        OR NEW.verification_reviewed_by      IS DISTINCT FROM OLD.verification_reviewed_by
        OR NEW.verification_reviewed_by_name IS DISTINCT FROM OLD.verification_reviewed_by_name
        OR NEW.verification_reviewed_at      IS DISTINCT FROM OLD.verification_reviewed_at
    ) THEN
        RAISE EXCEPTION 'verification review fields are set by an administrator only'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_guard_verification_review ON public.users;
CREATE TRIGGER users_guard_verification_review
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.users_guard_verification_review();

-- =============================================================================
-- 4. Previous versions of finalized narrative reports (#8)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.incident_narrative_report_versions (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id        UUID        NOT NULL REFERENCES public.incident_narrative_reports(id) ON DELETE RESTRICT,
    incident_id      UUID        NOT NULL REFERENCES public.incidents(id) ON DELETE RESTRICT,
    version_no       INTEGER     NOT NULL CHECK (version_no >= 1),
    -- The whole report as it stood before the change, exactly as stored.
    snapshot         JSONB       NOT NULL,
    changed_fields   TEXT[]      NOT NULL DEFAULT '{}',
    change_reason    TEXT        NOT NULL CHECK (char_length(btrim(change_reason)) BETWEEN 5 AND 1000),
    changed_by       UUID        NOT NULL,
    changed_by_name  TEXT,
    changed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (report_id, version_no)
);

COMMENT ON TABLE public.incident_narrative_report_versions IS
    'One row per change to a FINALIZED narrative report: the report as it was before '
    'the change, who changed it and why. Append-only (migration 044). changed_by has no '
    'foreign key so the record survives the account.';

CREATE INDEX IF NOT EXISTS narrative_versions_report_idx
    ON public.incident_narrative_report_versions (report_id, version_no DESC);

ALTER TABLE public.incident_narrative_report_versions ENABLE ROW LEVEL SECURITY;
-- No policies: read and written only by the backend's service key, which every
-- reader already goes through with an agency-scope check.
GRANT SELECT, INSERT ON public.incident_narrative_report_versions TO service_role;
REVOKE UPDATE, DELETE, TRUNCATE ON public.incident_narrative_report_versions FROM anon, authenticated;

DROP TRIGGER IF EXISTS narrative_versions_append_only ON public.incident_narrative_report_versions;
CREATE TRIGGER narrative_versions_append_only
    BEFORE UPDATE OR DELETE ON public.incident_narrative_report_versions
    FOR EACH ROW EXECUTE FUNCTION public.log_table_append_only();

DROP TRIGGER IF EXISTS narrative_versions_no_truncate ON public.incident_narrative_report_versions;
CREATE TRIGGER narrative_versions_no_truncate
    BEFORE TRUNCATE ON public.incident_narrative_report_versions
    FOR EACH STATEMENT EXECUTE FUNCTION public.log_table_no_truncate();

-- =============================================================================
-- Verification -- expect: outcome/completed_at/error on audit_logs, the four
-- review columns on users, the versions table, and five append-only triggers.
-- =============================================================================
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
       (table_name = 'audit_logs' AND column_name IN ('outcome', 'completed_at', 'error'))
    OR (table_name = 'users' AND column_name LIKE 'verification_review%')
    OR (table_name = 'users' AND column_name = 'verification_decision')
    OR (table_name = 'incident_narrative_report_versions' AND column_name = 'snapshot')
  )
ORDER BY table_name, column_name;

SELECT tgrelid::regclass AS table_name, tgname
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN ('audit_logs_append_only', 'rubric_audit_log_append_only',
                 'dispatch_log_append_only', 'narrative_versions_append_only',
                 'users_guard_verification_review')
ORDER BY 1, 2;
