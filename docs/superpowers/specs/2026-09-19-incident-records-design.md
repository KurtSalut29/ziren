# Incident Records — design

Date: 2026-09-19
Status: approved in chat, awaiting spec review

## Goal

Incident History currently reads as *monitoring*: a stat strip and a list of
status cards. It becomes **Incident Records**: a flat, complete record of every
incident, one row per incident and one column per fact, modelled on the
reference table the product owner supplied (record id, type, place, date,
time, source). Clicking a row opens the complete record.

## Scope

In:
- Rename Incident History → Incident Records (page title, sidebar label,
  route meta). The URL stays `/incident-history` so existing links work.
- Replace the card list with a records table.
- Drop the six stat cards; keep one summary line.
- Complete-record panel per incident.
- A generated record number on every incident, with a server-side lookup.
- Widen `/dispatch/history` with the fields the table and panel need.

Out (deliberately):
- **Barangay.** Incidents store a free-text address and coordinates, not a
  barangay, and the `barangays` table has no coordinates to derive one from.
  A guessed barangay on an official record is worse than none. The Location
  column shows address + municipality instead. Structured barangays would be a
  separate change to the mobile report flow.
- Export (Reports & Export already exists), editing records, mobile changes
  (the mobile app does not call `/dispatch/history`).

## Table

| Column | Source | Notes |
|---|---|---|
| Record no. | `incidents.record_number` (new) | `ZIR-2026-000123` |
| Type | `incident_category` | SOS badge when `sos_flagged` |
| Report | `report_text` | clamped to two lines, full text on hover and in the panel |
| Location | `location_address` + station's `agencies.municipality` | |
| Agency / Station | `stations(name, agencies(agency_type, ...))` | **Provincial Admin only**; an Agency Admin has one station |
| Date | `created_at` | separate column, as in the reference |
| Time | `created_at` | separate column |
| Severity | `severity` | icon + label, never colour alone; existing tokens |
| Status | `status` | existing status vocabulary |
| Responder | responder's `full_name` (new join) | blank when unassigned |
| Outcome | `outcome` | closed incidents only |

Kept from today: the sticky filter bar, server-side filters (window, dates,
status, severity, station, type), paging (100/page), and the unpaged total.
The stat strip is replaced by one line, e.g. "214 records · 31 critical · 180
resolved", from the existing `counts` in the response.

Search: the existing local search over the loaded page stays (it already
matches report text and address). Added: a server-side `record_no` lookup,
because a person citing a record number must find it wherever it sits, not
only on the current page.

## Complete record panel

Extend `IncidentDetailModal` (already has an `isHistory` mode) rather than
write a second detail view. It must present, for one incident:
summary (record no., status, severity, category); report text and wizard
answers; the triage reasoning (`signals`); location with coordinates;
timeline (filed → dispatched → accepted → resolved, with durations); response
(agency, responder name); outcome (casualties injured / fatal / transported,
notes); reporter (name, verification, SOS warnings); media.
Planning step: read what the modal already renders and add only what is
missing.

## Backend

**Migration `035_incident_record_number.sql`** (see the `supabase-migration`
skill):
- `incidents.record_number TEXT UNIQUE`, assigned by a `BEFORE INSERT` trigger
  so every insert path — including the mobile app — gets one.
- Format `ZIR-{year of created_at}-{6-digit sequence}`. The sequence is a
  single global one; the year prefix is the filing year.
- **Why not an agency prefix.** An incident's agency is unknown at filing and
  routing can change it later, so a prefix could be wrong on an official
  record. The agency has its own column.
- Backfill existing rows in `created_at` order, then set the column
  `NOT NULL`.
- Index for the lookup. `service_role` GRANTs included (the usual omission
  behind 42501).

**`get_incident_history`** (`dispatch_service.py`) adds to the select:
`record_number`, `latitude`, `longitude`, `accepted_at`, and the responder's
`full_name` via a join on `assigned_responder_id`. New optional `record_no`
query param (exact or prefix match, indexed). The router
(`routers/dispatch.py`) passes it through.
Role scoping is unchanged: Agency Admin pinned to their agency, Provincial
Admin pinned to their agency type. `record_no` must not widen that scope.

## Frontend

- `lib/api/dispatch.ts`: extend `HistoryIncident` and `HistoryQuery` (use the
  `api-contract-sync` skill; the mobile app is unaffected).
- `components/incidents/history-view.tsx`: swap the card list for the table;
  remove `StatStrip`; add the summary line and the record-no lookup.
- New table component alongside `IncidentRow`; `IncidentRow` stays because the
  active view uses it.
- `lib/nav/nav-config.ts`, `lib/utils/route-meta.ts`,
  `app/(dashboard)/incident-history/page.tsx`: label and title.
- Colour rules from `globals.css` apply unchanged (red = critical only;
  severity always paired with icon and label; agency hues fixed).

## Verification

- Backend (pytest): trigger assigns a number on insert; backfill numbers every
  existing row uniquely and in filing order; history returns the new fields;
  role scoping holds with and without `record_no`.
- Dashboard: `tsc --noEmit`; Playwright screenshots in light and dark as an
  Agency Admin and as a Provincial Admin, mocking `http://localhost:3000/api/**`
  (see the dashboard verification memory). A skeleton-only screenshot is not
  evidence.
- Apply migration 035 to the live Supabase only with the owner's go-ahead.

## Risks

- A very wide table at laptop width: Report and Location clamp, Agency/Station
  is Provincial-only, and the table scrolls horizontally rather than wrapping
  cells into tall rows.
- Backfill on a live table: run in one transaction, in `created_at` order.
