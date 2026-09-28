-- ============================================================
-- Migration 028: announcements — Super Admin's system-wide broadcasts
-- (spec Section 14).
--
-- target_type values match UserRole enum values exactly (agency_admin, not
-- agency_admins) so announcement_service.list_for_user's filter is a direct
-- `target_type = current_user['role']` comparison, no plural-to-singular
-- mapping needed.
--
-- GRANT is in this same migration — see migration 025's header for the
-- 42501 failure this pattern avoids repeating.
--
-- Run AFTER migration 027.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.announcements (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title             TEXT NOT NULL,
    body              TEXT NOT NULL,
    category          TEXT NOT NULL CHECK (category IN
                          ('maintenance', 'emergency', 'service_interruption', 'feature', 'reminder', 'general')),
    target_type       TEXT NOT NULL CHECK (target_type IN
                          ('all', 'agency_admin', 'responder', 'resident', 'agency')),
    target_agency_id  UUID REFERENCES public.agencies(id) ON DELETE CASCADE,
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_by        UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at        TIMESTAMPTZ,

    CONSTRAINT announcements_agency_target_requires_agency_id
        CHECK (target_type != 'agency' OR target_agency_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS announcements_active_idx ON public.announcements(is_active, created_at DESC);

COMMENT ON TABLE public.announcements IS
    'Super Admin system-wide broadcasts. target_type mirrors UserRole values '
    '(plus "all" and "agency") so filtering is a direct role comparison.';

CREATE TABLE IF NOT EXISTS public.announcement_reads (
    announcement_id UUID NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    read_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (announcement_id, user_id)
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_reads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "announcements: everyone reads active"
    ON public.announcements FOR SELECT
    USING (is_active = TRUE);

CREATE POLICY "announcements: super_admin full read"
    ON public.announcements FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'super_admin')
    );

CREATE POLICY "announcement_reads: user manages own"
    ON public.announcement_reads FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Writes to announcements happen via the backend's service-role client only
-- (announcements.py always runs behind require_super_admin at the
-- application layer before ever reaching a table call) — no INSERT/UPDATE
-- policy for authenticated users is needed or granted on that table.

GRANT ALL ON public.announcements TO service_role;
GRANT ALL ON public.announcement_reads TO service_role;

-- Verification -- run after applying.
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public' AND tablename IN ('announcements', 'announcement_reads');

SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name IN ('announcements', 'announcement_reads')
GROUP BY table_name, grantee;
