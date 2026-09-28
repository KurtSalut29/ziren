-- ============================================================
-- Migration 003b: Add media_urls to incidents + storage RLS
-- Idempotent — safe to re-run.
-- ============================================================

ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.incidents.media_urls IS
    'Array of Supabase Storage paths for optional photo/video attachments. '
    'Private bucket — only reporter + assigned agency can access. '
    'NOT fed into NLP pipeline.';

-- Storage bucket must be created manually in Supabase dashboard:
--   Storage → New bucket → Name: "incident-media" → Private
--   File size limit: 50MB
--   Allowed MIME: image/jpeg, image/png, image/webp, image/heic,
--                 video/mp4, video/quicktime, video/3gpp,
--                 audio/mp4, audio/x-m4a, audio/m4a, audio/aac,
--                 audio/mpeg, audio/wav, audio/ogg, audio/opus, audio/webm
--
--   The audio types are NOT optional. The resident's voice note is an
--   .m4a, and a bucket without them rejects every recording at the
--   Storage layer -- the report still saves, media_urls comes back empty,
--   and nothing in the app or the API says why. The allow-list on the
--   live bucket was widened on 2026-08-31; a freshly created one has to
--   include them from the start.

-- Storage RLS policies (idempotent)
DROP POLICY IF EXISTS "incident-media: reporter can upload"     ON storage.objects;
DROP POLICY IF EXISTS "incident-media: reporter can read own"   ON storage.objects;
DROP POLICY IF EXISTS "incident-media: reporter can delete own" ON storage.objects;

CREATE POLICY "incident-media: reporter can upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'incident-media'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "incident-media: reporter can read own"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'incident-media'
    AND (
        auth.uid()::text = (storage.foldername(name))[1]
        OR
        EXISTS (
            SELECT 1
            FROM public.incidents i
            JOIN public.users u ON u.id = auth.uid()
            WHERE i.id::text = (storage.foldername(name))[2]
            AND i.assigned_agency_id = u.agency_id
            AND u.role IN ('agency_admin', 'super_admin', 'responder')
        )
    )
);

CREATE POLICY "incident-media: reporter can delete own"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'incident-media'
    AND auth.uid()::text = (storage.foldername(name))[1]
);
