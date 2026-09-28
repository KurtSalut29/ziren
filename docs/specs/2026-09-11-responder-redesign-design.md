# Responder-Side Redesign — Design Spec

Covers the four responder tabs (Home, Reports, Map, Profile) in the Flutter app
(`ziren_mobile`). Written after the resident-side redesign was completed and
approved separately; this spec exists because incremental patches to the
responder side ("add a hero banner," "trim this," "match this mockup") kept
producing a screen that felt inconsistent with itself and with the rest of the
app. This document is the single source of truth for what each responder
screen should contain and why, so future changes have something to check
against instead of improvising per screen.

## 1. Why the previous approach didn't work

Three things happened in sequence, each locally reasonable, that produced a
screen with no coherent design:

1. The original responder Home was a "ResQLink prototype" layout — duty row,
   4-figure band, pending-response card, queue, then a folded-in dashboard
   (en-route/on-scene tiles, oldest-wait card, two charts). Functional, but
   never designed against resident's finished look.
2. A user-supplied reference mockup was matched closely — plain header (no
   photo), colored duty card with avatar/rank, 3 quick-action tiles, a
   recent-activity feed. This fixed the "doesn't look like the same product"
   problem but copied the mockup's structure uncritically, including two
   quick-action tiles that duplicate controls already on screen.
3. That result was flagged as "too messy," so the leftover dashboard sections
   (on-me-now tiles, charts) were cut — correctly reducing volume, but as a
   reaction to feedback rather than a plan.

The result matched a mockup and then got trimmed, but nobody had asked "what
does a responder actually need to see, in what order, and why" as a starting
question. This spec asks that question directly for all four screens.

## 2. Design principle: shared chrome, purpose-built structure

Resident and responder share one token system (`ZirenTokens`) and one set of
primitive widgets (buttons, dialogs, chips, list rows) — because the app's
color rules are operational, not decorative (severity is always red/amber/
green, agency hues are fixed, orange means "the one CTA"), and a dispatcher,
a resident, and a responder must agree on what a color means when they are
all looking at the same incident.

What they do **not** share is page structure. A resident opens Ziren rarely,
to calmly report something. A responder opens it mid-shift, often seconds
after a dispatch alert, needing the most urgent thing on screen almost
instantly. Forcing resident's layout onto responder screens (what happened in
step 2 above) optimizes for the wrong moment. The working analogy is Uber's
rider app vs. driver app: same brand, same components, different home screens
— because "find a ride" and "manage a shift without missing a dispatch" are
different jobs.

**Concrete consequence:** every responder screen pulls its list rows, section
headers, and card patterns from one place — a new `responder_kit.dart`
(mirroring `shared/widgets/home_kit.dart` and `shared/widgets/profile_kit.dart`)
— rather than each screen defining its own container styling. This is the
direct fix for "the pages are not consistent because we have other design in
each page."

## 3. Ground truth: what the backend actually supports today

Confirmed by direct inspection of `ziren_backend/app/routers/responder.py`,
`responder_service.py`, and the mobile `ResponderProvider`/
`ResponderIncidentModel`.

**Exists and already reaches the app (some of it fetched but never
displayed):**
- Active queue (`GET /responder/queue`), full incident detail, incident notes
  thread, accept/decline/close, scene-media upload, mutual-aid backup
  request, escalation request, distress signal, hazard reporting.
- History of the last 50 resolved/cancelled assignments (`GET
  /responder/history`).
- Dashboard figures (`GET /responder/dashboard`, 30-day window):
  `active_count`, **`active_critical`**, **`en_route_count`**, **`on_scene_count`**,
  **`oldest_waiting_minutes`**, **`resolved_today`**, **`resolved_period`**,
  `median_response_minutes`. Bold fields are fetched into `ResponderProvider`
  today but rendered nowhere — free to use, zero backend work.
- Notifications (per-user table, unread count, mark read) and Announcements
  (agency/responder-targeted broadcasts) — both real, general-purpose, reachable
  by responders.

**Does not exist anywhere in the backend (would need real backend work,
scoped separately from this redesign):**
- Duty *scheduling* (a planned shift/roster) — only a live on/off toggle exists.
- Certifications, training records, performance ratings — no tables, no fields.
- Equipment/unit status check — no field or endpoint.
- Vehicle type (fire truck vs. ambulance vs. patrol car) — only `agency_type`
  (BFP/PNP/MDRRMO) exists; no per-unit vehicle field.
