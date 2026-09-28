-- ============================================================
-- Migration 024: the responder stops being a write-only endpoint
--
-- WHAT WAS WRONG
--
-- Everything the responder side could do was a read or a status flip. Three
-- consequences, all of them silent:
--
-- 1. NOBODY KNEW IF THE RESPONDER SAW THE CALL. The FSM in
--    responder_service._VALID_TRANSITIONS starts at 'dispatched', which means
--    "a dispatcher pressed a button" — not "a unit is coming". There was no
--    acceptance anywhere in the schema, so an assignment that reached a phone
--    that was off, out of signal, or in someone's locker was indistinguishable
--    from one a crew was already driving on. The dispatcher found out by
--    nobody arriving.
--
-- 2. THE FSM WAS FORWARD-ONLY WITH NO EXIT. A responder whose truck broke
--    down, who was already committed to another call, or who had been sent to
--    the wrong municipality could not hand the incident back. The only way out
--    was for a dispatcher to notice the absence.
--
-- 3. 'resolved' RECORDED NOTHING BUT A TIMESTAMP.
--    responder_service.update_incident_status writes exactly
--    {"status": ..., "resolved_at": ...}. No outcome, no casualties, no "it
--    was a false alarm". This is the one that matters most for the project as
--    a whole: the severity rubric is the core claim of this system, and until
--    something records what the crew actually FOUND, the rubric can never be
--    scored against reality. "System said critical" has had nothing to be
--    compared against.
--
-- WHY 'dispatched' KEEPS ITS MEANING
--
-- The honest fix for (1) is a new status — assignment would move an incident
-- to 'notified', and only acceptance would promote it to 'dispatched', so the
-- word would finally mean what it says. That was rejected on blast radius:
-- dispatched_at feeds get_dashboard's median response time, the dispatcher
-- board's counts, the resident's status strip and both history filters, and
-- redefining it would quietly change every one of those numbers.
--
-- So acceptance is recorded ALONGSIDE the status rather than inside it, and
-- the API exposes a derived ack_state (pending | accepted | declined |
-- overdue) computed from these columns. Same clarity, no migration risk to
-- code that works.
--
-- WHY THE DEADLINE IS NOT STORED
--
-- There is no ack_deadline_at column. The deadline is a function of severity
-- (critical 60s, high 120s, otherwise 180s) and is computed at read time from
-- dispatched_at in responder_service._ACK_DEADLINE_SECONDS. Storing it would
-- freeze the policy into every historical row, so that tuning the number later
-- would leave the board judging old incidents by a rule nobody remembers.
--
-- NOTHING HERE AUTO-REASSIGNS
--
-- Deliberate, and the point of the feature rather than a limitation of it. An
-- overdue incident becomes loud on the dispatcher's board; it does not move
-- itself. A system that silently reassigns a life-safety call can stand two
-- crews down without either of them knowing, and there is no human left who
-- can tell that happened. The rule this feature is built on:
--
--     The system never silently reassigns a life-safety call.
--     It makes the silence impossible to miss.
--
-- NAMING: 'accepted', NOT 'acknowledged'
--
-- ziren_dashboard/lib/hooks/useIncidentAlerts.ts already owns the word
-- "acknowledge", where it means a dispatcher dismissed a chime — client-side,
-- session-scoped, never persisted, and says nothing about the incident. Two
-- unrelated meanings of one word in one product is how a reviewer ends up
-- reading the wrong code. The responder ACCEPTS.
--
-- Requires: migrations 002, 008, 010, 011 already applied. Idempotent.
-- Run in Supabase SQL Editor AFTER 023.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Acceptance and refusal
--
-- No GRANT needed: these are columns on public.incidents, which has carried
-- its service_role grant since 002. The 017/018 failure applies to new TABLES
-- — a column inherits the table's privileges. (New tables DO appear further
-- down, and they carry their grants with them.)
-- ------------------------------------------------------------
ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS accepted_at      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS declined_at      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS declined_reason  TEXT,
    ADD COLUMN IF NOT EXISTS declined_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS decline_count    INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.incidents.accepted_at IS
    'When the assigned responder confirmed on their own handset that they are '
    'taking this call. NULL while an assignment is outstanding — which is the '
    'condition the dispatcher board escalates on. Distinct from dispatched_at, '
    'which only records that a dispatcher clicked.';

