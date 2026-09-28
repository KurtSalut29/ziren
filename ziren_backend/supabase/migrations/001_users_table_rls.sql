-- ============================================================
-- Migration 001: users table + Row Level Security
-- Run this in the Supabase SQL editor (dev project first).
--
-- NOTE: agency_id FK to public.agencies is intentionally omitted here.
-- It will be added in migration 002 once the agencies table exists.
-- ============================================================

-- Extend auth.users with Ziren-specific profile data.
-- We use a separate public.users table that references auth.users(id)
-- so Supabase Auth manages credentials, we manage roles/profile.

CREATE TABLE IF NOT EXISTS public.users (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL UNIQUE,
    full_name   TEXT NOT NULL DEFAULT '',
    role        TEXT NOT NULL DEFAULT 'citizen'
                    CHECK (role IN ('citizen', 'dispatcher', 'agency_admin')),
    agency_id   UUID,
    -- FK to public.agencies added in migration 002 (after agencies table exists)
    -- agency_id is NULL for citizens, set for dispatchers/admins
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Auto-insert a public.users row when a new auth.users row is created
-- (via Supabase Auth signup). Role defaults to 'citizen'.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        COALESCE(NEW.raw_user_meta_data->>'role', 'citizen')
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- ============================================================
-- Row Level Security
-- ============================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Policy 1: Users can read their own row only
CREATE POLICY "users: read own row"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

-- Policy 2: Users can update their own row only
-- (role and is_verified cannot be self-updated — enforced via separate policy)
CREATE POLICY "users: update own row"
    ON public.users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        -- Prevent self-promotion of role
        role = (SELECT role FROM public.users WHERE id = auth.uid())
        AND is_verified = (SELECT is_verified FROM public.users WHERE id = auth.uid())
    );

-- Policy 3: Dispatchers can read all citizen rows (needed for incident context)
CREATE POLICY "users: dispatcher reads citizens"
    ON public.users FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role IN ('dispatcher', 'agency_admin')
        )
    );

-- Policy 4: Agency admins can update role/verified for users in their agency
CREATE POLICY "users: agency_admin manages own agency"
    ON public.users FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users admin
            WHERE admin.id = auth.uid()
            AND admin.role = 'agency_admin'
            AND admin.agency_id = public.users.agency_id
        )
    );

-- Policy 5: Authenticated users can insert their own row
-- (handle_new_auth_user trigger does this via SECURITY DEFINER,
--  but this allows the client to upsert profile data on first login)
CREATE POLICY "users: insert own row"
    ON public.users FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================================
-- Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS users_role_idx ON public.users(role);
CREATE INDEX IF NOT EXISTS users_agency_id_idx ON public.users(agency_id);
