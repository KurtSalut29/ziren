---
name: supabase-migration
description: Write, review, and apply Ziren's Supabase/Postgres migrations in ziren_backend/supabase/migrations — new tables, columns, RLS policies, SECURITY DEFINER helpers, and the service_role GRANTs that are the single most common omission in this project. Use whenever the user adds or changes a database table, column, index, RLS policy, or trigger, mentions a migration or the Supabase SQL Editor, or hits "permission denied for table", error 42501, an unexplained 500 from a backend endpoint, or infinite recursion in an RLS policy.
---

# Ziren Supabase migrations

Migrations live in `ziren_backend/supabase/migrations/`, numbered `NNN_name.sql`
and applied by hand in the Supabase SQL Editor. There is no migration runner —
which means an unapplied file looks identical to an applied one, and the only
real evidence a migration ran is its verification query.

## The failure that has already happened twice

Creating a table grants nothing. **RLS and GRANT are independent gates in
Postgres:** a policy that permits a row is irrelevant if the role has no table
privilege at all. The FastAPI backend connects as `service_role`, which
bypasses RLS but still needs the privilege.

Migrations 012 and 016 forgot it → migration 017 fixed it.
Migration 007 forgot it → migration 018 fixed it, months later.

The symptom is deceptive every time: `42501 permission denied for table …`
surfaces to the user as a generic 500 or, worse, as a soothing "please try
again shortly" for a condition that no retry can fix. In the rubric case the
engine's seed-file fallback kept severity scoring alive while the entire config
UI was inaccessible, so nothing looked broken.

**So: every migration that creates a table ends with its GRANT.**

```sql
GRANT ALL ON public.<table> TO service_role;
-- plus, only if the table is read before a session exists (reference data
-- shown on the registration form, etc.):
GRANT SELECT ON public.<table> TO anon, authenticated;
```

Withhold `anon`/`authenticated` deliberately, and say why in a comment. On
`access_requests` they were withheld because direct writes would let anyone
flood the table and direct reads would expose which officials had applied —
submissions go through the rate-limited API instead. That reasoning belongs in
the file, not in someone's memory.

## Anatomy of a migration here

Read `017_grants_for_new_tables.sql`, `018_grants_rubric_tables.sql`, and
`010_rls_agency_scoping.sql` before writing a new one — they are the house
style, and their comment headers double as the post-mortems that later feed
the weekly report.

```sql
-- ============================================================
-- Migration NNN: <one-line purpose>
--
-- <What was broken and how it presented to the user. Name the real
--  error string and SQLSTATE. If the symptom pointed at the wrong
--  subsystem, say so — that is the part worth remembering.>
--
-- <Decisions and their reasoning. What is deliberately NOT granted
--  or NOT scoped, and why.>
--
-- Requires: migrations X, Y already applied. Idempotent.
-- Run in Supabase SQL Editor AFTER NNN-1.
-- ============================================================

<DDL>

-- ------------------------------------------------------------
-- Verification — <what a correct result looks like>
-- ------------------------------------------------------------
SELECT ...;
```

Four properties every file should have:

- **Numbered after the highest existing file.** Suffixed letters (`001b`,
  `001c`, `002b`) mean "a fix to that migration's subject" — use them when
  patching an earlier migration's mistake, and a fresh number for new work.
- **Idempotent.** These get re-run against a database whose state nobody is
  certain of. `CREATE OR REPLACE`, `IF NOT EXISTS`, `DROP POLICY IF EXISTS`
  before `CREATE POLICY`.
- **Self-contained enough for a fresh database.** 017 restates a grant that 012
  already made, so one file gives the full picture. Repetition beats a reader
  reconstructing state across eighteen files.
- **Ends with a verification query** whose expected result is described in a
  comment. This is the only way to know it actually ran.

## RLS: scope by agency, and never recurse

`agency_admin` must only ever see their own agency's rows. Migration 010 closed
four gaps where they could read or write across agencies — incidents,
dispatch_log, stations, and the rubric tables. For a dispatch product this is a
confidentiality boundary, not a nicety.

Write policies against the `SECURITY DEFINER` helpers, never against an inline
subquery on `public.users`:

- `get_my_role()`
- `get_my_agency_id()`
- `get_my_agency_type()` — returns `NULL` for `super_admin`, who has no agency

A policy on `users` that subqueries `users` re-enters RLS and recurses; that is
what migration `001d_fix_rls_recursion.sql` exists to undo. `SECURITY DEFINER`
bypasses RLS inside the helper, which breaks the cycle and removes the extra
join at the same time.

Note the granularity difference that is easy to get wrong: **rubric configs are
per `agency_type`** (BFP/PNP/MDRRMO), not per `agency_id` — every BFP admin
shares one active BFP config. Incidents, stations and dispatch_log are per
`agency_id`.

## Workflow

1. **Read the last few migrations** to see current state and the next number.
2. **Write the file**, header first — writing the post-mortem before the DDL
   usually clarifies what the DDL should be.
3. **Checklist before handing it over:** GRANT for `service_role` on every new
   table · RLS enabled and agency-scoped on every new table · helpers used
   instead of subqueries · idempotent · verification query present.
4. **Tell the user to run it in the Supabase SQL Editor** and paste back the
   verification output. You cannot apply it yourself; confirming it ran is a
   real step, not a formality.
5. **Re-verify the affected endpoint** — hit it and check the status code.
   Migration 018's whole point is that the 500 was invisible from the outside.
6. **Capture the defect** if this migration fixes something real: symptom, root
   cause, evidence string. The `weekly-report` skill needs exactly that, and
   the details are never as easy to reconstruct later.