COMMENT ON COLUMN public.incidents.declined_reason IS
    'Why the responder could not take it. Constrained rather than free text so '
    'the dispatcher can act on it in one glance and so the reasons aggregate: '
    '"vehicle_down" appearing twenty times in a month is a fleet finding.';

COMMENT ON COLUMN public.incidents.decline_count IS
    'Increments on every refusal, and is never reset by reassignment. Three '
    'refusals on one incident is not a responder problem, it is a coverage '
    'problem, and it should be visible as one.';

-- Reasons a crew genuinely cannot go. 'other' exists because an enum that
-- cannot express the real answer gets filled in with the nearest wrong one,
-- and then the aggregate lies.
ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_declined_reason_check;
ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_declined_reason_check CHECK (
        declined_reason IS NULL OR declined_reason IN (
            'vehicle_down',        -- truck/ambulance not roadworthy
            'already_committed',   -- on another call that is not closed
            'out_of_area',         -- wrong municipality for this unit
            'insufficient_crew',   -- not enough hands to roll safely
            'road_impassable',     -- flood, landslide, cut bridge
            'other'
        )
    );

-- Partial index, not a full one. The board's hot query is "assignments still
-- outstanding", which is a small set at any moment; indexing the millions of
-- rows where accepted_at IS NOT NULL would be paying to find what nobody asks
-- for.
CREATE INDEX IF NOT EXISTS incidents_awaiting_accept_idx
    ON public.incidents (dispatched_at)
    WHERE accepted_at IS NULL
      AND status IN ('dispatched', 'en_route', 'arrived');


-- ------------------------------------------------------------
-- 2. After-action — what the crew actually found
--
-- This is the half of the loop that has never existed. Without it the incident
-- archive records what was REPORTED and what the rubric GUESSED, and nothing
-- at all about what was true.
-- ------------------------------------------------------------
ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS outcome                TEXT,
    ADD COLUMN IF NOT EXISTS outcome_notes          TEXT,
    ADD COLUMN IF NOT EXISTS casualties_injured     INTEGER,
    ADD COLUMN IF NOT EXISTS casualties_fatal       INTEGER,
    ADD COLUMN IF NOT EXISTS casualties_transported INTEGER,
    ADD COLUMN IF NOT EXISTS scene_media_urls       TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS closed_by              UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_outcome_check;
ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_outcome_check CHECK (
        outcome IS NULL OR outcome IN (
            'handled_on_scene',    -- dealt with, nobody moved
            'transported',         -- casualties taken to a facility
            'turned_over',         -- handed to PNP/BFP/MDRRMO/hospital
            'false_alarm',         -- nothing was happening
            'nobody_found',        -- arrived, no incident, no reporter
            'refused_assistance',  -- party present and declined help
            'unable_to_access',    -- could not reach the scene at all
            'other'
        )
    );

COMMENT ON COLUMN public.incidents.outcome IS
    'What the crew found, recorded at resolve time. THE POINT OF THIS COLUMN '
    'is rubric validation: severity has never been checkable against reality '
    'because nothing recorded reality. An incident the rubric scored critical '
    'that closes as false_alarm is a measurable rubric miss, and until now '
    'that comparison could not be made at all.';

COMMENT ON COLUMN public.incidents.casualties_injured IS
    'NULL and 0 mean different things and both are kept. NULL is "not '
    'recorded"; 0 is "the crew counted, and nobody was hurt". Collapsing them '
    'would turn every unfilled form into a clean scene.';

COMMENT ON COLUMN public.incidents.scene_media_urls IS
    'Storage paths for photos the RESPONDER took on scene. Deliberately a '
    'separate column from media_urls, which is the reporter''s: mixing them '
    'would make it impossible to tell what was known before the crew arrived '
    'from what they documented after, which is exactly the distinction an '
    'after-action review needs.';

-- Casualty counts are counts. A negative one is a bug reaching the database.
ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_casualties_nonneg_check;
ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_casualties_nonneg_check CHECK (
        (casualties_injured     IS NULL OR casualties_injured     >= 0) AND
        (casualties_fatal       IS NULL OR casualties_fatal       >= 0) AND
        (casualties_transported IS NULL OR casualties_transported >= 0)
    );


