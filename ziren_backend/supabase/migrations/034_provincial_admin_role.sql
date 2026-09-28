-- ============================================================
-- Migration 034: Provincial Admin — replaces Super Admin
--
-- Ziren previously had one super_admin role that saw and governed all
-- three agencies (PNP, BFP, MDRRMO) province-wide. In reality no such
-- person or organization exists in Biliran: each agency's largest station
-- (Naval, Almeria, Kawayan, Culaba, Caibiran, Cabucgayan, Biliran per
-- agency) has no counterpart that oversees the other two agencies. This
-- migration replaces super_admin with a single new role, provincial_admin,
-- scoped by agency_type (PNP/BFP/MDRRMO) instead of by a single agency_id
-- row -- mirroring how agency_admin is already scoped by agency_id, just
-- one level up. There will be 3 real accounts with this role, one per
-- agency_type, covering every municipal station of that agency across the
-- province.
--
-- Design: NOT 3 separate role enum values. One role value
-- ("provincial_admin") + a new users.agency_type column, matching the
-- existing agency_admin pattern (one role + a scope column). This keeps
-- require_role()/RLS checks simple ("role = 'provincial_admin'") with the
-- scoping done via agency_type comparison, exactly like agency_admin's
-- agency_id comparison today.
--
-- Which former-Super-Admin features become agency_type-scoped vs. stay
-- shared across all 3 Provincial Admins (see plan doc for full reasoning):
--   Scoped (Type A): incidents, dispatch_log, stations, rubric_configs,
--     rubric_audit_log, audit_logs, announcements, incident_notes,
--     incident_feedback, location_hazards, responder_distress,
--     incident-media storage, users (agency_admin/responder rows).
--   Shared (Type B) -- no agency dimension in the data model at all, so
--     splitting 3 ways would be artificial: system_config (account/
--     notification policies), resident-ids storage (identity verification
--     isn't agency-specific -- a resident's ID scan has no agency of its
--     own; agency_admin already reads/deletes ANY resident's scan
--     unconditionally today, confirmed in migration 015 -- provincial_admin
--     keeps that same unscoped access).
--
-- Unifying pattern for tables that need a per-row A/B marker: a nullable
-- agency_type column where NULL = shared/platform-wide and a set value =
-- scoped. Used here for audit_logs (system_config.updated etc. stay
-- visible to all 3; agency-owned actions are scoped).
--
-- BOOTSTRAP: matching the existing super_admin convention (see migration
-- 013's comment: "super_admin -> out-of-band, service key"), the 3 real
-- Provincial Admin accounts are NOT seeded by this migration. After
-- running this file, manually update or create them via the Supabase SQL
-- editor / service key -- see the commented template at the bottom.
--
-- Run AFTER migration 033.
-- ============================================================

-- ============================================================
-- 1. users -- role, new agency_type column, updated CHECK constraints
-- ============================================================

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_agency_required_check;

-- Existing super_admin rows (if any) must be converted to provincial_admin
-- with an agency_type BEFORE this constraint is added, or the ALTER below
-- will fail. Run this first and pick the right agency_type per account:
--   UPDATE public.users SET role = 'provincial_admin', agency_type = 'PNP'
--   WHERE id = '<existing super_admin user id>';
-- (repeat per real account -- see bottom-of-file template)

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS agency_type TEXT
        CHECK (agency_type IN ('BFP', 'PNP', 'MDRRMO'));

COMMENT ON COLUMN public.users.agency_type IS
    'Set only for provincial_admin: the single agency_type (PNP/BFP/MDRRMO) '
    'this admin oversees province-wide, across every municipal station of '
    'that type. NULL for every other role -- agency_admin/responder are '
    'scoped via agency_id instead, to one specific municipal branch.';

ALTER TABLE public.users
    ADD CONSTRAINT users_role_check
    CHECK (role IN ('resident', 'responder', 'agency_admin', 'provincial_admin'));

ALTER TABLE public.users
    ADD CONSTRAINT users_agency_required_check
    CHECK (
        (role IN ('responder', 'agency_admin') AND agency_id IS NOT NULL AND agency_type IS NULL)
        OR (role = 'provincial_admin' AND agency_id IS NULL AND agency_type IS NOT NULL)
        OR (role = 'resident' AND agency_id IS NULL AND agency_type IS NULL)
    );

-- ============================================================
-- 2. get_my_agency_type() -- resolve for both existing agency_id-based
--    roles (agency_admin/responder, via join, unchanged) AND the new
--    direct column (provincial_admin). One change cascades correctly into
--    every policy that already calls this helper.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_agency_type()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT COALESCE(u.agency_type, a.agency_type)
    FROM   public.users u
    LEFT JOIN public.agencies a ON a.id = u.agency_id
    WHERE  u.id = auth.uid();
$$;

-- ============================================================
-- 3. audit_logs -- add the shared/scoped marker column
-- ============================================================
ALTER TABLE public.audit_logs
    ADD COLUMN IF NOT EXISTS agency_type TEXT
        CHECK (agency_type IN ('BFP', 'PNP', 'MDRRMO'));

COMMENT ON COLUMN public.audit_logs.agency_type IS
    'NULL = platform-wide action, visible to every Provincial Admin '
    '(e.g. system_config.updated). Set = scoped to that agency_type only. '
    'Populated by audit_service.record() at write time.';

-- ============================================================
-- 4. RLS policy rewrites -- every policy that referenced super_admin.
--    Table by table, targeting the LATEST version of each policy (several
--    were already superseded by a later migration before this one).
-- ============================================================

-- ---- users ----
DROP POLICY IF EXISTS "users: super_admin reads all" ON public.users;
CREATE POLICY "users: provincial_admin reads all"
    ON public.users FOR SELECT
    USING (public.get_my_role() = 'provincial_admin');

DROP POLICY IF EXISTS "users: super_admin updates all" ON public.users;
CREATE POLICY "users: provincial_admin updates own scope"
    ON public.users FOR UPDATE
    USING (
        public.get_my_role() = 'provincial_admin'
        AND (
            agency_id IS NULL
            OR agency_id IN (
                SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
            )
        )
    )
    WITH CHECK (
        public.get_my_role() = 'provincial_admin'
        AND (
            agency_id IS NULL
            OR agency_id IN (
                SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
            )
        )
    );

-- ---- incidents ----
DROP POLICY IF EXISTS "incidents: super_admin reads all" ON public.incidents;
CREATE POLICY "incidents: provincial_admin reads own scope"
    ON public.incidents FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND assigned_agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

DROP POLICY IF EXISTS "incidents: super_admin updates all" ON public.incidents;
CREATE POLICY "incidents: provincial_admin updates own scope"
    ON public.incidents FOR UPDATE
    USING (
        public.get_my_role() = 'provincial_admin'
        AND assigned_agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

-- ---- dispatch_log ----
DROP POLICY IF EXISTS "dispatch_log: super_admin reads all" ON public.dispatch_log;
CREATE POLICY "dispatch_log: provincial_admin reads own scope"
    ON public.dispatch_log FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

DROP POLICY IF EXISTS "dispatch_log: super_admin inserts any" ON public.dispatch_log;
CREATE POLICY "dispatch_log: provincial_admin inserts own scope"
    ON public.dispatch_log FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'provincial_admin'
        AND dispatcher_id = auth.uid()
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

-- ---- stations ----
DROP POLICY IF EXISTS "stations: super_admin inserts any" ON public.stations;
CREATE POLICY "stations: provincial_admin inserts own scope"
    ON public.stations FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'provincial_admin'
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

DROP POLICY IF EXISTS "stations: super_admin updates any" ON public.stations;
CREATE POLICY "stations: provincial_admin updates own scope"
    ON public.stations FOR UPDATE
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

-- ---- rubric_configs (already has its own agency_type column -- no join needed) ----
DROP POLICY IF EXISTS "rubric_configs: super_admin reads all" ON public.rubric_configs;
CREATE POLICY "rubric_configs: provincial_admin reads own scope"
    ON public.rubric_configs FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_type = public.get_my_agency_type()
    );

DROP POLICY IF EXISTS "rubric_configs: super_admin inserts any" ON public.rubric_configs;
CREATE POLICY "rubric_configs: provincial_admin inserts own scope"
    ON public.rubric_configs FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'provincial_admin'
        AND agency_type = public.get_my_agency_type()
        AND created_by = auth.uid()
    );

