-- ============================================================
-- Migration 012: Residency verification + PWD accessibility
--
-- Two related problems this solves.
--
-- 1. RESIDENCY. `users.barangay` is free text, so there is nothing
--    connecting an account to an actual place in Biliran. This adds a
--    reference table of the province's municipalities and barangays and
--    points users at it by FK.
--
--    Design rule — verification NEVER gates reporting. A resident can
--    file an emergency report at verification_level 0. The level is
--    metadata the dispatcher sees, not a permission. Blocking an
--    unverified user from reporting an emergency would be a safety
--    defect, not a security feature.
--
-- 2. ACCESSIBILITY. A resident who is deaf or has a speech disability
--    cannot use a voice hotline at all, so this app is their only
--    channel. The accessibility columns are carried through to the
--    responding crew (see 012.4) so the crew knows before arrival.
--
-- Run AFTER migration 011.
--
-- ⚠ SEED DATA PROVENANCE — the barangay names below are a best-effort
--   transcription and are NOT authoritative. Verify every row against
--   the PSA Philippine Standard Geographic Code (PSGC) publication for
--   Region VIII / Biliran before production use, and fill in psgc_code
--   as you confirm each one. A wrong barangay name here misroutes a
--   dispatch. Rows with psgc_code IS NULL are unverified by definition.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Barangay reference table
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.barangays (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    municipality TEXT NOT NULL,
    name         TEXT NOT NULL,
    -- NULL until the row has been checked against the PSA PSGC list.
    psgc_code    TEXT DEFAULT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (municipality, name)
);

CREATE INDEX IF NOT EXISTS barangays_municipality_idx
    ON public.barangays(municipality);

COMMENT ON TABLE public.barangays IS
    'Reference list of Biliran barangays. Replaces free-text address entry so '
    'residency is structured and dispatch routing is reliable. psgc_code NULL '
    'means the row has not yet been verified against the PSA PSGC publication.';

-- Public reference data: readable by anyone, including during registration
-- (i.e. before the user has a session). Writes are service-key only.
ALTER TABLE public.barangays ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "barangays: public read" ON public.barangays;
CREATE POLICY "barangays: public read"
    ON public.barangays FOR SELECT
    TO anon, authenticated
    USING (TRUE);

GRANT SELECT ON public.barangays TO anon, authenticated;

-- service_role is what the FastAPI backend connects as. RLS and GRANT are
-- separate gates: without this the API gets 42501 regardless of policy.
GRANT ALL ON public.barangays TO service_role;

