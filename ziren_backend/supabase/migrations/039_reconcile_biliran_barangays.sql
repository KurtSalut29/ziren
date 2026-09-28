-- ============================================================
-- Migration 039: reconcile public.barangays with the PSA PSGC list
--
-- WHY. Testers registering from other barangays could not find theirs.
-- Migration 012 seeded 120 rows as a "best-effort transcription" (its header
-- says so, and that a wrong name misroutes a dispatch); the Philippine
-- Standard Geographic Code (PSGC) lists 132 barangays for Biliran. Compared
-- name by name, the table was missing 25 real barangays, had a few names
-- misspelled or filed under the wrong municipality (Villa Enage is Biliran's,
-- not Naval's; Salawaki is Salawad; Tabunan in Kawayan is Tabunan North), and
-- carried a handful that are not barangays at all (Poblacion Norte/Sur in
-- Almeria, "Poblacion" in three towns that have named poblacion barangays).
--
-- SOURCE. https://psgc.gitlab.io/api (PSGC, municipality by municipality).
-- Names follow the table's existing convention - the "(Pob.)" marker is left
-- off. psgc_code is filled in on every row that matches, which is what
-- migration 012 said to do as each row was confirmed.
--
-- SAFE BY CONSTRUCTION. Data only, no DDL. Idempotent - running it twice
-- changes nothing the second time. users.barangay_id is the only reference to
-- this table (ON DELETE SET NULL), so:
--   1. a misspelt/misplaced row is renamed IN PLACE (same id: every resident
--      who picked it keeps their barangay);
--   2. a duplicate of a real barangay is MERGED - residents are repointed at
--      the real one, then the duplicate is deleted;
--   3. a row that is not a barangay is deleted ONLY if no resident points at
--      it; otherwise it stays, and shows in the final check below.
--
-- Run in the Supabase SQL Editor. Expected result of the final check:
--   Almeria 13, Biliran 11, Cabucgayan 13, Caibiran 17, Culaba 17,
--   Kawayan 20, Maripipi 15, Naval 26  (= 132), and 0 rows without a psgc_code
--   unless a resident still points at one of the leftovers.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Rename / move misspelt or misplaced rows in place
-- ------------------------------------------------------------
UPDATE public.barangays SET municipality = 'Almeria', name = 'Poblacion', psgc_code = '087801007'
 WHERE municipality = 'Almeria' AND name = 'Poblacion Norte'
   AND NOT EXISTS (SELECT 1 FROM public.barangays x WHERE x.municipality = 'Almeria' AND x.name = 'Poblacion');
UPDATE public.barangays SET municipality = 'Cabucgayan', name = 'Salawad', psgc_code = '087803013'
 WHERE municipality = 'Cabucgayan' AND name = 'Salawaki'
   AND NOT EXISTS (SELECT 1 FROM public.barangays x WHERE x.municipality = 'Cabucgayan' AND x.name = 'Salawad');
UPDATE public.barangays SET municipality = 'Kawayan', name = 'Tabunan North', psgc_code = '087806013'
 WHERE municipality = 'Kawayan' AND name = 'Tabunan'
   AND NOT EXISTS (SELECT 1 FROM public.barangays x WHERE x.municipality = 'Kawayan' AND x.name = 'Tabunan North');
UPDATE public.barangays SET municipality = 'Maripipi', name = 'Ol-og', psgc_code = '087807014'
 WHERE municipality = 'Maripipi' AND name = 'Olingan'
   AND NOT EXISTS (SELECT 1 FROM public.barangays x WHERE x.municipality = 'Maripipi' AND x.name = 'Ol-og');
UPDATE public.barangays SET municipality = 'Biliran', name = 'Villa Enage', psgc_code = '087802011'
 WHERE municipality = 'Naval' AND name = 'Villa Enage'
   AND NOT EXISTS (SELECT 1 FROM public.barangays x WHERE x.municipality = 'Biliran' AND x.name = 'Villa Enage');

-- ------------------------------------------------------------
-- 2. Merge duplicates of a real barangay into it
-- ------------------------------------------------------------
UPDATE public.users SET barangay_id = (SELECT id FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Poblacion')
 WHERE barangay_id = (SELECT id FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Poblacion Sur')
   AND EXISTS (SELECT 1 FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Poblacion');
DELETE FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Poblacion Sur'
   AND EXISTS (SELECT 1 FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Poblacion');
UPDATE public.users SET barangay_id = (SELECT id FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Lo-ok')
 WHERE barangay_id = (SELECT id FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Looc')
   AND EXISTS (SELECT 1 FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Lo-ok');
DELETE FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Looc'
   AND EXISTS (SELECT 1 FROM public.barangays WHERE municipality = 'Almeria' AND name = 'Lo-ok');
UPDATE public.users SET barangay_id = (SELECT id FROM public.barangays WHERE municipality = 'Culaba' AND name = 'Patag')
 WHERE barangay_id = (SELECT id FROM public.barangays WHERE municipality = 'Culaba' AND name = 'Patag Norte')
   AND EXISTS (SELECT 1 FROM public.barangays WHERE municipality = 'Culaba' AND name = 'Patag');
DELETE FROM public.barangays WHERE municipality = 'Culaba' AND name = 'Patag Norte'
   AND EXISTS (SELECT 1 FROM public.barangays WHERE municipality = 'Culaba' AND name = 'Patag');

-- ------------------------------------------------------------
-- 3. Insert the official barangays that were missing (20)
-- ------------------------------------------------------------
INSERT INTO public.barangays (municipality, name, psgc_code) VALUES
('Almeria', 'Pulang Bato', '087801008'),
('Biliran', 'Busali', '087802003'),
('Biliran', 'San Roque', '087802009'),
('Cabucgayan', 'Baso', '087803002'),
('Caibiran', 'Alegria', '087804001'),
('Caibiran', 'Bari-is', '087804003'),
('Caibiran', 'Caulangohan', '087804010'),
('Caibiran', 'Palengke', '087804013'),
('Caibiran', 'Villa Vicenta', '087804018'),
('Culaba', 'Calipayan', '087805007'),
('Culaba', 'Pinamihagan', '087805013'),
('Kawayan', 'Mada-o', '087806008'),
('Kawayan', 'Masagaosao', '087806010'),
('Kawayan', 'Tubig Guinoo', '087806014'),
('Kawayan', 'Tucdao', '087806015'),
('Kawayan', 'Balite', '087806017'),
('Kawayan', 'Villa Cornejo', '087806019'),
('Maripipi', 'Bato', '087807003'),
('Maripipi', 'Burabod', '087807008'),
('Naval', 'Cabungaan', '087808022')
ON CONFLICT (municipality, name) DO NOTHING;

-- ------------------------------------------------------------
-- 4. Record the PSGC code on every row that matches an official barangay
--    (107 rows; names are left exactly as they are)
-- ------------------------------------------------------------
UPDATE public.barangays SET psgc_code = '087801001' WHERE municipality = 'Almeria' AND name = 'Caucab' AND psgc_code IS DISTINCT FROM '087801001';
UPDATE public.barangays SET psgc_code = '087801002' WHERE municipality = 'Almeria' AND name = 'Iyosan' AND psgc_code IS DISTINCT FROM '087801002';
UPDATE public.barangays SET psgc_code = '087801003' WHERE municipality = 'Almeria' AND name = 'Jamorawon' AND psgc_code IS DISTINCT FROM '087801003';
UPDATE public.barangays SET psgc_code = '087801004' WHERE municipality = 'Almeria' AND name = 'Lo-ok' AND psgc_code IS DISTINCT FROM '087801004';
UPDATE public.barangays SET psgc_code = '087801005' WHERE municipality = 'Almeria' AND name = 'Matanga' AND psgc_code IS DISTINCT FROM '087801005';
UPDATE public.barangays SET psgc_code = '087801006' WHERE municipality = 'Almeria' AND name = 'Pili' AND psgc_code IS DISTINCT FROM '087801006';
UPDATE public.barangays SET psgc_code = '087801009' WHERE municipality = 'Almeria' AND name = 'Salangi' AND psgc_code IS DISTINCT FROM '087801009';
UPDATE public.barangays SET psgc_code = '087801010' WHERE municipality = 'Almeria' AND name = 'Sampao' AND psgc_code IS DISTINCT FROM '087801010';
UPDATE public.barangays SET psgc_code = '087801011' WHERE municipality = 'Almeria' AND name = 'Tabunan' AND psgc_code IS DISTINCT FROM '087801011';
UPDATE public.barangays SET psgc_code = '087801012' WHERE municipality = 'Almeria' AND name = 'Talahid' AND psgc_code IS DISTINCT FROM '087801012';
UPDATE public.barangays SET psgc_code = '087801013' WHERE municipality = 'Almeria' AND name = 'Tamarindo' AND psgc_code IS DISTINCT FROM '087801013';
UPDATE public.barangays SET psgc_code = '087802001' WHERE municipality = 'Biliran' AND name = 'Bato' AND psgc_code IS DISTINCT FROM '087802001';
UPDATE public.barangays SET psgc_code = '087802002' WHERE municipality = 'Biliran' AND name = 'Burabod' AND psgc_code IS DISTINCT FROM '087802002';
UPDATE public.barangays SET psgc_code = '087802006' WHERE municipality = 'Biliran' AND name = 'Canila' AND psgc_code IS DISTINCT FROM '087802006';
UPDATE public.barangays SET psgc_code = '087802004' WHERE municipality = 'Biliran' AND name = 'Hugpa' AND psgc_code IS DISTINCT FROM '087802004';
UPDATE public.barangays SET psgc_code = '087802005' WHERE municipality = 'Biliran' AND name = 'Julita' AND psgc_code IS DISTINCT FROM '087802005';
UPDATE public.barangays SET psgc_code = '087802007' WHERE municipality = 'Biliran' AND name = 'Pinangumhan' AND psgc_code IS DISTINCT FROM '087802007';
UPDATE public.barangays SET psgc_code = '087802008' WHERE municipality = 'Biliran' AND name = 'San Isidro' AND psgc_code IS DISTINCT FROM '087802008';
UPDATE public.barangays SET psgc_code = '087802010' WHERE municipality = 'Biliran' AND name = 'Sanggalang' AND psgc_code IS DISTINCT FROM '087802010';
UPDATE public.barangays SET psgc_code = '087803001' WHERE municipality = 'Cabucgayan' AND name = 'Balaquid' AND psgc_code IS DISTINCT FROM '087803001';
UPDATE public.barangays SET psgc_code = '087803003' WHERE municipality = 'Cabucgayan' AND name = 'Bunga' AND psgc_code IS DISTINCT FROM '087803003';
UPDATE public.barangays SET psgc_code = '087803004' WHERE municipality = 'Cabucgayan' AND name = 'Caanibongan' AND psgc_code IS DISTINCT FROM '087803004';
UPDATE public.barangays SET psgc_code = '087803005' WHERE municipality = 'Cabucgayan' AND name = 'Casiawan' AND psgc_code IS DISTINCT FROM '087803005';
UPDATE public.barangays SET psgc_code = '087803007' WHERE municipality = 'Cabucgayan' AND name = 'Esperanza' AND psgc_code IS DISTINCT FROM '087803007';
UPDATE public.barangays SET psgc_code = '087803008' WHERE municipality = 'Cabucgayan' AND name = 'Langgao' AND psgc_code IS DISTINCT FROM '087803008';
UPDATE public.barangays SET psgc_code = '087803009' WHERE municipality = 'Cabucgayan' AND name = 'Libertad' AND psgc_code IS DISTINCT FROM '087803009';
UPDATE public.barangays SET psgc_code = '087803010' WHERE municipality = 'Cabucgayan' AND name = 'Looc' AND psgc_code IS DISTINCT FROM '087803010';
UPDATE public.barangays SET psgc_code = '087803011' WHERE municipality = 'Cabucgayan' AND name = 'Magbangon' AND psgc_code IS DISTINCT FROM '087803011';
UPDATE public.barangays SET psgc_code = '087803012' WHERE municipality = 'Cabucgayan' AND name = 'Pawikan' AND psgc_code IS DISTINCT FROM '087803012';
UPDATE public.barangays SET psgc_code = '087803014' WHERE municipality = 'Cabucgayan' AND name = 'Talibong' AND psgc_code IS DISTINCT FROM '087803014';
UPDATE public.barangays SET psgc_code = '087804002' WHERE municipality = 'Caibiran' AND name = 'Asug' AND psgc_code IS DISTINCT FROM '087804002';
UPDATE public.barangays SET psgc_code = '087804004' WHERE municipality = 'Caibiran' AND name = 'Binohangan' AND psgc_code IS DISTINCT FROM '087804004';
UPDATE public.barangays SET psgc_code = '087804005' WHERE municipality = 'Caibiran' AND name = 'Cabibihan' AND psgc_code IS DISTINCT FROM '087804005';
UPDATE public.barangays SET psgc_code = '087804006' WHERE municipality = 'Caibiran' AND name = 'Kawayanon' AND psgc_code IS DISTINCT FROM '087804006';
UPDATE public.barangays SET psgc_code = '087804007' WHERE municipality = 'Caibiran' AND name = 'Looc' AND psgc_code IS DISTINCT FROM '087804007';
UPDATE public.barangays SET psgc_code = '087804009' WHERE municipality = 'Caibiran' AND name = 'Manlabang' AND psgc_code IS DISTINCT FROM '087804009';
UPDATE public.barangays SET psgc_code = '087804011' WHERE municipality = 'Caibiran' AND name = 'Maurang' AND psgc_code IS DISTINCT FROM '087804011';
UPDATE public.barangays SET psgc_code = '087804012' WHERE municipality = 'Caibiran' AND name = 'Palanay' AND psgc_code IS DISTINCT FROM '087804012';
UPDATE public.barangays SET psgc_code = '087804014' WHERE municipality = 'Caibiran' AND name = 'Tomalistis' AND psgc_code IS DISTINCT FROM '087804014';
UPDATE public.barangays SET psgc_code = '087804015' WHERE municipality = 'Caibiran' AND name = 'Union' AND psgc_code IS DISTINCT FROM '087804015';
UPDATE public.barangays SET psgc_code = '087804016' WHERE municipality = 'Caibiran' AND name = 'Uson' AND psgc_code IS DISTINCT FROM '087804016';
UPDATE public.barangays SET psgc_code = '087804017' WHERE municipality = 'Caibiran' AND name = 'Victory' AND psgc_code IS DISTINCT FROM '087804017';
UPDATE public.barangays SET psgc_code = '087805001' WHERE municipality = 'Culaba' AND name = 'Acaban' AND psgc_code IS DISTINCT FROM '087805001';
UPDATE public.barangays SET psgc_code = '087805002' WHERE municipality = 'Culaba' AND name = 'Bacolod' AND psgc_code IS DISTINCT FROM '087805002';
UPDATE public.barangays SET psgc_code = '087805003' WHERE municipality = 'Culaba' AND name = 'Binongtoan' AND psgc_code IS DISTINCT FROM '087805003';
UPDATE public.barangays SET psgc_code = '087805004' WHERE municipality = 'Culaba' AND name = 'Bool Central' AND psgc_code IS DISTINCT FROM '087805004';
UPDATE public.barangays SET psgc_code = '087805005' WHERE municipality = 'Culaba' AND name = 'Bool East' AND psgc_code IS DISTINCT FROM '087805005';
UPDATE public.barangays SET psgc_code = '087805006' WHERE municipality = 'Culaba' AND name = 'Bool West' AND psgc_code IS DISTINCT FROM '087805006';
UPDATE public.barangays SET psgc_code = '087805014' WHERE municipality = 'Culaba' AND name = 'Culaba Central' AND psgc_code IS DISTINCT FROM '087805014';
UPDATE public.barangays SET psgc_code = '087805008' WHERE municipality = 'Culaba' AND name = 'Guindapunan' AND psgc_code IS DISTINCT FROM '087805008';
UPDATE public.barangays SET psgc_code = '087805009' WHERE municipality = 'Culaba' AND name = 'Habuhab' AND psgc_code IS DISTINCT FROM '087805009';
UPDATE public.barangays SET psgc_code = '087805010' WHERE municipality = 'Culaba' AND name = 'Looc' AND psgc_code IS DISTINCT FROM '087805010';
UPDATE public.barangays SET psgc_code = '087805011' WHERE municipality = 'Culaba' AND name = 'Marvel' AND psgc_code IS DISTINCT FROM '087805011';
UPDATE public.barangays SET psgc_code = '087805012' WHERE municipality = 'Culaba' AND name = 'Patag' AND psgc_code IS DISTINCT FROM '087805012';
UPDATE public.barangays SET psgc_code = '087805015' WHERE municipality = 'Culaba' AND name = 'Salvacion' AND psgc_code IS DISTINCT FROM '087805015';
UPDATE public.barangays SET psgc_code = '087805016' WHERE municipality = 'Culaba' AND name = 'San Roque' AND psgc_code IS DISTINCT FROM '087805016';
UPDATE public.barangays SET psgc_code = '087805017' WHERE municipality = 'Culaba' AND name = 'Virginia' AND psgc_code IS DISTINCT FROM '087805017';
UPDATE public.barangays SET psgc_code = '087806001' WHERE municipality = 'Kawayan' AND name = 'Baganito' AND psgc_code IS DISTINCT FROM '087806001';
UPDATE public.barangays SET psgc_code = '087806002' WHERE municipality = 'Kawayan' AND name = 'Balacson' AND psgc_code IS DISTINCT FROM '087806002';
UPDATE public.barangays SET psgc_code = '087806003' WHERE municipality = 'Kawayan' AND name = 'Bilwang' AND psgc_code IS DISTINCT FROM '087806003';
UPDATE public.barangays SET psgc_code = '087806004' WHERE municipality = 'Kawayan' AND name = 'Bulalacao' AND psgc_code IS DISTINCT FROM '087806004';
UPDATE public.barangays SET psgc_code = '087806005' WHERE municipality = 'Kawayan' AND name = 'Burabod' AND psgc_code IS DISTINCT FROM '087806005';
UPDATE public.barangays SET psgc_code = '087806018' WHERE municipality = 'Kawayan' AND name = 'Buyo' AND psgc_code IS DISTINCT FROM '087806018';
UPDATE public.barangays SET psgc_code = '087806006' WHERE municipality = 'Kawayan' AND name = 'Inasuyan' AND psgc_code IS DISTINCT FROM '087806006';
UPDATE public.barangays SET psgc_code = '087806007' WHERE municipality = 'Kawayan' AND name = 'Kansanok' AND psgc_code IS DISTINCT FROM '087806007';
UPDATE public.barangays SET psgc_code = '087806009' WHERE municipality = 'Kawayan' AND name = 'Mapuyo' AND psgc_code IS DISTINCT FROM '087806009';
UPDATE public.barangays SET psgc_code = '087806011' WHERE municipality = 'Kawayan' AND name = 'Masagongsong' AND psgc_code IS DISTINCT FROM '087806011';
UPDATE public.barangays SET psgc_code = '087806012' WHERE municipality = 'Kawayan' AND name = 'Poblacion' AND psgc_code IS DISTINCT FROM '087806012';
UPDATE public.barangays SET psgc_code = '087806020' WHERE municipality = 'Kawayan' AND name = 'San Lorenzo' AND psgc_code IS DISTINCT FROM '087806020';
UPDATE public.barangays SET psgc_code = '087806016' WHERE municipality = 'Kawayan' AND name = 'Ungale' AND psgc_code IS DISTINCT FROM '087806016';
UPDATE public.barangays SET psgc_code = '087807001' WHERE municipality = 'Maripipi' AND name = 'Agutay' AND psgc_code IS DISTINCT FROM '087807001';
UPDATE public.barangays SET psgc_code = '087807002' WHERE municipality = 'Maripipi' AND name = 'Banlas' AND psgc_code IS DISTINCT FROM '087807002';
UPDATE public.barangays SET psgc_code = '087807005' WHERE municipality = 'Maripipi' AND name = 'Binalayan East' AND psgc_code IS DISTINCT FROM '087807005';
UPDATE public.barangays SET psgc_code = '087807004' WHERE municipality = 'Maripipi' AND name = 'Binalayan West' AND psgc_code IS DISTINCT FROM '087807004';
UPDATE public.barangays SET psgc_code = '087807015' WHERE municipality = 'Maripipi' AND name = 'Binongtoan' AND psgc_code IS DISTINCT FROM '087807015';
UPDATE public.barangays SET psgc_code = '087807009' WHERE municipality = 'Maripipi' AND name = 'Calbani' AND psgc_code IS DISTINCT FROM '087807009';
UPDATE public.barangays SET psgc_code = '087807010' WHERE municipality = 'Maripipi' AND name = 'Canduhao' AND psgc_code IS DISTINCT FROM '087807010';
UPDATE public.barangays SET psgc_code = '087807011' WHERE municipality = 'Maripipi' AND name = 'Casibang' AND psgc_code IS DISTINCT FROM '087807011';
UPDATE public.barangays SET psgc_code = '087807012' WHERE municipality = 'Maripipi' AND name = 'Danao' AND psgc_code IS DISTINCT FROM '087807012';
UPDATE public.barangays SET psgc_code = '087807016' WHERE municipality = 'Maripipi' AND name = 'Ermita' AND psgc_code IS DISTINCT FROM '087807016';
UPDATE public.barangays SET psgc_code = '087807017' WHERE municipality = 'Maripipi' AND name = 'Trabugan' AND psgc_code IS DISTINCT FROM '087807017';
UPDATE public.barangays SET psgc_code = '087807018' WHERE municipality = 'Maripipi' AND name = 'Viga' AND psgc_code IS DISTINCT FROM '087807018';
UPDATE public.barangays SET psgc_code = '087808001' WHERE municipality = 'Naval' AND name = 'Agpangi' AND psgc_code IS DISTINCT FROM '087808001';
UPDATE public.barangays SET psgc_code = '087808002' WHERE municipality = 'Naval' AND name = 'Anislagan' AND psgc_code IS DISTINCT FROM '087808002';
UPDATE public.barangays SET psgc_code = '087808003' WHERE municipality = 'Naval' AND name = 'Atipolo' AND psgc_code IS DISTINCT FROM '087808003';
UPDATE public.barangays SET psgc_code = '087808021' WHERE municipality = 'Naval' AND name = 'Borac' AND psgc_code IS DISTINCT FROM '087808021';
UPDATE public.barangays SET psgc_code = '087808004' WHERE municipality = 'Naval' AND name = 'Calumpang' AND psgc_code IS DISTINCT FROM '087808004';
UPDATE public.barangays SET psgc_code = '087808005' WHERE municipality = 'Naval' AND name = 'Capiñahan' AND psgc_code IS DISTINCT FROM '087808005';
UPDATE public.barangays SET psgc_code = '087808006' WHERE municipality = 'Naval' AND name = 'Caraycaray' AND psgc_code IS DISTINCT FROM '087808006';
UPDATE public.barangays SET psgc_code = '087808007' WHERE municipality = 'Naval' AND name = 'Catmon' AND psgc_code IS DISTINCT FROM '087808007';
UPDATE public.barangays SET psgc_code = '087808008' WHERE municipality = 'Naval' AND name = 'Haguikhikan' AND psgc_code IS DISTINCT FROM '087808008';
UPDATE public.barangays SET psgc_code = '087808023' WHERE municipality = 'Naval' AND name = 'Imelda' AND psgc_code IS DISTINCT FROM '087808023';
UPDATE public.barangays SET psgc_code = '087808024' WHERE municipality = 'Naval' AND name = 'Larrazabal' AND psgc_code IS DISTINCT FROM '087808024';
UPDATE public.barangays SET psgc_code = '087808010' WHERE municipality = 'Naval' AND name = 'Libertad' AND psgc_code IS DISTINCT FROM '087808010';
UPDATE public.barangays SET psgc_code = '087808025' WHERE municipality = 'Naval' AND name = 'Libtong' AND psgc_code IS DISTINCT FROM '087808025';
UPDATE public.barangays SET psgc_code = '087808012' WHERE municipality = 'Naval' AND name = 'Lico' AND psgc_code IS DISTINCT FROM '087808012';
UPDATE public.barangays SET psgc_code = '087808013' WHERE municipality = 'Naval' AND name = 'Lucsoon' AND psgc_code IS DISTINCT FROM '087808013';
UPDATE public.barangays SET psgc_code = '087808014' WHERE municipality = 'Naval' AND name = 'Mabini' AND psgc_code IS DISTINCT FROM '087808014';
UPDATE public.barangays SET psgc_code = '087808009' WHERE municipality = 'Naval' AND name = 'Padre Inocentes Garcia' AND psgc_code IS DISTINCT FROM '087808009';
UPDATE public.barangays SET psgc_code = '087808026' WHERE municipality = 'Naval' AND name = 'Padre Sergio Eamiguel' AND psgc_code IS DISTINCT FROM '087808026';
UPDATE public.barangays SET psgc_code = '087808027' WHERE municipality = 'Naval' AND name = 'Sabang' AND psgc_code IS DISTINCT FROM '087808027';
UPDATE public.barangays SET psgc_code = '087808015' WHERE municipality = 'Naval' AND name = 'San Pablo' AND psgc_code IS DISTINCT FROM '087808015';
UPDATE public.barangays SET psgc_code = '087808017' WHERE municipality = 'Naval' AND name = 'Santissimo Rosario' AND psgc_code IS DISTINCT FROM '087808017';
UPDATE public.barangays SET psgc_code = '087808016' WHERE municipality = 'Naval' AND name = 'Santo Niño' AND psgc_code IS DISTINCT FROM '087808016';
UPDATE public.barangays SET psgc_code = '087808018' WHERE municipality = 'Naval' AND name = 'Talustusan' AND psgc_code IS DISTINCT FROM '087808018';
UPDATE public.barangays SET psgc_code = '087808019' WHERE municipality = 'Naval' AND name = 'Villa Caneja' AND psgc_code IS DISTINCT FROM '087808019';
UPDATE public.barangays SET psgc_code = '087808020' WHERE municipality = 'Naval' AND name = 'Villa Consuelo' AND psgc_code IS DISTINCT FROM '087808020';

-- ------------------------------------------------------------
-- 5. Remove rows that are not barangays - only if no resident points at them
-- ------------------------------------------------------------
DELETE FROM public.barangays b WHERE b.municipality = 'Biliran' AND b.name = 'Poblacion' AND b.psgc_code IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.barangay_id = b.id);
DELETE FROM public.barangays b WHERE b.municipality = 'Biliran' AND b.name = 'Uson' AND b.psgc_code IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.barangay_id = b.id);
DELETE FROM public.barangays b WHERE b.municipality = 'Caibiran' AND b.name = 'Mainit' AND b.psgc_code IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.barangay_id = b.id);
DELETE FROM public.barangays b WHERE b.municipality = 'Caibiran' AND b.name = 'Poblacion' AND b.psgc_code IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.barangay_id = b.id);
DELETE FROM public.barangays b WHERE b.municipality = 'Maripipi' AND b.name = 'Poblacion' AND b.psgc_code IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.barangay_id = b.id);

-- ------------------------------------------------------------
-- 6. Check
-- ------------------------------------------------------------
SELECT municipality, COUNT(*) AS barangays
FROM public.barangays
GROUP BY municipality
ORDER BY municipality;

-- Anything still without a PSGC code is a leftover a resident points at:
SELECT b.municipality, b.name, COUNT(u.id) AS residents_pointing_at_it
FROM public.barangays b
LEFT JOIN public.users u ON u.barangay_id = b.id
WHERE b.psgc_code IS NULL
GROUP BY b.municipality, b.name
ORDER BY b.municipality, b.name;

COMMIT;
