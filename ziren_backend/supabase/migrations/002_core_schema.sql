-- ============================================================
-- Migration 002: Core Schema — agencies, stations, incidents,
--                dispatch_log + PostGIS + RLS + seed data
--
-- Run AFTER migration 001.
-- Run in Supabase SQL editor (dev project).
-- ============================================================

-- ============================================================
-- 0. Enable PostGIS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- ============================================================
-- 1. agencies table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.agencies (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    agency_type     TEXT NOT NULL CHECK (agency_type IN ('BFP', 'PNP', 'MDRRMO')),
    municipality    TEXT NOT NULL,
    province        TEXT NOT NULL DEFAULT 'Biliran',
    region          TEXT NOT NULL DEFAULT 'Region VIII',
    -- Coverage area as a PostGIS polygon (WGS84 / EPSG:4326)
    coverage_area   GEOMETRY(POLYGON, 4326),
    contact_number  TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER agencies_updated_at
    BEFORE UPDATE ON public.agencies
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS agencies_type_idx ON public.agencies(agency_type);
CREATE INDEX IF NOT EXISTS agencies_municipality_idx ON public.agencies(municipality);
CREATE INDEX IF NOT EXISTS agencies_coverage_idx ON public.agencies USING GIST(coverage_area);

-- ============================================================
-- 2. stations table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.stations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agency_id       UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    address         TEXT,
    -- Station location as a PostGIS point
    location        GEOMETRY(POINT, 4326),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER stations_updated_at
    BEFORE UPDATE ON public.stations
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS stations_agency_idx ON public.stations(agency_id);
CREATE INDEX IF NOT EXISTS stations_location_idx ON public.stations USING GIST(location);

-- ============================================================
-- 3. incidents table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.incidents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

    -- The raw report text — never sanitize or truncate
    report_text         TEXT NOT NULL,

    -- Location as PostGIS point (WGS84)
    location            GEOMETRY(POINT, 4326),
    location_address    TEXT,  -- human-readable reverse-geocoded address

    -- Status lifecycle
    status              TEXT NOT NULL DEFAULT 'received'
                            CHECK (status IN ('received', 'processing', 'dispatched', 'resolved', 'cancelled')),

    -- Severity (NEVER ML — always from rule-based rubric, Phase 5)
    severity            TEXT CHECK (severity IN ('critical', 'high', 'medium', 'low')),

    -- Agency routing
    suggested_agency_id UUID REFERENCES public.agencies(id) ON DELETE SET NULL,
    assigned_agency_id  UUID REFERENCES public.agencies(id) ON DELETE SET NULL,

    -- NLP extracted signals (Phase 4) — stored as JSONB for flexibility
    -- Structure mirrors the 15 signals defined in the spec
    signals             JSONB,
    signals_confidence  NUMERIC(4,3),  -- 0.000–1.000; low = flagged for review

    -- Connectivity metadata
    submitted_via       TEXT NOT NULL DEFAULT 'internet'
                            CHECK (submitted_via IN ('internet', 'sms', 'offline_sync')),

    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dispatched_at       TIMESTAMPTZ,
    resolved_at         TIMESTAMPTZ
);

CREATE TRIGGER incidents_updated_at
    BEFORE UPDATE ON public.incidents
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Spatial index for "find incidents near station" queries
CREATE INDEX IF NOT EXISTS incidents_location_idx ON public.incidents USING GIST(location);
CREATE INDEX IF NOT EXISTS incidents_reporter_idx ON public.incidents(reporter_id);
CREATE INDEX IF NOT EXISTS incidents_status_idx ON public.incidents(status);
CREATE INDEX IF NOT EXISTS incidents_severity_idx ON public.incidents(severity);
CREATE INDEX IF NOT EXISTS incidents_created_idx ON public.incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS incidents_agency_idx ON public.incidents(assigned_agency_id);