-- ------------------------------------------------------------
-- 2. Seed — Biliran province, 8 municipalities
-- ------------------------------------------------------------
INSERT INTO public.barangays (municipality, name) VALUES
-- Naval (provincial capital)
('Naval', 'Agpangi'), ('Naval', 'Anislagan'), ('Naval', 'Atipolo'),
('Naval', 'Borac'), ('Naval', 'Calumpang'), ('Naval', 'Capiñahan'),
('Naval', 'Caraycaray'), ('Naval', 'Catmon'), ('Naval', 'Haguikhikan'),
('Naval', 'Imelda'), ('Naval', 'Larrazabal'), ('Naval', 'Libertad'),
('Naval', 'Libtong'), ('Naval', 'Lico'), ('Naval', 'Lucsoon'),
('Naval', 'Mabini'), ('Naval', 'Padre Inocentes Garcia'),
('Naval', 'Padre Sergio Eamiguel'), ('Naval', 'Sabang'),
('Naval', 'San Pablo'), ('Naval', 'Santissimo Rosario'),
('Naval', 'Santo Niño'), ('Naval', 'Talustusan'), ('Naval', 'Villa Caneja'),
('Naval', 'Villa Consuelo'), ('Naval', 'Villa Enage'),
-- Almeria
('Almeria', 'Caucab'), ('Almeria', 'Iyosan'), ('Almeria', 'Jamorawon'),
('Almeria', 'Lo-ok'), ('Almeria', 'Looc'), ('Almeria', 'Matanga'),
('Almeria', 'Pili'), ('Almeria', 'Poblacion Norte'),
('Almeria', 'Poblacion Sur'), ('Almeria', 'Salangi'), ('Almeria', 'Sampao'),
('Almeria', 'Tabunan'), ('Almeria', 'Talahid'), ('Almeria', 'Tamarindo'),
-- Biliran (municipality)
('Biliran', 'Bato'), ('Biliran', 'Burabod'), ('Biliran', 'Canila'),
('Biliran', 'Hugpa'), ('Biliran', 'Julita'), ('Biliran', 'Pinangumhan'),
('Biliran', 'Poblacion'), ('Biliran', 'San Isidro'),
('Biliran', 'Sanggalang'), ('Biliran', 'Uson'),
-- Cabucgayan
('Cabucgayan', 'Balaquid'), ('Cabucgayan', 'Bunga'),
('Cabucgayan', 'Caanibongan'), ('Cabucgayan', 'Casiawan'),
('Cabucgayan', 'Esperanza'), ('Cabucgayan', 'Langgao'),
('Cabucgayan', 'Libertad'), ('Cabucgayan', 'Looc'),
('Cabucgayan', 'Magbangon'), ('Cabucgayan', 'Pawikan'),
('Cabucgayan', 'Salawaki'), ('Cabucgayan', 'Talibong'),
-- Caibiran
('Caibiran', 'Asug'), ('Caibiran', 'Binohangan'), ('Caibiran', 'Cabibihan'),
('Caibiran', 'Kawayanon'), ('Caibiran', 'Looc'), ('Caibiran', 'Manlabang'),
('Caibiran', 'Mainit'), ('Caibiran', 'Maurang'), ('Caibiran', 'Palanay'),
('Caibiran', 'Poblacion'), ('Caibiran', 'Tomalistis'), ('Caibiran', 'Union'),
('Caibiran', 'Uson'), ('Caibiran', 'Victory'),
-- Culaba
('Culaba', 'Acaban'), ('Culaba', 'Bacolod'), ('Culaba', 'Binongtoan'),
('Culaba', 'Bool Central'), ('Culaba', 'Bool East'), ('Culaba', 'Bool West'),
('Culaba', 'Culaba Central'), ('Culaba', 'Guindapunan'),
('Culaba', 'Habuhab'), ('Culaba', 'Looc'), ('Culaba', 'Marvel'),
('Culaba', 'Patag'), ('Culaba', 'Patag Norte'), ('Culaba', 'Salvacion'),
('Culaba', 'San Roque'), ('Culaba', 'Virginia'),
-- Kawayan
('Kawayan', 'Balacson'), ('Kawayan', 'Baganito'), ('Kawayan', 'Bilwang'),
('Kawayan', 'Bulalacao'), ('Kawayan', 'Burabod'), ('Kawayan', 'Buyo'),
('Kawayan', 'Inasuyan'), ('Kawayan', 'Kansanok'),
('Kawayan', 'Mapuyo'), ('Kawayan', 'Masagongsong'), ('Kawayan', 'Poblacion'),
('Kawayan', 'San Lorenzo'), ('Kawayan', 'Tabunan'), ('Kawayan', 'Ungale'),
-- Maripipi
('Maripipi', 'Agutay'), ('Maripipi', 'Banlas'), ('Maripipi', 'Binalayan East'),
('Maripipi', 'Binalayan West'), ('Maripipi', 'Binongtoan'),
('Maripipi', 'Calbani'), ('Maripipi', 'Canduhao'), ('Maripipi', 'Casibang'),
('Maripipi', 'Danao'), ('Maripipi', 'Ermita'), ('Maripipi', 'Olingan'),
('Maripipi', 'Poblacion'), ('Maripipi', 'Trabugan'), ('Maripipi', 'Viga')
ON CONFLICT (municipality, name) DO NOTHING;

-- ------------------------------------------------------------
-- 3. Residency columns on users
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS barangay_id UUID
        REFERENCES public.barangays(id) ON DELETE SET NULL;

-- 0 = unverified (can still report)
-- 1 = phone verified (SMS OTP)
-- 2 = resident verified (admin- or document-confirmed)
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS verification_level SMALLINT NOT NULL DEFAULT 0
        CHECK (verification_level BETWEEN 0 AND 2);

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS verification_method TEXT DEFAULT NULL
        CHECK (verification_method IS NULL OR verification_method IN
               ('phone_otp', 'barangay_official', 'pwd_id', 'government_id'));

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ DEFAULT NULL;

-- Valid ID — optional, and the route to level 2 for a resident who is not a
-- PWD. Only the type and number are stored, never a photo of the document:
-- an ID image is sensitive personal information under the Data Privacy Act
-- (RA 10173) and storing it would make this system a far larger breach
-- target for no operational gain. An Agency Admin confirms the number
-- against the physical card during review.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS valid_id_type TEXT DEFAULT NULL
        CHECK (valid_id_type IS NULL OR valid_id_type IN (
            -- LGU-issued: these prove residency in a specific municipality,
            -- which is exactly what this system needs.
            'barangay_id', 'voters_id', 'pwd_id', 'senior_citizen_id',
            -- National: prove identity but not Biliran residency on their own.
            'philsys', 'umid', 'drivers_license', 'passport',
            'postal_id', 'philhealth', 'sss', 'tin'
        ));

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS valid_id_number TEXT DEFAULT NULL;