DROP POLICY IF EXISTS "rubric_configs: super_admin updates any" ON public.rubric_configs;
CREATE POLICY "rubric_configs: provincial_admin updates own scope"
    ON public.rubric_configs FOR UPDATE
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_type = public.get_my_agency_type()
    );

-- ---- rubric_audit_log (also has its own agency_type column directly) ----
DROP POLICY IF EXISTS "rubric_audit_log: super_admin reads all" ON public.rubric_audit_log;
CREATE POLICY "rubric_audit_log: provincial_admin reads own scope"
    ON public.rubric_audit_log FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_type = public.get_my_agency_type()
    );

DROP POLICY IF EXISTS "rubric_audit_log: admin inserts" ON public.rubric_audit_log;
CREATE POLICY "rubric_audit_log: admin inserts"
    ON public.rubric_audit_log FOR INSERT
    WITH CHECK (
        public.get_my_role() IN ('agency_admin', 'provincial_admin')
        AND (actor_id IS NULL OR actor_id = auth.uid())
    );

-- ---- audit_logs (Type A/B marker: NULL = shared, set = scoped) ----
DROP POLICY IF EXISTS "audit_logs: super_admin reads all" ON public.audit_logs;
CREATE POLICY "audit_logs: provincial_admin reads own scope"
    ON public.audit_logs FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND (agency_type IS NULL OR agency_type = public.get_my_agency_type())
    );

