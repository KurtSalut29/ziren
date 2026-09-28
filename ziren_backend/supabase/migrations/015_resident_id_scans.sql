-- ============================================================
-- Migration 015: Resident ID scans
--
-- Adds an uploaded image of the valid ID a resident selected, so an Agency
-- Admin can confirm the ID number against the document without the resident
-- having to appear in person.
--
-- PRIVACY POSTURE — read before changing anything here.
--
-- An image of a government ID is sensitive personal information under the
-- Data Privacy Act (RA 10173). Holding a library of them makes this system a
-- materially bigger breach target than it was when it stored only ID numbers.
-- That is a deliberate, accepted trade for in-person-free verification, and
-- the controls below are what make it defensible:
--
--   1. PRIVATE bucket. No public URL is ever generated. Reads go through
--      short-lived signed URLs.
--   2. Narrower than incident-media. Responders can read incident photos;
--      they must NOT read ID scans, because a responder has no role in
--      identity verification. Only the owner and verifying admins.
--   3. Path-scoped by owner: <auth.uid()>/<filename>. A user cannot read or
--      write outside their own folder.
--   4. Retention. The image exists to be checked once. After an admin sets
--      verification_level, the scan should be purged — see the retention
--      query at the bottom. Keeping it forever is the failure mode.
--   5. Still optional. Nothing here gates registration or reporting.
--
-- Bucket must be created manually in the Supabase dashboard:
--   Storage → New bucket → Name: "resident-ids" → PRIVATE
--   File size limit: 10MB
--   Allowed MIME: image/jpeg, image/png, image/webp, image/heic
--
-- Run AFTER migration 014.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Column
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS valid_id_image_path TEXT DEFAULT NULL;

COMMENT ON COLUMN public.users.valid_id_image_path IS
    'Storage path in the PRIVATE "resident-ids" bucket, formatted '
    '<user_id>/<filename>. Never a public URL. Should be purged once '
    'verification_level has been set — see migration 015 retention query.';

-- ------------------------------------------------------------
-- 2. Storage RLS
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "resident-ids: owner can upload"    ON storage.objects;
DROP POLICY IF EXISTS "resident-ids: owner can read own"  ON storage.objects;
DROP POLICY IF EXISTS "resident-ids: owner can delete"    ON storage.objects;
DROP POLICY IF EXISTS "resident-ids: admin can read"      ON storage.objects;
DROP POLICY IF EXISTS "resident-ids: admin can delete"    ON storage.objects;

-- Owner writes only into their own folder.
CREATE POLICY "resident-ids: owner can upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'resident-ids'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "resident-ids: owner can read own"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'resident-ids'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- A resident may withdraw their ID at any time.
CREATE POLICY "resident-ids: owner can delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'resident-ids'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Verifying admins only. Note the deliberate absence of 'responder' — a
-- responder attends incidents and has no part in identity verification, so
-- exposing scans to them would widen the blast radius for nothing.
CREATE POLICY "resident-ids: admin can read"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'resident-ids'
    AND public.get_my_role() IN ('agency_admin', 'super_admin')
);

-- Admins must be able to purge a scan after checking it (retention).
CREATE POLICY "resident-ids: admin can delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'resident-ids'
    AND public.get_my_role() IN ('agency_admin', 'super_admin')
);

-- ------------------------------------------------------------
-- 3. Retention
--
-- Run periodically. Any account already verified no longer needs its scan;
-- the row still records valid_id_type and valid_id_number as the audit trail.
-- Clearing the column is the signal to delete the storage object.
-- ------------------------------------------------------------
-- Accounts whose scan is now redundant:
SELECT id, email, valid_id_type, verification_level, valid_id_image_path
FROM public.users
WHERE valid_id_image_path IS NOT NULL
  AND verification_level >= 2
ORDER BY verified_at;

-- Scans left behind by accounts that were never reviewed (stale intake):
SELECT id, email, valid_id_type, created_at, valid_id_image_path
FROM public.users
WHERE valid_id_image_path IS NOT NULL
  AND verification_level = 0
  AND created_at < NOW() - INTERVAL '90 days'
ORDER BY created_at;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name  = 'valid_id_image_path';
