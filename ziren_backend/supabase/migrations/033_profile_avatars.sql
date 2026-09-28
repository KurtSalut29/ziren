-- ============================================================
-- Migration 033: Profile avatars (resident + responder)
--
-- Adds a self-service profile picture, so a user can put a real face on
-- their own account instead of the initials-only placeholder every screen
-- fell back to. Follows 015_resident_id_scans.sql's precedent exactly:
--
--   1. PRIVATE bucket. No public URL is ever generated. Reads go through
--      short-lived signed URLs, minted server-side in GET /users/me so the
--      raw storage path never has to reach the client.
--   2. Path-scoped by owner: <auth.uid()>/<filename>. A user cannot read,
--      write, or delete outside their own folder.
--   3. Self-read only for now. No screen shows another user's avatar today
--      (a resident's card, a responder's queue row, none of them render a
--      photo) — so, unlike incident-media, this grants no agency_admin or
--      responder cross-read. Widen this only when a real screen needs it.
--
-- Bucket must be created manually in the Supabase dashboard:
--   Storage -> New bucket -> Name: "avatars" -> PRIVATE
--   File size limit: 5MB
--   Allowed MIME: image/jpeg, image/png, image/webp
--
-- Requires: migration 032 already applied. Idempotent.
-- Run in Supabase SQL Editor AFTER 032.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Column
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS avatar_path TEXT DEFAULT NULL;

COMMENT ON COLUMN public.users.avatar_path IS
    'Storage path in the PRIVATE "avatars" bucket, formatted '
    '<user_id>/<filename>. Never a public URL — GET /users/me exchanges it '
    'for a short-lived signed URL server-side. NULL until the user uploads '
    'a picture, and the app falls back to initials.';

-- No GRANT needed here: public.users already grants service_role (see
-- 002b_grant_permissions.sql) and that privilege is table-wide, so it
-- already covers this new column.

-- ------------------------------------------------------------
-- 2. Storage RLS
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "avatars: owner can upload"     ON storage.objects;
DROP POLICY IF EXISTS "avatars: owner can read own"   ON storage.objects;
DROP POLICY IF EXISTS "avatars: owner can update own" ON storage.objects;
DROP POLICY IF EXISTS "avatars: owner can delete"     ON storage.objects;

-- Owner writes only into their own folder.
CREATE POLICY "avatars: owner can upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "avatars: owner can read own"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Replacing a picture re-uploads with upsert, which needs UPDATE too —
-- resident-ids never needed this because an ID scan is submitted once, but
-- an avatar is something people change their mind about.
CREATE POLICY "avatars: owner can update own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
)
WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "avatars: owner can delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- ------------------------------------------------------------
-- Verification
-- ------------------------------------------------------------
-- Column exists:
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name  = 'avatar_path';

-- Four avatars policies, all scoped to bucket_id = 'avatars':
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename   = 'objects'
  AND policyname LIKE 'avatars:%'
ORDER BY policyname;