-- ---- access_requests ----
DROP POLICY IF EXISTS "access_requests: super_admin reads"   ON public.access_requests;
DROP POLICY IF EXISTS "access_requests: super_admin updates" ON public.access_requests;

CREATE POLICY "access_requests: provincial_admin reads"
    ON public.access_requests FOR SELECT
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

CREATE POLICY "access_requests: provincial_admin updates"
    ON public.access_requests FOR UPDATE
    USING (
        public.get_my_role() = 'provincial_admin'
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    )
    WITH CHECK (
        public.get_my_role() = 'provincial_admin'
        AND agency_id IN (
            SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
        )
    );

-- ---- announcements (Type B for reading own-created; management stays
--      via the backend's service-role client, same as before -- only the
--      "full read" policy below is a real RLS-enforced authenticated path) ----
DROP POLICY IF EXISTS "announcements: super_admin full read" ON public.announcements;
CREATE POLICY "announcements: provincial_admin full read"
    ON public.announcements FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'provincial_admin')
    );

-- ---- incident_notes ----
DROP POLICY IF EXISTS "incident_notes: reporter, agency staff, responder, super_admin read" ON public.incident_notes;
CREATE POLICY "incident_notes: reporter, agency staff, responder, provincial_admin read"
    ON public.incident_notes FOR SELECT
    USING (
        (
            public.get_my_role() = 'provincial_admin'
            AND EXISTS (
                SELECT 1 FROM public.incidents i
                WHERE i.id = incident_notes.incident_id
                AND i.assigned_agency_id IN (
                    SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
                )
            )
        )
        OR EXISTS (
            SELECT 1 FROM public.incidents i
            WHERE i.id = incident_notes.incident_id
            AND (
                i.reporter_id = auth.uid()
                OR i.assigned_responder_id = auth.uid()
                OR (
                    public.get_my_role() = 'agency_admin'
                    AND i.assigned_agency_id = public.get_my_agency_id()
                )
            )
        )
    );
-- Write policy ("incident_notes: reporter, agency staff, responder write",
-- migration 031) never included super_admin -- oversight is read-only, no
-- change needed.

-- ---- incident_feedback ----
DROP POLICY IF EXISTS "incident_feedback: reporter or admin reads" ON public.incident_feedback;
CREATE POLICY "incident_feedback: reporter or admin reads"
    ON public.incident_feedback FOR SELECT
    USING (
        reporter_id = auth.uid()
        OR public.get_my_role() = 'agency_admin'
        OR (
            public.get_my_role() = 'provincial_admin'
            AND EXISTS (
                SELECT 1 FROM public.incidents i
                WHERE i.id = incident_feedback.incident_id
                AND i.assigned_agency_id IN (
                    SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
                )
            )
        )
    );

-- ---- location_hazards ----
DROP POLICY IF EXISTS "hazards: read own agency or province-wide" ON public.location_hazards;
CREATE POLICY "hazards: read own agency or province-wide"
    ON public.location_hazards FOR SELECT
    USING (
        agency_id IS NULL
        OR agency_id = public.get_my_agency_id()
        OR (
            public.get_my_role() = 'provincial_admin'
            AND agency_id IN (
                SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
            )
        )
    );

DROP POLICY IF EXISTS "hazards: staff write own agency" ON public.location_hazards;
CREATE POLICY "hazards: staff write own agency"
    ON public.location_hazards FOR ALL
    USING (
        (public.get_my_role() IN ('agency_admin', 'responder') AND agency_id = public.get_my_agency_id())
        OR (
            public.get_my_role() = 'provincial_admin'
            AND agency_id IN (
                SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
            )
        )
    )
    WITH CHECK (
        (public.get_my_role() IN ('agency_admin', 'responder') AND agency_id = public.get_my_agency_id())
        OR (
            public.get_my_role() = 'provincial_admin'
            AND agency_id IN (
                SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
            )
        )
    );

