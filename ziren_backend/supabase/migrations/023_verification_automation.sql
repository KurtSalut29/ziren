-- ============================================================
-- Migration 023: Pre-screen the verification queue
--
-- WHAT THIS IS FOR
--
-- An Agency Admin verifying a resident today opens a submission, looks at a
-- photograph of an ID and a selfie, and decides whether they are the same
-- person. That is the whole check. It is slow, it is almost always "yes", and
-- the small number of times it should be "no" are exactly the ones that an
-- hour of identical decisions makes easiest to miss.
--
-- These columns hold what the app worked out BEFORE a human opened the row, so
-- the queue can be sorted by what actually needs attention. The requirement
-- was phrased that way: make the check automatic "so that admins will just
-- double check the users".
--
-- NONE OF IT DECIDES ANYTHING
--
-- Same rule as migration 020's liveness note, and for the same reason. These
-- are SIGNALS. verification_level is raised only by a person, and
-- decide_verification is the only thing that writes it. Specifically:
--
--   * face_match_verdict = 'no_match' does NOT reject anybody. An ID
--     photograph fifteen years old, taken before an illness, or of someone
--     wearing a hijab in one image and not the other, will score badly and be
--     approved by an admin in four seconds.
--   * The client computes these. A modified app can send anything. They are
--     the same class of evidence as liveness_asserted_at, which migration 020
--     is explicit about: useful for triage, worthless as a trust boundary.
--   * Verification has never been a permission in Ziren. An unverified
--     resident reports an emergency exactly like a verified one (migration
--     012). Nothing here can stop anyone calling for help.
--
-- The face embedding model is optional and is not committed to the repository
-- (see scripts/fetch_face_model.py). A deployment without it writes
-- face_match_verdict = 'unavailable', which is a real, supported state and
-- reads on the dashboard as "check this by eye" -- exactly what an admin did
-- before this existed.
--
-- Requires: migrations 012, 015 and 020 already applied. Idempotent.
-- Run in Supabase SQL Editor AFTER 022.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Face match: ID portrait vs selfie
-- ------------------------------------------------------------

-- Cosine similarity in [-1, 1]. REAL, not NUMERIC: this is a model score with
-- four meaningful decimal places, not money.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS face_match_score REAL DEFAULT NULL;

-- Six values, and the three failure kinds are held apart on purpose. "We could
-- not find a face on the card" and "the faces do not match" are different
-- problems with different fixes -- one is a retake, the other is a review --
-- and collapsing them into a single boolean would lose the only part an admin
-- can act on.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS face_match_verdict TEXT DEFAULT NULL
        CHECK (face_match_verdict IS NULL OR face_match_verdict IN (
            'match',              -- above the match threshold
            'uncertain',          -- between the two thresholds
            'no_match',           -- below the no-match threshold
            'no_face_on_id',      -- ML Kit found no face on the card
            'no_face_in_selfie',  -- ML Kit found no face in the selfie
            'unavailable'         -- model not installed on this deployment
        ));

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS face_match_checked_at TIMESTAMPTZ DEFAULT NULL;

-- Which model produced the score. Without it, a later model swap or threshold
-- change leaves two incomparable populations of numbers in one column, both
-- looking like the same measurement.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS face_match_model TEXT DEFAULT NULL;

COMMENT ON COLUMN public.users.face_match_score IS
    'Cosine similarity between the ID portrait and the selfie, computed by the '
    'ArcFace model named in face_match_model. Advisory only -- never raise '
    'verification_level from it. See migration 023 header.';
COMMENT ON COLUMN public.users.face_match_verdict IS
    'Banded reading of face_match_score, or the reason no score exists. '
    'no_match means "look at this first", NOT "reject this".';

-- ------------------------------------------------------------
-- 2. What the on-device ID checks found
--
-- JSONB rather than a column per check. The set of checks will change as real
-- Philippine ID cards are seen in the field -- a new ID type, a new number
-- format, an expiry printed somewhere unexpected -- and each of those would
-- otherwise be a migration. Nothing queries an individual key; the dashboard
-- renders whatever is present and the review flags read two named keys with
-- COALESCE defaults, so an older row missing a key is not an error.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS id_checks JSONB DEFAULT NULL;

COMMENT ON COLUMN public.users.id_checks IS
    'On-device checks of the photographed ID: {readable, face_found, '
    'number_format_ok, expired, expiry_date, ...}. Client-computed and '
    'therefore advisory. Shape is deliberately open -- see migration 023.';

-- ------------------------------------------------------------
-- 3. Where the ID number came from
--
-- valid_id_number has existed since migration 012 and has always been typed by
-- hand. Now it can be read off the card by OCR, and the difference matters to
-- whoever reviews it: a number the OCR read and the person left alone was
-- checked against the card by a machine, and one they typed themselves was
-- not. An admin chasing a duplicate-ID flag needs to know which they are
-- looking at before deciding whether a mismatch is fraud or a typo.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS id_number_source TEXT DEFAULT NULL
        CHECK (id_number_source IS NULL OR id_number_source IN (
            'typed',       -- entered by hand, no OCR involved
            'ocr',         -- read off the card and accepted unchanged
            'ocr_edited'   -- read off the card, then corrected by the person
        ));

