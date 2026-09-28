-- ============================================================
-- Migration 020: Onboarding consent + identity verification
--
-- Three things this adds, and the reasoning for each.
--
-- 1. CONSENT. Nothing in this system currently records that a resident was
--    ever shown a privacy notice. Under the Data Privacy Act (RA 10173) the
--    consent has to be demonstrable, and "the app has a screen for it" is not
--    a record. The columns below capture what was agreed, which version of
--    the text, and in which language it was displayed -- that last one matters
--    because consent given against text the person could not read is not
--    consent.
--
-- 2. STRUCTURED IDENTITY. `full_name` is a single free-text field. You cannot
--    match a blob against the name printed on an ID card, which is precisely
--    what the new registration flow asks an admin to do. Name parts, date of
--    birth and sex are added alongside it. `full_name` is NOT dropped -- the
--    auth trigger, the dashboard and every incident payload read it -- it is
--    now composed from the parts by trigger, so both stay true at once.
--
-- 3. VERIFICATION EVIDENCE. Migration 015 added an ID scan. This adds the
--    selfie that goes with it, and the responder-side equivalent, so an
--    Agency Admin reviewing an account has the document, the face, and the
--    typed data side by side.
--
-- HONESTY NOTE ON LIVENESS -- read before treating it as a control.
--
--   The liveness check runs on the handset (ML Kit face detection with a
--   randomised blink / head-turn challenge). The server cannot verify that it
--   happened. A modified client can set `liveness_asserted_at` to anything.
--   The column is named "asserted" rather than "passed" for that reason.
--
--   It is a UX signal -- it stops honest users submitting a photo of a photo
--   by accident -- NOT a trust signal. verification_level must never be raised
--   by anything except a human looking at the evidence. If a later change
--   wants server-trustworthy liveness, that requires a server-side face API,
--   and this column is not a substitute for it.
--
-- Run AFTER migration 019.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Consent
--
-- Deliberately NOT frozen by RLS. Consent is the one thing the data subject
-- themselves gives, so the client has to be able to write it. The obvious
-- objection -- "a user could backdate their own consent" -- describes an
-- attack with no victim and no gain. Blocking the legitimate write to prevent
-- it would mean consent could only be recorded while the backend was
-- reachable, which on a rural connection means sometimes not at all.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS terms_version TEXT DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS privacy_version TEXT DEFAULT NULL;

-- Which language the notice was actually rendered in when they agreed.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS consent_locale TEXT DEFAULT NULL
        CHECK (consent_locale IS NULL OR consent_locale IN ('en', 'fil'));

COMMENT ON COLUMN public.users.terms_accepted_at IS
    'When this account agreed to the Terms of Use and Data Privacy Notice. '
    'NULL means never agreed -- re-prompt on next launch.';
COMMENT ON COLUMN public.users.consent_locale IS
    'Locale the consent text was displayed in. Consent against text the '
    'person could not read is not consent, so this is part of the record.';

-- ------------------------------------------------------------
-- 2. Structured name + person
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS first_name  TEXT DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS middle_name TEXT DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS last_name   TEXT DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS name_suffix TEXT DEFAULT NULL;

-- Age changes triage. A 3-year-old and a 40-year-old with the same reported
-- symptoms are not the same call, and the crew should know before arrival.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS date_of_birth DATE DEFAULT NULL
        CHECK (date_of_birth IS NULL OR
               (date_of_birth > '1900-01-01' AND date_of_birth <= CURRENT_DATE));

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS sex TEXT DEFAULT NULL
        CHECK (sex IS NULL OR sex IN ('male', 'female', 'prefer_not_to_say'));

COMMENT ON COLUMN public.users.date_of_birth IS
    'Used for triage context and to match against the ID document. Optional -- '
    'never required to register or to report an emergency.';

-- Keep full_name in step with the parts, without breaking anything that
-- already reads it. Only fires when the parts are actually populated, so the
-- existing rows (parts NULL, full_name set) are left exactly as they are.
CREATE OR REPLACE FUNCTION public.compose_full_name()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.first_name IS NOT NULL AND NEW.last_name IS NOT NULL THEN
        NEW.full_name := regexp_replace(
            trim(
                COALESCE(NEW.first_name, '')  || ' ' ||
                COALESCE(NEW.middle_name, '') || ' ' ||
                COALESCE(NEW.last_name, '')   || ' ' ||
                COALESCE(NEW.name_suffix, '')
            ),
            '\s+', ' ', 'g'
        );
    END IF;
    RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.compose_full_name() IS
    'Keeps users.full_name derived from the structured name parts. full_name '
    'remains the single field read by the auth trigger, the dashboard and the '
    'incident payload -- this trigger means adding parts did not require '
    'changing any of them.';

DROP TRIGGER IF EXISTS users_compose_full_name ON public.users;
CREATE TRIGGER users_compose_full_name
    BEFORE INSERT OR UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.compose_full_name();

-- ------------------------------------------------------------
-- 3. Address depth
--
-- barangay_id (012) is the routing key and stays authoritative. These two are
-- what a crew actually needs to find the door once they are in the barangay.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS purok_sitio    TEXT DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS street_address TEXT DEFAULT NULL;

-- ------------------------------------------------------------
-- 4. Verification evidence
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS selfie_image_path TEXT DEFAULT NULL;

