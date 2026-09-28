# Super Admin Feature Plan — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Super Admin role a fully distinct, working experience — system-wide
management, monitoring, analysis, and governance — separate from the Agency Admin's
operational dispatch role, per the 20-section spec.

**Architecture:** Additive, not a rewrite. Reuse existing tables/endpoints wherever the data
already exists (incidents, stations, agencies, users, rubric_configs). Add three new tables
(`audit_logs`, `notifications`, `announcements` + `announcement_reads`) and one small
key-value table (`system_config`) behind a shared `audit_service` write-path that both logs and
(optionally) fans out notifications, so Audit Logs (#10), System Governance's Configuration
History (#11), and Notifications (#15) share one implementation instead of three. New
dashboard pages are added under `ziren_dashboard/app/(dashboard)/`; existing pages
(`/incidents`, `/map`, `/rubric`→`/governance`, `/settings`) are extended with role-aware
branches rather than forked into parallel routes, so Agency Admin's working flows don't move.

**Tech Stack:** FastAPI + Supabase/Postgres (`ziren_backend`), Next.js 14 App Router + TS +
Tailwind + shadcn/radix via `components/efferd/ui/*` (`ziren_dashboard`).

**Spec:** `docs/specs/2026-09-09-super-admin-plan-features.md` (full 20-section spec + target
nav IA).

## Global Constraints

- Never trust role from the JWT — always `current_user["role"]` from `public.users`, per
  existing `get_current_user` (`ziren_backend/app/core/dependencies.py`).
- New migrations start at `026` (next free number after
  `ziren_backend/supabase/migrations/025_*.sql` if one lands first in this plan; check
  `ls ziren_backend/supabase/migrations` before naming — do not guess a number that collides).
- Every new table gets RLS policies **and** an explicit `GRANT ALL ... TO service_role` in the
  *same* migration that creates it — migrations `017`/`018` exist entirely because two earlier
  tables shipped without that grant and every endpoint 500'd with `42501`. Follow the pattern in
  `ziren_backend/supabase/migrations/007_rubric_config.sql` (RLS) and `018_grants_rubric_tables.sql`
  (grants + verification query) exactly.
- Do not touch `ziren_backend/app/models/incident.py`'s `IncidentStatus` enum, `rubric_service.py`
  scoring logic, or any mobile wizard-answer strings (memory: wizard answer strings are the
  severity payload — localizing/changing them breaks scoring silently).
- Do not change the severity/status color tokens described in memory
  `project_ziren_design_tokens` — Appearance work (Task 15) must keep them byte-identical
  through the off-white theme change.
- Agency Admin's existing pages/endpoints must keep working unchanged: `/incidents` (dispatch
  actions), `/responders`, `/coverage` polygon editing capability (may move UI location, must
  not lose function), `/rubric/[agency]` editing (may be re-hosted under `/governance`, must
  keep working), `dispatch.py`'s `_dispatcher = require_role("agency_admin")` gate stays as-is.
- Every new backend router file gets a matching `ziren_backend/tests/test_<name>.py` following
  the mock pattern in `ziren_backend/tests/test_responder_dashboard.py` (patch
  `app.core.dependencies.get_supabase` for auth, patch the service module's `get_supabase` for
  data).
- Every new/changed endpoint gets its TypeScript call added to `ziren_dashboard/lib/api/*.ts`
  with matching types — do not fetch with a raw untyped `fetch()` in a page component.
- Run `cd ziren_backend && python -m pytest -q` after each backend task and
  `cd ziren_dashboard && npm run build` (or `npx tsc --noEmit`) after each frontend task, before
  committing.
- Visual verification of any dashboard page uses the sessionStorage-seed + backend-mock approach
  in the `ziren-dev` skill / memory `project_ziren_dashboard_verification` — run it at the
  checkpoints marked below, not only at the very end.
- **Pragmatic MVP cuts, stated up front rather than silently dropped:**
  - Incident status vocabulary: the spec's 6 labels (Pending/Under Verification/Accepted/In
    Progress/Resolved/Cancelled) are a **display mapping** over the existing 5-value
    `IncidentStatus` enum (`received/processing/dispatched/resolved/cancelled`) — see Task 6.
    "Accepted" is not separately trackable yet (dispatch_log has no accepted-vs-in-progress
    split) and folds into "In Progress". Changing the underlying enum is out of scope.
  - System Status "Realtime services" is approximated as "reachable" whenever the DB check
    passes (same Supabase project) rather than a live websocket probe — Postgres/Supabase does
    not expose a cheap synchronous realtime health check from a request handler.
  - Two-factor authentication and interface language switching are *stubbed* in Settings
    (visible, described, disabled with "Coming soon") — spec says "if implemented", and this
    project has no 2FA/i18n infrastructure to hang a real toggle on.
  - "Security alerts" as a notification *type* exists in the schema/UI; there is no new
    brute-force/anomaly detector built to populate it. Out of scope.
  - Reports & Export: PDF via `reportlab` (pure-Python-wheel, no system deps), Excel via
    `openpyxl`, CSV via the stdlib `csv` module. Both are new pinned dependencies —
    add to `ziren_backend/requirements.txt`.

---

## Task 0: Confirm the next migration number and read current nav/auth wiring

**Files:** none changed — this is a look-before-you-leap check, folded into Task 1 rather than
split out as its own reviewable unit.

- [ ] Run `ls ziren_backend/supabase/migrations` and note the highest number `N`; all new
  migrations in this plan are numbered starting at `N+1`, sequentially, in the order the tasks
  below create them (Task 1 → first new number, Task 9 → next, Task 11 → next, Task 12 → next).
- [ ] Re-read `ziren_dashboard/lib/nav/nav-config.ts` and
  `ziren_dashboard/components/shell/ziren-header.tsx` in full immediately before Task 2 and
  Task 16 respectively — both are hand-edited below against the versions read on 2026-09-09;
  if either has changed, reconcile before applying the diff.

---

## Task 1: `audit_logs` table + `audit_service` — the shared write-path

