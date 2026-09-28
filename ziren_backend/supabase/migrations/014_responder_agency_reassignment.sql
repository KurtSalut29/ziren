-- ============================================================
-- Migration 014: Allow responder agency reassignment
--
-- DEFECT this repairs — responders are permanently trapped in Naval.
--
-- The mobile app resolved a responder's agency at signup with:
--
--     .eq('agency_type', agencyType)
--     .eq('municipality', 'Naval')       -- hardcoded
--
-- so a BFP responder in Kawayan was written into public.users with the
-- agency_id of BFP *Naval*. The code comment beside it said "Agency Admin
-- can update" — but two RLS rules made that impossible:
--
--   "users: agency_admin approves own responders"
--       USING (get_my_agency_id() = users.agency_id)
--         -> the Kawayan admin cannot even SELECT the row, because it
--            belongs to Naval's agency.
--       WITH CHECK (agency_id IS NOT DISTINCT FROM <current agency_id>)
--         -> and the Naval admin who CAN see it may not change agency_id.
--
-- Net effect: nobody in the system could move the responder. Seven of
-- Biliran's eight municipalities could not onboard responders at all, and
-- the failure was silent — registration returned success.
--
-- Two changes:
--   1. The mobile fix (resolve by the responder's own municipality) lands
--      in ziren_mobile/lib/features/auth/data/auth_repository.dart.
--   2. Here: let an agency admin release a mis-assigned responder, and let
--      a super admin reassign across agencies. Reassignment is a
--      privileged act, so residents/responders still cannot self-move —
--      "users: update own profile" continues to freeze agency_id.
--
-- Run AFTER migration 013.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Super Admin may reassign any user's agency
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "users: super_admin updates all" ON public.users;

CREATE POLICY "users: super_admin updates all"
    ON public.users FOR UPDATE
    USING (public.get_my_role() = 'super_admin')
    WITH CHECK (public.get_my_role() = 'super_admin');

-- ------------------------------------------------------------
-- 2. Agency Admin may release a responder to another agency
--
-- Still scoped to responders inside their own agency (USING is unchanged),
-- but WITH CHECK no longer pins agency_id, so the admin can hand a
-- mis-assigned responder over to the correct municipality. Role and
-- badge_id stay frozen — this is a transfer, not a promotion.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "users: agency_admin approves own responders" ON public.users;

CREATE POLICY "users: agency_admin approves own responders"
    ON public.users FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND public.get_my_agency_id() = public.users.agency_id
        AND public.users.role = 'responder'
    )
    WITH CHECK (
        -- May not change what kind of account this is.
        public.users.role = 'responder'
        AND COALESCE(badge_id,'') = COALESCE(
            (SELECT badge_id FROM public.users u2 WHERE u2.id = public.users.id), '')
        -- May only hand off to a real agency, never to NULL.
        AND agency_id IS NOT NULL
    );

-- ------------------------------------------------------------
-- 3. Find responders already stranded by the Naval default
--
-- Run this after deploying: any responder whose agency municipality is
-- Naval but whose own barangay sits in another municipality is a
-- candidate for reassignment.
-- ------------------------------------------------------------
SELECT
    u.id,
    u.full_name,
    u.badge_id,
    a.name         AS assigned_agency,
    a.municipality AS assigned_municipality,
    b.municipality AS resident_municipality
FROM public.users u
JOIN public.agencies  a ON a.id = u.agency_id
LEFT JOIN public.barangays b ON b.id = u.barangay_id
WHERE u.role = 'responder'
  AND a.municipality = 'Naval'
  AND (b.municipality IS NULL OR b.municipality <> 'Naval')
ORDER BY u.created_at;