COMMENT ON COLUMN public.users.valid_id_type IS
    'Optional ID used to reach verification_level 2. LGU-issued types '
    '(barangay_id, voters_id, pwd_id, senior_citizen_id) additionally prove '
    'residency, because the issuing LGU only issues to its own residents. '
    'Never required to register or to report an emergency.';
COMMENT ON COLUMN public.users.valid_id_number IS
    'ID number only — never an image of the document. Verified against the '
    'physical card by an Agency Admin.';

CREATE INDEX IF NOT EXISTS users_barangay_idx ON public.users(barangay_id);

COMMENT ON COLUMN public.users.verification_level IS
    'Tiered trust: 0 unverified, 1 phone-verified, 2 resident-verified. '
    'Displayed to dispatchers as reporter credibility. NEVER used to block '
    'incident submission — an unverified resident in an emergency must still '
    'be able to report.';

-- ------------------------------------------------------------
-- 4. Accessibility columns on users
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS is_pwd BOOLEAN NOT NULL DEFAULT FALSE;

-- LGU-issued PWD ID (RA 7277 / RA 10754). Issued by the MSWDO/PDAO of the
-- holder's own municipality, so it doubles as proof of residency.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS pwd_id_number TEXT DEFAULT NULL;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS disability_types TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS accessibility_notes TEXT DEFAULT NULL;

-- Preferred contact mode matters operationally: calling a deaf resident to
-- confirm an incident wastes minutes and may abort the dispatch.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS preferred_contact_mode TEXT NOT NULL DEFAULT 'any'
        CHECK (preferred_contact_mode IN ('any', 'sms_only', 'app_only', 'voice_ok'));

-- Set when a caregiver, barangay health worker or relative registered on
-- behalf of a resident who could not complete the form themselves.
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS registered_by UUID
        REFERENCES public.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.users.disability_types IS
    'Subset of: visual, hearing, speech, mobility, intellectual, psychosocial. '
    'Surfaced to the responding crew via the incident payload so they arrive '
    'prepared (e.g. do not attempt voice contact with a deaf reporter).';
COMMENT ON COLUMN public.users.pwd_id_number IS
    'LGU-issued PWD ID. Doubles as residency evidence because it is issued by '
    'the holder''s own municipality. Optional — never required to register.';
COMMENT ON COLUMN public.users.registered_by IS
    'Set when another user completed registration on this resident''s behalf '
    '(assisted registration). NULL for self-registered accounts.';

-- ------------------------------------------------------------
-- 5. RLS — freeze the fields a user must not set on themselves
--
-- SECURITY: verification_level and is_pwd/pwd_id_number are trust signals
-- shown to dispatchers. Without adding them to the existing WITH CHECK, a
-- resident could PATCH their own row to verification_level = 2 and appear
-- as a confirmed resident. The existing policy only froze role,
-- approval_status, agency_id and badge_id — every column added after it
-- was silently self-writable.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "users: update own profile" ON public.users;

CREATE POLICY "users: update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        role                = (SELECT role                FROM public.users WHERE id = auth.uid())
        AND approval_status = (SELECT approval_status     FROM public.users WHERE id = auth.uid())
        AND agency_id       IS NOT DISTINCT FROM (SELECT agency_id FROM public.users WHERE id = auth.uid())
        AND COALESCE(badge_id,'') = COALESCE((SELECT badge_id FROM public.users WHERE id = auth.uid()),'')
        -- Added in 012: trust signals are assigned by the system, not the user.
        AND verification_level  = (SELECT verification_level FROM public.users WHERE id = auth.uid())
        AND verification_method IS NOT DISTINCT FROM (SELECT verification_method FROM public.users WHERE id = auth.uid())
        AND verified_at         IS NOT DISTINCT FROM (SELECT verified_at         FROM public.users WHERE id = auth.uid())
        AND registered_by       IS NOT DISTINCT FROM (SELECT registered_by       FROM public.users WHERE id = auth.uid())
    );

-- ------------------------------------------------------------
-- 6. Verification queries
-- ------------------------------------------------------------
SELECT municipality, COUNT(*) AS barangay_count
FROM public.barangays
GROUP BY municipality
ORDER BY municipality;

-- Rows still awaiting PSGC confirmation:
SELECT COUNT(*) AS unverified_barangays
FROM public.barangays
WHERE psgc_code IS NULL;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'users'
  AND column_name IN (
      'barangay_id', 'verification_level', 'verification_method', 'verified_at',
      'is_pwd', 'pwd_id_number', 'disability_types', 'accessibility_notes',
      'preferred_contact_mode', 'registered_by'
  )
ORDER BY column_name;
