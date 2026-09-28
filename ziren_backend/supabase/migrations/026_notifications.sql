-- ============================================================
-- Migration 026: notifications — per-user notification feed
--
-- Backs the notification bell/center. Written by
-- notification_service.create_for_roles() / create_for_agency(), called
-- mostly from audit_service.record() via its NOTIFY_ACTIONS map, and
-- directly by announcement_service.publish() (migration 027).
--
-- GRANT is in this same migration -- see migration 025's header for the
-- 42501 failure this pattern avoids repeating.
--
-- Run AFTER migration 025.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.notifications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type         TEXT NOT NULL,
    title        TEXT NOT NULL,
    body         TEXT,
    is_important BOOLEAN NOT NULL DEFAULT FALSE,
    is_read      BOOLEAN NOT NULL DEFAULT FALSE,
    link         TEXT,
    metadata     JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notifications_recipient_unread_idx
    ON public.notifications(recipient_id, is_read, created_at DESC);

COMMENT ON TABLE public.notifications IS
    'Per-user notification feed. Written by notification_service, mostly '
    'triggered from audit_service.record() via its NOTIFY_ACTIONS map.';

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications: recipient reads own"
    ON public.notifications FOR SELECT
    USING (recipient_id = auth.uid());

CREATE POLICY "notifications: recipient updates own (read state)"
    ON public.notifications FOR UPDATE
    USING (recipient_id = auth.uid());

GRANT ALL ON public.notifications TO service_role;

-- Verification -- run after applying.
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'notifications';

SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'notifications'
GROUP BY table_name, grantee;
