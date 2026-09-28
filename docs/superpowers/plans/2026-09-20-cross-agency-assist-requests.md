# Cross-Agency Assist Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an agency currently handling an incident ask another agency present in the same municipality for help — a short request, a per-request chat, and an explicit Acknowledge/Decline — without giving the receiving agency any access to the incident itself.

**Architecture:** Two new Postgres tables (a mutable status envelope + an append-only message log, mirroring the existing `incidents`/`incident_notes` split), one new FastAPI service + router, and dashboard additions: a "Request assist" action inside the incident detail modal, a new panel on the Operational Area Agencies tab, and a shared chat component polled every ~6s while open.

**Tech Stack:** FastAPI + Supabase/Postgres (backend), Next.js 15 / React 19 / Tailwind 4 (dashboard), pytest (backend tests), scratchpad Playwright scripts against a mocked backend (frontend verification — this repo has no committed E2E test files; see Task 13).

**Spec:** `docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md`

## Global Constraints

- Dashboard only, `agency_admin` role only — no mobile/responder involvement, no `provincial_admin` write access (see spec's explicit platform-scope decision). `provincial_admin` visibility was not part of the approved spec; do not add it without asking.
- One target agency per request; hazmat-style dual-agency needs mean sending twice.
- The receiving agency never gets access to the incident row itself — only a narrow, live-projected snapshot (category, severity, location text) fetched at read time, never denormalized/copied.
- No Supabase Realtime for this feature — fast polling (~6s) while a thread panel is open, matching the spec's explicit rejection of the dashboard's first-ever direct Supabase connection.
- Status transitions are one-way: `pending → acknowledged` or `pending → declined`. No un-declining.
- Every migration ends with `GRANT ALL ... TO service_role;` and a verification query (see the `supabase-migration` skill). **The migration is written in this plan but must NOT be applied to the live database by the executor — hand the file to the project owner to run in the Supabase SQL Editor.**
- Never trust a client-supplied agency id for "who is acting" — always resolve the caller's own agency from `current_user["agency_id"]` (set by `get_current_user`), same rule every existing router in this codebase already follows.

---

## Task 1: Migration — `incident_assist_requests` + `incident_assist_messages`

**Files:**
- Create: `ziren_backend/supabase/migrations/036_incident_assist_requests.sql`

**Interfaces:**
- Produces: tables `public.incident_assist_requests` (columns: `id, incident_id, requesting_agency_id, requested_agency_id, overlap_flag, status, requested_by, responded_by, created_at, responded_at`) and `public.incident_assist_messages` (columns: `id, request_id, sender_agency_id, sender_id, body, created_at`), both RLS-enabled, granted to `service_role`.

- [ ] **Step 1: Write the migration file**

```sql
-- ============================================================
-- Migration 036: Cross-agency assist requests
--
-- Lets the agency currently handling an incident ask another agency
-- present in the same municipality for help — see
-- docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md
-- for the full design and why it is shaped this way.
--
-- TWO TABLES, MATCHING THE incidents/incident_notes SPLIT
--
-- incident_assist_requests is the mutable envelope (status changes over
-- time, same as incidents.status). incident_assist_messages is an
-- append-only log (never edited/deleted), same reasoning as migration
-- 030's incident_notes: a message is evidence of what was said and when.
--
-- THE RECEIVING AGENCY NEVER GETS INCIDENT ACCESS
--
-- incidents RLS is completely untouched by this migration. The
-- application layer (assist_request_service.py) projects a narrow,
-- live snapshot (category/severity/location) into API responses —
-- these two tables never copy incident columns, and the receiving
-- agency's RLS grant here is scoped to THESE tables only.
--
-- NO sender_role COLUMN on incident_assist_messages, unlike
-- incident_notes.author_role — every writer here is an agency_admin by
-- construction of the INSERT policy below (super_admin is read-only
-- oversight, mobile/responder is out of scope), so there is no role
-- variability for a denormalized column to preserve.
--
-- NOT added to the supabase_realtime publication. The design spec
-- chose fast polling over giving the dashboard its first-ever direct
-- Supabase Realtime subscription — nothing will subscribe to this
-- table, so publishing it would be pure overhead.
--
-- Requires: migrations 002 (incidents, users), 001d (get_my_role,
-- get_my_agency_id helpers). Idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.incident_assist_requests (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id           UUID NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
    requesting_agency_id  UUID NOT NULL REFERENCES public.agencies(id),
    requested_agency_id   UUID NOT NULL REFERENCES public.agencies(id),
    overlap_flag          TEXT,
    status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'acknowledged', 'declined')),
    requested_by          UUID NOT NULL REFERENCES public.users(id),
    responded_by          UUID REFERENCES public.users(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at          TIMESTAMPTZ,
    CONSTRAINT incident_assist_requests_distinct_agencies
        CHECK (requested_agency_id <> requesting_agency_id)
);

COMMENT ON TABLE public.incident_assist_requests IS
    'One row per "please help on this incident" request between two agencies. '
    'status is the only mutable field. See migration 036''s header.';

CREATE INDEX IF NOT EXISTS incident_assist_requests_incident_idx
    ON public.incident_assist_requests (incident_id);
CREATE INDEX IF NOT EXISTS incident_assist_requests_requesting_idx
    ON public.incident_assist_requests (requesting_agency_id, status);
CREATE INDEX IF NOT EXISTS incident_assist_requests_requested_idx
    ON public.incident_assist_requests (requested_agency_id, status);

CREATE TABLE IF NOT EXISTS public.incident_assist_messages (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id        UUID NOT NULL REFERENCES public.incident_assist_requests(id) ON DELETE CASCADE,
    sender_agency_id  UUID NOT NULL REFERENCES public.agencies(id),
    sender_id         UUID NOT NULL REFERENCES public.users(id),
    body              TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- append-only — no updated_at, no UPDATE/DELETE policy below.
);

COMMENT ON TABLE public.incident_assist_messages IS
    'Append-only chat scoped to one incident_assist_requests row. See migration 036''s header.';

CREATE INDEX IF NOT EXISTS incident_assist_messages_request_idx
    ON public.incident_assist_messages (request_id, created_at);

GRANT ALL ON public.incident_assist_requests TO service_role;
GRANT ALL ON public.incident_assist_messages TO service_role;

ALTER TABLE public.incident_assist_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incident_assist_messages ENABLE ROW LEVEL SECURITY;

-- ── incident_assist_requests policies ───────────────────────────────

DROP POLICY IF EXISTS "incident_assist_requests: party agencies and super_admin read" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: party agencies and super_admin read"
    ON public.incident_assist_requests FOR SELECT
    USING (
        public.get_my_role() = 'super_admin'
        OR (
            public.get_my_role() = 'agency_admin'
            AND (
                requesting_agency_id = public.get_my_agency_id()
                OR requested_agency_id = public.get_my_agency_id()
            )
        )
    );

DROP POLICY IF EXISTS "incident_assist_requests: requester inserts" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: requester inserts"
    ON public.incident_assist_requests FOR INSERT
    WITH CHECK (
        public.get_my_role() = 'agency_admin'
        AND requesting_agency_id = public.get_my_agency_id()
        AND requested_by = auth.uid()
    );

-- Status transitions only, only by the agency being asked. No DELETE.
DROP POLICY IF EXISTS "incident_assist_requests: requested agency responds" ON public.incident_assist_requests;
CREATE POLICY "incident_assist_requests: requested agency responds"
    ON public.incident_assist_requests FOR UPDATE
    USING (
        public.get_my_role() = 'agency_admin'
        AND requested_agency_id = public.get_my_agency_id()
    );

-- ── incident_assist_messages policies ───────────────────────────────

DROP POLICY IF EXISTS "incident_assist_messages: party agencies and super_admin read" ON public.incident_assist_messages;
CREATE POLICY "incident_assist_messages: party agencies and super_admin read"
    ON public.incident_assist_messages FOR SELECT
    USING (
        public.get_my_role() = 'super_admin'
        OR (
            public.get_my_role() = 'agency_admin'
            AND EXISTS (
                SELECT 1 FROM public.incident_assist_requests r
                WHERE r.id = incident_assist_messages.request_id
                  AND (
                      r.requesting_agency_id = public.get_my_agency_id()
                      OR r.requested_agency_id = public.get_my_agency_id()
                  )
            )
        )
    );

DROP POLICY IF EXISTS "incident_assist_messages: party agencies write" ON public.incident_assist_messages;
CREATE POLICY "incident_assist_messages: party agencies write"
    ON public.incident_assist_messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid()
        AND public.get_my_role() = 'agency_admin'
        AND sender_agency_id = public.get_my_agency_id()
        AND EXISTS (
            SELECT 1 FROM public.incident_assist_requests r
            WHERE r.id = incident_assist_messages.request_id
              AND (
                  r.requesting_agency_id = public.get_my_agency_id()
                  OR r.requested_agency_id = public.get_my_agency_id()
              )
        )
    );

-- ============================================================
-- Verification
--
-- Expect: 2 rows, rowsecurity = t for both, service_role_can_read = t for
-- both, policy_count = 3 for incident_assist_requests (SELECT/INSERT/UPDATE),
-- policy_count = 2 for incident_assist_messages (SELECT/INSERT).
-- ============================================================
SELECT c.relname                                             AS table_name,
       c.relrowsecurity                                      AS rls_enabled,
       has_table_privilege('service_role', c.oid, 'SELECT')  AS service_role_can_read,
       (SELECT count(*) FROM pg_policies p
         WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('incident_assist_requests', 'incident_assist_messages')
ORDER BY c.relname;
```

- [ ] **Step 2: Do not apply this migration**

This step is a reminder, not an action: leave the file written and unapplied. Tell the project owner it's ready and paste back the verification query's output once they've run it in the Supabase SQL Editor — do not run it yourself.

- [ ] **Step 3: Commit**

```bash
git add ziren_backend/supabase/migrations/036_incident_assist_requests.sql
git commit -m "feat(backend): add incident_assist_requests + incident_assist_messages migration"
```

---

## Task 2: Service — incident scoping + candidate agencies

**Files:**
- Create: `ziren_backend/app/services/assist_request_service.py`
- Test: `ziren_backend/tests/test_assist_requests.py`

**Interfaces:**
- Consumes: `app.core.dependencies.assert_agency_scope(current_user, agency_id)` (raises 403), `app.db.supabase_client.get_supabase()`.
- Produces: `_assert_owns_incident(db, incident_id, actor) -> dict` (incident row with `id, assigned_agency_id, status, incident_category, severity, location_address`), `list_candidate_agencies(incident_id, actor) -> list[dict]` (each `{id, name, agency_type, contact_number, email}`). Both consumed by later tasks in this same file.

- [ ] **Step 1: Write the failing tests**

```python
"""
assist_request_service — cross-agency "please help on this incident"
requests. See docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import assist_request_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"          # requesting agency
OTHER_AGENCY_ID = "b0000002-0000-0000-0000-000000000002"    # requested agency
THIRD_AGENCY_ID = "b0000003-0000-0000-0000-000000000003"    # different municipality
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"

AGENCY_ADMIN = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}
OTHER_AGENCY_ADMIN = {"id": "e0000005-0000-0000-0000-000000000005", "role": "agency_admin", "agency_id": OTHER_AGENCY_ID}


def _incident_row(assigned_agency_id=AGENCY_ID, inc_status="received"):
    return {
        "id": INCIDENT_ID, "assigned_agency_id": assigned_agency_id, "status": inc_status,
        "incident_category": "fire", "severity": "high", "location_address": "Brgy 1, Naval",
    }


def _mock_db(incident_row=None, own_agency_row=None, candidates_rows=None):
    """
    Builds a MagicMock whose .table(name) branches by table name — plain
    incident_notes_service-style single-chain mocks don't work here because
    this service queries TWO different tables (incidents, then agencies) in
    one function, and each needs its own canned .execute() result.
    """
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incidents":
            result = MagicMock()
            result.data = incident_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "agencies":
            own_result = MagicMock()
            own_result.data = own_agency_row
            cand_result = MagicMock()
            cand_result.data = candidates_rows or []
            # own-agency lookup: .select().eq("id", ...).maybe_single().execute()
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = own_result
            # candidates lookup: .select().eq("municipality",...).eq("is_active",True).neq("id",...).execute()
            m.select.return_value.eq.return_value.eq.return_value.neq.return_value.execute.return_value = cand_result
        return m

    db.table.side_effect = table
    return db


def test_owns_incident_ok_for_the_assigned_agency():
    db = _mock_db(incident_row=_incident_row())
    incident = assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert incident["assigned_agency_id"] == AGENCY_ID


def test_owns_incident_forbidden_for_a_different_agency():
    db = _mock_db(incident_row=_incident_row(assigned_agency_id=OTHER_AGENCY_ID))
    with pytest.raises(HTTPException) as exc:
        assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 403


def test_owns_incident_404_when_incident_missing():
    db = _mock_db(incident_row=None)
    with pytest.raises(HTTPException) as exc:
        assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 404


def test_list_candidate_agencies_excludes_self_and_scopes_to_municipality():
    db = _mock_db(
        incident_row=_incident_row(),
        own_agency_row={"id": AGENCY_ID, "municipality": "Naval"},
        candidates_rows=[{"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval", "agency_type": "MDRRMO", "contact_number": "0917", "email": "m@naval.gov.ph"}],
    )
    result = assist_request_service.list_candidate_agencies(INCIDENT_ID, AGENCY_ADMIN)
    assert result == [{"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval", "agency_type": "MDRRMO", "contact_number": "0917", "email": "m@naval.gov.ph"}]


def test_list_candidate_agencies_forbidden_for_a_different_agency():
    db = _mock_db(incident_row=_incident_row(assigned_agency_id=OTHER_AGENCY_ID))
    with pytest.raises(HTTPException) as exc:
        assist_request_service.list_candidate_agencies(INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 403
```

Add this to the test module, patched into every test above (module-scoped autouse fixture keeps the file from repeating the patch in every test):

```python
@pytest.fixture(autouse=True)
def _patch_get_supabase(monkeypatch, request):
    """Each test builds its own db via _mock_db and needs it patched in —
    tests above call assist_request_service functions directly after
    building `db`, so this fixture only needs to exist; the patch itself
    happens per-test via `with patch(...)` for clarity on what data feeds
    which call. (No-op fixture kept for symmetry with test_incident_notes.py;
    remove if unused once Task 3+ tests are added with their own patching.)
    """
    yield
```

Actually — simplify: skip the autouse fixture above (it adds nothing yet) and instead wrap each test body's call in `with patch("app.services.assist_request_service.get_supabase", return_value=db):`, exactly like `test_incident_notes.py` does. Rewrite the four test bodies to that shape, e.g.:

```python
def test_owns_incident_ok_for_the_assigned_agency():
    db = _mock_db(incident_row=_incident_row())
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        incident = assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert incident["assigned_agency_id"] == AGENCY_ID
```

(`_assert_owns_incident` takes `db` directly as its first argument — see Step 3 below — so the `patch` isn't strictly required for THIS specific helper, but IS required for `list_candidate_agencies`, which calls `get_supabase()` itself. Keep the `with patch(...)` wrapper on all five tests for consistency and so copy-pasting a test as a template for Task 3+ always works.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: FAIL — `ModuleNotFoundError` / `AttributeError: module 'app.services.assist_request_service' has no attribute ...` (the module doesn't exist yet).

- [ ] **Step 3: Write the minimal implementation**

```python
"""
assist_request_service — cross-agency "please help on this incident"
requests: agency_admin to agency_admin, one incident at a time.

The receiving agency never gets access to the incident row itself — every
function here returns a narrow, live-projected snapshot (category, severity,
location text), never the full incidents row. See
docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
"""

from datetime import datetime, timezone

from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase
from app.services.notification_service import create_for_agency_role

_INCIDENT_COLS = "id, assigned_agency_id, status, incident_category, severity, location_address"


def _assert_owns_incident(db: Client, incident_id: str, actor: dict) -> dict:
    """
    Only the agency currently assigned to an incident may request assist on
    it — reuses the same assert_agency_scope every other incident-scoped
    write in this codebase uses. agency_admin only (this feature has no
    responder/resident branch — see the design spec's platform-scope call).
    """
    result = (
        db.table("incidents")
        .select(_INCIDENT_COLS)
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")
    incident = result.data
    assert_agency_scope(actor, str(incident.get("assigned_agency_id") or ""))
    return incident


def list_candidate_agencies(incident_id: str, actor: dict) -> list[dict]:
    """Other active agencies in the SAME municipality as this incident's own
    agency — never every agency platform-wide, so a request can't be aimed
    at a station nowhere near the incident."""
    db: Client = get_supabase()
    incident = _assert_owns_incident(db, incident_id, actor)

    own = (
        db.table("agencies")
        .select("id, municipality")
        .eq("id", incident["assigned_agency_id"])
        .maybe_single()
        .execute()
    )
    if own is None or not own.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="This incident's agency could not be found.")

    result = (
        db.table("agencies")
        .select("id, name, agency_type, contact_number, email")
        .eq("municipality", own.data["municipality"])
        .eq("is_active", True)
        .neq("id", incident["assigned_agency_id"])
        .execute()
    )
    return result.data or []
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add ziren_backend/app/services/assist_request_service.py ziren_backend/tests/test_assist_requests.py
git commit -m "feat(backend): assist request incident-scoping and candidate agency lookup"
```

---

## Task 3: Service — `create_request` + notification

**Files:**
- Modify: `ziren_backend/app/services/assist_request_service.py`
- Modify: `ziren_backend/tests/test_assist_requests.py`

**Interfaces:**
- Consumes: `_assert_owns_incident` (Task 2), `notification_service.create_for_agency_role(agency_id, role, *, type_, title, body=None, link=None, is_important=False)` (already exists — see `app/services/notification_service.py`).
- Produces: `create_request(incident_id, requested_agency_id, message, overlap_flag, actor) -> dict` (a hydrated request: raw columns plus `requesting_agency_name`, `requested_agency_name`, `incident_category`, `severity`, `location_address`, `incident_status`, `can_respond`). Consumed by the router (Task 7) and by Task 4/6's shared `_hydrate_request` helper, defined in this task.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_assist_requests.py`:

```python
def _mock_db_for_create(incident_row, own_agency_row, target_agency_row, dup_rows, inserted_request, inserted_message):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incidents":
            result = MagicMock()
            result.data = incident_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "agencies":
            target_result = MagicMock()
            target_result.data = target_agency_row
            # target-agency lookup: .select().eq("id",...).maybe_single().execute()
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = target_result
            # name-backfill lookup inside _hydrate_request: .select().in_("id",...).execute()
            names_result = MagicMock()
            names_result.data = [
                {"id": incident_row["assigned_agency_id"], "name": "Requesting Agency"},
                {"id": target_agency_row["id"], "name": target_agency_row["name"]},
            ] if target_agency_row else []
            m.select.return_value.in_.return_value.execute.return_value = names_result
        elif name == "incident_assist_requests":
            dup_result = MagicMock()
            dup_result.data = dup_rows
            m.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = dup_result
            insert_result = MagicMock()
            insert_result.data = [inserted_request]
            m.insert.return_value.execute.return_value = insert_result
        elif name == "incident_assist_messages":
            insert_result = MagicMock()
            insert_result.data = [inserted_message]
            m.insert.return_value.execute.return_value = insert_result
        return m

    db.table.side_effect = table
    return db


def test_create_request_happy_path_inserts_request_and_opening_message_and_notifies():
    request_row = {
        "id": "f0000006-0000-0000-0000-000000000006", "incident_id": INCIDENT_ID,
        "requesting_agency_id": AGENCY_ID, "requested_agency_id": OTHER_AGENCY_ID,
        "overlap_flag": "fire", "status": "pending", "requested_by": AGENCY_ADMIN["id"],
        "responded_by": None, "created_at": "2026-09-20T00:00:00Z", "responded_at": None,
    }
    db = _mock_db_for_create(
        incident_row=_incident_row(),
        own_agency_row=None,
        target_agency_row={"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval", "agency_type": "MDRRMO", "municipality": "Naval", "is_active": True},
        dup_rows=[],
        inserted_request=request_row,
        inserted_message={"id": "g1", "request_id": request_row["id"], "sender_agency_id": AGENCY_ID, "sender_id": AGENCY_ADMIN["id"], "body": "Need crowd control", "created_at": "2026-09-20T00:00:00Z"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db), \
         patch("app.services.assist_request_service.create_for_agency_role") as mock_notify:
        result = assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "Need crowd control", "fire", AGENCY_ADMIN)

    assert result["id"] == request_row["id"]
    assert result["status"] == "pending"
    assert result["can_respond"] is False  # the REQUESTER is never the one who can respond
    mock_notify.assert_called_once()
    assert mock_notify.call_args.args[0] == OTHER_AGENCY_ID
    assert mock_notify.call_args.args[1] == "agency_admin"
    assert mock_notify.call_args.kwargs["is_important"] is True


def test_create_request_rejects_targeting_own_agency():
    db = _mock_db_for_create(_incident_row(), None, None, [], {}, {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, AGENCY_ID, "help", None, AGENCY_ADMIN)
    assert exc.value.status_code == 400


def test_create_request_rejects_empty_message():
    db = _mock_db_for_create(_incident_row(), None, None, [], {}, {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "   ", None, AGENCY_ADMIN)
    assert exc.value.status_code == 422


def test_create_request_rejects_inactive_target():
    db = _mock_db_for_create(
        _incident_row(), None,
        target_agency_row={"id": OTHER_AGENCY_ID, "name": "X", "agency_type": "MDRRMO", "municipality": "Naval", "is_active": False},
        dup_rows=[], inserted_request={}, inserted_message={},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "help", None, AGENCY_ADMIN)
    assert exc.value.status_code == 400


def test_create_request_rejects_duplicate_pending():
    db = _mock_db_for_create(
        _incident_row(), None,
        target_agency_row={"id": OTHER_AGENCY_ID, "name": "X", "agency_type": "MDRRMO", "municipality": "Naval", "is_active": True},
        dup_rows=[{"id": "existing"}], inserted_request={}, inserted_message={},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "help", None, AGENCY_ADMIN)
    assert exc.value.status_code == 409
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'create_request'`.

- [ ] **Step 3: Write the minimal implementation**

Append to `app/services/assist_request_service.py`:

```python
def _hydrate_request(db: Client, row: dict, actor: dict, requested_agency: dict | None = None) -> dict:
    """
    Attach display fields a raw incident_assist_requests row doesn't carry:
    both agencies' names, a narrow incident snapshot (never the full
    incidents row — see this module's docstring), and can_respond, computed
    here rather than left for the frontend because the dashboard's own
    session storage has no agency id to compare against client-side (see
    lib/hooks/useAuth.ts) — the server is the only place that knows it.
    """
    agencies: dict[str, dict] = {requested_agency["id"]: requested_agency} if requested_agency else {}
    missing = {row["requesting_agency_id"], row["requested_agency_id"]} - agencies.keys()
    if missing:
        fetched = db.table("agencies").select("id, name").in_("id", list(missing)).execute()
        agencies.update({a["id"]: a for a in (fetched.data or [])})

    incident = (
        db.table("incidents")
        .select("incident_category, severity, location_address, status")
        .eq("id", row["incident_id"])
        .maybe_single()
        .execute()
    )
    inc = incident.data if incident and incident.data else {}
    my_agency_id = str(actor.get("agency_id") or "")

    return {
        **row,
        "requesting_agency_name": agencies.get(row["requesting_agency_id"], {}).get("name"),
        "requested_agency_name": agencies.get(row["requested_agency_id"], {}).get("name"),
        "incident_category": inc.get("incident_category"),
        "severity": inc.get("severity"),
        "location_address": inc.get("location_address"),
        "incident_status": inc.get("status"),
        "can_respond": my_agency_id == row["requested_agency_id"] and row["status"] == "pending",
    }


def create_request(
    incident_id: str,
    requested_agency_id: str,
    message: str,
    overlap_flag: str | None,
    actor: dict,
) -> dict:
    if not message or not message.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="An opening message is required.")

    db: Client = get_supabase()
    incident = _assert_owns_incident(db, incident_id, actor)
    requesting_agency_id = incident["assigned_agency_id"]

    if requested_agency_id == requesting_agency_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot request assist from your own agency.")

    target = (
        db.table("agencies")
        .select("id, name, agency_type, municipality, is_active")
        .eq("id", requested_agency_id)
        .maybe_single()
        .execute()
    )
    if target is None or not target.data or not target.data["is_active"]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="That agency is not available to request assist from.")

    dup = (
        db.table("incident_assist_requests")
        .select("id")
        .eq("incident_id", incident_id)
        .eq("requested_agency_id", requested_agency_id)
        .eq("status", "pending")
        .execute()
    )
    if dup.data:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="A pending request to this agency already exists for this incident.")

    inserted = (
        db.table("incident_assist_requests")
        .insert({
            "incident_id": incident_id,
            "requesting_agency_id": requesting_agency_id,
            "requested_agency_id": requested_agency_id,
            "overlap_flag": overlap_flag,
            "requested_by": str(actor["id"]),
        })
        .execute()
    )
    request_row = inserted.data[0]

    db.table("incident_assist_messages").insert({
        "request_id": request_row["id"],
        "sender_agency_id": requesting_agency_id,
        "sender_id": str(actor["id"]),
        "body": message.strip(),
    }).execute()

    create_for_agency_role(
        requested_agency_id, "agency_admin",
        type_="assist_request",
        title=f"Assist requested by {actor.get('full_name') or 'another agency'}",
        body=message.strip(),
        link=f"/geographic?tab=agencies&assist={request_row['id']}",
        is_important=True,
    )

    return _hydrate_request(db, request_row, actor, target.data)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: PASS — 10 tests.

- [ ] **Step 5: Commit**

```bash
git add ziren_backend/app/services/assist_request_service.py ziren_backend/tests/test_assist_requests.py
git commit -m "feat(backend): create_request with duplicate/self-target guards and notification"
```

---

## Task 4: Service — `list_for_agency` + `get_thread`

**Files:**
- Modify: `ziren_backend/app/services/assist_request_service.py`
- Modify: `ziren_backend/tests/test_assist_requests.py`

**Interfaces:**
- Consumes: `_hydrate_request` (Task 3).
- Produces: `list_for_agency(actor, scope) -> list[dict]` (`scope` is `"sent"` or `"received"`), `get_thread(request_id, actor) -> dict` (`{"request": {...same shape as create_request's return...}, "messages": [{"id", "request_id", "sender_agency_id", "sender_id", "sender_name", "body", "created_at", "mine"}]}`), `_load_request_as_party(db, request_id, actor) -> dict` (403 if the actor's agency is party to neither side). Consumed by the router (Task 7) and by Task 5/6.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_assist_requests.py`:

```python
def _request_row(status_="pending", requesting=AGENCY_ID, requested=OTHER_AGENCY_ID):
    return {
        "id": "h0000007-0000-0000-0000-000000000007", "incident_id": INCIDENT_ID,
        "requesting_agency_id": requesting, "requested_agency_id": requested,
        "overlap_flag": None, "status": status_, "requested_by": AGENCY_ADMIN["id"],
        "responded_by": None, "created_at": "2026-09-20T00:00:00Z", "responded_at": None,
    }


def _mock_db_for_list(rows, agencies_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            result = MagicMock()
            result.data = rows
            m.select.return_value.eq.return_value.order.return_value.execute.return_value = result
        elif name == "agencies":
            result = MagicMock()
            result.data = agencies_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_list_for_agency_received_scope_filters_by_requested_agency_id():
    row = _request_row()
    db = _mock_db_for_list(
        rows=[row],
        agencies_rows=[{"id": AGENCY_ID, "name": "BFP Naval"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval"}],
        incidents_rows=[{"id": INCIDENT_ID, "incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"}],
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.list_for_agency(OTHER_AGENCY_ADMIN, "received")
    assert len(result) == 1
    assert result[0]["requesting_agency_name"] == "BFP Naval"
    assert result[0]["can_respond"] is True  # OTHER_AGENCY_ADMIN is the requested party, status is pending


def test_list_for_agency_rejects_bad_scope():
    db = _mock_db_for_list([], [], [])
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.list_for_agency(AGENCY_ADMIN, "everything")
    assert exc.value.status_code == 422


def _mock_db_for_thread(request_row, messages_rows, agencies_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            result = MagicMock()
            result.data = request_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "incident_assist_messages":
            result = MagicMock()
            result.data = messages_rows
            m.select.return_value.eq.return_value.order.return_value.execute.return_value = result
        elif name == "agencies":
            result = MagicMock()
            result.data = agencies_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_get_thread_marks_own_agencys_messages_mine():
    db = _mock_db_for_thread(
        request_row=_request_row(),
        messages_rows=[
            {"id": "m1", "request_id": "h1", "sender_agency_id": AGENCY_ID, "sender_id": "x", "body": "need help", "created_at": "t1", "users": {"full_name": "Alex"}},
            {"id": "m2", "request_id": "h1", "sender_agency_id": OTHER_AGENCY_ID, "sender_id": "y", "body": "on our way", "created_at": "t2", "users": {"full_name": "Bea"}},
        ],
        agencies_rows=[{"id": AGENCY_ID, "name": "BFP"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO"}],
        incidents_rows={"incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.get_thread("h1", AGENCY_ADMIN)
    assert result["messages"][0]["mine"] is True
    assert result["messages"][1]["mine"] is False
    assert result["messages"][0]["sender_name"] == "Alex"


def test_get_thread_forbidden_for_a_non_party_agency():
    third_admin = {"id": "z", "role": "agency_admin", "agency_id": THIRD_AGENCY_ID}
    db = _mock_db_for_thread(_request_row(), [], [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.get_thread("h1", third_admin)
    assert exc.value.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'list_for_agency'`.

- [ ] **Step 3: Write the minimal implementation**

Append to `app/services/assist_request_service.py`:

```python
def list_for_agency(actor: dict, scope: str) -> list[dict]:
    """scope='sent' -> requests my agency raised. scope='received' -> requests asking my agency for help."""
    if scope not in ("sent", "received"):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="scope must be 'sent' or 'received'.")

    db: Client = get_supabase()
    my_agency_id = str(actor.get("agency_id") or "")
    column = "requesting_agency_id" if scope == "sent" else "requested_agency_id"

    result = (
        db.table("incident_assist_requests")
        .select("*")
        .eq(column, my_agency_id)
        .order("created_at", desc=True)
        .execute()
    )
    rows = result.data or []
    if not rows:
        return []

    agency_ids = {r["requesting_agency_id"] for r in rows} | {r["requested_agency_id"] for r in rows}
    incident_ids = {r["incident_id"] for r in rows}
    agencies = {a["id"]: a for a in (db.table("agencies").select("id, name").in_("id", list(agency_ids)).execute().data or [])}
    incidents = {
        i["id"]: i for i in (
            db.table("incidents")
            .select("id, incident_category, severity, location_address, status")
            .in_("id", list(incident_ids))
            .execute().data or []
        )
    }

    return [
        {
            **r,
            "requesting_agency_name": agencies.get(r["requesting_agency_id"], {}).get("name"),
            "requested_agency_name": agencies.get(r["requested_agency_id"], {}).get("name"),
            "incident_category": incidents.get(r["incident_id"], {}).get("incident_category"),
            "severity": incidents.get(r["incident_id"], {}).get("severity"),
            "location_address": incidents.get(r["incident_id"], {}).get("location_address"),
            "incident_status": incidents.get(r["incident_id"], {}).get("status"),
            "can_respond": my_agency_id == r["requested_agency_id"] and r["status"] == "pending",
        }
        for r in rows
    ]


def _load_request_as_party(db: Client, request_id: str, actor: dict) -> dict:
    result = db.table("incident_assist_requests").select("*").eq("id", request_id).maybe_single().execute()
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Assist request not found.")
    row = result.data
    my_agency_id = str(actor.get("agency_id") or "")
    if actor.get("role") != "agency_admin" or my_agency_id not in (row["requesting_agency_id"], row["requested_agency_id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not a party to this assist request.")
    return row


def get_thread(request_id: str, actor: dict) -> dict:
    db: Client = get_supabase()
    request_row = _load_request_as_party(db, request_id, actor)
    my_agency_id = str(actor.get("agency_id") or "")

    messages = (
        db.table("incident_assist_messages")
        .select("id, request_id, sender_agency_id, sender_id, body, created_at, users(full_name)")
        .eq("request_id", request_id)
        .order("created_at", desc=False)
        .execute()
    )
    flattened = [
        {
            **{k: v for k, v in m.items() if k != "users"},
            "sender_name": (m.get("users") or {}).get("full_name"),
            "mine": m["sender_agency_id"] == my_agency_id,
        }
        for m in (messages.data or [])
    ]
    return {"request": _hydrate_request(db, request_row, actor), "messages": flattened}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: PASS — 14 tests.

- [ ] **Step 5: Commit**

```bash
git add ziren_backend/app/services/assist_request_service.py ziren_backend/tests/test_assist_requests.py
git commit -m "feat(backend): list_for_agency and get_thread with server-computed mine/can_respond"
```

---

## Task 5: Service — `post_message`

**Files:**
- Modify: `ziren_backend/app/services/assist_request_service.py`
- Modify: `ziren_backend/tests/test_assist_requests.py`

**Interfaces:**
- Consumes: `_load_request_as_party` (Task 4).
- Produces: `post_message(request_id, body, actor) -> dict` (`{"id", "request_id", "sender_agency_id", "sender_id", "sender_name", "body", "created_at", "mine": True}`). Consumed by the router (Task 7).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_assist_requests.py`:

```python
def _mock_db_for_post_message(request_row, incident_status, inserted_message):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            result = MagicMock()
            result.data = request_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = {"status": incident_status}
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "incident_assist_messages":
            result = MagicMock()
            result.data = [inserted_message]
            m.insert.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_post_message_happy_path():
    inserted = {"id": "m3", "request_id": "h1", "sender_agency_id": AGENCY_ID, "sender_id": AGENCY_ADMIN["id"], "body": "2 units", "created_at": "t3"}
    db = _mock_db_for_post_message(_request_row(), "received", inserted)
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.post_message("h1", "2 units", AGENCY_ADMIN)
    assert result["body"] == "2 units"
    assert result["mine"] is True


def test_post_message_rejects_empty_body():
    db = _mock_db_for_post_message(_request_row(), "received", {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.post_message("h1", "   ", AGENCY_ADMIN)
    assert exc.value.status_code == 422


def test_post_message_rejected_once_incident_resolved():
    db = _mock_db_for_post_message(_request_row(), "resolved", {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.post_message("h1", "still there?", AGENCY_ADMIN)
    assert exc.value.status_code == 409


def test_post_message_forbidden_for_a_non_party_agency():
    third_admin = {"id": "z", "role": "agency_admin", "agency_id": THIRD_AGENCY_ID}
    db = _mock_db_for_post_message(_request_row(), "received", {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.post_message("h1", "hi", third_admin)
    assert exc.value.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'post_message'`.

- [ ] **Step 3: Write the minimal implementation**

Append to `app/services/assist_request_service.py`:

```python
def post_message(request_id: str, body: str, actor: dict) -> dict:
    if not body or not body.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Message cannot be empty.")

    db: Client = get_supabase()
    request_row = _load_request_as_party(db, request_id, actor)

    incident = db.table("incidents").select("status").eq("id", request_row["incident_id"]).maybe_single().execute()
    if incident and incident.data and incident.data.get("status") in ("resolved", "cancelled"):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This incident is closed; the thread is read-only.")

    my_agency_id = str(actor.get("agency_id") or "")
    inserted = db.table("incident_assist_messages").insert({
        "request_id": request_id,
        "sender_agency_id": my_agency_id,
        "sender_id": str(actor["id"]),
        "body": body.strip(),
    }).execute()
    row = inserted.data[0]

    # No notification here — only the OPENING message notifies (see
    # create_request). A bell entry per reply would spam the feed during an
    # active exchange; an open thread panel's own polling is how replies
    # are seen, same as any chat you have open.
    return {**row, "sender_name": actor.get("full_name"), "mine": True}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: PASS — 18 tests.

- [ ] **Step 5: Commit**

```bash
git add ziren_backend/app/services/assist_request_service.py ziren_backend/tests/test_assist_requests.py
git commit -m "feat(backend): post_message with a resolved-incident read-only guard"
```

---

## Task 6: Service — `set_status`

**Files:**
- Modify: `ziren_backend/app/services/assist_request_service.py`
- Modify: `ziren_backend/tests/test_assist_requests.py`

**Interfaces:**
- Consumes: `_load_request_as_party`, `_hydrate_request` (Tasks 3-4), `create_for_agency_role`.
- Produces: `set_status(request_id, new_status, actor) -> dict` (same shape as `create_request`'s return). Consumed by the router (Task 7).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_assist_requests.py`:

```python
def _mock_db_for_set_status(request_row, updated_row, agencies_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            get_result = MagicMock()
            get_result.data = request_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = get_result
            upd_result = MagicMock()
            upd_result.data = [updated_row]
            m.update.return_value.eq.return_value.execute.return_value = upd_result
        elif name == "agencies":
            result = MagicMock()
            result.data = agencies_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_set_status_acknowledged_by_requested_agency_notifies_requester():
    row = _request_row()
    updated = {**row, "status": "acknowledged", "responded_by": OTHER_AGENCY_ADMIN["id"], "responded_at": "t9"}
    db = _mock_db_for_set_status(
        row, updated,
        agencies_rows=[{"id": AGENCY_ID, "name": "BFP"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO"}],
        incidents_rows={"incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db), \
         patch("app.services.assist_request_service.create_for_agency_role") as mock_notify:
        result = assist_request_service.set_status("h1", "acknowledged", OTHER_AGENCY_ADMIN)
    assert result["status"] == "acknowledged"
    mock_notify.assert_called_once()
    assert mock_notify.call_args.args[0] == AGENCY_ID  # notifies the ORIGINAL requester's agency


def test_set_status_rejects_invalid_value():
    db = _mock_db_for_set_status(_request_row(), {}, [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.set_status("h1", "maybe", OTHER_AGENCY_ADMIN)
    assert exc.value.status_code == 422


def test_set_status_forbidden_for_the_requesting_agency_itself():
    db = _mock_db_for_set_status(_request_row(), {}, [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.set_status("h1", "acknowledged", AGENCY_ADMIN)
    assert exc.value.status_code == 403


def test_set_status_rejects_a_second_response():
    db = _mock_db_for_set_status(_request_row(status_="declined"), {}, [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.set_status("h1", "acknowledged", OTHER_AGENCY_ADMIN)
    assert exc.value.status_code == 409
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: FAIL — `AttributeError: ... has no attribute 'set_status'`.

- [ ] **Step 3: Write the minimal implementation**

Append to `app/services/assist_request_service.py`:

```python
def set_status(request_id: str, new_status: str, actor: dict) -> dict:
    if new_status not in ("acknowledged", "declined"):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="status must be 'acknowledged' or 'declined'.")

    db: Client = get_supabase()
    request_row = _load_request_as_party(db, request_id, actor)

    my_agency_id = str(actor.get("agency_id") or "")
    if my_agency_id != request_row["requested_agency_id"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the requested agency can respond to this request.")
    if request_row["status"] != "pending":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"This request was already {request_row['status']}.")

    updated = (
        db.table("incident_assist_requests")
        .update({
            "status": new_status,
            "responded_by": str(actor["id"]),
            "responded_at": datetime.now(timezone.utc).isoformat(),
        })
        .eq("id", request_id)
        .execute()
    )
    row = updated.data[0]

    create_for_agency_role(
        row["requesting_agency_id"], "agency_admin",
        type_="assist_response",
        title=f"Assist request {new_status}",
        body=f"Your request was {new_status} by {actor.get('full_name') or 'the other agency'}.",
        link=f"/geographic?tab=agencies&assist={row['id']}",
        is_important=True,
    )
    return _hydrate_request(db, row, actor)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests.py -v`
Expected: PASS — 22 tests.

- [ ] **Step 5: Commit**

```bash
git add ziren_backend/app/services/assist_request_service.py ziren_backend/tests/test_assist_requests.py
git commit -m "feat(backend): set_status with one-way transitions and response notification"
```

---

## Task 7: Router + registration

**Files:**
- Create: `ziren_backend/app/routers/assist_requests.py`
- Modify: `ziren_backend/app/main.py:20-25` (import tuple), `ziren_backend/app/main.py:254` (add after the `sms.router` registration)
- Test: `ziren_backend/tests/test_assist_requests_router.py`

**Interfaces:**
- Consumes: every function from `assist_request_service` (Tasks 2-6), `app.core.dependencies.require_role`.
- Produces: 6 HTTP endpoints under `/assist-requests`.

- [ ] **Step 1: Write the failing tests**

```python
"""Router-level checks for /assist-requests: role enforcement and that each
route reaches the right service function. Service logic itself is covered
by tests/test_assist_requests.py — these tests only prove the wiring."""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

AGENCY_ADMIN_USER = {"id": "u1", "role": "agency_admin", "agency_id": "a1", "full_name": "Admin"}
RESPONDER_USER = {"id": "u2", "role": "responder", "agency_id": "a1", "full_name": "Resp"}


def _as(user):
    from app.core.dependencies import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user


def teardown_function():
    app.dependency_overrides.clear()


def test_responder_forbidden_from_every_route():
    _as(RESPONDER_USER)
    assert client.get("/assist-requests?scope=sent").status_code == 403
    assert client.get("/assist-requests/candidates?incident_id=i1").status_code == 403
    assert client.post("/assist-requests", json={"incident_id": "i1", "requested_agency_id": "a2", "message": "hi"}).status_code == 403


def test_list_route_reaches_list_for_agency():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.list_for_agency", return_value=[]) as mock_fn:
        res = client.get("/assist-requests?scope=received")
    assert res.status_code == 200
    assert res.json() == []
    mock_fn.assert_called_once_with(AGENCY_ADMIN_USER, "received")


def test_candidates_route_does_not_collide_with_the_id_route():
    """/assist-requests/candidates must resolve to the candidates handler,
    not be swallowed by GET /assist-requests/{request_id} — this only
    passes if candidates() is registered before the {request_id} route."""
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.list_candidate_agencies", return_value=[]) as mock_fn:
        res = client.get("/assist-requests/candidates?incident_id=i1")
    assert res.status_code == 200
    mock_fn.assert_called_once_with("i1", AGENCY_ADMIN_USER)


def test_create_route_reaches_create_request_with_all_fields():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.create_request", return_value={"id": "r1"}) as mock_fn:
        res = client.post("/assist-requests", json={
            "incident_id": "i1", "requested_agency_id": "a2", "message": "help", "overlap_flag": "fire",
        })
    assert res.status_code == 200
    mock_fn.assert_called_once_with("i1", "a2", "help", "fire", AGENCY_ADMIN_USER)


def test_status_route_reaches_set_status():
    _as(AGENCY_ADMIN_USER)
    with patch("app.routers.assist_requests.assist_request_service.set_status", return_value={"id": "r1", "status": "acknowledged"}) as mock_fn:
        res = client.patch("/assist-requests/r1/status", json={"status": "acknowledged"})
    assert res.status_code == 200
    mock_fn.assert_called_once_with("r1", "acknowledged", AGENCY_ADMIN_USER)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests_router.py -v`
Expected: FAIL — 404s (the router doesn't exist / isn't registered yet).

- [ ] **Step 3: Write the minimal implementation**

```python
"""
/assist-requests — cross-agency "we need your help on this incident"
requests. agency_admin only, both sending and receiving. See
docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.

ROUTE ORDER MATTERS: GET /candidates is registered before GET /{request_id}
so "candidates" is never swallowed as a request_id path parameter.
"""

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.core.dependencies import require_role
from app.services import assist_request_service

router = APIRouter()
_agency_admin = require_role("agency_admin")


class CreateAssistRequestBody(BaseModel):
    incident_id: str
    requested_agency_id: str
    message: str
    overlap_flag: str | None = None


class PostMessageBody(BaseModel):
    body: str


class SetStatusBody(BaseModel):
    status: str  # "acknowledged" | "declined" — validated in the service


@router.get("/candidates")
def candidates(incident_id: str = Query(...), current_user: dict = Depends(_agency_admin)):
    return assist_request_service.list_candidate_agencies(incident_id, current_user)


@router.post("")
def create(payload: CreateAssistRequestBody, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.create_request(
        payload.incident_id, payload.requested_agency_id, payload.message,
        payload.overlap_flag, current_user,
    )


@router.get("")
def list_mine(scope: str = Query(...), current_user: dict = Depends(_agency_admin)):
    return assist_request_service.list_for_agency(current_user, scope)


@router.get("/{request_id}")
def thread(request_id: str, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.get_thread(request_id, current_user)


@router.post("/{request_id}/messages")
def send_message(request_id: str, payload: PostMessageBody, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.post_message(request_id, payload.body, current_user)


@router.patch("/{request_id}/status")
def respond(request_id: str, payload: SetStatusBody, current_user: dict = Depends(_agency_admin)):
    return assist_request_service.set_status(request_id, payload.status, current_user)
```

Edit `app/main.py`:

```python
# Before (line ~20):
from app.routers import (
    auth, incidents, dispatch, users, rubric, responder, stations,
    triage as triage_router, map as map_router, audit, notifications,
    geographic, analytics, governance, ai_monitoring, system_status,
    announcements, reports, search, sms,
)

# After:
from app.routers import (
    auth, incidents, dispatch, users, rubric, responder, stations,
    triage as triage_router, map as map_router, audit, notifications,
    geographic, analytics, governance, ai_monitoring, system_status,
    announcements, reports, search, sms, assist_requests,
)
```

```python
# Add after the existing sms.router line (~254):
app.include_router(sms.router, prefix="/sms", tags=["sms"])
app.include_router(assist_requests.router, prefix="/assist-requests", tags=["assist-requests"])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest tests/test_assist_requests_router.py tests/test_assist_requests.py -v`
Expected: PASS — 27 tests total.

- [ ] **Step 5: Run the full backend suite to confirm zero regressions**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest -q`
Expected: PASS, same count as before this plan plus the 27 new tests.

- [ ] **Step 6: Commit**

```bash
git add ziren_backend/app/routers/assist_requests.py ziren_backend/app/main.py ziren_backend/tests/test_assist_requests_router.py
git commit -m "feat(backend): wire /assist-requests router into the app"
```

---

## Task 8: Frontend — `lib/api/assist-requests.ts`

**Files:**
- Create: `ziren_dashboard/lib/api/assist-requests.ts`

**Interfaces:**
- Consumes: `apiClient` (`get`/`post`/`patch`), `ApiError` from `./client`.
- Produces: types `AssistCandidate`, `AssistStatus`, `AssistRequestSummary`, `AssistMessage`, `AssistThread`; functions `fetchAssistCandidates`, `createAssistRequest`, `listAssistRequests`, `fetchAssistThread`, `postAssistMessage`, `setAssistStatus`. Consumed by Tasks 9-12.

- [ ] **Step 1: Write the file**

```ts
/**
 * Typed client for /assist-requests — cross-agency "we need your help on
 * this incident" requests. See
 * ziren_backend/app/services/assist_request_service.py and
 * docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
 */

import { apiClient } from './client';

export interface AssistCandidate {
  id: string;
  name: string;
  agency_type: string;
  contact_number: string | null;
  email: string | null;
}

export type AssistStatus = 'pending' | 'acknowledged' | 'declined';

export interface AssistRequestSummary {
  id: string;
  incident_id: string;
  requesting_agency_id: string;
  requesting_agency_name: string | null;
  requested_agency_id: string;
  requested_agency_name: string | null;
  overlap_flag: string | null;
  status: AssistStatus;
  created_at: string;
  responded_at: string | null;
  incident_category: string | null;
  severity: string | null;
  location_address: string | null;
  incident_status: string | null;
  /** Computed server-side: can THIS viewer act on it right now? See
   *  assist_request_service._hydrate_request for why this isn't derived
   *  client-side (the dashboard has no agency id in session storage). */
  can_respond: boolean;
}

export interface AssistMessage {
  id: string;
  request_id: string;
  sender_agency_id: string;
  sender_id: string;
  sender_name: string | null;
  body: string;
  created_at: string;
  /** Computed server-side — see AssistRequestSummary.can_respond's note. */
  mine: boolean;
}

export interface AssistThread {
  request: AssistRequestSummary;
  messages: AssistMessage[];
}

export function fetchAssistCandidates(incidentId: string, token: string): Promise<AssistCandidate[]> {
  return apiClient.get(`/assist-requests/candidates?incident_id=${encodeURIComponent(incidentId)}`, token);
}

export function createAssistRequest(
  incidentId: string,
  requestedAgencyId: string,
  message: string,
  overlapFlag: string | null,
  token: string,
): Promise<AssistRequestSummary> {
  return apiClient.post('/assist-requests', {
    incident_id: incidentId,
    requested_agency_id: requestedAgencyId,
    message,
    overlap_flag: overlapFlag,
  }, token);
}

export function listAssistRequests(scope: 'sent' | 'received', token: string): Promise<AssistRequestSummary[]> {
  return apiClient.get(`/assist-requests?scope=${scope}`, token);
}

export function fetchAssistThread(requestId: string, token: string): Promise<AssistThread> {
  return apiClient.get(`/assist-requests/${requestId}`, token);
}

export function postAssistMessage(requestId: string, body: string, token: string): Promise<AssistMessage> {
  return apiClient.post(`/assist-requests/${requestId}/messages`, { body }, token);
}

export function setAssistStatus(
  requestId: string,
  newStatus: 'acknowledged' | 'declined',
  token: string,
): Promise<AssistRequestSummary> {
  return apiClient.patch(`/assist-requests/${requestId}/status`, { status: newStatus }, token);
}
```

- [ ] **Step 2: Type-check**

Run: `cd ziren_dashboard && npx tsc --noEmit`
Expected: no new errors attributable to this file.

- [ ] **Step 3: Commit**

```bash
git add ziren_dashboard/lib/api/assist-requests.ts
git commit -m "feat(dashboard): typed client for /assist-requests"
```

---

## Task 9: Frontend — `AssistThreadPanel`

**Files:**
- Create: `ziren_dashboard/components/incidents/assist-thread-panel.tsx`

**Interfaces:**
- Consumes: `useAssistThread` (Task 10 — write this task's component against the hook's planned shape, then Task 10 supplies it), `postAssistMessage`, `setAssistStatus` (Task 8), `AG_COLOR`/`AGENCY_ICON`... actually only `CATEGORY_ICON`, `SEV_COLOR`, `SEV_ICON` from `incident-vocabulary.ts`, `CATEGORY_LABELS` from `@/lib/charts/queue-series`.
- Produces: `<AssistThreadPanel requestId token onStatusChange? className? />`. Consumed by Tasks 11-12.

Do Task 10 (the hook) first if working strictly bottom-up — the two are listed in spec order but the hook has no dependency on this component, so implementers may swap their order freely. This task assumes `useAssistThread` already exists.

- [ ] **Step 1: Write the file**

```tsx
'use client';

/**
 * The chat for one cross-agency assist request — snapshot header, message
 * thread, compose box, and (only for the requested agency, only while
 * pending) Acknowledge/Decline. Shared by the incident detail modal (the
 * requesting side) and the Agencies tab's Assist requests panel (both
 * sides — the receiving agency never gets incident access, so this panel
 * is the only place their half of the thread exists). See
 * docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
 */

import { useEffect, useRef, useState } from 'react';
import { Check, Send, X } from 'lucide-react';
import { useAssistThread } from '@/lib/hooks/useAssistThread';
import { postAssistMessage, setAssistStatus, type AssistMessage, type AssistStatus } from '@/lib/api/assist-requests';
import { CATEGORY_ICON, SEV_COLOR, SEV_ICON } from '@/components/incidents/incident-vocabulary';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { cn } from '@/lib/utils';

export function AssistThreadPanel({
  requestId,
  token,
  onStatusChange,
  className,
}: {
  requestId: string;
  token: string;
  onStatusChange?: () => void;
  className?: string;
}) {
  const { thread, loading, error, refresh } = useAssistThread(requestId, token);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [responding, setResponding] = useState(false);
  const scrollEnd = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scrollEnd.current?.scrollIntoView({ block: 'end' });
  }, [thread?.messages.length]);

  if (loading && !thread) {
    return <div className={cn('p-5 text-[13px] text-muted-foreground', className)}>Loading conversation…</div>;
  }
  if (error && !thread) {
    return <div className={cn('p-5 text-[13px] text-[var(--color-system-warning)]', className)}>{error}</div>;
  }
  if (!thread) return null;

  const { request, messages } = thread;
  const closed = request.incident_status === 'resolved' || request.incident_status === 'cancelled';
  const SevIcon = request.severity ? SEV_ICON[request.severity] : undefined;
  const CategoryIcon = request.incident_category ? CATEGORY_ICON[request.incident_category] : undefined;
  const tint = request.severity ? SEV_COLOR[request.severity] : 'var(--color-text-tertiary)';

  async function send() {
    if (!draft.trim() || closed) return;
    setSending(true);
    try {
      await postAssistMessage(requestId, draft.trim(), token);
      setDraft('');
      refresh();
    } finally {
      setSending(false);
    }
  }

  async function respond(newStatus: 'acknowledged' | 'declined') {
    setResponding(true);
    try {
      await setAssistStatus(requestId, newStatus, token);
      refresh();
      onStatusChange?.();
    } finally {
      setResponding(false);
    }
  }

  return (
    <div className={cn('flex min-h-0 flex-col', className)}>
      <div className="flex items-start gap-3 border-b border-[var(--color-surface-border)] px-4 py-3">
        <span
          aria-hidden="true"
          className="flex size-8 shrink-0 items-center justify-center rounded-lg"
          style={{ backgroundColor: `color-mix(in srgb, ${tint} 14%, transparent)`, color: tint }}
        >
          {SevIcon ? <SevIcon className="size-4" /> : CategoryIcon ? <CategoryIcon className="size-4" /> : null}
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-[13.5px] font-semibold text-foreground">
            {request.incident_category ? CATEGORY_LABELS[request.incident_category] ?? request.incident_category : 'Incident'}
            {request.location_address && <span className="font-normal text-muted-foreground"> · {request.location_address}</span>}
          </p>
          <p className="mt-0.5 text-[12px] text-muted-foreground">
            {request.requesting_agency_name} asked {request.requested_agency_name}
          </p>
        </div>
        <StatusPill status={request.status} />
      </div>

      {closed && (
        <p className="border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-2 text-[12px] text-muted-foreground">
          This incident has been resolved — this thread is read-only.
        </p>
      )}

      <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-4 py-3">
        {messages.map(m => <MessageBubble key={m.id} message={m} />)}
        <div ref={scrollEnd} />
      </div>

      {request.can_respond && (
        <div className="flex gap-2 border-t border-[var(--color-surface-border)] px-4 py-3">
          <button
            className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-[var(--color-system-success)] px-3 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50"
            disabled={responding}
            onClick={() => void respond('acknowledged')}
            type="button"
          >
            <Check aria-hidden="true" className="size-4" /> We&apos;re responding
          </button>
          <button
            className="flex flex-1 items-center justify-center gap-1.5 rounded-lg border border-[var(--color-surface-border)] px-3 py-2 text-[13px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)] disabled:opacity-50"
            disabled={responding}
            onClick={() => void respond('declined')}
            type="button"
          >
            <X aria-hidden="true" className="size-4" /> Can&apos;t assist
          </button>
        </div>
      )}

      {!closed && (
        <div className="flex items-end gap-2 border-t border-[var(--color-surface-border)] px-4 py-3">
          <textarea
            className="max-h-24 min-h-9 flex-1 resize-none rounded-lg border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2 text-[13px]"
            disabled={sending}
            onChange={e => setDraft(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }}
            placeholder="Write a message…"
            rows={1}
            value={draft}
          />
          <button
            aria-label="Send"
            className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-[var(--color-brand)] text-white transition-opacity hover:opacity-90 disabled:opacity-50"
            disabled={sending || !draft.trim()}
            onClick={() => void send()}
            type="button"
          >
            <Send aria-hidden="true" className="size-4" />
          </button>
        </div>
      )}
    </div>
  );
}

function StatusPill({ status }: { status: AssistStatus }) {
  const style: Record<AssistStatus, { bg: string; fg: string; label: string }> = {
    pending:      { bg: 'var(--color-surface-raised)',    fg: 'var(--color-text-secondary)', label: 'Pending' },
    acknowledged: { bg: 'var(--color-system-success-bg)', fg: 'var(--color-system-success)', label: 'Responding' },
    declined:     { bg: 'var(--color-system-warning-bg)', fg: 'var(--color-system-warning)', label: 'Declined' },
  };
  const s = style[status];
  return (
    <span className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide" style={{ backgroundColor: s.bg, color: s.fg }}>
      {s.label}
    </span>
  );
}

function MessageBubble({ message }: { message: AssistMessage }) {
  return (
    <div className={cn('flex flex-col', message.mine ? 'items-end' : 'items-start')}>
      <div
        className={cn(
          'max-w-[80%] rounded-xl px-3 py-2 text-[13px] leading-snug',
          message.mine ? 'bg-[var(--color-brand)] text-white' : 'bg-[var(--color-surface-raised)] text-foreground',
        )}
      >
        {message.body}
      </div>
      <span className="mt-0.5 px-1 text-[11px] text-muted-foreground">
        {message.sender_name ?? 'Someone'} · {new Date(message.created_at).toLocaleTimeString('en-PH', { hour: 'numeric', minute: '2-digit' })}
      </span>
    </div>
  );
}
```

- [ ] **Step 2: Type-check** (will still fail until Task 10 supplies the hook)

Run: `cd ziren_dashboard && npx tsc --noEmit`
Expected: one error, `Cannot find module '@/lib/hooks/useAssistThread'` — resolved by Task 10. Do not commit until Task 10 is also done.

---

## Task 10: Frontend — `useAssistThread` polling hook

**Files:**
- Create: `ziren_dashboard/lib/hooks/useAssistThread.ts`

**Interfaces:**
- Consumes: `fetchAssistThread` (Task 8), `ApiError`, `signOut`.
- Produces: `useAssistThread(requestId: string | null, token: string | null, pollMs = 6000) -> { thread: AssistThread | null, loading: boolean, error: string | null, refresh: () => void }`. Consumed by Task 9.

- [ ] **Step 1: Write the file**

```ts
'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { fetchAssistThread, type AssistThread } from '@/lib/api/assist-requests';

export interface AssistThreadState {
  thread: AssistThread | null;
  loading: boolean;
  error: string | null;
  refresh: () => void;
}

/**
 * Loads one assist-request thread and polls it every `pollMs` while mounted
 * and the tab is visible — the "fast polling while open" delivery mechanism
 * the design spec chose over giving the dashboard its first-ever direct
 * Supabase Realtime subscription (see the spec's Global Constraints).
 * Stops the moment the panel unmounts; there is no background poll.
 */
export function useAssistThread(
  requestId: string | null,
  token: string | null,
  pollMs = 6000,
): AssistThreadState {
  const [thread, setThread] = useState<AssistThread | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const latest = useRef(0);

  const load = useCallback((silent = false) => {
    if (!requestId || !token) return;
    const ticket = ++latest.current;
    if (!silent) setLoading(true);
    fetchAssistThread(requestId, token)
      .then(res => {
        if (ticket !== latest.current) return;
        setThread(res);
        setError(null);
      })
      .catch((e: unknown) => {
        if (ticket !== latest.current) return;
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        if (!silent) setError(e instanceof Error ? e.message : 'Could not load this conversation.');
      })
      .finally(() => { if (ticket === latest.current) setLoading(false); });
  }, [requestId, token]);

  useEffect(() => {
    setThread(null);
    load(false);
  }, [load]);

  useEffect(() => {
    if (!requestId || !token) return;
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') load(true);
    }, pollMs);
    return () => clearInterval(id);
  }, [requestId, token, pollMs, load]);

  return { thread, loading, error, refresh: () => load(false) };
}
```

- [ ] **Step 2: Type-check both Task 9 and Task 10 together**

Run: `cd ziren_dashboard && npx tsc --noEmit`
Expected: clean.

- [ ] **Step 3: Lint**

Run: `cd ziren_dashboard && npx eslint components/incidents/assist-thread-panel.tsx lib/hooks/useAssistThread.ts`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add ziren_dashboard/components/incidents/assist-thread-panel.tsx ziren_dashboard/lib/hooks/useAssistThread.ts
git commit -m "feat(dashboard): AssistThreadPanel chat component and its polling hook"
```

---

## Task 11: Frontend — `AssistRequestDialog` + wire into the incident detail modal

**Files:**
- Create: `ziren_dashboard/components/incidents/assist-request-dialog.tsx`
- Modify: `ziren_dashboard/components/incidents/incident-detail-modal.tsx`

**Interfaces:**
- Consumes: `fetchAssistCandidates`, `createAssistRequest` (Task 8), `AG_COLOR`, `AGENCY_ICON` (`incident-vocabulary.ts`), the `Dialog`/`DialogClose`/`DialogContent`/`DialogDescription`/`DialogTitle` set from `@/components/efferd/ui/dialog`.
- Produces: `<AssistRequestDialog token incidentId overlapFlags triggerRef onClose onSuccess onError />`, wired into `incident-detail-modal.tsx`'s existing `showXModal` state family.

- [ ] **Step 1: Write `assist-request-dialog.tsx`**

```tsx
'use client';

/**
 * "Request assist" — compose a new cross-agency assist request from inside
 * the incident detail modal. Not one of dispatch-action-modals.tsx's
 * siblings on purpose: this one fetches its own candidate list and has a
 * compose step, not a single confirm action, so it gets its own file.
 *
 * Uses the triggerRef + onCloseAutoFocus/onOpenAutoFocus pattern
 * option-dialog.tsx established this session (Radix's own "restore
 * previous focus" does not reliably land back on a plain button that
 * isn't a <Dialog.Trigger>) rather than this file's older sibling modals'
 * simpler pattern, since this dialog is also reused from the Agencies tab
 * where that convention is already the norm.
 */

import { useEffect, useState } from 'react';
import { Check, Send, X } from 'lucide-react';
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  createAssistRequest, fetchAssistCandidates, type AssistCandidate,
} from '@/lib/api/assist-requests';
import { AG_COLOR, AGENCY_ICON } from '@/components/incidents/incident-vocabulary';
import { cn } from '@/lib/utils';

const OVERLAP_TO_AGENCY_TYPE: Record<string, string> = {
  fire: 'BFP',
  injuries: 'MDRRMO',
  flooding: 'MDRRMO',
  missing_person: 'PNP',
  // hazmat can mean either BFP or MDRRMO — BFP is the suggested default,
  // MDRRMO is one click away like every other suggestion here.
  hazmat: 'BFP',
};

export function AssistRequestDialog({
  token,
  incidentId,
  overlapFlags,
  triggerRef,
  onClose,
  onSuccess,
  onError,
}: {
  token: string;
  incidentId: string;
  /** The incident's own overlap_agencies, if any — drives the auto-suggested target. */
  overlapFlags: string[];
  triggerRef: React.RefObject<HTMLButtonElement | null>;
  onClose: () => void;
  onSuccess: () => void;
  onError: (m: string) => void;
}) {
  const [candidates, setCandidates] = useState<AssistCandidate[] | null>(null);
  const [target, setTarget] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);

  useEffect(() => {
    let live = true;
    fetchAssistCandidates(incidentId, token)
      .then(list => {
        if (!live) return;
        setCandidates(list);
        const suggestedType = overlapFlags.map(f => OVERLAP_TO_AGENCY_TYPE[f]).find(Boolean);
        const suggested = suggestedType ? list.find(a => a.agency_type === suggestedType) : undefined;
        setTarget((suggested ?? list[0])?.id ?? null);
      })
      .catch((e: unknown) => onError(e instanceof Error ? e.message : 'Could not load nearby agencies.'));
    return () => { live = false; };
    // overlapFlags/onError are stable for the dialog's lifetime (a fresh
    // instance mounts per open) — only re-fetch if the incident changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [incidentId, token]);

  const usedFlag = overlapFlags.find(f => OVERLAP_TO_AGENCY_TYPE[f] === candidates?.find(a => a.id === target)?.agency_type) ?? null;

  async function send() {
    if (!target || !message.trim()) return;
    setSending(true);
    try {
      await createAssistRequest(incidentId, target, message.trim(), usedFlag, token);
      onSuccess();
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Could not send the request.');
    } finally {
      setSending(false);
    }
  }

  return (
    <Dialog onOpenChange={open => { if (!open && !sending) onClose(); }} open>
      <DialogContent
        className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[440px]"
        onCloseAutoFocus={e => { e.preventDefault(); triggerRef.current?.focus(); }}
        onOpenAutoFocus={e => { e.preventDefault(); (e.target as HTMLElement).querySelector('textarea')?.focus(); }}
        showCloseButton={false}
      >
        <div className="flex items-start gap-3 px-5 pb-3 pt-5">
          <div className="min-w-0 flex-1">
            <DialogTitle className="text-[16px] font-bold leading-tight tracking-tight text-foreground">Request assist</DialogTitle>
            <DialogDescription className="mt-1 text-[13px] leading-snug">
              Ask another agency present in this area for help on this incident.
            </DialogDescription>
          </div>
          <DialogClose aria-label="Close" className="-mr-1 -mt-1 flex size-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground">
            <X aria-hidden="true" className="size-4" />
          </DialogClose>
        </div>

        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 pb-5">
          <div>
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Agency</p>
            {candidates === null ? (
              <p className="text-[13px] text-muted-foreground">Loading…</p>
            ) : candidates.length === 0 ? (
              <p className="text-[13px] text-muted-foreground">No other active agency is registered in this incident&apos;s municipality.</p>
            ) : (
              <div className="flex flex-col gap-1.5" role="radiogroup">
                {candidates.map(a => {
                  const Icon = AGENCY_ICON[a.agency_type];
                  const active = target === a.id;
                  return (
                    <button
                      aria-checked={active}
                      className={cn(
                        'flex w-full items-center gap-3 rounded-xl border px-3.5 py-2.5 text-left transition-colors',
                        active
                          ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]'
                          : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] hover:bg-[var(--color-surface-hover)]',
                      )}
                      key={a.id}
                      onClick={() => setTarget(a.id)}
                      role="radio"
                      type="button"
                    >
                      {Icon && (
                        <span
                          aria-hidden="true"
                          className="flex size-8 shrink-0 items-center justify-center rounded-lg"
                          style={{ backgroundColor: `color-mix(in srgb, ${AG_COLOR[a.agency_type]} 14%, transparent)`, color: AG_COLOR[a.agency_type] }}
                        >
                          <Icon className="size-4" />
                        </span>
                      )}
                      <span className="min-w-0 flex-1 text-[14px] font-semibold text-foreground">{a.name}</span>
                      {active && <Check aria-hidden="true" className="size-4 shrink-0 text-[var(--color-brand)]" />}
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          <div>
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Message</p>
            <textarea
              className="w-full resize-none rounded-lg border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2 text-[13px]"
              onChange={e => setMessage(e.target.value)}
              placeholder="What do you need from them? e.g. Crowd control at the north entrance."
              rows={3}
              value={message}
            />
          </div>
        </div>

        <div className="flex justify-end gap-2 border-t border-[var(--color-surface-border)] px-5 py-3">
          <button
            className="rounded-lg px-3.5 py-2 text-[13px] font-semibold text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="flex items-center gap-1.5 rounded-lg bg-[var(--color-brand)] px-4 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50"
            disabled={sending || !target || !message.trim()}
            onClick={() => void send()}
            type="button"
          >
            <Send aria-hidden="true" className="size-4" /> Send request
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 2: Wire it into `incident-detail-modal.tsx`**

Four separate edits to `ziren_dashboard/components/incidents/incident-detail-modal.tsx`:

Edit 2a — add `useRef` to the existing React import:
```tsx
// Before:
import { useCallback, useEffect, useState } from 'react';
// After:
import { useCallback, useEffect, useRef, useState } from 'react';
```

Edit 2b — add `Handshake` to the existing lucide-react import (alphabetically, between `Flag` and `HelpCircle`) and import the new dialog:
```tsx
// Before:
import {
  AlertTriangle, CalendarClock, Check, CircleHelp, ClipboardCheck, Clock,
  Flag, HelpCircle, ListTree, MapPin, Phone, Shield,
  ShieldCheck, ShieldX, Siren, Sparkles, Star, UserCheck, UserRound, X,
} from 'lucide-react';
// After:
import {
  AlertTriangle, CalendarClock, Check, CircleHelp, ClipboardCheck, Clock,
  Flag, Handshake, HelpCircle, ListTree, MapPin, Phone, Shield,
  ShieldCheck, ShieldX, Siren, Sparkles, Star, UserCheck, UserRound, X,
} from 'lucide-react';
```

```tsx
// Before:
import {
  CancelModal, DispatchModal, FlagSosModal, RejectReportModal,
  RequestClarificationModal,
} from '@/components/incidents/dispatch-action-modals';
// After:
import {
  CancelModal, DispatchModal, FlagSosModal, RejectReportModal,
  RequestClarificationModal,
} from '@/components/incidents/dispatch-action-modals';
import { AssistRequestDialog } from '@/components/incidents/assist-request-dialog';
```

Edit 2c — add state and a ref alongside the existing `showXModal` family (after `showClarifyModal`):
```tsx
// Before:
  const [showClarifyModal, setShowClarifyModal] = useState(false);
  const [showAcceptConfirm, setShowAcceptConfirm] = useState(false);
// After:
  const [showClarifyModal, setShowClarifyModal] = useState(false);
  const [showAssistDialog, setShowAssistDialog] = useState(false);
  const assistTriggerRef = useRef<HTMLButtonElement>(null);
  const [showAcceptConfirm, setShowAcceptConfirm] = useState(false);
```

Edit 2d — add the button after the existing "Also present" row, and render the dialog when open:
```tsx
// Before:
                    {detail.overlap_agencies && detail.overlap_agencies.length > 0 && (
                      <_Row label="Also present">
                        {detail.overlap_agencies
                          .map(f => OVERLAP_LABELS[f] ?? f)
                          .join(' · ')}
                      </_Row>
                    )}
                    {view.showWizardAnswers && <_Answers items={facets.what} />}
// After:
                    {detail.overlap_agencies && detail.overlap_agencies.length > 0 && (
                      <_Row label="Also present">
                        {detail.overlap_agencies
                          .map(f => OVERLAP_LABELS[f] ?? f)
                          .join(' · ')}
                      </_Row>
                    )}
                    <_Row icon={Handshake} label="Coordination">
                      <button
                        className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--color-surface-border)] px-3 py-1.5 text-[12.5px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
                        onClick={() => setShowAssistDialog(true)}
                        ref={assistTriggerRef}
                        type="button"
                      >
                        Request assist
                      </button>
                    </_Row>
                    {view.showWizardAnswers && <_Answers items={facets.what} />}
```

Then, near wherever this file already conditionally renders its sibling modals (search for `{showCancelModal && (` or similar), add:
```tsx
{showAssistDialog && (
  <AssistRequestDialog
    incidentId={detail.id}
    onClose={() => setShowAssistDialog(false)}
    onError={m => setActionError(m)}
    onSuccess={() => { setShowAssistDialog(false); setSuccessMsg('Assist request sent.'); }}
    overlapFlags={detail.overlap_agencies ?? []}
    token={token}
    triggerRef={assistTriggerRef}
  />
)}
```

Match this block's exact placement and the `onSuccess`/`onError` wiring to how the neighboring `{showCancelModal && <CancelModal .../>}`-style block (if present) already sets `actionError`/`successMsg` on its own success/error paths — copy that block's surrounding shape exactly rather than inventing a new convention, since `actionError` and `successMsg` are this component's own existing state, not new state this task introduces.

- [ ] **Step 3: Type-check**

Run: `cd ziren_dashboard && npx tsc --noEmit`
Expected: clean.

- [ ] **Step 4: Lint**

Run: `cd ziren_dashboard && npx eslint components/incidents/assist-request-dialog.tsx components/incidents/incident-detail-modal.tsx`
Expected: clean.

- [ ] **Step 5: Visual check**

Start the dashboard (`npm run dev`), open Live Queue or Incident Records as an `agency_admin`, open any incident's detail modal, confirm a "Request assist" row appears under "What happened" with a working button that opens the dialog, that the agency list loads and an overlap flag (if the mocked incident has one) pre-selects the mapped agency type, and that sending closes the dialog and shows a success message. Screenshot both light and dark.

- [ ] **Step 6: Commit**

```bash
git add ziren_dashboard/components/incidents/assist-request-dialog.tsx ziren_dashboard/components/incidents/incident-detail-modal.tsx
git commit -m "feat(dashboard): Request assist dialog wired into the incident detail modal"
```

---

## Task 12: Frontend — Assist requests panel on the Agencies tab

**Files:**
- Modify: `ziren_dashboard/components/operational-area/agencies-tab.tsx`
- Modify: `ziren_dashboard/app/(dashboard)/geographic/page.tsx:235`

**Interfaces:**
- Consumes: `listAssistRequests` (Task 8), `AssistThreadPanel` (Task 9), `Panel`/`Empty` (`./kit`).
- Produces: `AgenciesTab` gains a required `token: string` prop.

- [ ] **Step 1: Pass `token` down from the page**

```tsx
// ziren_dashboard/app/(dashboard)/geographic/page.tsx — before:
            {tab === 'agencies' && <AgenciesTab data={data} />}
// After:
            {tab === 'agencies' && <AgenciesTab data={data} token={token} />}
```

(`token` is already guaranteed non-null at this point in `page.tsx` — the component returns `null` earlier, at the existing `if (!token) return null;` guard, before this line is ever reached.)

- [ ] **Step 2: Add the panel to `agencies-tab.tsx`**

```tsx
// Before:
import Link from 'next/link';
import { Building2, Mail, MapPin, Phone, ShieldAlert } from 'lucide-react';
import type { AgencyPresence, AreaFilters, OperationalArea } from '@/lib/api/operational-area';
import { AG_COLOR } from '@/components/incidents/incident-vocabulary';
import { periodLong } from './period';
import { AgencyChip, BarList, Empty, Note, Panel, SIGNAL_LABEL, fmtInt } from './kit';

export function AgenciesTab({ data }: { data: OperationalArea }) {
// After:
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { Building2, Handshake, Mail, MapPin, Phone, ShieldAlert } from 'lucide-react';
import type { AgencyPresence, AreaFilters, OperationalArea } from '@/lib/api/operational-area';
import { listAssistRequests, type AssistRequestSummary } from '@/lib/api/assist-requests';
import { AssistThreadPanel } from '@/components/incidents/assist-thread-panel';
import { AG_COLOR } from '@/components/incidents/incident-vocabulary';
import { periodLong } from './period';
import { AgencyChip, BarList, Empty, Note, Panel, SIGNAL_LABEL, fmtInt } from './kit';

// AgenciesTab fetches this one small, independent list itself rather than
// threading it through OperationalArea's payload/useOperationalArea hook:
// assist requests aren't filtered by this screen's period/municipality the
// way everything else in that payload is, and this keeps the much larger
// operational-area.ts/geographic.py contract untouched for an unrelated
// feature — see the design spec.
export function AgenciesTab({ data, token }: { data: OperationalArea; token: string }) {
```

Add the panel's own component and state, and render it — insert a new `<AssistRequestsPanel token={token} />` as the FIRST child inside the existing outer `<div className="flex flex-col gap-4">`, before the "Agencies here" `<Panel>`:

```tsx
// Before:
  return (
    <div className="flex flex-col gap-4">
      <Panel
        description={`Every agency with a presence in ${data.area.municipality}. When a report needs more than one of you, this is who to call.`}
        title="Agencies here"
      >
// After:
  return (
    <div className="flex flex-col gap-4">
      <AssistRequestsPanel token={token} />

      <Panel
        description={`Every agency with a presence in ${data.area.municipality}. When a report needs more than one of you, this is who to call.`}
        title="Agencies here"
      >
```

Append the new sub-component at the bottom of the file, after `AgencyCard`:

```tsx
function AssistRequestsPanel({ token }: { token: string }) {
  const [received, setReceived] = useState<AssistRequestSummary[] | null>(null);
  const [sent, setSent] = useState<AssistRequestSummary[] | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  function reload() {
    void listAssistRequests('received', token).then(setReceived);
    void listAssistRequests('sent', token).then(setSent);
  }

  useEffect(reload, [token]);

  const pendingIncoming = (received ?? []).filter(r => r.status === 'pending');
  const rest = [...(received ?? []).filter(r => r.status !== 'pending'), ...(sent ?? [])]
    .sort((a, b) => b.created_at.localeCompare(a.created_at));

  return (
    <Panel description="Requests for help between agencies, tied to a specific incident." title="Assist requests">
      {received === null || sent === null ? (
        <p className="text-[13px] text-muted-foreground">Loading…</p>
      ) : pendingIncoming.length === 0 && rest.length === 0 ? (
        <Empty icon={Handshake} title="No assist requests yet">
          Ask another agency for help from any incident&apos;s detail view, or requests asking for YOUR help will show up here.
        </Empty>
      ) : (
        <div className="flex flex-col divide-y divide-[var(--color-surface-border)]">
          {[...pendingIncoming, ...rest].map(r => (
            <AssistRequestRow key={r.id} onOpen={() => setOpenId(r.id)} request={r} />
          ))}
        </div>
      )}

      {openId && (
        <div className="mt-3 overflow-hidden rounded-xl border border-[var(--color-surface-border)]">
          <AssistThreadPanel
            className="h-[420px]"
            onStatusChange={reload}
            requestId={openId}
            token={token}
          />
        </div>
      )}
    </Panel>
  );
}

function AssistRequestRow({ request, onOpen }: { request: AssistRequestSummary; onOpen: () => void }) {
  const STATUS_WORD: Record<string, string> = { pending: 'Pending', acknowledged: 'Responding', declined: 'Declined' };
  return (
    <button
      className="flex w-full items-center justify-between gap-3 py-3 text-left first:pt-0 last:pb-0 hover:bg-[var(--color-surface-hover)]"
      onClick={onOpen}
      type="button"
    >
      <span className="min-w-0">
        <span className="block truncate text-[13.5px] font-medium text-foreground">
          {request.requesting_agency_name} → {request.requested_agency_name}
        </span>
        <span className="block truncate text-[12px] text-muted-foreground">{request.location_address ?? 'Location not on file'}</span>
      </span>
      <span className="shrink-0 text-[12px] font-semibold text-muted-foreground">{STATUS_WORD[request.status]}</span>
    </button>
  );
}
```

- [ ] **Step 3: Type-check**

Run: `cd ziren_dashboard && npx tsc --noEmit`
Expected: clean.

- [ ] **Step 4: Lint**

Run: `cd ziren_dashboard && npx eslint components/operational-area/agencies-tab.tsx "app/(dashboard)/geographic/page.tsx"`
Expected: clean.

- [ ] **Step 5: Visual check**

Open Operational Area → Agencies tab as `agency_admin`, confirm the new "Assist requests" panel renders above "Agencies here" with an empty state when there are none, and (using a mocked backend response) that a pending incoming request shows Acknowledge/Decline inside its opened thread and a sent one shows its status. Screenshot light and dark, 1440/1024/390px.

- [ ] **Step 6: Commit**

```bash
git add ziren_dashboard/components/operational-area/agencies-tab.tsx "ziren_dashboard/app/(dashboard)/geographic/page.tsx"
git commit -m "feat(dashboard): Assist requests panel on the Operational Area Agencies tab"
```

---

## Task 13: End-to-end verification

**Files:**
- Create (scratchpad, not committed): `verify-assist-requests.js` in this session's scratchpad directory.

**Interfaces:**
- Consumes: the full stack built in Tasks 1-12, a running `npm run dev` dashboard and `uvicorn app.main:app --reload` backend (or, per this repo's established convention, a fully-mocked `page.route('http://localhost:3000/api/**', ...)` Playwright script — no real backend required; see the `ziren-dev` skill's screenshotting section and `feedback_testing_rigor_and_tooling` memory).

- [ ] **Step 1: Write the verification script**

Mirror the shape of the prior `verify-option-dialogs.js` / `verify-queue-clear.js` scripts (two mocked browser contexts, one per agency, sharing the same `incident_assist_requests`/`incident_assist_messages` mock arrays so agency B's context sees what agency A's context wrote). Cover at minimum:
1. Sending a request from the incident detail modal closes the dialog and shows a success message.
2. The receiving agency's Agencies tab shows the request as an incoming, pending item with a working Acknowledge/Decline pair.
3. Clicking Acknowledge updates the status pill and removes the action buttons.
4. A message sent from one mocked session appears in the other session's open thread within one poll interval — use `page.clock` (`install()` then `fastForward(7000)`), per this project's established convention for testing pollers without a real wait (`feedback_testing_rigor_and_tooling` lesson 8).
5. Once the mocked incident's status is `resolved`, the thread renders its read-only notice and the compose box is gone.
6. No console errors in either session.

- [ ] **Step 2: Run it**

Run: `node verify-assist-requests.js` (from the scratchpad directory, with the dashboard dev server running)
Expected: every check reports PASS.

- [ ] **Step 3: Fix anything that fails**

Diagnose with a small standalone `page.evaluate` script before guessing, per this project's own established debugging discipline — do not iterate blindly on the full suite.

- [ ] **Step 4: Re-run the full backend suite and existing frontend regression scripts**

Run: `cd ziren_backend && .venv\Scripts\python.exe -m pytest -q`
Run the dashboard's pre-existing scratchpad suites that touch `incident-detail-modal.tsx` or `agencies-tab.tsx` (at minimum `verify-area.js`, `verify-records.js`) to confirm zero regressions from this plan's edits to those two files.
Expected: everything that passed before this plan still passes.

- [ ] **Step 5: Report completion**

Summarize to the user: what was built, that the migration is written but not applied (needs to be run in the Supabase SQL Editor), and the verification results. Do not commit anything beyond what each task above already committed — this step is reporting only.

---

## Self-Review Notes

- **Spec coverage:** every in-scope item from the design spec has a task — schema/RLS (1), candidate lookup (2), create+notify (3), list/thread (4), messages (5), status (6), router (7), typed client (8), chat UI (9), polling (10), compose dialog + incident modal wiring (11), Agencies tab panel (12), verification (13). The spec's non-goals (mobile, standing inbox, realtime, multi-target) have no corresponding task, by design.
- **Real gap found and resolved during planning, not left as a placeholder:** the design spec assumed the frontend could compare agency ids to know "mine" vs "theirs" and "can I respond", but `lib/hooks/useAuth.ts` (checked directly, Task 9/10 prep) stores no agency id in session storage — only `token`, `role`, `email`, `agencyType` (BFP/PNP/MDRRMO, not a UUID). Resolved by computing `mine`/`can_respond` server-side in `_hydrate_request`/`get_thread` (Tasks 3-4) and shipping them as plain booleans, so no frontend component needs an agency id at all.
- **Route flattened from the spec's nested form:** the spec wrote `POST /incidents/{id}/assist-requests`; Task 7 uses `POST /assist-requests` with `incident_id` in the body instead, to fit this codebase's one-router-one-prefix convention (confirmed against `app/main.py`'s `include_router` calls) rather than mixing two prefixes in one router file. Functionally identical.
- **One endpoint added beyond the spec's literal list:** `GET /assist-requests/candidates` (Task 2/7). The spec said the target-agency list is "the same list the Agencies tab already fetches" but didn't specify how the incident detail modal — which has no access to the Operational Area payload — would obtain it. Resolved with a small, focused endpoint reusing the exact municipality-scoped query idiom already in `operational_area_service.py`.
- **Type consistency check:** `AssistRequestSummary`/`AssistMessage` (Task 8) field names match `_hydrate_request`'s/`get_thread`'s Python dict keys exactly (`can_respond`, `mine`, `requesting_agency_name`, etc.) — verified by re-reading Tasks 3-6 against Task 8 while writing this plan. `AssistThreadPanel` (Task 9) reads only fields Task 8 declares. `assist-request-dialog.tsx` (Task 11) calls `createAssistRequest` with the exact five positional args Task 8 defines.
- **`provincial_admin` is deliberately absent**, including from read access — the approved spec never mentions the role. Existing analogous tables (`incidents`, `incident_notes`, `dispatch_log`) all give `provincial_admin` oversight read across their own agency_type's stations, so this may be an oversight in the spec rather than a deliberate exclusion. Flagged for the user in the completion report (Task 13, Step 5) rather than decided unilaterally here — do not add it without asking first.