-- ------------------------------------------------------------
-- 3. Mutual aid — one incident asking for another agency
--
-- Multi-agency response is the norm here, not the exception: a structure fire
-- needs BFP on the fire, MDRRMO on the casualties and PNP on the crowd. Until
-- now that coordination happened entirely on the radio and left no record, so
-- the archive shows one agency attending incidents that three attended.
--
-- Modelled as a real linked incident rather than a flag, because the second
-- agency needs the whole machine — its own triage, its own dispatcher, its own
-- assignment, its own responder, its own after-action. A boolean on the parent
-- would give the ambulance crew nothing to be dispatched to.
-- ------------------------------------------------------------
ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS backup_of_incident_id UUID
        REFERENCES public.incidents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS backup_reason         TEXT,
    ADD COLUMN IF NOT EXISTS backup_requested_by   UUID
        REFERENCES public.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.incidents.backup_of_incident_id IS
    'Set on the CHILD incident, pointing at the incident whose responder asked '
    'for help. ON DELETE SET NULL rather than CASCADE: closing or removing the '
    'parent must never delete the ambulance''s own record of its own call.';

CREATE INDEX IF NOT EXISTS incidents_backup_parent_idx
    ON public.incidents (backup_of_incident_id)
    WHERE backup_of_incident_id IS NOT NULL;


-- ------------------------------------------------------------
-- 4. ETA — the resident's half of the loop
--
-- A resident who reports an emergency currently sees nothing afterwards. Not
-- who is coming, not whether anyone is. The responder's phone already pings
-- its position to users.location (migration 011, endpoint finally written in
-- Phase 6C); this is that same signal turned around and pointed back at the
-- person waiting.
-- ------------------------------------------------------------
ALTER TABLE public.incidents
    ADD COLUMN IF NOT EXISTS eta_minutes     INTEGER,
    ADD COLUMN IF NOT EXISTS eta_updated_at  TIMESTAMPTZ;

COMMENT ON COLUMN public.incidents.eta_minutes IS
    'Straight-line distance over an assumed road speed, recomputed on each '
    'location ping while status = en_route. Deliberately coarse and always '
    'shown to the resident as "about N minutes": promising a precise arrival '
    'to someone whose house is on fire is worse than promising nothing.';

ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_eta_sane_check;
ALTER TABLE public.incidents
    ADD CONSTRAINT incidents_eta_sane_check CHECK (
        eta_minutes IS NULL OR (eta_minutes >= 0 AND eta_minutes <= 600)
    );


