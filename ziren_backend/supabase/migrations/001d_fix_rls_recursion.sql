-- ============================================================
-- Migration 001d: Fix RLS infinite recursion on public.users
--
-- RLS policies that subquery public.users to check the caller's
-- role cause infinite recursion. Fix: SECURITY DEFINER helper
-- functions that bypass RLS to safely read the caller's role
-- and agency_id.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT role FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_agency_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT agency_id FROM public.users WHERE id = auth.uid();
$$;

DROP POLICY IF EXISTS "users: read own row"                         ON public.users;
DROP POLICY IF EXISTS "users: update own profile"                   ON public.users;
DROP POLICY IF EXISTS "users: agency_admin reads own agency"        ON public.users;
DROP POLICY IF EXISTS "users: agency_admin approves own responders" ON public.users;
DROP POLICY IF EXISTS "users: super_admin reads all"                ON public.users;
DROP POLICY IF EXISTS "users: insert own row"                       ON public.users;

CREATE POLICY "users: read own row"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "users: update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        role = (SELECT role FROM public.users WHERE id = auth.uid())
        AND approval_status = (SELECT approval_status FROM public.users WHERE id = auth.uid())
        AND agency_id IS NOT DISTINCT FROM (SELECT agency_id FROM public.users WHERE id = auth.uid())
        AND COALESCE(badge_id,'') = COALESCE((SELECT badge_id FROM public.users WHERE id = auth.uid()),'')
    );

CREATE POLICY "users: agency_admin reads own agency"
    ON public.users FOR SELECT
    USING (
        public.get_my_role() = 'agency_admin'
        AND public.get_my_agency_id() = public.users.agency_id
    );

CREATE POLICY "users: agency_admin approves own responders"
    ON public.users FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND public.get_my_agency_id() = public.users.agency_id
        AND public.users.role = 'responder'
    )
    WITH CHECK (
        role = (SELECT role FROM public.users WHERE id = public.users.id)
        AND agency_id IS NOT DISTINCT FROM (SELECT agency_id FROM public.users WHERE id = public.users.id)
        AND COALESCE(badge_id,'') = COALESCE((SELECT badge_id FROM public.users WHERE id = public.users.id),'')
    );

CREATE POLICY "users: super_admin reads all"
    ON public.users FOR SELECT
    USING (public.get_my_role() = 'super_admin');

CREATE POLICY "users: insert own row"
    ON public.users FOR INSERT
    WITH CHECK (auth.uid() = id);
