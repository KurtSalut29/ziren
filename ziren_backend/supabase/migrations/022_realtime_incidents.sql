-- ============================================================
-- Migration 022: Put incidents on the Realtime publication
--
-- THE BUG
--
-- Responders were never told a report had been assigned to them. The mobile
-- app has had a Supabase Realtime subscription since Phase 6B.3
-- (ResponderNotificationProvider) that listens on public.incidents filtered by
-- assigned_responder_id, and it has never received a single event.
--
-- Not because the filter was wrong, and not because RLS blocked it —
-- migration 010's "incidents: responder reads assigned" policy permits exactly
-- these rows. Because the table was never added to the `supabase_realtime`
-- publication, and a table outside the publication produces no WAL stream for
-- Realtime to read. There is no error anywhere in that path: the client
-- channel reports SUBSCRIBED, the callback is registered, and nothing ever
-- arrives. From the phone it is indistinguishable from a quiet night.
--
-- The symptom reaching the user was "the responder side has no notifications",
-- which reads as a missing FEATURE. It was a missing GRANT-shaped thing: one
-- line of DDL nobody wrote, under a client that had been finished for weeks.
--
-- WHY ONLY incidents
--
-- Realtime streams every change on a published table to every subscriber whose
-- RLS lets them see it. `users` is deliberately NOT published: it carries the
-- verification evidence paths, the ID numbers and the accessibility profile,
-- and there is no client that needs to watch it live. Publishing a table is a
-- data-exposure decision, not a performance one, so it is made per table and
-- only where something actually subscribes.
--
-- REPLICA IDENTITY IS LEFT ALONE
--
-- Realtime evaluates its filters against the NEW row, which is fully present
-- under the default replica identity, so the subscription works as written.
-- What the default does NOT give is a populated `oldRecord` on UPDATE — only
-- the primary key. REPLICA IDENTITY FULL would fix that at the cost of writing
-- every column of every incident update into the WAL, permanently, so that a
-- phone can diff two rows.
--
-- The client does not need it. An assignment arrives as an UPDATE (the row is
-- INSERTed by the resident with assigned_responder_id NULL, and the dispatcher
-- sets it later), so "is this new to me" cannot be answered by the event type
-- either way. ResponderNotificationProvider answers it by tracking which
-- incident ids it has already seen — which is correct across a reconnect, a
-- cold start and a reassignment, none of which an oldRecord diff handles.
--
-- Requires: migrations 002 and 010 already applied. Idempotent.
-- Run in Supabase SQL Editor AFTER 021.
-- ============================================================

DO $$
BEGIN
    -- ALTER PUBLICATION ... ADD TABLE is an error, not a no-op, when the table
    -- is already a member. These files get re-run against databases whose
    -- state nobody is sure of, so the membership is checked first.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname    = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'incidents'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.incidents;
    END IF;
END $$;

-- ------------------------------------------------------------
-- Verification
--
-- Expect exactly one row: public | incidents. An empty result means the
-- publication add did not take, and the responder app will go on looking
-- healthy while receiving nothing.
-- ------------------------------------------------------------
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND schemaname = 'public'
  AND tablename = 'incidents';