-- ------------------------------------------------------------
-- 5. location_hazards — what the map cannot tell you
--
-- "Bridge out at Caraycaray." "Narrow road past the chapel, tricycle only."
-- "Dogs on the property." This knowledge exists in Biliran, entirely inside
-- the heads of the crews who have been there, and it is lost every time one of
-- them transfers or retires. A responder who learns about the cut bridge by
-- arriving at it has lost the call.
--
-- NEW TABLE — so it carries its own GRANT. See 017/018.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.location_hazards (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Where. A point plus a radius rather than a barangay FK: hazards are
    -- physical (this bridge, this bend) and do not respect boundaries, and a
    -- barangay-wide warning is too coarse to be worth reading.
    location     GEOMETRY(POINT, 4326) NOT NULL,
    radius_m     INTEGER NOT NULL DEFAULT 300 CHECK (radius_m > 0 AND radius_m <= 5000),

    hazard_type  TEXT NOT NULL CHECK (hazard_type IN (
        'road_impassable',   -- cut bridge, landslide, permanent washout
        'access_difficult',  -- narrow, steep, foot or motorcycle only
        'security',          -- known hostility, armed history, crowd risk
        'animal',            -- dogs, livestock on the road
        'structural',        -- unsafe building, live wires
        'other'
    )),
    note         TEXT NOT NULL,

    -- Who it belongs to. NULL = province-wide, visible to every agency: a cut
    -- bridge is a cut bridge for the ambulance as much as the fire truck.
    agency_id    UUID REFERENCES public.agencies(id) ON DELETE CASCADE,

    created_by   UUID REFERENCES public.users(id) ON DELETE SET NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.location_hazards IS
    'Standing local knowledge about getting to a place, contributed by the '
    'crews who have been there. Not incident data — a hazard outlives the '
    'incident that revealed it, which is the entire reason it is a table and '
    'not a note on an incident row.';

CREATE INDEX IF NOT EXISTS location_hazards_geo_idx
    ON public.location_hazards USING GIST(location);
CREATE INDEX IF NOT EXISTS location_hazards_active_idx
    ON public.location_hazards (is_active) WHERE is_active;

DROP TRIGGER IF EXISTS location_hazards_updated_at ON public.location_hazards;
CREATE TRIGGER location_hazards_updated_at
    BEFORE UPDATE ON public.location_hazards
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ------------------------------------------------------------
-- 6. responder_distress — the responder's own emergency
--
-- Every safety feature in this product points at the resident. The people who
-- walk into the burning building and the armed domestic dispute have had no
-- way to call for help for themselves, on a device that is already a
-- location-aware panic button for everybody else.
--
-- A table rather than a column on users, because a distress event has a
-- lifecycle (raised, seen, cleared, by whom) and because the history is the
-- point: "how often do our crews hit this button, and where" is a question an
-- agency admin should be able to ask.
--
-- NEW TABLE — carries its own GRANT.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.responder_distress (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    responder_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

    -- The call they were on, if any. NULL is valid and expected: a responder
    -- can be in trouble between calls, and refusing the alert because it has
    -- no incident to attach to would be the worst possible failure mode.
    incident_id   UUID REFERENCES public.incidents(id) ON DELETE SET NULL,
    agency_id     UUID REFERENCES public.agencies(id) ON DELETE SET NULL,

    kind          TEXT NOT NULL CHECK (kind IN ('panic', 'no_movement')),
    location      GEOMETRY(POINT, 4326),
    note          TEXT,

    raised_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cleared_at    TIMESTAMPTZ,
    cleared_by    UUID REFERENCES public.users(id) ON DELETE SET NULL,
    clear_note    TEXT
);

COMMENT ON COLUMN public.responder_distress.kind IS
    '''panic'' is the responder pressing and holding the button themselves. '
    '''no_movement'' is raised by the backend when a responder has been '
    'en_route with no position change and no status change past a threshold — '
    'weaker evidence, and shown to the dispatcher as a question rather than an '
    'alarm, because the ordinary explanation is a phone in a cupholder.';

COMMENT ON COLUMN public.responder_distress.cleared_at IS
    'Only a dispatcher or agency admin clears this, never the responder and '
    'never a timeout. A distress signal that ages out on its own is a distress '
    'signal nobody answered.';

CREATE INDEX IF NOT EXISTS responder_distress_open_idx
    ON public.responder_distress (raised_at DESC) WHERE cleared_at IS NULL;
CREATE INDEX IF NOT EXISTS responder_distress_responder_idx
    ON public.responder_distress (responder_id);


-- ------------------------------------------------------------
-- 6b. When the position was last reported
--
-- users.location has existed since migration 011 and carries no timestamp, so
-- a stale position is indistinguishable from a current one: a responder
-- parked at the scene and a responder whose phone died forty minutes ago look
-- identical on the dispatcher's map, and both look identical to one driving.
--
-- This is what makes the 'no_movement' half of responder_distress possible at
-- all. Without it the kind could be declared and never raised, which is worse
-- than not offering it — a safety feature that exists in the schema and never
-- fires is one a dispatcher may believe is watching.
-- ------------------------------------------------------------
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN public.users.location_updated_at IS
    'Set on every PATCH /responder/location. A NULL here on a responder with a '
    'location means the position predates this column — treat it as unknown '
    'age rather than as current.';


-- ------------------------------------------------------------
-- 7. GRANTS — the step 012, 016 and 007 each forgot
--
-- RLS and GRANT are independent gates. The backend connects as service_role
-- and bypasses RLS, and still cannot read a table it has no privilege on:
-- the failure is 42501 and it surfaces as a generic 500.
--
-- anon/authenticated are withheld from BOTH tables, deliberately:
--   location_hazards    — writes go through the API so they are attributable
--                         to a responder and rate-limited; a direct write
--                         would let any signed-in account post a fake
--                         "road impassable" that diverts an ambulance.
--   responder_distress  — the open set says which crews are in trouble and
--                         exactly where they are. Nothing outside the backend
--                         reads it.
-- ------------------------------------------------------------
GRANT ALL ON public.location_hazards   TO service_role;
GRANT ALL ON public.responder_distress TO service_role;


-- ------------------------------------------------------------
-- 8. RLS — agency-scoped, via the helpers, never an inline subquery
--
-- Policies are written against get_my_role() / get_my_agency_id(), which are
-- SECURITY DEFINER and therefore do not re-enter RLS. An inline subquery on
-- public.users from a policy is what 001d exists to undo.
-- ------------------------------------------------------------
ALTER TABLE public.location_hazards   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.responder_distress ENABLE ROW LEVEL SECURITY;

-- Hazards: everyone signed in reads the province-wide ones plus their own
-- agency's. Withholding another agency's local knowledge would be withholding
-- a cut bridge from the ambulance.
DROP POLICY IF EXISTS "hazards: read own agency or province-wide" ON public.location_hazards;
CREATE POLICY "hazards: read own agency or province-wide"
    ON public.location_hazards FOR SELECT
    USING (
        agency_id IS NULL
        OR public.get_my_role() = 'super_admin'
        OR agency_id = public.get_my_agency_id()
    );

DROP POLICY IF EXISTS "hazards: staff write own agency" ON public.location_hazards;
CREATE POLICY "hazards: staff write own agency"
    ON public.location_hazards FOR ALL
    USING (
        public.get_my_role() = 'super_admin'
        OR (public.get_my_role() IN ('agency_admin', 'responder')
            AND agency_id = public.get_my_agency_id())
    )
    WITH CHECK (
        public.get_my_role() = 'super_admin'
        OR (public.get_my_role() IN ('agency_admin', 'responder')
            AND agency_id = public.get_my_agency_id())
    );

-- Distress: a responder sees their own signals; staff see their agency's.
DROP POLICY IF EXISTS "distress: responder reads own" ON public.responder_distress;
CREATE POLICY "distress: responder reads own"
    ON public.responder_distress FOR SELECT
    USING (
        responder_id = auth.uid()
        OR public.get_my_role() = 'super_admin'
        OR (public.get_my_role() = 'agency_admin'
            AND agency_id = public.get_my_agency_id())
    );

DROP POLICY IF EXISTS "distress: responder raises own" ON public.responder_distress;
CREATE POLICY "distress: responder raises own"
    ON public.responder_distress FOR INSERT
    WITH CHECK (responder_id = auth.uid());


-- ------------------------------------------------------------
-- 9. Realtime
--
-- responder_distress is published so the dispatcher console learns about a
-- panic press in the second it happens rather than on the next 15s poll. That
-- is the whole difference between this feature working and not.
--
-- location_hazards is NOT published: it changes rarely, nothing watches it
-- live, and publishing a table is a data-exposure decision made per table.
-- (Migration 022 is the cautionary tale in the other direction — incidents was
-- left OUT of the publication and the responder subscription silently received
-- nothing for weeks. If 022 has not been run yet, run it: none of the
-- acceptance flow reaches a phone without it.)
-- ------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'responder_distress'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.responder_distress;
    END IF;
END $$;


-- ============================================================
-- Verification
--
-- Expect THREE result sets:
--   1. 18 rows — every new incidents column, all nullable except
--      decline_count and scene_media_urls which carry defaults.
--   2. 2 rows  — location_hazards and responder_distress, both rowsecurity = t
--      and both with has_table_privilege = t for service_role. A FALSE in that
--      last column is the 42501 bug from 017/018 about to happen again.
--   3. 1 row   — responder_distress on the realtime publication.
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'incidents'
  AND column_name IN (
      'accepted_at', 'declined_at', 'declined_reason', 'declined_by',
      'decline_count', 'outcome', 'outcome_notes', 'casualties_injured',
      'casualties_fatal', 'casualties_transported', 'scene_media_urls',
      'closed_by', 'backup_of_incident_id', 'backup_reason',
      'backup_requested_by', 'eta_minutes', 'eta_updated_at'
  )
ORDER BY column_name;

SELECT c.relname                                             AS table_name,
       c.relrowsecurity                                      AS rls_enabled,
       has_table_privilege('service_role', c.oid, 'SELECT')  AS service_role_can_read,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('location_hazards', 'responder_distress')
ORDER BY c.relname;

SELECT tablename FROM pg_publication_tables
WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
  AND tablename IN ('incidents', 'responder_distress')
ORDER BY tablename;
