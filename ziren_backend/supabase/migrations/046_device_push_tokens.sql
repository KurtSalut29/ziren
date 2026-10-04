-- 046: phones that can receive push notifications
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Evaluator findings #11 and #12 (2026-10-05): a resident got no phone
-- notification for an admin's chat message, or any update to their report,
-- while the app was closed or in the background; a responder got no alert for
-- a new assignment either. Notices only arrived while the app was open
-- (Supabase Realtime). Push through Firebase Cloud Messaging reaches a closed
-- app; this table holds each signed-in phone's FCM registration token so the
-- backend knows where to send.
--
-- One row per phone (the token is unique); a phone that changes hands moves
-- to the new account on its next registration. Rows are deleted on sign-out
-- and when FCM reports the token dead.

CREATE TABLE IF NOT EXISTS public.device_push_tokens (
    token         TEXT        PRIMARY KEY CHECK (char_length(token) BETWEEN 20 AND 4096),
    user_id       UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    platform      TEXT        NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios', 'web')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_push_tokens_user_idx ON public.device_push_tokens (user_id);

COMMENT ON TABLE public.device_push_tokens IS
    'FCM registration tokens of signed-in phones (migration 046). Written and read only '
    'by the backend; a phone registers through POST /users/me/push-token.';

ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;
-- No policies: the backend's service key is the only reader and writer.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_push_tokens TO service_role;
REVOKE ALL ON public.device_push_tokens FROM anon, authenticated;

-- Verification -- expect one row.
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'device_push_tokens';