COMMENT ON COLUMN public.users.id_number_source IS
    'Whether valid_id_number was typed, read by OCR, or read and then '
    'corrected. Tells a reviewing admin how much the number has been checked.';

-- ------------------------------------------------------------
-- 4. Index the submissions that actually need a look
--
-- Partial, and narrow on purpose: this is the "show me the ones that matter"
-- query the verification queue runs when priority_only is set. Indexing the
-- clean submissions would be dead weight, since nothing ever asks for them by
-- verdict.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS users_face_match_needs_review_idx
    ON public.users (created_at DESC)
    WHERE verification_level = 0
      AND face_match_verdict IN ('no_match', 'uncertain', 'no_face_on_id');

-- ------------------------------------------------------------
-- 5. RLS -- freeze the new signals once a decision has been made
--
-- The client legitimately writes all six columns during registration, so they
-- are NOT frozen outright: the checks run on the handset and there is nowhere
-- else for them to come from.
--
-- What must not happen is a resident rewriting their own face_match_verdict
-- after an admin has approved them, leaving an approved account whose evidence
-- no longer describes what was approved. Migration 020 froze identity at
-- verification_level >= 2 for exactly this reason; this extends the same rule
-- to the new signals rather than inventing a second one.
--
-- IT EXTENDS THE EXISTING POLICY. It does not add a new one, and the
-- difference is not stylistic. Multiple PERMISSIVE policies for the same
-- command are OR-ed together in Postgres, so a second UPDATE policy on
-- public.users whose WITH CHECK is merely `id = auth.uid()` would not tighten
-- anything -- it would hand every user a second, unguarded route past every
-- freeze migrations 012 and 020 put in place. The first draft of this file did
-- exactly that.
--
-- So "users: update own profile" is dropped and recreated in full, with 020's
-- clauses restated verbatim and the new columns appended. Repetition beats a
-- reader reconstructing the live policy across three migrations.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "users: update own profile" ON public.users;

CREATE POLICY "users: update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        role                = (SELECT role            FROM public.users WHERE id = auth.uid())
        AND approval_status = (SELECT approval_status FROM public.users WHERE id = auth.uid())
        AND agency_id       IS NOT DISTINCT FROM (SELECT agency_id FROM public.users WHERE id = auth.uid())
        AND COALESCE(badge_id,'') = COALESCE((SELECT badge_id FROM public.users WHERE id = auth.uid()),'')
        -- 012: trust signals are assigned by the system, not the user.
        AND verification_level  = (SELECT verification_level  FROM public.users WHERE id = auth.uid())
        AND verification_method IS NOT DISTINCT FROM (SELECT verification_method FROM public.users WHERE id = auth.uid())
        AND verified_at         IS NOT DISTINCT FROM (SELECT verified_at         FROM public.users WHERE id = auth.uid())
        AND registered_by       IS NOT DISTINCT FROM (SELECT registered_by       FROM public.users WHERE id = auth.uid())
        -- 020 + 023: once an admin has checked the document, the details it was
        -- checked against -- and the evidence it was checked alongside -- stop
        -- being self-editable.
        AND (
            (SELECT verification_level FROM public.users WHERE id = auth.uid()) < 2
            OR (
                    first_name    IS NOT DISTINCT FROM (SELECT first_name    FROM public.users WHERE id = auth.uid())
                AND middle_name   IS NOT DISTINCT FROM (SELECT middle_name   FROM public.users WHERE id = auth.uid())
                AND last_name     IS NOT DISTINCT FROM (SELECT last_name     FROM public.users WHERE id = auth.uid())
                AND name_suffix   IS NOT DISTINCT FROM (SELECT name_suffix   FROM public.users WHERE id = auth.uid())
                AND date_of_birth IS NOT DISTINCT FROM (SELECT date_of_birth FROM public.users WHERE id = auth.uid())
                -- 023: the pre-screen evidence, frozen with the identity it
                -- describes.
                AND valid_id_type      IS NOT DISTINCT FROM (SELECT valid_id_type      FROM public.users WHERE id = auth.uid())
                AND valid_id_number    IS NOT DISTINCT FROM (SELECT valid_id_number    FROM public.users WHERE id = auth.uid())
                AND face_match_verdict IS NOT DISTINCT FROM (SELECT face_match_verdict FROM public.users WHERE id = auth.uid())
                AND face_match_score   IS NOT DISTINCT FROM (SELECT face_match_score   FROM public.users WHERE id = auth.uid())
                AND id_checks          IS NOT DISTINCT FROM (SELECT id_checks          FROM public.users WHERE id = auth.uid())
            )
        )
    );

-- ------------------------------------------------------------
-- Verification
--
-- Expect five rows: face_match_checked_at, face_match_model,
-- face_match_score, face_match_verdict, id_checks, id_number_source
-- (six, in name order). An empty result means the ALTERs did not run and the
-- registration flow will 500 with PGRST204 on its first face-match write.
-- ------------------------------------------------------------
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name IN (
      'face_match_score', 'face_match_verdict', 'face_match_checked_at',
      'face_match_model', 'id_checks', 'id_number_source'
  )
ORDER BY column_name;
