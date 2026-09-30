-- 043: announcements v2 - safety alerts aimed at places, and residents answering them
--
-- Run once in the Supabase SQL Editor. Safe to re-run: every statement is
-- idempotent (ADD COLUMN IF NOT EXISTS, CREATE ... IF NOT EXISTS, and the
-- category check is dropped and re-added).
--
-- WHY. Announcements could only be aimed at a ROLE ("all residents") or one
-- agency. An evacuation order is for two barangays of one town: sent to the
-- whole province, everyone else learns to ignore the next one - which is how a
-- warning system stops working. And once it was sent, nobody could tell who had
-- read it, who was safe, or who was still waiting for help.
--
-- WHAT.
--   1. New kinds of announcement - evacuation order, weather advisory, hazard
--      warning, road closure, missing person, all clear, relief, health, drill,
--      power/water interruption - beside the six that already existed.
--   2. details: the facts each kind needs (the wind signal, the evacuation
--      centres, the road), as JSON so a new field is not a new migration.
--   3. target_municipalities / target_barangays: WHERE it applies. NULL means
--      the whole province, as before, so every existing row keeps its meaning.
--      target_barangays holds {id, name, municipality} so the phone can say
--      "Brgy. Atipolo, Caraycaray" without a join.
--   4. asks_response + announcement_responses: a resident answers "I am safe"
--      or "I need help"; the station sees who needs help and who has not
--      answered, and marks when someone has been reached.
--   5. ends_announcement_id / ended_at / ended_by_announcement_id: an "all
--      clear" ends the warning it answers, and the warning remembers what
--      ended it.
--   6. issuer_agency_type: which Provincial Admin (BFP, PNP, MDRRMO) issued it,
--      shown to the people it reaches.
--
-- The backend keeps working before this is run: an announcement that uses
-- none of the new fields is still published the old way. One that does is
-- refused with a message naming this file.

-- ── 1. The kinds ──────────────────────────────────────────────────────────

DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.announcements'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%category%'
  LOOP
    EXECUTE format('ALTER TABLE public.announcements DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.announcements
  ADD CONSTRAINT announcements_category_check CHECK (category IN (
    -- safety alerts
    'evacuation', 'weather', 'hazard', 'road_closure', 'missing_person', 'all_clear', 'emergency',
    -- information
    'relief', 'health', 'drill', 'utility',
    'maintenance', 'service_interruption', 'feature', 'reminder', 'general'
  ));

-- ── 2-6. The new columns ──────────────────────────────────────────────────

ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS details                  JSONB   NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS target_municipalities    TEXT[],
  ADD COLUMN IF NOT EXISTS target_barangays         JSONB,
  ADD COLUMN IF NOT EXISTS asks_response            BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS issuer_agency_type       TEXT,
  ADD COLUMN IF NOT EXISTS ends_announcement_id     UUID REFERENCES public.announcements(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ended_at                 TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ended_by_announcement_id UUID REFERENCES public.announcements(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.announcements.details IS
  'Facts for the kind: weather {signal, rainfall, storm_name}, hazard {hazard}, evacuation {kind, centers[], bring}, road_closure {road, alternate, reopens}, missing_person {name, age, last_seen, description, contact}, ...';
COMMENT ON COLUMN public.announcements.target_municipalities IS
  'Where it applies. NULL = the whole province.';
COMMENT ON COLUMN public.announcements.target_barangays IS
  'Narrows a municipality to these barangays: [{id, name, municipality}]. A municipality with none listed is covered whole.';
COMMENT ON COLUMN public.announcements.asks_response IS
  'Residents it reaches are asked to answer "I am safe" or "I need help" (announcement_responses).';

-- ── 4. The answers ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.announcement_responses (
  announcement_id UUID NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status          TEXT NOT NULL CHECK (status IN ('safe', 'need_help')),
  note            TEXT CHECK (char_length(note) <= 300),
  latitude        DOUBLE PRECISION CHECK (latitude BETWEEN -90 AND 90),
  longitude       DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180),
  responded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  handled_at      TIMESTAMPTZ,
  handled_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  PRIMARY KEY (announcement_id, user_id)
);

CREATE INDEX IF NOT EXISTS announcement_responses_status_idx
  ON public.announcement_responses (announcement_id, status);

COMMENT ON TABLE public.announcement_responses IS
  'A resident''s answer to a safety alert. Written only by the backend (service role).';

ALTER TABLE public.announcement_responses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "announcement_responses: resident reads own" ON public.announcement_responses;
CREATE POLICY "announcement_responses: resident reads own"
  ON public.announcement_responses FOR SELECT
  USING (user_id = auth.uid());

-- Same pattern as 028: writes go through the backend's service-role client, so
-- the GRANT is what matters (see migration 025's header for the 42501 it avoids).
GRANT ALL ON public.announcement_responses TO service_role;
GRANT ALL ON public.announcements TO service_role;

-- PostgREST caches the schema; make the new columns visible immediately.
NOTIFY pgrst, 'reload schema';

-- Verification - run after applying. Expect 8 new columns and the table.
SELECT column_name, data_type FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'announcements'
   AND column_name IN ('details', 'target_municipalities', 'target_barangays', 'asks_response',
                       'issuer_agency_type', 'ends_announcement_id', 'ended_at', 'ended_by_announcement_id')
 ORDER BY column_name;
SELECT tablename, rowsecurity FROM pg_tables
 WHERE schemaname = 'public' AND tablename = 'announcement_responses';