-- ============================================================
-- 4. dispatch_log table (append-only audit trail)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.dispatch_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id         UUID NOT NULL REFERENCES public.incidents(id) ON DELETE RESTRICT,
    dispatcher_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    agency_id           UUID NOT NULL REFERENCES public.agencies(id) ON DELETE RESTRICT,

    -- What the system suggested vs. what the human chose
    suggested_severity  TEXT CHECK (suggested_severity IN ('critical', 'high', 'medium', 'low')),
    chosen_severity     TEXT CHECK (chosen_severity IN ('critical', 'high', 'medium', 'low')),
    suggested_agency_id UUID REFERENCES public.agencies(id) ON DELETE SET NULL,
    chosen_agency_id    UUID REFERENCES public.agencies(id) ON DELETE SET NULL,

    -- Human override flag + reason
    was_override        BOOLEAN NOT NULL DEFAULT FALSE,
    override_reason     TEXT,

    action              TEXT NOT NULL CHECK (action IN ('dispatched', 'resolved', 'cancelled', 'reassigned')),
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at — dispatch_log rows are immutable
);

CREATE INDEX IF NOT EXISTS dispatch_log_incident_idx ON public.dispatch_log(incident_id);
CREATE INDEX IF NOT EXISTS dispatch_log_dispatcher_idx ON public.dispatch_log(dispatcher_id);
CREATE INDEX IF NOT EXISTS dispatch_log_created_idx ON public.dispatch_log(created_at DESC);

-- ============================================================
-- 5. Wire agency FK back into users (deferred from migration 001)
-- ============================================================
ALTER TABLE public.users
    ADD CONSTRAINT users_agency_id_fkey
    FOREIGN KEY (agency_id) REFERENCES public.agencies(id) ON DELETE SET NULL;

-- ============================================================
-- 6. Row Level Security — agencies
-- ============================================================
ALTER TABLE public.agencies ENABLE ROW LEVEL SECURITY;

-- Everyone authenticated can read agencies (needed for incident routing display)
CREATE POLICY "agencies: authenticated read"
    ON public.agencies FOR SELECT
    TO authenticated
    USING (TRUE);

-- Only agency_admin can update their own agency record
CREATE POLICY "agencies: admin updates own agency"
    ON public.agencies FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role = 'agency_admin'
            AND u.agency_id = public.agencies.id
        )
    );

-- ============================================================
-- 7. Row Level Security — stations
-- ============================================================
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "stations: authenticated read"
    ON public.stations FOR SELECT
    TO authenticated
    USING (TRUE);

-- ============================================================
-- 8. Row Level Security — incidents
-- ============================================================
ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;

-- Citizens can only read their own reports
CREATE POLICY "incidents: resident reads own"
    ON public.incidents FOR SELECT
    USING (
        auth.uid() = reporter_id
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role IN ('responder', 'agency_admin', 'super_admin')
        )
    );

-- Residents can insert their own reports
CREATE POLICY "incidents: resident inserts own"
    ON public.incidents FOR INSERT
    WITH CHECK (auth.uid() = reporter_id);

-- Only agency_admin / super_admin can update incidents (status changes, routing)
CREATE POLICY "incidents: dispatcher updates"
    ON public.incidents FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role IN ('agency_admin', 'super_admin')
        )
    );

-- Nobody can delete incidents (soft-cancel via status field)
-- (No DELETE policy = DELETE denied for all)

-- ============================================================
-- 9. Row Level Security — dispatch_log (append-only)
-- ============================================================
ALTER TABLE public.dispatch_log ENABLE ROW LEVEL SECURITY;

-- Agency Admins and Super Admins can read
CREATE POLICY "dispatch_log: admin reads"
    ON public.dispatch_log FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role IN ('agency_admin', 'super_admin')
        )
    );

-- Only agency_admin/super_admin can insert
CREATE POLICY "dispatch_log: admin inserts"
    ON public.dispatch_log FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid()
            AND u.role IN ('agency_admin', 'super_admin')
        )
        AND dispatcher_id = auth.uid()
    );

-- NO UPDATE or DELETE policies — dispatch_log is immutable
-- Citizens cannot read dispatch_log at all

-- ============================================================
-- 10. Seed data — Biliran agencies & stations
-- ============================================================

-- Insert agencies for all 8 municipalities of Biliran
-- Coverage polygons are approximate bounding boxes (WGS84)
-- Real boundaries should be replaced with official shapefiles

INSERT INTO public.agencies (id, name, agency_type, municipality, coverage_area, contact_number) VALUES

-- Naval (provincial capital)
('a0000001-0000-0000-0000-000000000001', 'BFP Naval Station', 'BFP', 'Naval',
 ST_GeomFromText('POLYGON((124.38 11.55, 124.46 11.55, 124.46 11.62, 124.38 11.62, 124.38 11.55))', 4326),
 '(053) 500-9911'),