-- See the honesty note in the header. Client-asserted, not server-verified.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS liveness_asserted_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS liveness_method TEXT DEFAULT NULL
        CHECK (liveness_method IS NULL OR liveness_method IN
               ('mlkit_blink', 'mlkit_head_turn', 'mlkit_smile', 'none'));

-- What the submitted evidence is claimed to prove about residency. An
-- LGU-issued ID proves it directly (the LGU only issues to its own
-- residents); a national ID proves identity but not where the holder lives.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS residency_proof_type TEXT DEFAULT NULL
        CHECK (residency_proof_type IS NULL OR residency_proof_type IN
               ('lgu_id', 'national_id', 'barangay_certificate',
                'utility_bill', 'none'));

COMMENT ON COLUMN public.users.selfie_image_path IS
    'Storage path in the PRIVATE "resident-ids" bucket, <user_id>/<filename>. '
    'Same retention rule as valid_id_image_path (migration 015): purge once '
    'verification_level has been decided.';
COMMENT ON COLUMN public.users.liveness_asserted_at IS
    'Set by the CLIENT after an on-device ML Kit challenge. NOT server-'
    'verifiable and NOT a trust signal -- see migration 020 header. Never '
    'raise verification_level from this column.';

-- ------------------------------------------------------------
-- 5. Responder-specific
--
-- Today an Agency Admin approves a responder on the strength of a typed badge
-- number with no evidence attached to it, because register_screen.dart
-- explicitly passes validIdImage: null for responders. That is the gap.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS rank_or_position     TEXT DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS unit_assignment      TEXT DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS date_joined          DATE DEFAULT NULL;
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS agency_id_image_path TEXT DEFAULT NULL;

COMMENT ON COLUMN public.users.agency_id_image_path IS
    'Storage path in the PRIVATE "responder-ids" bucket. Separate from '
    'resident-ids because the reader sets differ: a resident ID is reviewed '
    'by any verifying admin, an agency ID by that agency own admin.';

-- ------------------------------------------------------------
-- 6. Verification queue index
--
-- Partial index: the queue only ever asks for accounts that still need a
-- decision, so indexing the reviewed ones would be dead weight.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS users_verification_pending_idx
    ON public.users (created_at DESC)
    WHERE verification_level = 0 AND valid_id_image_path IS NOT NULL;

-- ------------------------------------------------------------
-- 7. RLS -- extend the frozen set
--
-- 012 froze the trust signals that existed then. Two points here.
--
-- (a) Nothing new is frozen outright: the client legitimately writes its own
--     consent, name, address, and evidence paths during registration. The
--     paths are already constrained by storage RLS to the user own folder.
--
-- (b) Identity becomes immutable ONCE VERIFIED. Without this, a resident
--     could be approved at level 2 and then quietly change their name or date
--     of birth, leaving an account that a dispatcher trusts but whose details
--     no longer match the document an admin actually checked. Below level 2
--     they can still correct their own typos freely.
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
        -- 020: once an admin has checked the document, the details it was
        -- checked against stop being self-editable.
        AND (
            (SELECT verification_level FROM public.users WHERE id = auth.uid()) < 2
            OR (
                    first_name    IS NOT DISTINCT FROM (SELECT first_name    FROM public.users WHERE id = auth.uid())
                AND middle_name   IS NOT DISTINCT FROM (SELECT middle_name   FROM public.users WHERE id = auth.uid())
                AND last_name     IS NOT DISTINCT FROM (SELECT last_name     FROM public.users WHERE id = auth.uid())
                AND name_suffix   IS NOT DISTINCT FROM (SELECT name_suffix   FROM public.users WHERE id = auth.uid())
                AND date_of_birth IS NOT DISTINCT FROM (SELECT date_of_birth FROM public.users WHERE id = auth.uid())
            )
        )
    );

-- ------------------------------------------------------------
-- 8. Grants
--
-- RLS and GRANT are separate gates. This project has hit 42501 from a missing
-- GRANT more than once -- the columns above are covered by the existing
-- table-level grant, but re-asserting it is free and the omission is the
-- single most common failure here.
-- ------------------------------------------------------------
GRANT SELECT, UPDATE ON public.users TO authenticated;
GRANT ALL ON public.users TO service_role;

-- ------------------------------------------------------------
-- 9. Verification
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name IN (
      'terms_accepted_at', 'terms_version', 'privacy_version', 'consent_locale',
      'first_name', 'middle_name', 'last_name', 'name_suffix',
      'date_of_birth', 'sex', 'purok_sitio', 'street_address',
      'selfie_image_path', 'liveness_asserted_at', 'liveness_method',
      'residency_proof_type', 'rank_or_position', 'unit_assignment',
      'date_joined', 'agency_id_image_path'
  )
ORDER BY column_name;

-- The compose trigger must be present, or full_name silently stops tracking
-- the parts and the dashboard starts showing stale names.
SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.users'::regclass
  AND tgname  = 'users_compose_full_name';

-- The policy must mention date_of_birth, or section 7(b) did not take.
SELECT polname,
       (pg_get_expr(polwithcheck, polrelid) LIKE '%date_of_birth%')
           AS freezes_identity_when_verified
FROM pg_policy
WHERE polrelid = 'public.users'::regclass
  AND polname  = 'users: update own profile';