- Server-side historical analytics beyond the one rolling median — the
  per-day/severity-mix charts already in the app are computed client-side
  from `history`, not a backend endpoint.

Nothing in this spec's mobile-side design proposes screens backed by data
that doesn't exist. Where the ideal design needs something the backend
doesn't have, it's called out explicitly in §7 as a separate future phase.

## 4. Home — "what needs me right now"

**Governing constraint (confirmed with the user):** the dominant real-world
moment is seconds after a dispatch alert — near-zero reading time, and this
governs every density/hierarchy decision below. Note that the full-screen
dark "incoming call" alert (`IncidentAlertScreen`) already handles the literal
alert moment; Home is what a responder checks around that moment — at cold
start, after finishing a call, or periodically to confirm status — so its job
is situational awareness, delivered fast.

**Structure, top to bottom:**

1. **Identity bar** — unchanged from the current build: brand mark, "Ziren
   Responder," bell. No photo banner (that stays a Profile-only treatment,
   confirmed working already).
2. **Duty status** — compact two-zone card (colored state + white
   identity/avatar row), unchanged from the current build. It gates every
   assignment a responder can receive, so it must register instantly, but a
   responder interacts with it rarely, so it must not visually outweigh the
   content below it.
3. **What's on me right now** — the active queue, ranked severity-then-age,
   unchanged card design (`ResponderQueueCard` already reads well: rank,
   icon-in-circle by severity, severity chip, SOS flag, progress bar). This
   is the actual content of the screen and the visual anchor after duty state.
4. **Glanceable numbers** — three cells: **Assigned**, **Critical**, and
   **Oldest waiting** (replacing the current third cell, "Typical" response
   time). Assigned and Critical are unchanged from the current build; Oldest
   waiting swaps in using a dashboard field that's already fetched and
   unused. Small, positioned as context for the queue above them, not a
   competing section.
5. **Recent activity** — up to 4 rows from `history`, reusing `ReportRow`
   verbatim from Reports (no second implementation of the same card). Lowest
   priority; only renders when non-empty.

**Change — drop "Typical" (median response time) from this row.** It answers
"how am I doing generally," a retrospective/performance question, not "what
needs me right now." It moves to Reports' and Profile's shift-record views
(§5, §7), where it sits with the rest of the performance data instead of
competing with genuinely urgent numbers on the one screen built for speed.

**Change — drop two of the three quick-action tiles.**
"View My Tasks" opens the Reports tab, which is a bottom-nav icon directly
below it. "Report Unit Status" toggles duty, which is the card directly
above it. Both are shortcuts to something already one tap away or already on
screen — under an alert-glance read, three saturated color tiles that mostly
duplicate visible controls cost scan time for no real gain. Keep only
**"Awaiting Dispatch,"** which is a genuine shortcut: it jumps straight into
the worst-ranked open assignment without a scroll, the same job the deleted
`PendingResponseCard` used to do, done as a single small entry point instead
of a second gradient hero card competing with the duty card above it.

**New, small addition (no backend work):** when a new item lands in the
queue while Home is open, briefly highlight the top queue card (a ~2s color
pulse) so a responder looking at the screen when a dispatch arrives sees
something change, not just a silently incremented number.

**Per-dimension notes:**
- *Spacing:* generous gaps between the 4 sections, tight spacing within each
  — matches current `space16`/`space20` between, `space8`/`space10` within.
- *Color:* dropping the two extra tile colors removes the one place on this
  screen where color didn't carry meaning (severity/duty/status colors all
  still do).
- *Feedback/states:* duty toggle keeps its existing busy-spinner swap.
- *Accessibility:* duty switch needs a semantic label describing the
  resulting state ("Go off duty" / "Go on duty"), not just "switch" — currently
  relies on adjacent text alone for a screen-reader user. Fix as part of this
  pass.

## 5. Reports — "the record"

Filter row (All/Active/Closed, unchanged — it already works) plus a
**List / Record segmented control** at the top, rather than stacking a chart
section below a potentially-long list (the same "too much on one screen"
failure mode Home just had).