('a0000001-0000-0000-0000-000000000002', 'PNP Naval Station', 'PNP', 'Naval',
 ST_GeomFromText('POLYGON((124.38 11.55, 124.46 11.55, 124.46 11.62, 124.38 11.62, 124.38 11.55))', 4326),
 '(053) 500-9166'),
('a0000001-0000-0000-0000-000000000003', 'MDRRMO Naval', 'MDRRMO', 'Naval',
 ST_GeomFromText('POLYGON((124.38 11.55, 124.46 11.55, 124.46 11.62, 124.38 11.62, 124.38 11.55))', 4326),
 '(053) 500-9000'),

-- Almeria
('a0000002-0000-0000-0000-000000000001', 'BFP Almeria Station', 'BFP', 'Almeria',
 ST_GeomFromText('POLYGON((124.39 11.62, 124.47 11.62, 124.47 11.70, 124.39 11.70, 124.39 11.62))', 4326),
 NULL),
('a0000002-0000-0000-0000-000000000002', 'PNP Almeria Station', 'PNP', 'Almeria',
 ST_GeomFromText('POLYGON((124.39 11.62, 124.47 11.62, 124.47 11.70, 124.39 11.70, 124.39 11.62))', 4326),
 NULL),
('a0000002-0000-0000-0000-000000000003', 'MDRRMO Almeria', 'MDRRMO', 'Almeria',
 ST_GeomFromText('POLYGON((124.39 11.62, 124.47 11.62, 124.47 11.70, 124.39 11.70, 124.39 11.62))', 4326),
 NULL),

-- Biliran (municipality)
('a0000003-0000-0000-0000-000000000001', 'BFP Biliran Station', 'BFP', 'Biliran',
 ST_GeomFromText('POLYGON((124.44 11.57, 124.52 11.57, 124.52 11.65, 124.44 11.65, 124.44 11.57))', 4326),
 NULL),
('a0000003-0000-0000-0000-000000000002', 'PNP Biliran Station', 'PNP', 'Biliran',
 ST_GeomFromText('POLYGON((124.44 11.57, 124.52 11.57, 124.52 11.65, 124.44 11.65, 124.44 11.57))', 4326),
 NULL),
('a0000003-0000-0000-0000-000000000003', 'MDRRMO Biliran', 'MDRRMO', 'Biliran',
 ST_GeomFromText('POLYGON((124.44 11.57, 124.52 11.57, 124.52 11.65, 124.44 11.65, 124.44 11.57))', 4326),
 NULL),

-- Cabucgayan
('a0000004-0000-0000-0000-000000000001', 'BFP Cabucgayan Station', 'BFP', 'Cabucgayan',
 ST_GeomFromText('POLYGON((124.52 11.45, 124.60 11.45, 124.60 11.53, 124.52 11.53, 124.52 11.45))', 4326),
 NULL),
('a0000004-0000-0000-0000-000000000002', 'PNP Cabucgayan Station', 'PNP', 'Cabucgayan',
 ST_GeomFromText('POLYGON((124.52 11.45, 124.60 11.45, 124.60 11.53, 124.52 11.53, 124.52 11.45))', 4326),
 NULL),
('a0000004-0000-0000-0000-000000000003', 'MDRRMO Cabucgayan', 'MDRRMO', 'Cabucgayan',
 ST_GeomFromText('POLYGON((124.52 11.45, 124.60 11.45, 124.60 11.53, 124.52 11.53, 124.52 11.45))', 4326),
 NULL),

-- Caibiran
('a0000005-0000-0000-0000-000000000001', 'BFP Caibiran Station', 'BFP', 'Caibiran',
 ST_GeomFromText('POLYGON((124.55 11.55, 124.63 11.55, 124.63 11.63, 124.55 11.63, 124.55 11.55))', 4326),
 NULL),
('a0000005-0000-0000-0000-000000000002', 'PNP Caibiran Station', 'PNP', 'Caibiran',
 ST_GeomFromText('POLYGON((124.55 11.55, 124.63 11.55, 124.63 11.63, 124.55 11.63, 124.55 11.55))', 4326),
 NULL),
('a0000005-0000-0000-0000-000000000003', 'MDRRMO Caibiran', 'MDRRMO', 'Caibiran',
 ST_GeomFromText('POLYGON((124.55 11.55, 124.63 11.55, 124.63 11.63, 124.55 11.63, 124.55 11.55))', 4326),
 NULL),