-- ---- responder_distress ----
DROP POLICY IF EXISTS "distress: responder reads own" ON public.responder_distress;
CREATE POLICY "distress: responder reads own"
    ON public.responder_distress FOR SELECT
    USING (
        responder_id = auth.uid()
        OR (public.get_my_role() = 'agency_admin' AND agency_id = public.get_my_agency_id())
        OR (
            public.get_my_role() = 'provincial_admin'
            AND agency_id IN (
                SELECT id FROM public.agencies WHERE agency_type = public.get_my_agency_type()
            )
        )
    );

-- ---- system_config (Type B: shared, unconditional for the role -- no scoping) ----
DROP POLICY IF EXISTS "system_config: super_admin reads all" ON public.system_config;
CREATE POLICY "system_config: provincial_admin reads all"
    ON public.system_config FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'provincial_admin')
    );

-- ---- storage: incident-media (agency_admin/responder unchanged; provincial_admin added, scoped) ----
DROP POLICY IF EXISTS "incident-media: reporter can read own" ON storage.objects;
CREATE POLICY "incident-media: reporter can read own"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'incident-media'
    AND (
        auth.uid()::text = (storage.foldername(name))[1]
        OR EXISTS (
            SELECT 1
            FROM public.incidents i
            JOIN public.users u ON u.id = auth.uid()
            WHERE i.id::text = (storage.foldername(name))[2]
            AND (
                (u.role IN ('agency_admin', 'responder') AND i.assigned_agency_id = u.agency_id)
                OR (u.role = 'provincial_admin' AND i.assigned_agency_id IN (
                    SELECT id FROM public.agencies WHERE agency_type = u.agency_type
                ))
            )
        )
    )
);

-- ---- storage: resident-ids (Type B: identity verification has no agency
--      dimension -- agency_admin already reads/deletes ANY resident's scan
--      unconditionally today; provincial_admin keeps the same, no scoping) ----
DROP POLICY IF EXISTS "resident-ids: admin can read" ON storage.objects;
CREATE POLICY "resident-ids: admin can read"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'resident-ids'
    AND public.get_my_role() IN ('agency_admin', 'provincial_admin')
);

DROP POLICY IF EXISTS "resident-ids: admin can delete" ON storage.objects;
CREATE POLICY "resident-ids: admin can delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'resident-ids'
    AND public.get_my_role() IN ('agency_admin', 'provincial_admin')
);

-- ============================================================
-- 5. incident_notes_author_role_check -- notes authored by a provincial
--    admin (oversight comments, if ever allowed) use the new role name.
-- ============================================================
ALTER TABLE public.incident_notes DROP CONSTRAINT IF EXISTS incident_notes_author_role_check;
ALTER TABLE public.incident_notes
    ADD CONSTRAINT incident_notes_author_role_check
    CHECK (author_role IN ('agency_admin', 'responder', 'provincial_admin', 'resident'));

-- ============================================================
-- 6. Bootstrap template -- run manually, per real account, AFTER
--    reviewing which email maps to which agency_type. Do not run blind.
-- ============================================================
-- UPDATE public.users SET role = 'provincial_admin', agency_id = NULL, agency_type = 'PNP'
--   WHERE email = '<pnp provincial admin email>';
-- UPDATE public.users SET role = 'provincial_admin', agency_id = NULL, agency_type = 'BFP'
--   WHERE email = '<bfp provincial admin email>';
-- UPDATE public.users SET role = 'provincial_admin', agency_id = NULL, agency_type = 'MDRRMO'
--   WHERE email = '<mdrrmo provincial admin email>';

-- ============================================================
-- Verification -- run after applying.
-- ============================================================
SELECT conname FROM pg_constraint WHERE conrelid = 'public.users'::regclass AND conname LIKE 'users_%check%';

SELECT policyname, tablename FROM pg_policies
WHERE schemaname = 'public' AND policyname LIKE '%super_admin%';
-- ^ should return ZERO rows once this migration and all bootstrap updates are complete.

SELECT policyname, tablename FROM pg_policies
WHERE schemaname = 'public' AND policyname LIKE '%provincial_admin%'
ORDER BY tablename;

SELECT id, email, role, agency_id, agency_type FROM public.users WHERE role = 'provincial_admin';
