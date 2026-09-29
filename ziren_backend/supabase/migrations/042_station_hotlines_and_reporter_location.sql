-- 042: official station hotlines + where the reporter stood
--
-- Run once in the Supabase SQL Editor. Safe to re-run: every statement is
-- idempotent (ADD COLUMN IF NOT EXISTS, and UPDATEs that set fixed values).
--
-- ── 1. Official station hotlines ─────────────────────────────────────────
--
-- Supplied by the stations themselves (2026-09-30) to replace the three
-- placeholder numbers seeded in 002. They are what a resident with no
-- internet calls instead of reporting, so the app also ships a copy of this
-- list (ziren_mobile/lib/features/hotlines/domain/station_hotlines.dart) —
-- keep the two in step.
--
-- Format of agencies.contact_number, read by the app and the dashboard:
--   one number                     0905-480-1417
--   several, labelled or not       Globe: 0955-723-6300; Smart: 0948-024-3466
-- Numbers are separated by ";". An optional "Label:" names the network or
-- line. An agency admin can edit this from the dashboard (Agency profile).

UPDATE public.agencies SET contact_number = CASE id
  -- Naval
  WHEN 'a0000001-0000-0000-0000-000000000001' THEN 'Globe: 0955-723-6300; Smart: 0948-024-3466; Landline: (053) 500-9546'
  WHEN 'a0000001-0000-0000-0000-000000000002' THEN 'Smart: 0921-555-3961'
  WHEN 'a0000001-0000-0000-0000-000000000003' THEN '0905-480-1417'
  -- Almeria
  WHEN 'a0000002-0000-0000-0000-000000000001' THEN 'Globe: 0927-733-2298'
  WHEN 'a0000002-0000-0000-0000-000000000002' THEN 'Smart: 0928-830-7633'
  WHEN 'a0000002-0000-0000-0000-000000000003' THEN '0936-721-6929'
  -- Biliran
  WHEN 'a0000003-0000-0000-0000-000000000001' THEN '0977-269-0942'
  WHEN 'a0000003-0000-0000-0000-000000000002' THEN '0928-766-2020; 0998-847-9659'
  WHEN 'a0000003-0000-0000-0000-000000000003' THEN '0963-118-2800'
  -- Cabucgayan
  WHEN 'a0000004-0000-0000-0000-000000000001' THEN '0912-587-8288; 0917-320-6105'
  WHEN 'a0000004-0000-0000-0000-000000000002' THEN '0977-819-6634; 0910-355-3511'
  WHEN 'a0000004-0000-0000-0000-000000000003' THEN '0977-810-8015'
  -- Caibiran
  WHEN 'a0000005-0000-0000-0000-000000000001' THEN '0917-115-0372'
  WHEN 'a0000005-0000-0000-0000-000000000002' THEN '0938-984-9929'
  WHEN 'a0000005-0000-0000-0000-000000000003' THEN 'MDRRMO/EMS: 0969-189-2388'
  -- Culaba
  WHEN 'a0000006-0000-0000-0000-000000000001' THEN 'Globe: 0956-631-0409'
  WHEN 'a0000006-0000-0000-0000-000000000002' THEN '0998-598-6558'
  WHEN 'a0000006-0000-0000-0000-000000000003' THEN '0967-132-8850'
  -- Kawayan
  WHEN 'a0000007-0000-0000-0000-000000000001' THEN 'Globe: 0953-394-9486; Smart: 0929-168-8304'
  WHEN 'a0000007-0000-0000-0000-000000000002' THEN '0999-187-9043'
  WHEN 'a0000007-0000-0000-0000-000000000003' THEN '0917-137-5989'
  ELSE contact_number
END
WHERE id IN (
  'a0000001-0000-0000-0000-000000000001', 'a0000001-0000-0000-0000-000000000002', 'a0000001-0000-0000-0000-000000000003',
  'a0000002-0000-0000-0000-000000000001', 'a0000002-0000-0000-0000-000000000002', 'a0000002-0000-0000-0000-000000000003',
  'a0000003-0000-0000-0000-000000000001', 'a0000003-0000-0000-0000-000000000002', 'a0000003-0000-0000-0000-000000000003',
  'a0000004-0000-0000-0000-000000000001', 'a0000004-0000-0000-0000-000000000002', 'a0000004-0000-0000-0000-000000000003',
  'a0000005-0000-0000-0000-000000000001', 'a0000005-0000-0000-0000-000000000002', 'a0000005-0000-0000-0000-000000000003',
  'a0000006-0000-0000-0000-000000000001', 'a0000006-0000-0000-0000-000000000002', 'a0000006-0000-0000-0000-000000000003',
  'a0000007-0000-0000-0000-000000000001', 'a0000007-0000-0000-0000-000000000002', 'a0000007-0000-0000-0000-000000000003'
);

-- ── 2. Where the reporter stood ──────────────────────────────────────────
--
-- incidents.location is WHERE THE INCIDENT IS: it routes the report and is
-- where a crew drives. A resident can now report an incident they are not at
-- (a relative in Larrazabal called them in Kawayan) by placing it on the map;
-- the app then sends their own position here so the dispatcher sees the two
-- differ and can call back to confirm. Both stay NULL/false for the usual
-- "I am at the incident" report.

ALTER TABLE public.incidents
  ADD COLUMN IF NOT EXISTS reported_from_elsewhere BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS reporter_location       GEOMETRY(POINT, 4326),
  ADD COLUMN IF NOT EXISTS reporter_address        TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'incidents_reporter_address_len'
  ) THEN
    ALTER TABLE public.incidents
      ADD CONSTRAINT incidents_reporter_address_len CHECK (char_length(reporter_address) <= 300);
  END IF;
END $$;

COMMENT ON COLUMN public.incidents.reported_from_elsewhere IS
  'True when the reporter placed the incident on the map instead of reporting where they stand.';
COMMENT ON COLUMN public.incidents.reporter_location IS
  'Where the reporter was when reporting from elsewhere. incidents.location stays the incident itself.';
COMMENT ON COLUMN public.incidents.reporter_address IS
  'Human-readable place of reporter_location, as the app named it.';

-- PostgREST caches the schema; make the new columns visible immediately.
NOTIFY pgrst, 'reload schema';