Foundation for Audit Logs (#10), System Governance's Configuration History (#11), and half of
Notifications (#15). Build this before any module that needs to log into it.

**Files:**
- Create: `ziren_backend/supabase/migrations/<N+1>_audit_logs.sql`
- Create: `ziren_backend/app/services/audit_service.py`
- Create: `ziren_backend/app/routers/audit.py`
- Modify: `ziren_backend/app/main.py` (register the new router)
- Modify: `ziren_backend/app/core/dependencies.py` (add `require_super_admin` and
  `assert_agency_scope` — additive only, do not touch `require_role`/`require_approved_responder`)
- Test: `ziren_backend/tests/test_audit_service.py`
- Test: `ziren_backend/tests/test_audit_router.py`

**Interfaces:**
- Produces: `audit_service.record(db, *, actor: dict, action: str, target_type: str, target_id: str | None = None, target_label: str | None = None, previous: dict | None = None, new: dict | None = None, metadata: dict | None = None) -> dict` — inserts one `audit_logs` row, returns it. `actor` is a `current_user` dict (has `id`, `role`, `full_name`). Never raises on notification failure (see Task 9's `notification_service.create_for_roles`, which this calls internally when `action` is in `audit_service.NOTIFY_ACTIONS`).
- Produces: `audit_service.NOTIFY_ACTIONS: dict[str, tuple[str, ...]]` — maps an `action` string to the roles that should get a notification for it, e.g. `{"station.created": ("super_admin",), "responder.suspended": ("super_admin",), "rubric.activated": ("super_admin",)}`. Empty/absent mapping = audit-only, no notification.
- Produces: `GET /audit-logs` (super_admin only) — query params `actor_id`, `target_type`, `action`, `date_from`, `date_to`, `limit` (default 50, max 200), `offset`; returns `{items: AuditLogEntry[], total: int}`.
- Consumes (later tasks call this): every mutation task below (station create/deactivate, agency admin create, account suspend, rubric activate, announcement publish, system_config update, verification decision) calls `audit_service.record(...)` at the point it currently only logs via `structlog`.

- [ ] **Step 1: Write the migration** (`ziren_backend/supabase/migrations/<N+1>_audit_logs.sql`), following `007_rubric_config.sql`'s shape and `018`'s grant pattern in the *same* file this time:

```sql
-- ============================================================
-- Migration <N+1>: audit_logs — general-purpose admin action trail
--
-- Superset of rubric_audit_log (migration 007), which stays as-is for the
-- rubric engine's own fallback-to-seed events. This table is the general
-- "who changed what" record the Super Admin's Audit Logs module reads,
-- written by audit_service.record() from any router, not only rubric.py.
--
-- GRANT is in this same migration (not a follow-up), unlike rubric_configs/
-- rubric_audit_log which needed 018 as a bugfix afterwards — see that
-- migration's header for exactly the 42501 failure this avoids repeating.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id       UUID REFERENCES public.users(id) ON DELETE SET NULL,
    actor_role     TEXT,
    actor_name     TEXT,
    action         TEXT NOT NULL,
    target_type    TEXT NOT NULL,
    target_id      TEXT,
    target_label   TEXT,
    previous_value JSONB,
    new_value      JSONB,
    metadata       JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS audit_logs_created_idx ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_actor_idx   ON public.audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS audit_logs_target_idx  ON public.audit_logs(target_type, target_id);
CREATE INDEX IF NOT EXISTS audit_logs_action_idx  ON public.audit_logs(action);

COMMENT ON TABLE public.audit_logs IS
    'Append-only trail of administrative actions across the whole app. '
    'Written exclusively by app.services.audit_service.record() — never '
    'updated or deleted. actor_id is NULL only for system-generated rows.';

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_logs: super_admin reads all"
    ON public.audit_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'super_admin'
        )
    );

-- Inserts happen via the backend's service-role client, never a user JWT —
-- audit_service.record() always writes as service_role. No INSERT policy
-- for authenticated users is needed or granted.
-- No UPDATE or DELETE policy anywhere — immutable, append-only.

GRANT ALL ON public.audit_logs TO service_role;

-- Verification — run after applying.
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'audit_logs';

SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'audit_logs'
GROUP BY table_name, grantee;
```

- [ ] **Step 2: Apply the migration** to the project's Supabase instance (via the Supabase SQL
  editor or CLI, matching however prior migrations in this repo were applied — check
  `ziren_backend/supabase/` for a `config.toml` / README noting the method before assuming CLI
  access). Run the two verification `SELECT`s at the bottom and confirm `rowsecurity = true` and
  a `service_role` row with `INSERT, SELECT, UPDATE, DELETE` privileges.

- [ ] **Step 3: Add `require_super_admin` and `assert_agency_scope` to `dependencies.py`** —
  additive, appended after `require_approved_responder`, not a refactor of anything existing:

```python
require_super_admin = require_role("super_admin")


def assert_agency_scope(current_user: dict, agency_id: str) -> None:
    """
    Raise HTTP 403 if an agency_admin is trying to act outside their own
    agency. super_admin is always permitted.

    New shared version for routers added after this point (audit, agencies,
    analytics, geographic, governance, ai_classification). Existing
    per-router copies (_assert_agency_write_scope in stations.py,
    _assert_agency_scope in rubric.py) are NOT touched — they work, and
    consolidating them is a separate, lower-value refactor.
    """
    if current_user.get("role") == "super_admin":
        return
    if str(current_user.get("agency_id") or "") != str(agency_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only act on your own agency's records.",
        )
```

- [ ] **Step 4: Write `app/services/audit_service.py`**:

```python
"""
audit_service — the single write-path for administrative audit trail rows.

Every mutation a Super Admin or Agency Admin makes to a managed resource
(station, account, rubric config, system config, announcement) calls
record() here instead of (or in addition to) structlog. This is what the
Audit Logs module (#10) and System Governance's Configuration History
(#11) read, and it is also how Notifications (#15) get most of their
content: a NOTIFY_ACTIONS entry fans a row out to the given roles' inboxes.
"""

from typing import Any

import structlog

from app.db.supabase_client import get_supabase
from app.services import notification_service

log = structlog.get_logger()

# action -> roles to notify. Absent action = audit-only, no notification.
NOTIFY_ACTIONS: dict[str, tuple[str, ...]] = {
    "station.created":            ("super_admin",),
    "station.deactivated":        ("super_admin",),
    "agency_admin.created":       ("super_admin",),
    "agency_admin.assigned":      ("super_admin",),
    "account.suspended":          ("super_admin",),
    "account.deactivated":        ("super_admin",),
    "account.reactivated":        ("super_admin",),
    "verification.approved":      ("super_admin",),
    "verification.rejected":      ("super_admin",),
    "rubric.activated":           ("super_admin",),
    "system_config.updated":      ("super_admin",),
    "announcement.published":     ("agency_admin", "super_admin"),
}


def record(
    *,
    actor: dict,
    action: str,
    target_type: str,
    target_id: str | None = None,
    target_label: str | None = None,
    previous: dict | None = None,
    new: dict | None = None,
    metadata: dict | None = None,
) -> dict:
    """
    Insert one audit_logs row. Never raises — a failed audit write must not
    fail the operation it is describing; it logs via structlog instead so
    the gap is at least visible in the server log.
    """
    db = get_supabase()
    payload = {
        "actor_id":       str(actor.get("id")) if actor.get("id") else None,
        "actor_role":     actor.get("role"),
        "actor_name":     actor.get("full_name"),
        "action":         action,
        "target_type":    target_type,
        "target_id":      str(target_id) if target_id is not None else None,
        "target_label":   target_label,
        "previous_value": previous,
        "new_value":      new,
        "metadata":       metadata,
    }
    try:
        result = db.table("audit_logs").insert(payload).execute()
        row = (result.data or [payload])[0]
    except Exception:
        log.error("audit_service.write_failed", action=action, target_type=target_type, target_id=target_id, exc_info=True)
        return payload

    roles = NOTIFY_ACTIONS.get(action)
    if roles:
        try:
            notification_service.create_for_roles(
                roles=roles,
                type_=action,
                title=_notify_title(action, target_label or target_id or ""),
                body=metadata.get("notify_body") if metadata else None,
                link=metadata.get("notify_link") if metadata else None,
                exclude_user_id=str(actor.get("id")) if actor.get("id") else None,
            )
        except Exception:
            log.error("audit_service.notify_failed", action=action, exc_info=True)

    return row


def _notify_title(action: str, label: str) -> str:
    verb = action.split(".")[-1].replace("_", " ")
    noun = action.split(".")[0].replace("_", " ")
    return f"{noun.capitalize()} {verb}: {label}" if label else f"{noun.capitalize()} {verb}"
```

- [ ] **Step 5: Write `app/routers/audit.py`**:

```python
"""GET /audit-logs — Super Admin's system-wide administrative audit trail."""

import structlog
from fastapi import APIRouter, Depends, Query

from app.core.dependencies import require_super_admin
from app.db.supabase_client import get_supabase

log = structlog.get_logger()
router = APIRouter()


@router.get("/")
def list_audit_logs(
    actor_id: str | None = Query(None),
    target_type: str | None = Query(None),
    action: str | None = Query(None),
    date_from: str | None = Query(None, description="ISO date, inclusive"),
    date_to: str | None = Query(None, description="ISO date, inclusive"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(require_super_admin),
):
    db = get_supabase()
    query = db.table("audit_logs").select("*", count="exact").order("created_at", desc=True)
    if actor_id:
        query = query.eq("actor_id", actor_id)
    if target_type:
        query = query.eq("target_type", target_type)
    if action:
        query = query.eq("action", action)
    if date_from:
        query = query.gte("created_at", date_from)
    if date_to:
        query = query.lte("created_at", date_to)
    result = query.range(offset, offset + limit - 1).execute()
    return {"items": result.data or [], "total": result.count or 0}
```

- [ ] **Step 6: Register the router in `app/main.py`** — find where `rubric.router` or
  `stations.router` is `include_router`'d and add `app.include_router(audit.router, prefix="/audit-logs", tags=["audit"])` alongside it, importing `from app.routers import audit`.

- [ ] **Step 7: Write `tests/test_audit_service.py`** — mock `get_supabase` at the module level,
  assert `record()` inserts the right payload shape and calls `notification_service.create_for_roles`
  when `action` is in `NOTIFY_ACTIONS`, and does NOT call it otherwise. Assert `record()` swallows
  an exception from `db.table(...).insert(...).execute()` and logs rather than raising.

- [ ] **Step 8: Write `tests/test_audit_router.py`** — following `test_responder_dashboard.py`'s
  `_call` pattern, assert `GET /audit-logs/` 403s for `agency_admin` and `resident`, 200s for
  `super_admin`, and that query params are forwarded to the correct Supabase filter chain calls.

- [ ] **Step 9: Run `pytest ziren_backend/tests/test_audit_service.py ziren_backend/tests/test_audit_router.py -v`** and confirm all pass. (`notification_service` doesn't exist yet — stub it as an empty module with `create_for_roles(**kwargs): pass` for now; Task 9 replaces it with the real implementation and re-runs these tests.)

- [ ] **Step 10: Commit.**

```bash
git add ziren_backend/supabase/migrations ziren_backend/app/services/audit_service.py ziren_backend/app/routers/audit.py ziren_backend/app/main.py ziren_backend/app/core/dependencies.py ziren_backend/tests/test_audit_service.py ziren_backend/tests/test_audit_router.py
git commit -m "feat(backend): add general-purpose audit_logs table and audit_service"
```

---

## Task 2: Restructure the sidebar nav to the target Super Admin IA

**Files:**
- Modify: `ziren_dashboard/lib/nav/nav-config.ts` (full rewrite of the `NAV` array and `NavRole`)
- Test: none (this file has no existing test; if the repo gains one, add
  `ziren_dashboard/lib/nav/nav-config.test.ts` covering `getNavGroups` for both roles)

**Interfaces:**
- Produces: the same exports (`NavRole`, `NavItem`, `NavGroup`, `getNavGroups`, `isItemActive`,
  `isItemExpanded`) with an unchanged signature — every later task that adds a page adds one
  `NavItem` to this file rather than re-deriving the nav model.

- [ ] **Step 1: Replace the `NAV` array** with the target IA from the spec. Routes not yet built
  by later tasks are added here anyway (matching the existing convention of "everything here
  already exists" — by the time this file is committed as final in Task 20, they will). Import
  additional icons as needed (`LayoutDashboard`/`Radar` for Dashboard, `Siren` for Incident
  Monitoring, `MapPinned` for Incident Map, `LineChart` for Analytics, `Globe2` for Geographic
  Overview, `UserCog` for Accounts, `Building2` for Agencies, `ScanFace` for Verification,
  `Scale` for System Governance, `BrainCircuit` for AI & Classification, `ClipboardList` for
  Audit Logs, `Activity` for System Status, `Bell` for Notifications, `Megaphone` for
  Announcements, `FileDown` for Reports & Export, `Settings` for Settings):

```typescript
export interface NavRole {
  isSuperAdmin: boolean;
  isAgencyAdmin: boolean;
}

const NAV: NavGroup[] = [
  {
    label: 'Overview',
    items: [
      { href: '/overview', label: 'Dashboard', icon: Radar },
    ],
  },
  {
    label: 'Monitoring',
    items: [
      { href: '/incidents', label: 'Incident Monitoring', icon: Siren, matchNested: true },
      { href: '/map', label: 'Incident Map', icon: MapPinned },
      { href: '/analytics', label: 'System Analytics', icon: LineChart, visible: r => r.isSuperAdmin },
      { href: '/geographic', label: 'Geographic Overview', icon: Globe2, visible: r => r.isSuperAdmin },
    ],
  },
  {
    label: 'Management',
    items: [
      { href: '/accounts', label: 'Accounts', icon: UserCog, matchNested: true, visible: r => r.isSuperAdmin },
      { href: '/agencies', label: 'Agencies', icon: Building2, matchNested: true, visible: r => r.isSuperAdmin },
      { href: '/responders', label: 'Responders', icon: Users, matchNested: true, visible: r => r.isAgencyAdmin },
      { href: '/verification', label: 'Verification', icon: ScanFace, matchNested: true, visible: r => r.isAgencyAdmin || r.isSuperAdmin },
    ],
  },
  {
    label: 'Governance',
    items: [
      { href: '/governance', label: r => r.isSuperAdmin ? 'System Governance' : 'Severity Configuration', icon: Scale, matchNested: true },
      { href: '/ai-classification', label: 'AI & Classification', icon: BrainCircuit, visible: r => r.isSuperAdmin },
      { href: '/audit-logs', label: 'Audit Logs', icon: ClipboardList, visible: r => r.isSuperAdmin },
      { href: '/system-status', label: 'System Status', icon: Activity, visible: r => r.isSuperAdmin },
    ],
  },
  {
    label: 'Communication',
    items: [
      { href: '/announcements', label: 'Announcements', icon: Megaphone, visible: r => r.isSuperAdmin },
      { href: '/reports', label: 'Reports & Export', icon: FileDown, visible: r => r.isSuperAdmin },
    ],
  },
  {
    label: 'Personal',
    items: [
      { href: '/settings', label: 'Settings', icon: Settings },
    ],
  },
];
```

  `label` as a function of role (for the `/governance` item) is a **new capability** `NavItem`
  doesn't have today — update the interface:

```typescript
export interface NavItem {
  href: string;
  label: string | ((role: NavRole) => string);
  icon: LucideIcon;
  visible?: (role: NavRole) => boolean;
  children?: NavItem[];
  matchNested?: boolean;
}
```

  and in `getNavGroups`, resolve it: `label: typeof item.label === 'function' ? item.label(role) : item.label`. Every consumer of `NavItem.label` (`ziren-sidebar.tsx`) already renders `item.label` as a plain string in JSX — after `getNavGroups` resolves the function, the shape it returns is unchanged, so `ziren-sidebar.tsx` needs no edit for this.

  Drop `/coverage` entirely from the nav (superseded by Task 8's Agencies module + Task 7's
  Geographic Overview) — do not add a nav item for it.

- [ ] **Step 2: Update `getNavGroups`** to resolve function-typed labels as shown above.

- [ ] **Step 3: `npx tsc --noEmit` in `ziren_dashboard/`** and fix any type errors (this will
  surface every consumer of `NavItem` that assumed `label: string` — check
  `ziren-sidebar.tsx` doesn't destructure `item.label` before `getNavGroups` resolves it; it
  currently reads groups from `getNavGroups(role)` and never sees a `NavItem` before resolution,
  so it should be unaffected, but verify).

- [ ] **Step 4: Manual check** — this task creates nav entries for pages that don't exist yet
  (`/analytics`, `/geographic`, `/agencies`, `/governance`, `/ai-classification`, `/audit-logs`,
  `/system-status`, `/announcements`, `/reports`). That's intentional (later tasks build them)
  but means the app will 404 on those links until then. Note in the PR/commit description which
  tasks close each gap, and do not deploy this alone to production — it's fine mid-plan in a
  branch.

- [ ] **Step 5: Commit.**

```bash
git add ziren_dashboard/lib/nav/nav-config.ts
git commit -m "feat(dashboard): restructure sidebar nav to the Super Admin target IA"
```

---

## Task 3: Sidebar logo size + Sign-Out confirmation (quick wins, fully independent)

**Files:**
- Modify: `ziren_dashboard/components/shell/ziren-sidebar.tsx`
- Modify: `ziren_dashboard/components/shell/ziren-header.tsx`
- Test: none existing for either file; skip adding one (both are presentational — cover by the
  visual verification checkpoint below, not unit tests).

**Interfaces:**
- Consumes: `AlertDialog`, `AlertDialogTrigger`, `AlertDialogContent`, `AlertDialogHeader`,
  `AlertDialogTitle`, `AlertDialogDescription`, `AlertDialogFooter`, `AlertDialogCancel`,
  `AlertDialogAction` from `@/components/efferd/ui/alert-dialog` (already exists in the repo —
  read that file first to confirm its exact export names before writing the import).

- [ ] **Step 1: Sidebar logo** — in `ziren-sidebar.tsx`, change `<ZirenLogo priority size={24} />`
  to `<ZirenLogo priority size={32} />`. Re-check the surrounding `SidebarHeader` classes
  (`h-14 justify-center`) still look right at the new size when you hit the visual checkpoint
  below — bump `h-14` to `h-16` if the mark now clips or crowds the wordmark next to it.

- [ ] **Step 2: Sign-out confirmation** — in `ziren-header.tsx`, read the full file first (only
  lines 150-200 were seen during planning) to find where `user.onSignOut` is defined/passed in
  and the imports block. Replace the direct-call `DropdownMenuItem`:

```tsx
<DropdownMenuItem onClick={user.onSignOut}>
  <LogOut />
  Sign out
</DropdownMenuItem>
```

  with an `AlertDialog` wrapping a `DropdownMenuItem` that does NOT auto-close the dropdown into
  a lost click (Radix dropdown items close their menu on click before a nested dialog can open,
  which is a known interaction — the fix is `onSelect={(e) => e.preventDefault()}` on the item so
  the menu stays mounted long enough for the dialog trigger to fire):

```tsx
<AlertDialog>
  <AlertDialogTrigger asChild>
    <DropdownMenuItem onSelect={e => e.preventDefault()}>
      <LogOut />
      Sign out
    </DropdownMenuItem>
  </AlertDialogTrigger>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Sign Out?</AlertDialogTitle>
      <AlertDialogDescription>
        Are you sure you want to sign out of your Ziren account?
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel>Cancel</AlertDialogCancel>
      <AlertDialogAction onClick={user.onSignOut}>Sign Out</AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

  Add the import line for the `alert-dialog` primitives at the top of the file.

- [ ] **Step 3: `npx tsc --noEmit`** in `ziren_dashboard/` to confirm no type errors from the new
  JSX / import.

- [ ] **Step 4: Visual verification checkpoint** — using the `ziren-dev` skill's
  sessionStorage-seed approach, load the dashboard as a super_admin and: confirm the logo reads
  clearly at the new size without crowding the wordmark or the collapse toggle; open the account
  menu and click "Sign out"; confirm the confirmation dialog appears with the exact copy above
  and that "Cancel" closes it without signing out, while "Sign Out" actually calls `signOut()`
  and lands on `/login`.

- [ ] **Step 5: Commit.**

```bash
git add ziren_dashboard/components/shell/ziren-sidebar.tsx ziren_dashboard/components/shell/ziren-header.tsx
git commit -m "feat(dashboard): larger sidebar logo and sign-out confirmation dialog"
```

---

## Task 4: `notification_service` + `notifications` table + notification center

Builds the real bell/notification center (#15), which `audit_service` (Task 1) already calls
into via `NOTIFY_ACTIONS`.

**Files:**
- Create: `ziren_backend/supabase/migrations/<N+2>_notifications.sql`
- Create: `ziren_backend/app/services/notification_service.py` (replaces the Task 1 stub)
- Create: `ziren_backend/app/routers/notifications.py`
- Modify: `ziren_backend/app/main.py` (register router)
- Test: `ziren_backend/tests/test_notifications.py`
- Create: `ziren_dashboard/lib/api/notifications.ts`
- Modify: `ziren_dashboard/components/shell/ziren-header.tsx` (wire the existing bell icon to
  real data)
- Create: `ziren_dashboard/components/shell/notification-center.tsx` (the dropdown panel)

**Interfaces:**
- Produces: `notification_service.create_for_roles(*, roles: tuple[str, ...], type_: str, title: str, body: str | None = None, link: str | None = None, exclude_user_id: str | None = None) -> None` — looks up every user with `role IN roles`, inserts one `notifications` row per recipient (excluding `exclude_user_id`, so an actor doesn't get notified of their own action).
- Produces: `notification_service.list_for_user(user_id: str, *, unread_only: bool = False, limit: int = 50, offset: int = 0) -> dict` → `{items: [...], total: int, unread_count: int}`.
- Produces: `notification_service.mark_read(user_id: str, notification_id: str) -> dict`.
- Produces: `notification_service.mark_all_read(user_id: str) -> int` (count updated).
- Produces: `GET /notifications/` , `PATCH /notifications/{id}/read`, `PATCH /notifications/read-all`, `GET /notifications/unread-count` — all `Depends(get_current_user)` (any authenticated role reads their own).
- Produces (frontend): `fetchNotifications(token)`, `markNotificationRead(id, token)`, `markAllNotificationsRead(token)`, `fetchUnreadCount(token)` in `lib/api/notifications.ts`, typed against a `NotificationItem` interface `{id, type, title, body, is_important, is_read, link, created_at}`.
- Consumes: `ziren-header.tsx`'s existing bell `Button`/badge markup (found via `unreadCount` stub during the survey) — replace the stub state with real polling.

- [ ] **Step 1: Migration** `<N+2>_notifications.sql`:

```sql
CREATE TABLE IF NOT EXISTS public.notifications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type         TEXT NOT NULL,
    title        TEXT NOT NULL,
    body         TEXT,
    is_important BOOLEAN NOT NULL DEFAULT FALSE,
    is_read      BOOLEAN NOT NULL DEFAULT FALSE,
    link         TEXT,
    metadata     JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notifications_recipient_unread_idx
    ON public.notifications(recipient_id, is_read, created_at DESC);

COMMENT ON TABLE public.notifications IS
    'Per-user notification feed. Written by notification_service.create_for_roles(), '
    'called mostly from audit_service.record() via NOTIFY_ACTIONS.';

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications: recipient reads own"
    ON public.notifications FOR SELECT
    USING (recipient_id = auth.uid());

CREATE POLICY "notifications: recipient updates own (read state)"
    ON public.notifications FOR UPDATE
    USING (recipient_id = auth.uid());

GRANT ALL ON public.notifications TO service_role;

SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'notifications';
SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'notifications' GROUP BY table_name, grantee;
```

- [ ] **Step 2: Apply the migration**, run the verification queries.

- [ ] **Step 3: Write `app/services/notification_service.py`** implementing the four functions
  in Interfaces above. `create_for_roles` does: `db.table("users").select("id").in_("role", list(roles)).execute()`, then filters out `exclude_user_id`, then a single batched `db.table("notifications").insert([...]).execute()` with one dict per remaining recipient (`recipient_id`, `type`, `title`, `body`, `link`, `metadata=None`, `is_important=False`).

- [ ] **Step 4: Write `app/routers/notifications.py`** — 4 routes per Interfaces, all
  `Depends(get_current_user)`, every query filtered to `.eq("recipient_id", current_user["id"])`
  so a user can never read or mark another user's notifications regardless of the RLS
  fallback layer.

- [ ] **Step 5: Register in `main.py`**, mirroring Task 1 Step 6.

- [ ] **Step 6: Write `tests/test_notifications.py`** — cover: `create_for_roles` excludes the
  actor, inserts one row per matching-role user; `GET /notifications/` returns only the caller's
  rows; `PATCH /notifications/{id}/read` 404s for a notification belonging to someone else (not
  a 403 — don't leak existence).

- [ ] **Step 7: Re-run Task 1's tests** (`test_audit_service.py`) now that the real
  `notification_service` exists instead of the stub — confirm they still pass unmodified (they
  should, since the stub and the real module expose the same `create_for_roles` signature).

- [ ] **Step 8: Frontend — `lib/api/notifications.ts`**:

```typescript
import { apiClient } from './client';

export interface NotificationItem {
  id: string;
  type: string;
  title: string;
  body: string | null;
  is_important: boolean;
  is_read: boolean;
  link: string | null;
  created_at: string;
}

export const fetchNotifications = (token: string, unreadOnly = false) =>
  apiClient.get<{ items: NotificationItem[]; total: number; unread_count: number }>(
    `/notifications/?unread_only=${unreadOnly}`, token,
  );

export const markNotificationRead = (id: string, token: string) =>
  apiClient.patch<NotificationItem>(`/notifications/${id}/read`, {}, token);

export const markAllNotificationsRead = (token: string) =>
  apiClient.patch<{ updated: number }>('/notifications/read-all', {}, token);

export const fetchUnreadCount = (token: string) =>
  apiClient.get<{ unread_count: number }>('/notifications/unread-count', token);
```

- [ ] **Step 9: Frontend — `components/shell/notification-center.tsx`** — a dropdown (reuse
  `DropdownMenu` from `components/efferd/ui/dropdown-menu`, matching the pattern already used for
  the account menu in `ziren-header.tsx`) listing up to 20 recent notifications, an unread dot per
  item, "Mark all read" action, each item's `onClick` calls `markNotificationRead` then navigates
  to `link` if present. Poll `fetchUnreadCount` every 30s (same `setInterval` pattern as
  `useIncidentAlerts`'s `POLL_MS`, but far less latency-sensitive — 30s not 10s) via a small
  `useNotifications(token)` hook colocated in the same file or a new
  `lib/hooks/useNotifications.ts` if it grows past ~40 lines.

- [ ] **Step 10: Wire it into `ziren-header.tsx`** — replace whatever produces the current static
  `unreadCount` badge with `<NotificationCenter token={token} />`, removing the now-dead stub
  state.

- [ ] **Step 11: `npx tsc --noEmit`**, then visual checkpoint: seed a super_admin session, trigger
  one `NOTIFY_ACTIONS` event from the backend (easiest: call `POST /stations/` to create a test
  station, which fires `station.created`) and confirm a notification appears in the bell within
  30s with the right title, and that clicking it marks it read (badge count decrements).

- [ ] **Step 12: Commit.**

```bash
git add ziren_backend/supabase/migrations ziren_backend/app/services/notification_service.py ziren_backend/app/routers/notifications.py ziren_backend/app/main.py ziren_backend/tests/test_notifications.py ziren_dashboard/lib/api/notifications.ts ziren_dashboard/components/shell/notification-center.tsx ziren_dashboard/components/shell/ziren-header.tsx
git commit -m "feat: functional notification center backed by a real notifications table"
```

---

## Task 5: Wire `audit_service.record()` into existing mutation endpoints

Now that Tasks 1+4 exist, go back through the routers that already perform the actions in
`NOTIFY_ACTIONS` and add the `record()` call at each site — this is what actually populates
Audit Logs and Notifications; without this step they exist but stay empty.

**Files:**
- Modify: `ziren_backend/app/routers/stations.py` (`create_station`, `deactivate_station`)
- Modify: `ziren_backend/app/services/user_service.py` (agency admin creation, account
  suspend/deactivate/reactivate — exact function names TBD by reading the file; grep for
  `def create_agency_admin`, `def suspend`, `def deactivate`, `def reactivate` first)
- Modify: `ziren_backend/app/routers/rubric.py` (`activate` endpoint)
- Test: extend the existing test files for each of the above rather than creating new ones —
  e.g. add one assertion to `tests/test_station_resolution.py` or a new
  `test_stations_audit.py` if that file is about resolution logic, not station CRUD (check
  before deciding).

**Interfaces:**
- Consumes: `audit_service.record` from Task 1.

- [ ] **Step 1: `stations.py` — `create_station`**, right after the successful insert and before
  the existing `log.info("super_admin.station_created", ...)` call, add:

```python
from app.services import audit_service
...
audit_service.record(
    actor=current_user,
    action="station.created",
    target_type="station",
    target_id=result.data[0]["id"],
    target_label=result.data[0].get("name"),
    new=payload,
    metadata={"notify_body": f"New station '{body.name}' added to agency {agency_check.data['name']}."},
)
```

  Do not remove the existing `structlog` call — both stay; `audit_service` is the durable,
  queryable record, `structlog` is the operational log.

- [ ] **Step 2: `stations.py` — `deactivate_station`**, same pattern with
  `action="station.deactivated"`, `previous={"is_active": True}`, `new={"is_active": False}`.

- [ ] **Step 3: `user_service.py`** — find the agency-admin creation function (likely
  `create_agency_admin` per the `/super/agency-admins` route from the survey) and the
  suspend/deactivate/reactivate functions for accounts. Add `audit_service.record(...)` calls
  with `action` values `"agency_admin.created"`, `"account.suspended"`, `"account.deactivated"`,
  `"account.reactivated"` respectively, `target_type="user"`, `target_id=<the affected user's
  id>`, `target_label=<their full_name or email>`. For suspend/deactivate/reactivate, populate
  `previous`/`new` with the `{"approval_status": ..., "is_verified": ...}` or whatever field
  actually flips — read the function body first to know the real field name(s) before writing
  the call.

- [ ] **Step 4: `rubric.py` — the `activate` endpoint**, add `audit_service.record(action="rubric.activated", target_type="rubric_config", target_id=<version id>, target_label=f"{agency_type} v{version}", previous={"version": <old active version, if fetched>}, new={"version": version})`. This is in addition to the existing `rubric_audit_log` write in `rubric_service.py` — do not remove that; it stays as the rubric engine's own append-only record. This adds the SAME event to the general trail too, so Audit Logs (#10) shows rubric activations alongside station/account changes without querying two tables.

- [ ] **Step 5: Run the full backend test suite** (`cd ziren_backend && python -m pytest -q`) —
  confirm nothing in the untouched 30+ existing test files broke. These functions already have
  tests mocking their Supabase calls; adding an `audit_service.record()` call means those tests'
  mocked `db` object now also needs `db.table("audit_logs").insert(...).execute()` and
  `db.table("users").select(...).in_(...).execute()` (for the notification fan-out) to not
  explode on an unmocked `MagicMock` chain — `MagicMock()` auto-mocks arbitrary attribute access,
  so this typically works with zero test changes, but verify by actually running them, not by
  assuming it.

- [ ] **Step 6: Manually trigger each action** against a local backend (or via the visual
  checkpoint browser session) and confirm a row lands in `audit_logs` and, where applicable, in
  `notifications` for existing super_admin accounts.

- [ ] **Step 7: Commit.**

```bash
git add ziren_backend/app/routers/stations.py ziren_backend/app/services/user_service.py ziren_backend/app/routers/rubric.py
git commit -m "feat(backend): record audit trail entries at existing mutation sites"
```

---

## Task 6: Incident Monitoring — relabel + read-only enforcement (mostly frontend)

The backend already does almost all of this: `dispatch.py`'s `_admin_read` dependency already
lets `super_admin` read `/dispatch/queue`, `/dispatch/history`, and `/dispatch/queue/{id}` across
**every** agency, and the mutating routes (`assign`/`override`/`resolve`/`cancel`) are already
`_dispatcher = require_role("agency_admin")`-only — a `super_admin` bearer token already gets a
403 from those today. This task is the frontend catching up to what the API already enforces.

**Files:**
- Modify: `ziren_dashboard/components/incidents/active-view.tsx`
- Modify: `ziren_dashboard/components/incidents/incident-row.tsx`
- Modify: `ziren_dashboard/components/incidents/incident-detail-modal.tsx`
- Modify: `ziren_dashboard/app/(dashboard)/incidents/page.tsx` (page heading text)
- Test: none new — this is presentational conditional rendering; cover at the visual checkpoint.

**Interfaces:**
- Consumes: `useAuth().isSuperAdmin` (already exists) threaded down as a prop, e.g.
  `readOnly={isSuperAdmin}`, into `active-view.tsx` → `incident-row.tsx` /
  `incident-detail-modal.tsx`.

- [ ] **Step 1: Read all three component files in full first** — they were modified recently
  (per `git status`) for an unrelated change, so re-derive their current prop shape before
  editing rather than trusting the survey summary.

- [ ] **Step 2: Page heading** — in `app/(dashboard)/incidents/page.tsx`, make the `<h1>` (or
  equivalent) text conditional: `isSuperAdmin ? 'Incident Monitoring' : 'Incidents'`. Nav label
  already says "Incident Monitoring" for everyone from Task 2 — spec section 3 only requires the
  *Super Admin's* view to read that way; re-check the spec if this should differ for Agency Admin
  (spec doesn't actually require Agency Admin's copy to change, so leaving the nav label uniform
  and only branching the in-page heading is the minimal, correct reading — do not over-rename
  Agency Admin's page).

- [ ] **Step 3: Hide/disable actions** — in `active-view.tsx`/`incident-row.tsx`, wrap whatever
  renders the Assign/Override/Resolve/Cancel buttons or menu items in `{!isSuperAdmin && (...)}`.
  Do not just `disabled` them with the button still visible — the spec says Super Admin should
  not see dispatch as an available action at all, and a visible-but-disabled button invites a
  "why can't I click this" support question a hidden one doesn't.

- [ ] **Step 4: `incident-detail-modal.tsx`** — same treatment for any inline assign/resolve
  controls; keep all *read* fields (reporter, station/agency, severity, timestamps, dispatch
  history, responder info) visible and unchanged for both roles — the spec explicitly wants the
  full field list visible to Super Admin, just not the write actions.

- [ ] **Step 5: Status label mapping** — add a small pure function (colocate in
  `ziren_dashboard/lib/utils/incident-status.ts`, new file) mapping the backend's
  `IncidentStatus` values to the spec's display vocabulary, per the MVP cut noted in Global
  Constraints:

```typescript
export type DisplayIncidentStatus =
  | 'Pending' | 'Under Verification' | 'In Progress' | 'Resolved' | 'Cancelled';

export function toDisplayStatus(status: string): DisplayIncidentStatus {
  switch (status) {
    case 'received':   return 'Pending';
    case 'processing': return 'Under Verification';
    case 'dispatched': return 'In Progress';
    case 'resolved':   return 'Resolved';
    case 'cancelled':  return 'Cancelled';
    default:           return 'Pending';
  }
}
```

  Use this ONLY in Super-Admin-facing surfaces (Incident Monitoring, Incident Map, System
  Analytics, Reports) — Agency Admin's existing incident views keep showing whatever status
  copy they show today; do not change Agency Admin's working UI as a side effect of this
  function existing.

- [ ] **Step 6: `npx tsc --noEmit`**, then visual checkpoint as both roles: confirm agency_admin
  still sees and can use Assign/Resolve/Cancel exactly as before (regression check — this is the
  one that must not break), and super_admin sees the full incident list/detail with those actions
  absent and status labels using the new display mapping.

- [ ] **Step 7: Commit.**

```bash
git add ziren_dashboard/components/incidents ziren_dashboard/app/\(dashboard\)/incidents/page.tsx ziren_dashboard/lib/utils/incident-status.ts
git commit -m "feat(dashboard): Super Admin gets read-only Incident Monitoring, Agency Admin unchanged"
```

---

## Task 7: Verification — extend beyond residents to stations, agency admins, responders

**Files:**
- Modify: `ziren_backend/app/services/user_service.py` (generalize the resident-only
  verification query functions, or add sibling functions — read the existing
  `/verification/residents*` implementation first to decide whether to parametrize by role or
  add `list_pending_agency_admins`, `list_pending_responders`, `list_pending_stations` as
  separate functions; separate functions are almost certainly cleaner here since a station
  "registration" and a resident ID/liveness check share almost no fields)
- Modify: `ziren_backend/app/routers/users.py` (new routes; keep existing
  `/verification/residents*` routes untouched)
- Test: extend `ziren_backend/tests/test_access_request.py` or add
  `ziren_backend/tests/test_verification_expanded.py`
- Modify: `ziren_dashboard/app/(dashboard)/verification/page.tsx` (add tabs: Residents |
  Agency Stations | Agency Admins | Responders)
- Modify: `ziren_dashboard/lib/api/` — add a `verification.ts` if the current calls are inline,
  or extend the existing one (check first)

**Interfaces:**
- Produces: `GET /users/verification/stations` — super_admin only; returns newly-created
  stations awaiting nothing today (stations are active immediately per `create_station` in
  Task-untouched `stations.py`) — **reconsider before building this**: re-read
  `stations.py::create_station`; if it sets `is_active=True` unconditionally with no pending
  state, there is no station "registration queue" to verify, and this sub-tab should instead
  show *stations created in the last N days* as a review/audit list, not an approve/reject
  queue. Do not invent a `pending` status on stations that doesn't exist in the schema — that
  would require its own migration and contradicts spec section 6, which frames station creation
  as something the Super Admin *does*, not approves.
- Produces: `GET /users/verification/agency-admins` — agency admins created via
  `/super/agency-admins` go through Supabase invite + `/accept-invite`; check whether
  `user_service` already tracks an "invite accepted" vs "invite pending" state on these rows
  (likely via `approval_status` or a null `password`/auth state) — expose that as the
  verification list rather than inventing new state.
- Produces: `GET /users/verification/responders`, reusing `ApprovalStatus` (`pending` is
  already a real value for responders per `require_approved_responder`) — this one is
  straightforward: `db.table("users").select(...).eq("role", "responder").eq("approval_status", "pending")`, mirroring the resident list function's shape (reuse its `bulk-decide` pattern:
  `POST /users/verification/responders/decide`).
- Consumes: whatever `apiClient.get/post` wrapper the current verification page uses — match it.

- [ ] **Step 1: Read `ziren_backend/app/services/user_service.py` and
  `ziren_backend/app/routers/users.py` end to end** for the current `/verification/residents*`
  implementation (list, get, bulk-decide, patch) — this task's shape must mirror it exactly for
  residents to stay working, and to know the real field names before writing sibling functions.

- [ ] **Step 2: Read `ziren_backend/app/routers/users.py`'s `/super/agency-admins*` and
  `/super/access-requests*`** — agency admin "verification" may already effectively be the
  existing access-request approve/reject flow (an Agency Admin's access request IS their
  verification). If so, this sub-task is "surface the existing access-requests list under the
  Verification page's Agency Admins tab" rather than new backend work — confirm this before
  writing new endpoints; do not duplicate `/super/access-requests` under a new path.

- [ ] **Step 3: For responders** (the one genuinely new list, per Step 1's finding that
  `approval_status='pending'` already exists and is enforced by `require_approved_responder`),
  write `list_pending_responders()` in `user_service.py` and `decide_responders()` (bulk
  approve/reject, setting `approval_status`), mirroring the resident bulk-decide function's
  signature and validation.

- [ ] **Step 4: Add routes to `users.py`**: `GET /verification/responders`,
  `POST /verification/responders/decide` — `Depends(require_role("agency_admin", "super_admin"))`
  with an `assert_agency_scope` check for `agency_admin` (a responder's `agency_id` must match
  the caller's, unless the caller is `super_admin`), reusing the shared helper from Task 1. Each
  decision calls `audit_service.record(action="verification.approved" | "verification.rejected", target_type="user", target_id=responder_id, ...)`.

- [ ] **Step 5: Write tests** covering: `super_admin` sees responders across all agencies,
  `agency_admin` sees only their own agency's, a decide call updates `approval_status` and
  writes an audit row.

- [ ] **Step 6: Frontend — `verification/page.tsx``** — read the full current file (1056 lines
  per the survey) before editing. Add a tab strip (reuse whatever `Tabs` primitive the codebase
  already uses elsewhere — check `components/efferd/ui/tabs.tsx`) with "Residents" (existing
  behavior, unchanged), "Agency Admins" (Step 2's finding — likely just the existing
  access-requests UI moved/duplicated under this tab), "Responders" (new, calling Step 4's
  routes). If Step 1/2's findings mean there is genuinely nothing to show for "Agency Station
  registrations" (per the Step-3-adjacent note above), render that tab with an explanatory empty
  state ("Stations are created directly by Super Admins under Agencies — no separate
  verification step.") rather than a fake queue — an honest empty state beats invented data.

- [ ] **Step 7: `npx tsc --noEmit`**, visual checkpoint as both `agency_admin` and `super_admin`:
  confirm Residents tab behavior is byte-identical to before this task, and the new tabs load
  without error.

- [ ] **Step 8: Commit.**

```bash
git add ziren_backend/app/services/user_service.py ziren_backend/app/routers/users.py ziren_backend/tests ziren_dashboard/app/\(dashboard\)/verification
git commit -m "feat: extend Verification to agency admins and responders alongside residents"
```

---

## Task 8: Agency Management module (extract from Coverage, add personnel/activity views)

**Files:**
- Create: `ziren_dashboard/app/(dashboard)/agencies/page.tsx` (list: BFP/PNP/MDRRMO → stations)
- Create: `ziren_dashboard/app/(dashboard)/agencies/[stationId]/page.tsx` (station detail: info,
  status, personnel, activity, coverage boundary editor — the polygon editor UI moves here from
  `/coverage`, function preserved)
- Create: `ziren_dashboard/lib/api/agencies.ts`
- Modify: `ziren_backend/app/routers/stations.py` — add `GET /{station_id}/personnel` (roster of
  responders + the assigned agency admin at that station) and `GET /{station_id}/activity`
  (recent incidents/dispatch_log entries for that station's agency, paginated) — both
  `_admin_only` with `assert_agency_scope`.
- Delete: `ziren_dashboard/app/(dashboard)/coverage/page.tsx` (after confirming its polygon
  editor component is extracted, not just deleted — see Step 2)
- Test: `ziren_backend/tests/test_stations_personnel.py`

**Interfaces:**
- Produces: `GET /stations/{id}/personnel` → `{agency_admin: {...} | null, responders: [...]}`
- Produces: `GET /stations/{id}/activity?days=30&limit=20` → `{items: [...], total: int}` (reuse
  the shape `dispatch_service.get_incident_history` already returns, filtered to this station's
  `agency_id` — call that service function rather than writing new query logic if its signature
  allows an agency filter; check `get_incident_history`'s params before deciding to reuse vs.
  write a thin new query).
- Consumes: existing `POST /stations/`, `PATCH /stations/{id}/deactivate`,
  `PATCH /stations/{id}/coverage`, `PATCH /stations/{id}/location`,
  `PATCH /stations/agencies/{id}` (agency profile), `POST /users/super/agency-admins` (create
  agency admin) — all already exist; this task's frontend calls them from a new page, no
  backend changes needed for these five.

- [ ] **Step 1: Read `ziren_dashboard/app/(dashboard)/coverage/page.tsx` in full.** Identify
  every piece of UI it renders: (a) the polygon boundary editor over the map, (b) the station
  roster/CRUD list (per its own doc comments noted in the survey), (c) anything else. This task
  keeps (a) and (b)'s *functionality* but re-homes it — Coverage Areas as a standalone concept is
  removed per spec section 8, but the ability to draw/edit an agency's coverage polygon (which
  `incidents.py`'s `/coverage-check` depends on operationally) must not be lost.

- [ ] **Step 2: Extract the polygon editor** into its own component,
  `ziren_dashboard/components/agencies/coverage-boundary-editor.tsx`, taking `agencyId` and the
  current `coverage_area` as props and calling `PATCH /stations/{id}/coverage` on save — pure
  extraction, no behavior change, so it can be reused inside the new station detail page.

- [ ] **Step 3: Backend — `stations.py` additions.** Read `dispatch_service.get_incident_history`'s
  signature (seen in the earlier grep: `def get_incident_history(...)`) to see if it already
  accepts an agency filter; if yes, `GET /stations/{id}/activity` is a thin wrapper resolving
  `station_id → agency_id` then calling it. Write `GET /stations/{id}/personnel`:

```python
@router.get("/{station_id}/personnel")
def get_station_personnel(
    station_id: str,
    current_user: dict = _admin_only,
):
    db = get_supabase()
    station = db.table("stations").select("id, agency_id").eq("id", station_id).single().execute()
    if not station.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found.")
    agency_id = str(station.data["agency_id"])
    _assert_agency_write_scope(current_user, agency_id)

    admins = (
        db.table("users").select("id, full_name, email, approval_status")
        .eq("agency_id", agency_id).eq("role", "agency_admin").execute()
    ).data or []
    responders = (
        db.table("users").select("id, full_name, badge_id, approval_status, is_verified")
        .eq("agency_id", agency_id).eq("role", "responder").execute()
    ).data or []
    return {"agency_admins": admins, "responders": responders}
```

  (Note: this queries by `agency_id`, not `station_id` — re-check whether `users` has a
  `station_id` column distinct from `agency_id`; the survey only confirmed `agency_id` on
  `users`. If personnel are only tracked per-agency, not per-station, say so plainly in the UI —
  "Personnel across all of {agency_name}'s stations" — rather than implying a per-station
  breakdown the data can't support.)

- [ ] **Step 4: Frontend — `lib/api/agencies.ts`** wraps: `fetchStations`, `fetchStation`,
  `createStation`, `deactivateStation`, `updateStationLocation`, `updateCoverage`,
  `fetchAgencyProfile`, `updateAgencyProfile`, `createAgencyAdmin` (existing endpoint from
  `users.py`), `fetchStationPersonnel`, `fetchStationActivity` — typed wrappers around
  `apiClient`, one function per endpoint, matching the style in
  `ziren_dashboard/lib/api/dispatch.ts`.

- [ ] **Step 5: `app/(dashboard)/agencies/page.tsx`** — three sections (BFP/PNP/MDRRMO), each
  listing its stations (name, municipality, active/inactive badge, assigned agency admin's name)
  with a "New Station" action (super_admin only — matches `_super_admin_only` on
  `POST /stations/`) opening a form calling `createStation`. Row click → `/agencies/[stationId]`.

- [ ] **Step 6: `app/(dashboard)/agencies/[stationId]/page.tsx`** — station info card
  (editable via `updateStationLocation`/`updateAgencyProfile`), status toggle
  (activate/deactivate, calling `deactivateStation` — note there's no `reactivate` endpoint per
  the survey; if the spec's "Activate a station" has no backend counterpart, either add
  `PATCH /stations/{id}/activate` mirroring `deactivate_station` exactly, or flag it in the
  commit message as a gap for a follow-up task — prefer adding the endpoint, it's a 15-line
  mirror of existing code), `CoverageBoundaryEditor` from Step 2, personnel list (Step 3's
  endpoint), activity feed (Step 3's endpoint), and an "Assign/Replace Agency Admin" action
  calling `createAgencyAdmin` or a new `PATCH /users/super/agency-admins/{id}` reassignment if
  one already exists (check `users.py`'s `/super/agency-admins*` PATCH route from the survey
  before assuming you need to add one).

- [ ] **Step 7: If Step 6 needed a new `PATCH /stations/{id}/activate`**, add it to
  `stations.py` mirroring `deactivate_station`, call `audit_service.record(action="station.activated" ...)` — note this isn't in `NOTIFY_ACTIONS` from Task 1; either add it there too (small
  edit to Task 1's dict) or leave it audit-only, your call, but be consistent with
  `station.deactivated` which IS notified — asymmetry there would be a real inconsistency worth
  avoiding, so add `"station.activated": ("super_admin",)` to `NOTIFY_ACTIONS`.

- [ ] **Step 8: Delete `coverage/page.tsx`** and its nav entry (already dropped from
  `nav-config.ts` in Task 2) — but only after confirming in the visual checkpoint that
  `/agencies/[stationId]` fully replaces its capability. Do NOT delete
  `components/agencies/coverage-boundary-editor.tsx`'s dependencies (the underlying map/polygon
  drawing library code) if `coverage/page.tsx` was the only consumer and Step 2 already
  extracted what's needed — check for orphaned imports with a quick grep before deleting the old
  page file's directory.

- [ ] **Step 9: Backend tests** — `test_stations_personnel.py` covering the new
  `/personnel` and `/activity` endpoints' role/scope enforcement.

- [ ] **Step 10: `npx tsc --noEmit`, run backend tests, visual checkpoint** as super_admin:
  create a station, view its detail page, edit its coverage polygon, view personnel/activity,
  deactivate then reactivate it. As agency_admin: confirm they can still edit their own agency's
  coverage/location (existing capability) but cannot reach `/agencies` (nav-gated to super_admin
  in Task 2) and get a 403 if they hit `POST /stations/` directly.

- [ ] **Step 11: Commit.**

```bash
git add ziren_dashboard/app/\(dashboard\)/agencies ziren_dashboard/components/agencies ziren_dashboard/lib/api/agencies.ts ziren_backend/app/routers/stations.py ziren_backend/tests/test_stations_personnel.py
git rm -r ziren_dashboard/app/\(dashboard\)/coverage
git commit -m "feat: Agency Management module, retiring the standalone Coverage Areas page"
```

---

## Task 9: Accounts — geographic residents tree + responder station assignment

**Files:**
- Modify: `ziren_dashboard/app/(dashboard)/accounts/page.tsx` (921 lines — read in full first)
- Modify: `ziren_backend/app/routers/users.py` (extend the residents listing to support
  `municipality`/`barangay` filters if it doesn't already — check the existing
  `/super/directory` or resident-listing endpoint's query params first)
- Test: extend whatever test currently covers `/super/directory` or add
  `ziren_backend/tests/test_accounts_geo_filter.py`

**Interfaces:**
- Produces (if not already present): `GET /users/super/directory?role=resident&municipality=&barangay=&q=` — confirm current params by reading the router before adding; do not add a duplicate query param under a different name for the same filter.
- Produces: `GET /barangays` (per the survey, this already exists — reuse it to populate the
  Municipality → Barangay picker instead of hardcoding a list).

- [ ] **Step 1: Read `accounts/page.tsx` in full** and the `/super/directory` +
  `/barangays` endpoints in `users.py`. Determine exactly what filtering already works
  client-side vs. server-side today.

- [ ] **Step 2: Add municipality/barangay filter UI** to the Residents tab: two cascading
  `Select`s (municipality first, populated from distinct `barangays.municipality` values or a
  fixed Biliran municipality list if one already exists in the codebase — grep for
  `"Naval"` or `"Biliran"` municipality constants before inventing a new list), then barangay
  (from `/barangays` filtered by the chosen municipality), applied as query params to the
  existing directory fetch.

- [ ] **Step 3: If the backend doesn't already support these filters server-side**, add
  `municipality: str | None` / `barangay_id: str | None` query params to the relevant
  `users.py` route and corresponding `.eq(...)` / join filter in `user_service.py` — do this
  only if Step 1 showed it's missing; if client-side filtering over an already-fetched full list
  is what exists today and the resident count is small (check: is there pagination already?),
  extending server-side filtering is still preferable for correctness at scale, but note in the
  commit if you chose to keep client-side filtering for now because pagination doesn't exist yet
  and adding both in one task is too large — splitting that into a follow-up is fine, just say so.

- [ ] **Step 4: Responder "assign to station" action** — per spec section 5. Check whether
  `PATCH /users/agency/responders/{id}` (or similar, from the `/agency/responders*` routes noted
  in the survey) already supports changing `agency_id`, given migration `014` is literally titled
  "responder_agency_reassignment". If that migration already built this, this step is "surface
  the existing capability in the Accounts page's Responders tab for a super_admin", not new
  backend work — read migration `014` and its router support before writing anything.

- [ ] **Step 5: `npx tsc --noEmit`, backend tests if any were added, visual checkpoint** — filter
  residents by municipality then barangay and confirm the list narrows correctly; reassign a
  responder's station and confirm it persists.

- [ ] **Step 6: Commit.**

```bash
git add ziren_dashboard/app/\(dashboard\)/accounts/page.tsx ziren_backend/app/routers/users.py ziren_backend/app/services/user_service.py
git commit -m "feat: geographic filtering for Residents and station reassignment in Accounts"
```

---

## Task 10: Incident Map — Super Admin's two-view map (Network / History), no routes

**Files:**
- Modify: `ziren_dashboard/components/map/ZirenMap.tsx` (branch rendering by role — read the
  full 643-line file first)
- Modify: `ziren_dashboard/app/(dashboard)/map/page.tsx`
- Modify: `ziren_backend/app/routers/map.py` (extend `GET /map/data` with a `view` param, or add
  a second endpoint — decide after reading the current implementation)
- Test: extend whatever test file covers `map.py` today, or add `test_map_views.py`

**Interfaces:**
- Produces: `GET /map/data?view=network` → residents (coarse location or barangay centroid —
  check what location data residents actually have; do NOT expose a resident's exact home
  address on a map layer without checking whether that's already how `/map/data` behaves for
  agency_admin today — if it already returns resident points, this task just adds filters; if
  it doesn't, do not add exact resident geolocation as a NEW exposure without flagging it as a
  privacy decision for the user to confirm), agency stations, responders (current position, if
  already tracked — `responder.location` per migration `011` was mentioned in the survey).
  Filterable by `municipality`, `barangay`, `account_type`, `agency`, `station` — query params.
- Produces: `GET /map/data?view=history` → resolved/completed/historical incidents only
  (`status IN ('resolved','cancelled')`), explicitly NO route/path geometry in the response for
  this view.
- Consumes: existing `GET /map/data` behavior for `agency_admin` — must be completely unchanged
  when `view` param is absent or the caller is not `super_admin`.

- [ ] **Step 1: Read `ziren_backend/app/routers/map.py` and its service function in full.**
  Determine current response shape and whether resident points are already included.

- [ ] **Step 2: Read `ZirenMap.tsx` in full**, identify where operational route rendering (line
  from incident to responding station) is drawn, so it can be conditionally suppressed for
  `super_admin`'s history view without touching the agency_admin operational path.

- [ ] **Step 3: Backend — add the `view` param**, defaulting to today's existing behavior when
  absent (so agency_admin's current map call, which won't send `view`, is byte-identical).
  `view=network`: query `stations`, on-duty `responders` (existing on-duty query pattern from
  `dispatch_service.get_available_responders`, generalized to "all agencies" for super_admin),
  and residents (only if already exposed — see the flag in Interfaces above; if not currently
  exposed, add resident points scoped to barangay-level centroid, not exact address, and note
  this privacy choice explicitly in the PR description). `view=history`: query
  `incidents` where `status IN ('resolved', 'cancelled')`, joined to station/agency, explicitly
  omitting any route/path field.

- [ ] **Step 4: Frontend — `map/page.tsx``** — for `isSuperAdmin`, render a view toggle
  ("Network" / "History") above the map, each calling `GET /map/data?view=...` with the
  filter controls (municipality/barangay/account-type/agency/station selects) from spec section
  7A. For non-super-admin, render exactly what exists today (no toggle, no `view` param sent).

- [ ] **Step 5: `ZirenMap.tsx``** — accept a `showRoutes: boolean` prop (default `true` to match
  current behavior), only drawing the incident→station line when `true`; the Super Admin history
  view passes `showRoutes={false}`.

- [ ] **Step 6: Tests + visual checkpoint** — confirm agency_admin's map is pixel-for-pixel
  unchanged (same data, same routes drawn), then super_admin sees both views, filters work, and
  no route lines appear in the history view.

- [ ] **Step 7: Commit.**

```bash
git add ziren_backend/app/routers/map.py ziren_dashboard/components/map/ZirenMap.tsx ziren_dashboard/app/\(dashboard\)/map/page.tsx
git commit -m "feat: Super Admin Network/History map views alongside the unchanged operational map"
```

---

## Task 11: Geographic Overview (new page + backend aggregation)

**Files:**
- Create: `ziren_backend/app/services/geographic_service.py`
- Create: `ziren_backend/app/routers/geographic.py`
- Modify: `ziren_backend/app/main.py`
- Create: `ziren_dashboard/app/(dashboard)/geographic/page.tsx`
- Create: `ziren_dashboard/lib/api/geographic.ts`
- Test: `ziren_backend/tests/test_geographic.py`

**Interfaces:**
- Produces: `geographic_service.get_overview(municipality: str, barangay: str | None) -> dict`
  → `{registered_residents: int, registered_responders: int, agency_stations: [...], nearby_agencies: [...], incident_count: int, incident_types: dict[str, int], resolved_incidents: int, active_incidents: int, historical_activity: [{month: str, count: int}]}`. Pulled with plain Python aggregation over `users`, `stations`/`agencies`, and `incidents` filtered by `barangay_id`/`municipality` — no new SQL functions; fetch the relevant rows (id, barangay_id, created_at, status for incidents; role, barangay_id for users) and use `collections.Counter` in Python. This project's data volume (one province) makes in-process aggregation reasonable; do not introduce a new Postgres RPC function for this.
- Produces: `GET /geographic/overview?municipality=X&barangay=Y` (super_admin only).
- Produces: `GET /geographic/municipalities` → distinct municipality list (from `barangays` or `agencies`, whichever is authoritative — check which table has the canonical municipality list before picking one).

- [ ] **Step 1: Write `geographic_service.get_overview`** — fetch `barangays` row for the given
  barangay (or all barangays in the municipality if `barangay` is omitted) to resolve
  `barangay_id`(s); then:
  - `db.table("users").select("id, role").eq("role", "resident").in_("barangay_id", ids)` → count
  - `db.table("users").select("id, agency_id").eq("role", "responder")` joined via each
    responder's agency's `municipality` field (responders don't have `barangay_id` per the
    `UserProfile` model — they're tied to an agency, not a residence — so "registered
    responders" for a geographic area means responders whose agency serves that municipality;
    state this interpretation in a code comment since it's a judgment call, not an obvious fact)
  - `db.table("stations").select(...).eq/agencies.municipality` for stations + nearby agencies
  - `db.table("incidents").select("id, status, incident_category, created_at, location_address")` filtered by matching barangay/municipality text or station's agency municipality (incidents don't carry `barangay_id` directly per the `IncidentResponse` model seen earlier — they have `location_address` free text and a `station_id`; the most reliable join is via the assigned station's agency municipality, not string-matching `location_address` — use that, and note the limitation that this attributes an incident to "the municipality of the station that handled it", not necessarily where it physically occurred, since precise geocoding per barangay isn't in the current schema)
  - Aggregate `incident_types` via `Counter(i["incident_category"] for i in rows)`,
    `resolved_incidents`/`active_incidents` via status membership, `historical_activity` by
    `Counter(i["created_at"][:7] for i in rows)` (year-month buckets).

- [ ] **Step 2: Router** — `geographic.py` with the two routes, `Depends(require_super_admin)`.

- [ ] **Step 3: Register in `main.py`.**

- [ ] **Step 4: Tests** — mock the three table fetches, assert the aggregation math on a small
  fixed fixture (e.g. 3 residents, 2 responders, 5 incidents with known categories/statuses) and
  check every returned count matches by hand-computed expectation.

- [ ] **Step 5: Frontend** — `lib/api/geographic.ts` wraps both routes;
  `geographic/page.tsx` renders a Municipality → Barangay cascading picker (reuse the pattern
  from Task 9 Step 2) and, on selection, the counts/breakdowns as stat cards + a small bar
  chart for `incident_types` and a line for `historical_activity` (reuse existing chart
  components under `components/charts/` if their prop shapes fit — check
  `category-mix-chart.tsx` and `incident-volume-chart.tsx` before writing new chart components).

- [ ] **Step 6: `npx tsc --noEmit`, run backend tests, visual checkpoint.**

- [ ] **Step 7: Commit.**

```bash
git add ziren_backend/app/services/geographic_service.py ziren_backend/app/routers/geographic.py ziren_backend/app/main.py ziren_backend/tests/test_geographic.py ziren_dashboard/app/\(dashboard\)/geographic ziren_dashboard/lib/api/geographic.ts
git commit -m "feat: Geographic Overview module replacing removed Coverage Areas"
```

---

## Task 12: System Analytics (new page + backend aggregation)

**Files:**
- Create: `ziren_backend/app/services/analytics_service.py`
- Create: `ziren_backend/app/routers/analytics.py`
- Modify: `ziren_backend/app/main.py`
- Create: `ziren_dashboard/app/(dashboard)/analytics/page.tsx`
- Create: `ziren_dashboard/lib/api/analytics.ts`
- Test: `ziren_backend/tests/test_analytics.py`

**Interfaces:**
- Produces: `analytics_service.incident_analytics(period: str, date_from: str | None, date_to: str | None) -> dict` — `period` in `{"day","month","year"}` controls bucket granularity for a time series; returns `{by_period: [{bucket, count}], by_municipality: {...}, by_barangay: {...}, by_agency: {...}, by_type: {...}, resolved_vs_unresolved: {resolved, unresolved}, avg_resolution_minutes: float | None, frequency_trend: [...]}`.
- Produces: `analytics_service.user_analytics() -> dict` — registration trend per role over time (bucketed by month from `users.created_at`), growth by municipality/barangay.
- Produces: `analytics_service.agency_analytics() -> dict` — per-agency: incidents handled, resolution rate (`resolved / total`), avg response time (time from `created_at` to `dispatched_at`), avg resolution time (`created_at` to `resolved_at`), completed vs cancelled counts. Reuse `dispatch_service.get_incident_activity`'s underlying query shape (it already returns lifecycle timestamps + status + agency per the router docstring) rather than re-querying `incidents` from scratch — check if it can be called with a wide `days` window or if a new unbounded query is cleaner; prefer reuse if the function signature allows `days=3650` without breaking its own contract, otherwise write a dedicated query.
- Produces: `GET /analytics/incidents`, `GET /analytics/users`, `GET /analytics/agencies` — all `require_super_admin`.

- [ ] **Step 1: Write `analytics_service.py`** implementing the three functions above, all via
  Python aggregation (`collections.Counter`/`defaultdict`) over fetched rows — same rationale as
  Task 11, no new SQL functions. For `avg_resolution_minutes`, compute
  `(resolved_at - created_at).total_seconds() / 60` per resolved incident and average; guard
  against `None` timestamps.

- [ ] **Step 2: Router + registration**, mirroring Task 11.

- [ ] **Step 3: Tests** — fixed fixture of incidents/users with known timestamps and statuses;
  assert every computed aggregate against hand-calculated values, including the
  avg-resolution-time math and at least one empty-dataset case (no incidents in range → `avg_resolution_minutes: None`, not a division-by-zero crash).

- [ ] **Step 4: Frontend** — `analytics/page.tsx` with three tabs (Incident / User / Agency
  Analytics) matching the spec's three sub-sections, each with a period selector
  (day/month/year) for the incident tab and reusing existing chart components where their prop
  shapes fit, adding new ones under `components/charts/` only for chart types that don't already
  exist (e.g. a resolution-rate bar-per-agency chart, if `agency-share-chart.tsx` doesn't already
  do this — check first).

- [ ] **Step 5: `npx tsc --noEmit`, run backend tests, visual checkpoint.**

- [ ] **Step 6: Commit.**

```bash
git add ziren_backend/app/services/analytics_service.py ziren_backend/app/routers/analytics.py ziren_backend/app/main.py ziren_backend/tests/test_analytics.py ziren_dashboard/app/\(dashboard\)/analytics ziren_dashboard/lib/api/analytics.ts
git commit -m "feat: System Analytics module — incident, user, and agency trend analysis"
```

---

## Task 13: System Governance (rename + expand Rubric Config) + AI & Classification Monitoring

**Files:**
- Rename/modify: `ziren_dashboard/app/(dashboard)/rubric/page.tsx` →
  `ziren_dashboard/app/(dashboard)/governance/page.tsx` (and `rubric/[agency]/page.tsx` →
  `governance/severity/[agency]/page.tsx`, or keep the dynamic segment at
  `governance/[agency]/page.tsx` if that reads better against the existing routing — pick one
  and keep it consistent with how the page links to itself)
- Create: `ziren_backend/supabase/migrations/<N+3>_system_config.sql`
- Create: `ziren_backend/app/services/governance_service.py`
- Create: `ziren_backend/app/routers/governance.py`
- Create: `ziren_backend/app/services/ai_monitoring_service.py`
- Create: `ziren_backend/app/routers/ai_monitoring.py`
- Create: `ziren_dashboard/app/(dashboard)/ai-classification/page.tsx`
- Modify: `ziren_backend/app/main.py`
- Test: `ziren_backend/tests/test_governance.py`, `ziren_backend/tests/test_ai_monitoring.py`

**Interfaces:**
- Produces: `system_config` table — `key TEXT PRIMARY KEY, value JSONB, description TEXT, updated_by UUID, updated_at TIMESTAMPTZ`. Seed rows via migration `INSERT ... ON CONFLICT (key) DO NOTHING`: `account_policies` (`{"require_id_verification": true, "auto_suspend_after_inactive_days": null}`), `notification_policies` (`{"system_alerts": true, "admin_notifications": true, "incident_alerts": true}`).
- Produces: `GET /governance/incident-configuration` → read-only: the live `IncidentCategory` and `IncidentStatus` enum values from `app/models/incident.py` (introspect via `[e.value for e in IncidentCategory]`, do not hardcode a second copy that can drift) — labelled clearly in the UI as "defined in code, not editable here" per the MVP cut in Global Constraints.
- Produces: `GET /governance/severity-configuration` → thin wrapper listing agencies with a link to each's existing `rubric.py` config UI (no new severity logic — this reuses `rubric.py` entirely).
- Produces: `GET /governance/account-policies`, `PATCH /governance/account-policies`, `GET /governance/notification-policies`, `PATCH /governance/notification-policies` — read/write `system_config` rows by key; every `PATCH` calls `audit_service.record(action="system_config.updated", target_type="system_config", target_id=key, previous=<old value>, new=<new value>)`.
- Produces: `GET /governance/configuration-history` → thin wrapper over `GET /audit-logs/?target_type=system_config` UNION conceptually with rubric activations (`action=rubric.activated`, already flowing into `audit_logs` since Task 5) — simplest implementation: call `audit_service`'s own table with `action IN ("system_config.updated", "rubric.activated")` rather than building a second query path.
- Produces: `ai_monitoring_service.get_stats() -> dict` — reads `app/ml/VERSION` file for `model_version`; queries `incidents.signals` JSONB for `model_confidence`, `verification_status`, `engine_version` across all incidents with a non-null `signals->>'engine'`; returns `{model_version, model_status: "active", total_classifications: int, confidence_distribution: {"0.0-0.5": n, "0.5-0.7": n, "0.7-0.9": n, "0.9-1.0": n}, verification_breakdown: {"AGREE": n, "MISMATCH_FLAGGED": n, "UNCERTAIN": n, "NO_SELECTION": n, "NO_TEXT": n}, sample_corrections: [{predicted, user_selected, result}, ...]}` (last 20, most recent first) — this is real data from the existing `TriageSignals` payload already stored per incident, not a new pipeline.
- Produces: `GET /ai-classification/stats` → calls the above, `require_super_admin`.

- [ ] **Step 1: Migration `<N+3>_system_config.sql`** — table + RLS (super_admin read/write via
  service_role, same GRANT pattern as Tasks 1 and 4) + the two seed `INSERT`s. Apply and verify.

- [ ] **Step 2: `governance_service.py` + `governance.py` router** implementing the 6 routes in
  Interfaces. The incident-configuration route literally does
  `from app.models.incident import IncidentCategory, IncidentStatus` and returns their `.value`
  lists plus static descriptive labels — no database query needed for that one route.

- [ ] **Step 3: `ai_monitoring_service.py`** — fetch
  `db.table("incidents").select("signals").not_.is_("signals", "null").execute()`, then in
  Python: filter to rows where `signals.get("engine")` is truthy, bucket
  `signals.get("model_confidence")` into the 4 ranges above, `Counter` on
  `signals.get("verification_status")`, and for `sample_corrections` take the last 20 by whatever
  ordering is available (if `signals` alone doesn't carry a timestamp, join against the
  incident's own `created_at` by selecting `id, created_at, signals` instead of `signals` alone).
  Read `app/ml/VERSION` with a plain `open(...).read().strip()`, wrapped in try/except
  `FileNotFoundError` → `model_version: "unknown"` rather than crashing the whole endpoint over a
  missing version file.

- [ ] **Step 4: `ai_monitoring.py` router** — one route, `require_super_admin`.

- [ ] **Step 5: Register both routers in `main.py`.**

- [ ] **Step 6: Tests** for both new services — `test_governance.py` covers policy read/write +
  audit trail write on PATCH; `test_ai_monitoring.py` covers the bucketing/counting math against
  a fixed fixture of incidents with known `signals` payloads, including at least one incident
  with `signals: null` (must be excluded, not crash) and one with `engine: null` but
  `signals` present (must also be excluded from `total_classifications` — a non-AI-assisted
  report with an empty `signals` shell should not count as an AI classification).

- [ ] **Step 7: Frontend — rename `rubric/` → `governance/`.** Read the current
  `rubric/page.tsx` and `rubric/[agency]/page.tsx` in full before moving anything (they're the
  live, working severity-editing UI — do not lose functionality in the rename). Restructure as
  tabs: "Severity Configuration" (the existing rubric list/edit UI, unchanged internals, just
  re-hosted), "Incident Configuration" (new, read-only display of Step 2's data), "Account
  Policies" (new form bound to Step 2's account-policies route), "Notification Policies" (same
  pattern), "Configuration History" (new, a filtered view of the Audit Logs list from Task 1,
  reusing whatever table component Task 14 builds for the full Audit Logs page — if Task 14
  hasn't landed yet when this task executes, build a minimal inline table here and have Task 14
  extract a shared `AuditLogTable` component instead of duplicating table markup twice; note this
  dependency explicitly when sequencing these two tasks). For `agency_admin`, per Task 2's nav
  label logic, only the "Severity Configuration" tab is visible/reachable — the other four tabs
  are Super-Admin-only content, hidden via the same `isSuperAdmin` check pattern used everywhere
  else in this plan, not a separate route.

- [ ] **Step 8: Update every existing internal link/redirect that pointed at `/rubric`** (grep
  the whole `ziren_dashboard/` tree for `'/rubric'` string literals — likely in
  `nav-config.ts` — Task 2 already updated `nav-config.ts` — and possibly in
  `incident-detail-modal.tsx` if it links out to a rubric config page) to point at `/governance`.

- [ ] **Step 9: `ai-classification/page.tsx`** — stat cards for `total_classifications`,
  `model_version`/`model_status`, a bar chart for `confidence_distribution`, a breakdown table
  for `verification_breakdown`, and a recent-corrections table from `sample_corrections`
  (columns: AI Prediction, Human/Resident Selection, Result — colored green for `AGREE`, amber
  for `UNCERTAIN`, red for `MISMATCH_FLAGGED`, matching this project's existing severity-color
  conventions rather than inventing a new palette — check `project_ziren_design_tokens` memory
  for the right hues to reuse).

- [ ] **Step 10: `npx tsc --noEmit`, run backend tests, visual checkpoint** as both roles —
  confirm agency_admin's severity-editing workflow at the new `/governance` URL works exactly as
  `/rubric` did, and super_admin sees all five tabs plus the separate AI & Classification page.

- [ ] **Step 11: Commit.**

```bash
git add ziren_backend/supabase/migrations ziren_backend/app/services/governance_service.py ziren_backend/app/routers/governance.py ziren_backend/app/services/ai_monitoring_service.py ziren_backend/app/routers/ai_monitoring.py ziren_backend/app/main.py ziren_backend/tests/test_governance.py ziren_backend/tests/test_ai_monitoring.py
git add ziren_dashboard/app/\(dashboard\)/governance ziren_dashboard/app/\(dashboard\)/ai-classification
git rm -r ziren_dashboard/app/\(dashboard\)/rubric
git commit -m "feat: System Governance (renamed from Rubric Config) + AI & Classification Monitoring"
```

---

## Task 14: Audit Logs page (frontend) + shared `AuditLogTable` component

**Files:**
- Create: `ziren_dashboard/app/(dashboard)/audit-logs/page.tsx`
- Create: `ziren_dashboard/components/audit/audit-log-table.tsx` (shared with Task 13 Step 7's
  Configuration History tab — if Task 13 already built an inline table, refactor it to use this
  component instead of leaving two copies)
- Create: `ziren_dashboard/lib/api/audit.ts`

**Interfaces:**
- Consumes: `GET /audit-logs/` from Task 1.
- Produces: `<AuditLogTable items={AuditLogEntry[]} />` — columns: Date & Time, User (actor_name
  + actor_role), Action, Target (target_type + target_label), with an expandable row or a
  "View diff" action showing `previous_value`/`new_value` as a simple JSON diff (a two-column
  before/after, not a full diffing library — this data is small, structured JSON, not prose).

- [ ] **Step 1: `lib/api/audit.ts`** — typed wrapper around `GET /audit-logs/` with the filter
  params from Task 1's route.

- [ ] **Step 2: `components/audit/audit-log-table.tsx`** as described in Interfaces.

- [ ] **Step 3: `app/(dashboard)/audit-logs/page.tsx`** — filter bar (actor, target type, action,
  date range — reuse whatever date-range picker component already exists in the codebase, check
  `components/ui/` before adding a new one) + `AuditLogTable` + pagination (the route already
  returns `{items, total}` for this).

- [ ] **Step 4: If Task 13 already shipped with an inline table for Configuration History**,
  refactor that tab to import and use `AuditLogTable` with a `target_type=system_config` /
  `action=rubric.activated` filter baked in, deleting the duplicated markup.

- [ ] **Step 5: `npx tsc --noEmit`, visual checkpoint** — confirm filters narrow results
  correctly and pagination works past the first page (requires enough seed data; if the local/
  dev database has fewer than `limit` rows, trigger a few more actions from earlier tasks to get
  past one page for this check).

- [ ] **Step 6: Commit.**

```bash
git add ziren_dashboard/app/\(dashboard\)/audit-logs ziren_dashboard/components/audit ziren_dashboard/lib/api/audit.ts
git commit -m "feat: Audit Logs page with shared AuditLogTable component"
```

---

## Task 15: System Status

**Files:**
- Create: `ziren_backend/app/services/system_status_service.py`
- Create: `ziren_backend/app/routers/system_status.py`
- Modify: `ziren_backend/app/main.py`
- Create: `ziren_dashboard/app/(dashboard)/system-status/page.tsx`
- Create: `ziren_dashboard/lib/api/system-status.ts`
- Test: `ziren_backend/tests/test_system_status.py`

**Interfaces:**
- Produces: `system_status_service.check_all() -> list[dict]` — one `{name, status: "operational"|"down", latency_ms: float, detail: str | None}` per component: Authentication, Database, Incident Service, Notification Service, Map Service, AI/NLP Service, File Storage, Realtime Services. Each check wrapped in its own try/except so one failing component doesn't take down the whole endpoint or hide the others' results.
- Produces: `GET /system-status/` (super_admin only — or arguably any admin; spec frames it as a Super Admin feature, keep it `require_super_admin` for consistency with the rest of Governance).

- [ ] **Step 1: Write `system_status_service.py`** with one small function per component,
  each timed and try/excepted individually:

```python
import time
from pathlib import Path

from app.db.supabase_client import get_supabase


def _timed(fn) -> dict:
    start = time.perf_counter()
    try:
        fn()
        return {"status": "operational", "latency_ms": round((time.perf_counter() - start) * 1000, 1), "detail": None}
    except Exception as exc:
        return {"status": "down", "latency_ms": round((time.perf_counter() - start) * 1000, 1), "detail": str(exc)[:200]}


def check_all() -> list[dict]:
    db = get_supabase()
    checks = [
        ("Authentication",       lambda: db.auth.admin.list_users(page=1, per_page=1)),
        ("Database",             lambda: db.table("users").select("id").limit(1).execute()),
        ("Incident Service",     lambda: db.table("incidents").select("id").limit(1).execute()),
        ("Notification Service", lambda: db.table("notifications").select("id").limit(1).execute()),
        ("Map Service",          lambda: db.table("stations").select("id").limit(1).execute()),
        ("File Storage",         lambda: db.storage.list_buckets()),
        # Realtime piggybacks on the DB check per the MVP cut in Global Constraints —
        # there is no cheap synchronous websocket probe available here.
        ("Realtime Services",    lambda: db.table("incidents").select("id").limit(1).execute()),
        ("AI/NLP Service",       lambda: _check_ml_artifacts()),
    ]
    return [{"name": name, **_timed(fn)} for name, fn in checks]


def _check_ml_artifacts() -> None:
    version_file = Path(__file__).resolve().parents[1] / "ml" / "VERSION"
    if not version_file.exists():
        raise FileNotFoundError("app/ml/VERSION not found")
```

  (Confirm the actual path to `app/ml/VERSION` relative to this new file before trusting
  `parents[1]` — adjust to match the real directory depth once you've located it with
  `find ziren_backend/app/ml -name VERSION` or equivalent.)

- [ ] **Step 2: Router + registration**, `require_super_admin`.

- [ ] **Step 3: Tests** — mock each `db.table(...)`/`db.storage`/`db.auth.admin` call, assert
  one failing check reports `"down"` while the rest still report `"operational"` in the same
  response (this is the behavior worth testing — a single try/except per check, not one around
  the whole list).

- [ ] **Step 4: Frontend** — `system-status/page.tsx` renders a card grid, one per component,
  green dot + "Operational" or red dot + "Down" + the `detail` message when down, plus latency
  in small text. Poll every 60s (this is the least time-sensitive page in the whole plan — no
  need for `useIncidentAlerts`-style aggressive polling).

- [ ] **Step 5: `npx tsc --noEmit`, run backend tests, visual checkpoint** — confirm all 8 show
  operational against a healthy local backend.

- [ ] **Step 6: Commit.**

```bash
git add ziren_backend/app/services/system_status_service.py ziren_backend/app/routers/system_status.py ziren_backend/app/main.py ziren_backend/tests/test_system_status.py ziren_dashboard/app/\(dashboard\)/system-status ziren_dashboard/lib/api/system-status.ts
git commit -m "feat: System Status page with real per-service health checks"
```

---

## Task 16: Announcements

**Files:**
- Create: `ziren_backend/supabase/migrations/<N+4>_announcements.sql`
- Create: `ziren_backend/app/services/announcement_service.py`
- Create: `ziren_backend/app/routers/announcements.py`
- Modify: `ziren_backend/app/main.py`
- Create: `ziren_dashboard/app/(dashboard)/announcements/page.tsx`
- Create: `ziren_dashboard/lib/api/announcements.ts`
- Test: `ziren_backend/tests/test_announcements.py`

**Interfaces:**
- Produces: `announcements` + `announcement_reads` tables (schema below).
- Produces: `announcement_service.publish(actor, *, title, body, category, target_type, target_agency_id=None, expires_at=None) -> dict` — inserts the announcement, then fans out via `notification_service.create_for_roles` (or a targeted variant — see Step 3) and calls `audit_service.record(action="announcement.published", ...)`.
- Produces: `announcement_service.list_for_user(user: dict) -> list[dict]` — announcements where `target_type='all'` OR `target_type` matches the user's role OR (`target_type='agency'` AND `target_agency_id = user.agency_id`), `is_active=True`, not expired.
- Produces: `GET /announcements/` (any authenticated role — filtered to what applies to them via `list_for_user`), `POST /announcements/` (super_admin only), `PATCH /announcements/{id}/deactivate` (super_admin only).

- [ ] **Step 1: Migration** `<N+4>_announcements.sql`:

```sql
CREATE TABLE IF NOT EXISTS public.announcements (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title             TEXT NOT NULL,
    body              TEXT NOT NULL,
    category          TEXT NOT NULL CHECK (category IN
                          ('maintenance','emergency','service_interruption','feature','reminder','general')),
    target_type       TEXT NOT NULL CHECK (target_type IN
                          ('all','agency_admin','responder','resident','agency')),
    target_agency_id  UUID REFERENCES public.agencies(id) ON DELETE CASCADE,
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_by        UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at        TIMESTAMPTZ,

    CONSTRAINT announcements_agency_target_requires_agency_id
        CHECK (target_type != 'agency' OR target_agency_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS announcements_active_idx ON public.announcements(is_active, created_at DESC);

CREATE TABLE IF NOT EXISTS public.announcement_reads (
    announcement_id UUID NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    read_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (announcement_id, user_id)
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_reads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "announcements: everyone reads active" ON public.announcements
    FOR SELECT USING (is_active = TRUE);

CREATE POLICY "announcements: super_admin full read" ON public.announcements
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'super_admin')
    );

CREATE POLICY "announcement_reads: user manages own" ON public.announcement_reads
    FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

GRANT ALL ON public.announcements TO service_role;
GRANT ALL ON public.announcement_reads TO service_role;

SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('announcements','announcement_reads');
SELECT table_name, grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name IN ('announcements','announcement_reads') GROUP BY table_name, grantee;
```

  Note `target_type` values here are singular role names (`agency_admin`, not `agency_admins`)
  to match `UserRole` enum values exactly — makes the `list_for_user` filter a direct
  `target_type = current_user['role']` comparison instead of a plural-to-singular mapping.

- [ ] **Step 2: Apply migration, verify.**

- [ ] **Step 3: `announcement_service.py`** — `publish()` inserts the row, then targets
  notifications precisely: if `target_type == 'all'`, notify all four roles; if it names a
  specific role, notify only that role; if `target_type == 'agency'`, notify only users with
  that `agency_id` (this needs a small addition to `notification_service` —
  `create_for_agency(agency_id, ...)` mirroring `create_for_roles` — add it there rather than
  overloading `create_for_roles` with an incompatible parameter). `list_for_user()` implements
  the OR-filter from Interfaces.

- [ ] **Step 4: Router** — 3 routes per Interfaces; `POST /announcements/` body validated by a
  Pydantic model matching `publish()`'s kwargs.

- [ ] **Step 5: Register in `main.py`.**

- [ ] **Step 6: Tests** — `publish()` with each `target_type` fans out to the right recipient
  set (mock `notification_service.create_for_roles`/`create_for_agency` and assert call args);
  `list_for_user()` returns the right subset for a resident vs. an agency_admin at a specific
  agency vs. a responder at a different agency (must NOT see an `agency`-targeted announcement
  for an agency they don't belong to).

- [ ] **Step 7: Frontend** — `announcements/page.tsx`: for `super_admin`, a "Publish" form
  (title, body, category select, target-type select with a conditional agency picker when
  `target_type='agency'`) above a list of past announcements with a "Deactivate" action; for
  every other role, a read-only feed of announcements that apply to them (this page is reachable
  by everyone per spec section 14's audience, even though Task 2's nav only shows the link to
  `super_admin` — either add a Communication nav entry visible to all roles pointing here, or
  decide announcements surface to non-super-admins only via the notification center rather than
  a dedicated page; re-check spec section 14/15's intent and pick one — the notification-center
  route is simpler and already built by Task 4, so prefer that unless the user asks for a
  separate announcements feed page for every role).

- [ ] **Step 8: `npx tsc --noEmit`, run backend tests, visual checkpoint** — publish one
  announcement per `target_type` and confirm the right role(s) see it / get notified.

- [ ] **Step 9: Commit.**

```bash
git add ziren_backend/supabase/migrations ziren_backend/app/services/announcement_service.py ziren_backend/app/services/notification_service.py ziren_backend/app/routers/announcements.py ziren_backend/app/main.py ziren_backend/tests/test_announcements.py ziren_dashboard/app/\(dashboard\)/announcements ziren_dashboard/lib/api/announcements.ts
git commit -m "feat: Announcements module with role/agency targeting"
```

---

## Task 17: Reports & Export

**Files:**
- Modify: `ziren_backend/requirements.txt` (add `openpyxl==3.1.5`, `reportlab==4.2.5`)
- Create: `ziren_backend/app/services/report_service.py`
- Create: `ziren_backend/app/routers/reports.py`
- Modify: `ziren_backend/app/main.py`
- Create: `ziren_dashboard/app/(dashboard)/reports/page.tsx`
- Create: `ziren_dashboard/lib/api/reports.ts`
- Test: `ziren_backend/tests/test_reports.py`

**Interfaces:**
- Produces: `report_service.build_report(report_type: str, fmt: str, **filters) -> tuple[bytes, str, str]` returning `(file_bytes, filename, media_type)`. `report_type` in `{"monthly_incidents","agency_performance","municipality_incidents","barangay_incidents","resident_registrations","responders","incident_resolution"}`. `fmt` in `{"csv","xlsx","pdf"}`. Reuses `analytics_service`/`geographic_service` functions from Tasks 11-12 for the underlying data rather than re-querying — each report type maps to one of those functions' output, reshaped into rows.
- Produces: `GET /reports/{report_type}?format=csv|xlsx|pdf&...filters` (super_admin only) — a `StreamingResponse`/`Response` with the right `Content-Type` and `Content-Disposition: attachment; filename=...`.

- [ ] **Step 1: Add the two dependencies to `requirements.txt`** with a short comment noting
  they're for Reports & Export CSV/Excel/PDF generation, then
  `pip install -r ziren_backend/requirements.txt` in the project's venv and confirm both import
  cleanly (`python -c "import openpyxl, reportlab"`) before writing code against them — catch any
  Windows wheel-availability problem immediately rather than after writing the service.

- [ ] **Step 2: `report_service.py`** — one `_rows_for(report_type, filters) -> tuple[list[str], list[list]]` (headers, rows) per report type, each calling into the appropriate Task 11/12 service function and flattening its dict output into tabular rows. Then three renderers:
  - `_to_csv(headers, rows) -> bytes` via `csv.writer` over an `io.StringIO`, encoded utf-8.
  - `_to_xlsx(headers, rows) -> bytes` via `openpyxl.Workbook()`, one sheet, header row bolded.
  - `_to_pdf(title, headers, rows) -> bytes` via `reportlab.platypus` (`SimpleDocTemplate`, `Table`, `TableStyle`) — a plain title + table, no charts; this is explicitly a data export, not a designed report.

  `build_report()` dispatches `_rows_for` then the matching renderer, returning the bytes plus a
  filename like `f"{report_type}_{date.today().isoformat()}.{fmt}"` and the correct media type
  (`text/csv`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`,
  `application/pdf`).

- [ ] **Step 3: Router** — one route, `report_type` as a path param validated against the known
  set (422 on an unknown value, not a 500), `format` as a query param, filters passed through as
  additional query params specific to each report type (e.g. `month`, `year`, `agency_id`,
  `municipality`).

- [ ] **Step 4: Register in `main.py`.**

- [ ] **Step 5: Tests** — for each `report_type`/`fmt` combination (21 combinations — a
  parametrized test, not 21 hand-written ones), assert the response has non-empty bytes and the
  right `Content-Type`; for CSV specifically, parse the returned bytes back with `csv.reader` and
  assert the header row matches the expected columns for that report type.

- [ ] **Step 6: Frontend** — `reports/page.tsx`: a report-type picker, filter fields relevant to
  the selected type, a format picker (CSV/Excel/PDF), and a "Generate" button that calls the
  endpoint and triggers a browser download (`window.location.href = url` with the token as a
  query param, since a `<a download>` needs a same-origin URL or a blob — check whether the
  existing codebase already has a download-triggering pattern for any export elsewhere before
  inventing one; if the API requires an Authorization header the browser can't attach to a plain
  navigation, fetch the blob client-side and create an object URL for the download instead).

- [ ] **Step 7: Run `pip install`, run backend tests, `npx tsc --noEmit`, visual checkpoint** —
  generate at least one report in each format and confirm the downloaded file opens correctly
  (CSV in a text editor, XLSX in a spreadsheet app if available, PDF in a viewer).

- [ ] **Step 8: Commit.**

```bash
git add ziren_backend/requirements.txt ziren_backend/app/services/report_service.py ziren_backend/app/routers/reports.py ziren_backend/app/main.py ziren_backend/tests/test_reports.py ziren_dashboard/app/\(dashboard\)/reports ziren_dashboard/lib/api/reports.ts
git commit -m "feat: Reports & Export — CSV/Excel/PDF generation across 7 report types"
```

---

## Task 18: Settings — Profile, Appearance (off-white theme), Accessibility, Security, Language stub

**Files:**
- Modify: `ziren_dashboard/app/(dashboard)/settings/page.tsx` (read in full first — currently
  agency-scoped: agency profile, notification rules, theme)
- Modify: `ziren_dashboard/app/globals.css` (or wherever the light-theme CSS variables live —
  locate via grep for the existing severity/status color tokens from memory
  `project_ziren_design_tokens` before touching anything)
- Create: `ziren_backend/supabase/migrations/<N+5>_accessibility_prefs.sql` (only if
  `users` doesn't already have accessibility columns — the survey noted migration `012` already
  added "accessibility" fields to residents; check `UserProfile`'s
  `is_pwd`/`disability_types`/`accessibility_notes` — those are resident-specific disability
  fields, NOT the admin UI accessibility prefs from spec section 17 (font size, scaling, high
  contrast, reduced motion) — these are two different concerns that happen to share the word
  "accessibility"; the admin UI prefs are almost certainly better stored client-side only, since
  they're per-device display preferences, not identity data — prefer `localStorage` over a new
  DB column/migration for this, and only add a migration if there's a real cross-device sync
  requirement, which the spec doesn't state)
- Test: none new for the localStorage-based accessibility prefs (no server round-trip to test);
  add a small test if Step 3 ends up touching a backend password-change endpoint that lacks one.

**Interfaces:**
- Produces: `useAccessibilityPrefs()` hook (`ziren_dashboard/lib/hooks/useAccessibilityPrefs.ts`)
  reading/writing `localStorage` keys (`font_size`, `interface_scale`, `text_spacing`,
  `high_contrast`, `reduced_motion`, `larger_controls`), applied as CSS custom properties / a
  `data-*` attribute on `<html>` (mirroring how theme preference is already applied, per
  `ThemePreference`/`preference` seen in `ziren-header.tsx` — follow that exact mechanism for
  consistency rather than inventing a second one).
- Consumes: existing `PATCH /users/me` for Profile tab fields (full_name, phone_number, contact
  info — already supported per `UpdateProfileRequest`) and whatever password-change endpoint
  already exists (check `auth.py`/`users.py` for one before assuming it needs to be built new).

- [ ] **Step 1: Read `settings/page.tsx` in full**, and locate the light-theme CSS variable
  definitions (likely `globals.css` or a Tailwind config) plus every place the severity colors
  (`critical`/`high`/`medium`/`low`) are defined, per memory `project_ziren_design_tokens` — list
  every variable name that must survive this task unchanged before editing anything.

- [ ] **Step 2: Off-white Light Mode** — change ONLY the light-theme's neutral/background/surface/
  border/text tokens (per spec section 17: soft off-white page background, slightly darker card
  surfaces, dark gray text instead of pure black, subtle borders, Ziren orange as the primary
  accent — orange is presumably already the accent, confirm it's unchanged) — do not touch dark
  mode's tokens, and do not touch ANY token whose name matches a severity/status color from the
  design-tokens memory. Pick concrete values (do not leave "TBD" placeholders): background
  `#FAFAF8` or similar warm off-white (check existing brand orange hue first and pick a
  neutral that doesn't clash — e.g. if the orange is warm/red-leaning, a slightly warm gray like
  `#F7F6F3` reads better than a cool gray), card surface one step darker (`#F0EFEB`-ish), body
  text `#27272A`-ish dark gray instead of pure `#000000`/`#111111`, borders `#E4E2DC`-ish.
  Exact hex values are a judgment call — pick something and verify visually rather than agonizing
  over the precise value; the important constraint is "not pure white, not touching severity
  colors."

- [ ] **Step 3: Profile tab** — form bound to `PATCH /users/me` for name/contact fields, a
  password-change sub-form (find or build the backend endpoint — check `auth.py` for a
  `change-password` route; Supabase Auth typically exposes this via
  `db.auth.update_user({"password": ...})` called with the user's own session, which the backend
  may need to proxy since the dashboard doesn't hold a raw Supabase client — check how login/
  token refresh currently works before deciding whether this needs a new backend route or can
  call Supabase directly from the frontend), and a profile-picture upload if the existing media
  upload infrastructure (used for incident attachments) can be reused for this — check
  `media_upload_service.dart`'s backend counterpart in `ziren_backend` for a reusable upload
  endpoint before building a new one.

- [ ] **Step 4: Accessibility tab** — `useAccessibilityPrefs` hook + UI controls (font size
  stepper, scale slider, text spacing toggle, high-contrast toggle, reduced-motion toggle,
  larger-controls toggle) applying their values as CSS custom properties on `document.documentElement`, e.g. `--user-font-scale`, consumed by a small addition to `globals.css`
  (`html { font-size: calc(16px * var(--user-font-scale, 1)); }` and similar for the others).
  Keyboard navigation support: audit that every interactive control already added across this
  entire plan (Tasks 1-17's new pages) is reachable via Tab and has a visible focus ring — this
  is a checklist item against Task 19 (accessibility skill), not new component work here.

- [ ] **Step 5: Notification Preferences tab** — bound to the existing agency
  `notification_rules` (unchanged, already works) PLUS a new personal-notification toggle set
  bound to `system_config`'s `notification_policies`... no — re-read spec section 17: "Users can
  configure which notifications THEY receive" is per-user, not the system-wide policy from
  Task 13's Governance module (that's the ADMIN policy of what's enabled globally; this is an
  individual's personal opt-out within what's globally enabled). This needs a genuinely new
  per-user preference store — reuse the `localStorage` approach from Step 4 for a first pass
  (a set of notification `type` strings the user has muted, checked client-side before rendering
  each notification in `notification-center.tsx` from Task 4), rather than adding another DB
  table for this — note this as the pragmatic choice, since server-side enforcement (not sending
  a muted notification at all) would require passing per-recipient preferences into
  `notification_service.create_for_roles`, which is a heavier change for a "nice to have" personal
  filter; client-side hiding is an honest, working MVP.

- [ ] **Step 6: Security tab** — Active Sessions and Login History: check whether Supabase Auth's
  admin API exposes session listing for a user (`db.auth.admin.list_user_sessions` or similar,
  or whether this project stores its own session/login-event log anywhere) before building UI for
  data that doesn't exist; if it's not available without new instrumentation, render the section
  with an honest "not available yet" state rather than fabricating session data — do not invent
  fake login history. 2FA: a disabled toggle with "Coming soon" tooltip, per the Global
  Constraints MVP cut.

- [ ] **Step 7: Language tab** — a single `<Select>` with "English" as the only enabled option and
  the other Filipino-language options (Filipino/Bisaya/Waray — reuse the exact list from
  `UpdateProfileRequest.valid_language`'s validator, seen in `user.py`, for consistency) shown but
  disabled with "Coming soon", per the MVP cut.

- [ ] **Step 8: `npx tsc --noEmit`, visual checkpoint in BOTH light and dark mode, both roles** —
  this is the highest-regression-risk task in the whole plan (it touches shared CSS tokens).
  Specifically verify: severity badges (critical/high/medium/low) render in their existing exact
  colors in both themes; the incident map's status colors are unchanged; the new off-white light
  background doesn't reduce contrast below readable levels anywhere text sits directly on it.

- [ ] **Step 9: Commit.**

```bash
git add ziren_dashboard/app/\(dashboard\)/settings ziren_dashboard/app/globals.css ziren_dashboard/lib/hooks/useAccessibilityPrefs.ts ziren_dashboard/components/shell/notification-center.tsx
git commit -m "feat: expanded Settings (profile/appearance/accessibility/security/language) and off-white light theme"
```

---

## Task 19: Global Search — real cross-entity search

**Files:**
- Create: `ziren_backend/app/services/search_service.py`
- Create: `ziren_backend/app/routers/search.py`
- Modify: `ziren_backend/app/main.py`
- Modify: `ziren_dashboard/components/shell/shell-search.tsx` (currently a plain controlled
  input with no query logic per the survey)
- Create: `ziren_dashboard/lib/api/search.ts`
- Test: `ziren_backend/tests/test_search.py`

**Interfaces:**
- Produces: `search_service.search(query: str, current_user: dict) -> dict` → `{residents: [...], responders: [...], agency_admins: [...], stations: [...], incidents: [...], municipalities: [...], barangays: [...]}`, each list capped at ~5 items with just enough fields to render a result row (id, label, sublabel, a link path). `agency_admin` callers get results scoped to their own agency where that makes sense (their own agency's responders/stations/incidents only — residents/municipalities/barangays are not agency-scoped and stay unrestricted for both roles, since an agency admin legitimately needs to find any resident who reported to them).
- Produces: `GET /search?q=...` — `Depends(require_role("agency_admin", "super_admin"))`, 422 if `q` is shorter than 2 characters (don't run a query on a single keystroke).
- Consumes: `apiClient.get` pattern.

- [ ] **Step 1: `search_service.py`** — for each entity type, an `ilike` query
  (`db.table(...).select(...).ilike("full_name", f"%{query}%").limit(5).execute()`, or the
  relevant column — `name` for stations, `report_text`/an incident id prefix match for
  incidents, `name` for municipalities/barangays). For an incident id search specifically
  (spec's `INC-2026-00125` example) — check whether incidents actually have a human-readable ID
  in that format or only a UUID (per `IncidentResponse.id: UUID` seen earlier, they do NOT
  today) — if there's no `INC-####-#####`-style identifier anywhere in the schema, that part of
  the spec's example doesn't map onto real data; implement UUID substring matching instead and
  note in the code comment that the spec's human-readable incident ID format doesn't exist in
  this schema yet (a bigger, separate change — generating and displaying a readable incident
  reference number — is out of scope for this plan; flag it as a follow-up rather than
  fabricating a fake ID format).

- [ ] **Step 2: Router**, `require_role("agency_admin", "super_admin")`, `q: str = Query(..., min_length=2)`.

- [ ] **Step 3: Register in `main.py`.**

- [ ] **Step 4: Tests** — assert agency_admin's results are scoped correctly for
  agency-specific entities and unscoped for geographic ones; assert a `q` shorter than 2 chars
  422s.

- [ ] **Step 5: Frontend — `lib/api/search.ts`** typed wrapper; add a debounced (~250ms) call in
  `shell-search.tsx` and render a results dropdown grouped by entity type, each row navigating to
  the right page (`/accounts?highlight=id` for a resident, `/agencies/{stationId}` for a station,
  `/incidents/{id}` for an incident, etc. — some of these deep-link params may not exist yet on
  the target pages; if a target page can't highlight/scroll to a specific row, navigating to the
  page itself (without the highlight) is an acceptable fallback — don't block this task on adding
  highlight support to five other pages).

- [ ] **Step 6: `npx tsc --noEmit`, run backend tests, visual checkpoint** — type a known
  station name, a known resident name, and a municipality name; confirm relevant grouped results
  appear and clicking one navigates correctly.

- [ ] **Step 7: Commit.**

```bash
git add ziren_backend/app/services/search_service.py ziren_backend/app/routers/search.py ziren_backend/app/main.py ziren_backend/tests/test_search.py ziren_dashboard/components/shell/shell-search.tsx ziren_dashboard/lib/api/search.ts
git commit -m "feat: implement real cross-entity Global Search"
```

---

## Task 20: Dashboard overview — make it Super-Admin-appropriate

Spec section 2: the Dashboard should read as "current overall state of the system," not an
operational dispatch view, for a Super Admin. The existing `/overview` page (662 lines, per the
survey) is shared by both roles today — this task branches it, not replaces it.

**Files:**
- Modify: `ziren_dashboard/app/(dashboard)/overview/page.tsx`

**Interfaces:**
- Consumes: `analytics_service`/`geographic_service` endpoints from Tasks 11-12 for
  super_admin's summary cards, alongside whatever this page already fetches.

- [ ] **Step 1: Read the full current `overview/page.tsx`.** Identify which sections are
  operational-dispatch-flavored (e.g. a live queue widget, "waiting report" table mentioned in
  the survey) versus general-purpose stats/charts that suit both roles equally.

- [ ] **Step 2: For `isSuperAdmin`**, replace or hide any operational-queue-flavored widget with
  system-wide summary cards: total agencies, total stations, total registered users by role,
  incidents today/this week (counts only, no action buttons), a link into System Analytics for
  deeper trends, and a link into System Status for health. Keep existing charts
  (`incident-volume-chart`, `severity-trend-chart`, etc.) if they already aggregate system-wide
  rather than per-agency data for a super_admin caller — check whether the underlying data fetch
  is already unscoped for super_admin (likely yes, mirroring `dispatch_service`'s pattern) before
  assuming new endpoints are needed here.

- [ ] **Step 3: For `agency_admin`**, leave the page exactly as it is today — this task is
  additive branching, not a redesign of the Agency Admin's working dashboard.

- [ ] **Step 4: `npx tsc --noEmit`, visual checkpoint both roles.**

- [ ] **Step 5: Commit.**

```bash
git add ziren_dashboard/app/\(dashboard\)/overview/page.tsx
git commit -m "feat: Super Admin dashboard reflects system-wide state, not dispatch operations"
```

---

## Task 21: Final integration pass

Run once every prior task has landed.

- [ ] **Step 1:** `cd ziren_backend && python -m pytest -q` — full suite green.
- [ ] **Step 2:** `cd ziren_dashboard && npx tsc --noEmit && npm run build` — clean build.
- [ ] **Step 3:** Re-read `nav-config.ts` and click through every link as `super_admin`: confirm
  zero 404s (this closes out the gap Task 2 Step 4 flagged).
- [ ] **Step 4:** Click through every link as `agency_admin`: confirm the pre-existing pages
  (`/overview`, `/incidents`, `/responders`, `/verification`, `/map`, `/governance`,
  `/settings`) behave exactly as they did before this plan started — this is the regression
  check that matters most, since breaking Agency Admin's working dispatch flow is explicitly
  out of bounds per Global Constraints.
- [ ] **Step 5:** Confirm the four constraint items from Global Constraints one more time
  explicitly: `IncidentStatus` enum untouched, `rubric_service.py` scoring untouched, no mobile
  wizard string touched, severity/status color tokens byte-identical to before Task 18.
- [ ] **Step 6:** Update `MEMORY.md` / write a `project` memory noting the Super Admin feature
  plan is implemented, which sections landed vs. which MVP cuts remain open follow-ups (2FA,
  language switching, real-time websocket health check, human-readable incident reference IDs,
  server-side per-user notification muting) — this is exactly the kind of "surprising, non-obvious"
  context future sessions need, per this project's memory conventions.
- [ ] **Step 7: Final commit** (if Step 6 touched any repo files beyond memory) or confirm the
  branch is ready for the user to review/merge.