-- Culaba
('a0000006-0000-0000-0000-000000000001', 'BFP Culaba Station', 'BFP', 'Culaba',
 ST_GeomFromText('POLYGON((124.48 11.67, 124.56 11.67, 124.56 11.75, 124.48 11.75, 124.48 11.67))', 4326),
 NULL),
('a0000006-0000-0000-0000-000000000002', 'PNP Culaba Station', 'PNP', 'Culaba',
 ST_GeomFromText('POLYGON((124.48 11.67, 124.56 11.67, 124.56 11.75, 124.48 11.75, 124.48 11.67))', 4326),
 NULL),
('a0000006-0000-0000-0000-000000000003', 'MDRRMO Culaba', 'MDRRMO', 'Culaba',
 ST_GeomFromText('POLYGON((124.48 11.67, 124.56 11.67, 124.56 11.75, 124.48 11.75, 124.48 11.67))', 4326),
 NULL),

-- Kawayan
('a0000007-0000-0000-0000-000000000001', 'BFP Kawayan Station', 'BFP', 'Kawayan',
 ST_GeomFromText('POLYGON((124.35 11.58, 124.43 11.58, 124.43 11.66, 124.35 11.66, 124.35 11.58))', 4326),
 NULL),
('a0000007-0000-0000-0000-000000000002', 'PNP Kawayan Station', 'PNP', 'Kawayan',
 ST_GeomFromText('POLYGON((124.35 11.58, 124.43 11.58, 124.43 11.66, 124.35 11.66, 124.35 11.58))', 4326),
 NULL),
('a0000007-0000-0000-0000-000000000003', 'MDRRMO Kawayan', 'MDRRMO', 'Kawayan',
 ST_GeomFromText('POLYGON((124.35 11.58, 124.43 11.58, 124.43 11.66, 124.35 11.66, 124.35 11.58))', 4326),
 NULL),

-- Maripipi
('a0000008-0000-0000-0000-000000000001', 'BFP Maripipi Station', 'BFP', 'Maripipi',
 ST_GeomFromText('POLYGON((124.30 11.78, 124.38 11.78, 124.38 11.86, 124.30 11.86, 124.30 11.78))', 4326),
 NULL),
('a0000008-0000-0000-0000-000000000002', 'PNP Maripipi Station', 'PNP', 'Maripipi',
 ST_GeomFromText('POLYGON((124.30 11.78, 124.38 11.78, 124.38 11.86, 124.30 11.86, 124.30 11.78))', 4326),
 NULL),
('a0000008-0000-0000-0000-000000000003', 'MDRRMO Maripipi', 'MDRRMO', 'Maripipi',
 ST_GeomFromText('POLYGON((124.30 11.78, 124.38 11.78, 124.38 11.86, 124.30 11.86, 124.30 11.78))', 4326),
 NULL)

ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 11. Seed data — stations (one per agency for now)
-- ============================================================
INSERT INTO public.stations (agency_id, name, address, location) VALUES

-- Naval stations
('a0000001-0000-0000-0000-000000000001', 'BFP Naval Main Station', 'P. Burgos St., Naval, Biliran',
 ST_GeomFromText('POINT(124.4063 11.5836)', 4326)),
('a0000001-0000-0000-0000-000000000002', 'PNP Naval Station', 'Caneja St., Naval, Biliran',
 ST_GeomFromText('POINT(124.4078 11.5841)', 4326)),
('a0000001-0000-0000-0000-000000000003', 'MDRRMO Naval Office', 'Capitol Compound, Naval, Biliran',
 ST_GeomFromText('POINT(124.4055 11.5830)', 4326)),

-- Almeria stations
('a0000002-0000-0000-0000-000000000001', 'BFP Almeria Station', 'Almeria, Biliran',
 ST_GeomFromText('POINT(124.4301 11.6512)', 4326)),
('a0000002-0000-0000-0000-000000000002', 'PNP Almeria Station', 'Almeria, Biliran',
 ST_GeomFromText('POINT(124.4310 11.6520)', 4326)),
('a0000002-0000-0000-0000-000000000003', 'MDRRMO Almeria', 'Municipal Hall, Almeria, Biliran',
 ST_GeomFromText('POINT(124.4295 11.6505)', 4326))

ON CONFLICT DO NOTHING;
