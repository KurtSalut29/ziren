# Cross-Agency Assist Requests — design

Date: 2026-09-20
Status: approved in chat, awaiting spec review

## Goal

The Operational Area "Agencies" tab (`agencies-tab.tsx`) already tells a
dispatcher who else operates in their municipality, but the only way to act on
that is `tel:`/`mailto:` — Ziren hands off to the phone and gets out of the
way entirely. Separately, a reporter's own overlap flags
(`incidents.overlap_agencies`: fire / injuries / flooding / missing_person /
hazmat) are collected on the report form and displayed read-only ("Also
present: Fire · Injuries") but nothing ever *acts* on them — no other agency
is ever actually told.

This adds a real in-app way for one agency to ask another for help on a
specific incident: a short request tied to that incident, a small
per-request chat to work out details, and an explicit accept/decline so the
requester knows whether help is coming — without turning Ziren into a
general messaging product.

## Scope

In:
- "Request assist" action on an incident, from the agency currently handling
  it, targeting another agency present in the same municipality.
- Auto-suggests a target agency from the incident's overlap flag
  (fire→BFP, injuries/flooding→MDRRMO, missing_person→PNP,
  hazmat→BFP+MDRRMO — user picks one), always overridable, always requires
  an opening message.
- A small per-request chat thread between exactly the two agencies involved.
- Explicit Acknowledge / Decline on the receiving side, independent of the
  chat itself.
- Dashboard only, `agency_admin` only, both sending and receiving.

Out (deliberately):
- **No incident access for the receiving agency.** They get a narrow,
  live-projected snapshot (category, severity, location text) and the chat —
  never the incident row itself. `incidents` RLS is untouched.
- **No mobile/responder involvement.** Same audience as the Agencies tab
  today; a responder keeps being dispatched by their own admin.
- **No standing agency-to-agency inbox.** Each thread belongs to one request,
  which belongs to one incident. Coordinating on a *different* incident
  between the same two agencies is a new request, not a continued thread.
- **No true realtime.** The dashboard has never subscribed to Supabase
  Realtime (only the mobile app has, e.g. `incident_notes`,
  `responder_distress`); this does not start now. Fast polling instead.
- **No multi-target broadcast.** One request targets one agency. Hazmat
  needing both BFP and MDRRMO means sending twice.
- **No un-declining, no editing/deleting messages, no expiry job.** A
  declined request stays declined; send a new one if circumstances change.

## Data model

Two tables, matching the existing split between a mutable envelope
(`incidents`) and an immutable log (`incident_notes`, `dispatch_log`) rather
than inventing a third shape:

```sql
-- migration 036 (next after 035)

CREATE TABLE public.incident_assist_requests (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id           UUID NOT NULL REFERENCES public.incidents(id) ON DELETE CASCADE,
    requesting_agency_id  UUID NOT NULL REFERENCES public.agencies(id),
    requested_agency_id   UUID NOT NULL REFERENCES public.agencies(id)
                          CHECK (requested_agency_id <> requesting_agency_id),
    overlap_flag          TEXT,   -- the OverlapFlag that suggested this, NULL if hand-picked
    status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'acknowledged', 'declined')),
    requested_by          UUID NOT NULL REFERENCES public.users(id),
    responded_by          UUID REFERENCES public.users(id),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at           TIMESTAMPTZ
);

CREATE TABLE public.incident_assist_messages (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id        UUID NOT NULL REFERENCES public.incident_assist_requests(id) ON DELETE CASCADE,
    sender_agency_id  UUID NOT NULL REFERENCES public.agencies(id),
    sender_id         UUID NOT NULL REFERENCES public.users(id),
    -- No denormalized sender_role: unlike incident_notes (agency_admin,
    -- responder, and super_admin all write there), every writer here is
    -- an agency_admin by construction of the INSERT policy below — a
    -- column with only one possible value doesn't earn its place.
    body              TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- append-only — no updated_at, no UPDATE/DELETE policy
);

CREATE INDEX incident_assist_requests_incident_idx ON public.incident_assist_requests (incident_id);
CREATE INDEX incident_assist_requests_agency_idx   ON public.incident_assist_requests (requested_agency_id, status);
CREATE INDEX incident_assist_messages_request_idx  ON public.incident_assist_messages (request_id, created_at);
```

Sending the opening message *is* creating the request — one atomic service
call inserts both rows, no separate "note" field on the envelope.

Duplicate guard (service-layer, not a DB constraint): creating a request is
rejected if a `pending` request already exists for the same
`(incident_id, requested_agency_id)`.

Lifecycle guard (service-layer): once the underlying incident's own `status`
is `resolved` or `cancelled`, new messages are rejected with a clear error;
the thread renders read-only. No DB trigger — checked where every other
incident-adjacent write already checks incident state.

## Backend

**Migration `036_incident_assist_requests.sql`** — header documents the
snapshot-only boundary explicitly (why the receiving agency never gets a
join into the full incident), follows `incident_notes`' RLS shape:

| Table | SELECT | INSERT | UPDATE |
|---|---|---|---|
| `incident_assist_requests` | `agency_admin` of either party agency; `super_admin` (all, read-only) | `agency_admin`, `requesting_agency_id = get_my_agency_id()`, `requested_by = auth.uid()` | `agency_admin`, `requested_agency_id = get_my_agency_id()` only (status transitions) |
| `incident_assist_messages` | `agency_admin` of either party agency (via join to parent request); `super_admin` (all, read-only) | `agency_admin` of either party agency, `sender_id = auth.uid()` | none (append-only) |

`GRANT ALL ... TO service_role;` only — same as `incident_notes`, no
`authenticated` grant, since the FastAPI backend is the only caller and it
connects as `service_role`. RLS exists for defense-in-depth and consistency
with house style, not as the live enforcement boundary (that's the router).
Neither table joins `supabase_realtime` (nothing subscribes, per the polling
decision above). Ends with the usual verification query (RLS enabled, grant
present, policy count).

**`app/services/assist_request_service.py`** (new):
- `create_request(incident_id, requested_agency_id, message, actor)` —
  validates actor's agency is the incident's `assigned_agency_id`, target
  agency is active and in the same municipality, no existing pending
  duplicate; inserts both rows; calls `notification_service`.
- `list_for_agency(agency_id, scope: "sent" | "received")` — joins a narrow
  incident projection (`incident_category`, `severity`, `location_address`,
  `created_at`) live at read time, never the full row.
- `get_thread(request_id, actor)` — the envelope + all messages, after
  confirming actor's agency is a party to it.
- `post_message(request_id, body, actor)` — rejects if incident is resolved
  /cancelled or actor's agency isn't a party.
- `set_status(request_id, status, actor)` — only the `requested_agency_id`
  side, only `pending → acknowledged` or `pending → declined`.

**`app/routers/assist_requests.py`** (new):
```
POST   /incidents/{incident_id}/assist-requests     create (target + opening message)
GET    /assist-requests?scope=sent|received          list mine, both sides
GET    /assist-requests/{id}                          one thread + messages
POST   /assist-requests/{id}/messages                 send (polled by an open panel)
PATCH  /assist-requests/{id}/status                    acknowledge | decline
```
Every handler resolves the caller's agency from their own session, never
from the request body — same rule Operational Area's router already follows
("scoping is decided in the router from the caller's role, never from the
query").

## Notifications

Reuses `notification_service.create_for_agency_role()` as-is, no changes to
that module:
- New request → `create_for_agency_role(requested_agency_id, 'agency_admin', type_='assist_request', is_important=True, link='/geographic?tab=agencies&assist={id}')`.
- Status change → same call back to `requesting_agency_id`, `type_='assist_response'`.
- New chat messages do **not** each notify — only the opening message does.
  A bell notification per keystroke-adjacent event would drown the existing
  feed; an open panel's own polling is how replies are seen, same as any
  chat you have open.

## Frontend

- `lib/api/assist-requests.ts` (new) — thin client for the five endpoints
  above, following the existing `lib/api/*.ts` shape.
- `components/incidents/incident-detail-modal.tsx` — "Request assist" button
  beside the existing "Also present" row; opens `AssistRequestDialog`
  (agency picker styled like `OptionDialog`, reusing `AGENCY_ICON`/`AG_COLOR`;
  auto-selected target from `overlap_flag`, always overridable; a compose box
  for the opening message).
- `components/operational-area/agencies-tab.tsx` — new "Assist requests"
  panel: Incoming (actionable) and Sent (status) lists, each row opening the
  shared thread panel.
- `components/incidents/assist-thread-panel.tsx` (new, shared by both entry
  points) — snapshot header (category/severity/location icons from the same
  vocabulary the tables already use), message list, compose box, and the two
  status buttons when incoming + pending.
- `lib/hooks/useAssistThread.ts` (new) — polls `GET /assist-requests/{id}`
  every ~6s while the panel is mounted, stops on unmount; same silent-refresh
  shape Operational Area's 60s poll already uses, just faster because this is
  a conversation, not a dashboard.
- Notification bell needs no structural change — it already renders
  `title`/`body`/`link`; the link target is new, the rendering isn't.

## Verification

- Backend (pytest, mocked DB): create/list/thread/message/status happy paths;
  guardrails — can't target own agency, duplicate pending blocked, only the
  target agency can acknowledge/decline, status transitions are one-way,
  messages rejected once the incident is resolved/cancelled, every endpoint
  respects agency scoping regardless of what the request body claims. Plus a
  live-schema read-only run of the new service functions (mocks can't catch a
  wrong column — see testing memory).
- Frontend: `tsc --noEmit`, `eslint` clean. Playwright suite: overlap-flag
  auto-suggestion picks the right default per flag and stays overridable;
  sending creates the thread and the receiving agency's notification;
  duplicate-request button shows disabled "Already requested" state;
  Acknowledge/Decline updates status and notifies back; a message sent from
  one mocked session appears in the other within one poll interval
  (`page.clock`, per existing convention); a resolved incident's thread
  renders read-only.
- Migration is written but **not applied by me** — paste back the
  verification query's output after running it in the Supabase SQL Editor,
  per this project's standing rule.

## Risks

- The flag→agency auto-suggestion can guess wrong (e.g. "injuries" isn't
  always MDRRMO's alone) — mitigated by always allowing override, never
  auto-sending.
- Fast polling from every open thread panel adds backend load during a
  simultaneous multi-request event (e.g. a large fire) — acceptable at
  capstone scale; a real scaling concern if this ever needed to run beyond
  it, deliberately deferred rather than solved now.
- No expiry on a `pending` request that nobody answers — its own visible
  `created_at` age is the only signal, same as how stale notifications
  behave today.
- Chat lag is real (a few seconds, not instant) — an accepted trade-off of
  not introducing the dashboard's first direct Supabase connection for this.