- **List** view: the existing `ReportRow`-based list, unchanged.
- **Record** view: the shift analytics pulled off Home in the previous pass —
  `ClosedPerDayChart`, `SeverityMixRing`, plus the response-time median — all
  driven by already-fetched `history`/`dashboard` data via the existing
  `ResponderTrends` helper. Renders an honest empty state (no fake zeros) when
  there's nothing closed yet, matching the rule already established elsewhere
  in this codebase.

This keeps Reports as the single home for "how is my shift/record looking,"
separate from Home's "what do I do right now," without forcing a responder to
scroll past one to reach the other.

## 6. Map — no structural change, one real data gap

The existing satellite/offline map, agency-filter pills, station detail
sheet, and in-app routing already work and don't need a redesign — this
session's earlier review didn't find a real problem here once the offline-map
and directions work landed.

Agency-colored pins stay as the baseline (real, meaningful today: BFP
red-coral, PNP sky-blue, MDRRMO emerald). Vehicle-specific icons (fire truck
vs. ambulance vs. patrol car) are not implementable now — no vehicle-type data
exists anywhere in the backend. See §7 for the proposed addition.

## 7. Profile — identity plus shift record

Keep the current, already-verified build: photo banner, avatar, name/agency/
station chips, Contact and Assignment sections. Add a compact shift-record
summary (2-3 numbers: assigned now, resolved this period, typical response
time) using the same real dashboard fields as Reports' Record view, condensed
— so Profile answers "who is this and how is their shift going," not just
"what is their badge number."

Certifications, Training History, and Performance Ratings from the earlier
reference mockup are **not** part of this phase. They would need new backend
tables and — just as importantly — a way for an Agency Admin to actually enter
that data, which doesn't exist on the dashboard either. Scoped honestly below
as a separate future proposal rather than built as placeholder rows with
nothing behind them.

## 8. Shared pattern library — `responder_kit.dart`

New file, `lib/features/responder/presentation/widgets/responder_kit.dart`,
holding the primitives every responder screen should draw from instead of
each screen inventing its own card/section style:

- `ResponderSectionHeading` — title + optional trailing action, matching
  `HomeSectionHeading`'s look so the two roles' section headers are visually
  identical even though the pages around them differ.
- The duty-status card, the quick-action tile, the stat-cell — currently
  private classes inside `responder_home_screen.dart` — move here as public
  widgets so Reports/Profile can reuse the stat-cell style for their own
  numbers instead of re-implementing it.
- `IncidentActionRow`/`IncidentActionCard` (already extracted this session
  for the incident-detail screen's grouped actions) move here too, since
  they're general-purpose, not detail-screen-specific.

This is the concrete fix for "we have other design in each page" — after
this, a new responder screen has a defined place to draw its patterns from,
the same way `home_kit.dart` already serves the resident side.

## 9. Explicitly deferred — real backend work, separate phase

Not implemented as part of this redesign; scoped here so they're not lost,
and so implementation doesn't get tempted to fake them.

**Vehicle type for map markers** — small: one enum column (e.g. `fire_truck`,
`ambulance`, `patrol_car`, `rescue_unit`) on the responder or station record,
plus a dropdown wherever units are managed on the web dashboard. Low
complexity, real value for the Map screen once done.

**Certifications / Training History / Performance Ratings** — larger: new
table(s) keyed to a responder, and an Agency Admin-side UI to enter and
maintain that data (nobody else is positioned to attest to it). This is a
genuinely separate feature with its own design questions (who can edit, what
counts as a "rating," expiry on certifications) and should get its own
brainstorming pass rather than being bundled here.

## 10. Testing / verification approach

Consistent with how the rest of this session's mobile work has been
verified: `flutter analyze` clean after every file change, then live
on-device verification via `adb` screenshots for every screen touched —
online and, where relevant (Map), offline. No change is reported done
without a live screenshot confirming it, matching the standard already
practiced throughout this project.

## 11. Out of scope

- Bottom-nav tab structure (Home/Reports/Map/Profile) is unchanged — this
  spec is about content within each tab, not the tab set itself.
- The full-screen incoming-alert design (`IncidentAlertScreen`, dark
  "incoming call" style) is not touched by this spec. The user's confirmed
  alert-glance usage context supports its existing rationale; revisiting it
  is a separate decision if wanted later.
- Resident-side screens are unaffected.
