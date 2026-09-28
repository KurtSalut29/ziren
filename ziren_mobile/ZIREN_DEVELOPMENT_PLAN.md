# ZIREN — Master Development Plan & Task Tracker

**Purpose:** This file is the single source of truth for Ziren's development. It is meant to be read by Kiro (or any AI coding agent) before touching any code, and re-read whenever a new task begins. It tracks *what* to build, *in what order*, and *the rules that must never be broken* while building it.

> If you are Kiro (or any AI agent) reading this file: read the **Agent Rules** section in full before writing a single line of code. These rules override any shortcut that seems convenient in the moment.

---

## 0. AGENT RULES (Read This First — Every Session)

These rules apply to **every task** in this document, without exception.

### 0.1 Plan before code
- Do not generate code immediately after being given a task. First restate the task in your own words, list the files/modules it will touch, and list the security implications. Wait for confirmation if anything is ambiguous.
- If a task description conflicts with the locked architecture decisions in Section 1, **stop and flag the conflict** instead of silently resolving it.
- Break every task into small, reviewable commits/PRs. No single commit should implement more than one checklist item from this file.

### 0.2 Security is not optional
- Every endpoint that touches user data, incident reports, or location data must have authentication AND authorization checks — never authentication alone.
- Assume all client input (mobile app, web dashboard) is hostile. Validate and sanitize server-side, even if the client already validates.
- Never log sensitive data in plaintext (passwords, tokens, exact reporter location + identity together, phone numbers) to console or third-party logging services.
- Any new database table touching incident data, user accounts, or agency accounts must have Row Level Security (RLS) policies written and tested *before* the table is used by application code — not added later "when there's time."
- Secrets (Supabase service key, Claude API key) must only ever exist in environment variables / secret managers, never committed, never hardcoded, never sent to the client.
- Rate-limit all public-facing endpoints (especially incident submission and auth) to prevent abuse/spam of emergency channels.
- Every task involving auth, dispatch logic, or the severity rubric requires a written test case before it is marked done.

### 0.3 Respect the locked architecture (do not silently redesign)
- Severity is **never** an ML output. It is always computed by the rule-based rubric per agency (BFP / PNP / MDRRMO). If a task seems to require ML-based severity, stop and flag it — this is a deliberate, defended design decision.
- The AI (NLP pipeline + ResQ AI Chat) is **assistive only**. It must never trigger an automatic dispatch. A human dispatcher always has final authority and override power. Do not build any code path where AI output directly creates a dispatch action without a human confirmation step in between.
- The NLP pipeline extracts exactly the 15 structured signals already defined in the spec (incident_type, casualty_mentioned, injured_count, weapon_mentioned, why_category, how_category, etc.) — do not add or remove signals without flagging it as a scope change.
- Connectivity: the app submits over the **internet only**. An SMS gateway fallback was built, tested end-to-end on real hardware, and deliberately descoped — see Deviations Log 2026-09-24. Do not re-add it without re-reading that entry; the blocker (a resident's own SIM needs outbound SMS credit, which the app cannot provide or work around) has not changed. On-device NLP and store-and-forward remain legitimate future layers if pursued — they were never built and are not affected by this decision.
- Tech stack is fixed: Flutter (mobile), Next.js (dispatcher dashboard), FastAPI (backend), Supabase + PostGIS (database). Do not introduce a different framework/library for a core function without flagging it first.
- Mapping stack is fixed: MapLibre GL + self-hosted OpenStreetMap vector tiles, not Mapbox or Google Maps SDKs. Do not add a Mapbox/Google Maps API key or pull in a billed mapping SDK without flagging it first — this was a deliberate cost/dependency decision for a public-safety tool (see Section 1 rationale).

### 0.4 Documentation & traceability
- Every completed task gets its checkbox marked `[x]` in this file, plus a one-line note of what was actually built (in case it diverged from plan).
- Any deviation from this plan must be written down in the "Deviations Log" at the bottom of this file, with the reason.
- Keep `ZIREN_KIRO_SPEC_V2.md` and this file in sync — this file tracks sequencing/progress, the spec file tracks technical detail.

### 0.5 When in doubt
- Ask Kurt before assuming. Do not guess at business logic for emergency dispatch, agency routing, or severity scoring — these came from real field interviews with BFP/PNP/MDRRMO and should not be reinterpreted.
- Prefer the boring, well-tested solution over the clever one, especially for anything in the reporting → dispatch pipeline.

### 0.6 Build the full scope of a phase, not a partial slice
- Before starting any phase, re-read its full checklist in Section 2 **and** cross-check it against that role's full entry in Section 1.5 (Finalized Feature List). A phase is not "done" just because the first feature under it works — every checklist item and every Section 1.5 feature line touching that phase must be either built or explicitly deferred with a reason.
- A phase/task must not be marked `[x]` or "Complete" in Section 2 or the Quick Status Snapshot (Section 4) if only part of its scope was built. Partial work stays `[ ]` (or gets an explicit "partial — see note" marker naming exactly what's missing) so the gap is visible at a glance instead of hiding inside a checked box.
- If a built feature isn't already a line item in this file (e.g. it was added ad hoc while implementing something else), add it as a checklist item under the correct phase — retroactively if needed — before marking anything done. The checklist must always reflect the real, full scope of each role's dashboard/app, not just whatever got touched first.
- When a task description is vague or feels smaller than what the role actually needs (e.g. "build the admin panel"), do not default to the smallest interpretation. Flag it and ask Kurt to confirm the full feature boundary before implementing, rather than shipping a partial version and calling it done.

---

## 1. Locked Architecture Summary (context, not a task list)

| Layer | Choice |
|---|---|
| Mobile app | Flutter |
| Dispatcher dashboard | Next.js |
| Backend API | FastAPI |
| Database | Supabase (Postgres + PostGIS) |
| NLP | TF-IDF + Logistic Regression, multi-label, char n-grams, 15 structured signals |
| Severity | Rule-based rubric, separate per agency (BFP / PNP / MDRRMO), never ML |
| AI Chat (ResQ) | Claude API, assistive only, human-in-the-loop |
| Connectivity | Internet only. A report that cannot reach the backend is not sent — the resident is told plainly and directed to call 911. See Deviations Log 2026-09-24. |
| Core principle | AI never dispatches autonomously. Dispatcher override is absolute. |
| User roles | 4 roles: **Resident** (mobile, reports incidents), **Responder** (mobile, field officer — accepts/updates assigned incidents), **Agency Admin** (web dashboard, manages one agency: BFP/PNP/MDRRMO — triages incidents, dispatches Responders, manages accounts/rubric config), **Super Admin** (web dashboard, cross-agency oversight) |
| Mapping / geospatial UI | OpenStreetMap vector tiles via MapLibre GL (`maplibre_gl` for Flutter, `maplibre-gl` for Next.js) — **not Mapbox**. Self-hosted, Biliran-only offline MBTiles package. No API key, no usage-based billing. See rationale below. |

**Why MapLibre + OpenStreetMap over Mapbox (locked 2026-08-02):**

*Mapbox* — polished default styling, a built-in Navigation SDK with turn-by-turn guidance, traffic data, and better out-of-the-box search/geocoding. But: usage-based billing with no hard spending cap, offline tile downloads billed separately from the free MAU tier, requires an internet-connected account/API key to set up and periodically refresh styles, and an ongoing dependency on a foreign company's pricing decisions for a public-safety tool serving Biliran's own community.

*OpenStreetMap + MapLibre* — completely free forever, no API key, no billing risk, no per-user tile caps. One offline tile package can be pre-generated for all of Biliran (a small island — tens of MB, not gigabytes) and shipped with the app or served from Ziren's own Supabase/backend. Full control over styling, no vendor lock-in — a meaningfully better fit for a government-adjacent emergency system: the map layer must not silently degrade because a bill wasn't paid or a free tier was exceeded during a crisis surge. Tradeoff: no built-in turn-by-turn navigation SDK (bring-your-own routing, e.g. self-hosted OSRM/Valhalla, or just straight-line distance/ETA estimates), map styling needs more manual work, and OSM geocoding/search for Philippine addresses can be spottier in rural areas than Mapbox's — though Biliran's OSM road coverage is decent.

**Decision:** MapLibre GL + self-hosted OSM vector tiles for the base map and offline capability, across both `ziren_mobile` and `ziren_dashboard`. If Responders genuinely need turn-by-turn routing (not just "here's the incident location"), layer in a lightweight self-hosted OSRM instance for routing rather than pulling in Mapbox's Navigation SDK — keeps everything free and dependency-free, the same philosophy behind Section 1's other infrastructure choices. See Phase 6C for the build-out.

---

## 1.5 Finalized Feature List

This is the complete, agreed-upon feature set for Ziren. **Core Features (must-have)** are what the system is defended on and must be fully working. **Extended Features (nice-to-have)** add value but are not required for the system to be considered complete — they can be descoped without weakening the defense.

### Core Features (Required — Must Ship)

**Mobile App (Flutter)**
1. Login / Register (Resident, Responder, Agency Admin, Super Admin roles)
2. Incident Reporting — station/agency selection (manual, by Resident) → free-text, multilingual (Filipino/Bisaya/Waray/English), GPS location capture, optional voice-to-text, optional photo/video attachment
3. SOS Quick-Report — one-tap emergency shortcut with auto-suggested station (GPS-based), minimal confirmation, full verified identity attached (no anonymous submissions), anti-abuse safeguards (rate limiting, trust indicators, escalating consequences)
4. Report Status Tracking — citizen sees received/dispatched/resolved status
5. Resident Home/Dashboard — quick-access home screen (report status summary, quick-report entry points)
6. ResQ AI Chat — Claude-powered, assistive-only report guidance (5W1H)
7. Connectivity Handling — internet-only submission with an honest, checked-against-the-real-backend online/offline state shown before sending (see Deviations Log 2026-09-24 for why the originally-planned SMS/on-device-NLP/store-and-forward fallback layers were descoped), including draft/save of incomplete reports
8. Notifications — status updates to citizen
9. Settings/Profile Management — all roles (profile edit, notification preferences, emergency contacts for Resident, availability status for Responder)
10. Responder Mobile Experience — incident queue, accept/decline, status updates, navigation, availability toggle

**Dashboard (Next.js) — Agency Admin & Super Admin**
11. Live Incident Queue — real-time, severity-sorted (Agency Admin, scoped to their agency)
12. Incident Detail View — raw report, extracted signals, suggested severity/agency, map, reporter identity + trust/history indicators
13. Dispatch Action + Override — Agency Admin confirms/overrides suggested severity/agency and assigns a Responder; fully logged
14. Cross-Jurisdiction & Multi-Agency Routing
15. Agency Admin Panel — manage accounts, coverage areas, rubric config (Agency Admin scoped to own agency; Super Admin has cross-agency visibility)

**AI/Backend Engine**
16. NLP Signal Extraction — TF-IDF + Logistic Regression, 15 structured signals
17. Rule-Based Severity Rubric — per agency (BFP/PNP/MDRRMO), never ML
18. Human-in-the-Loop Dispatch — system-wide principle, no autonomous AI dispatch
19. Coverage-Area Validation — PostGIS check that flags mismatches between Resident-selected station and actual location coverage (backup/validation layer, not primary router)

### Extended Features (Optional — Future Work / Stretch Goals)
20. Analytics/Reporting Dashboard — incident trends, response time metrics per municipality
21. Report History/Heatmap — spatial visualization of incident concentration
22. Live Map of Responder En Route — real-time location sharing from Responder to Resident (privacy-sensitive, higher complexity)
23. Post-Resolution Rating/Feedback — citizen rates the response after an incident is resolved
24. Model Feedback Loop — dispatcher flags bad extractions to inform future retraining
25. Onboarding/Tutorial — first-time user walkthrough
26. Emergency Contacts/Quick Dial — hotline fallback if all connectivity layers fail

> **Defense tip:** present #1–19 as the delivered system. If time allows and #20–26 get built, present them as evidence of forward planning — but don't let them become required for a "successful" defense.

---

## 2. Development Phases & Tasks

Use these checkboxes to track progress. Suggested order — phases can overlap slightly, but do not start a phase whose dependencies aren't checked off.

### Phase 0 — Project Setup & Environment
- [x] Initialize Git repo with proper `.gitignore` (env files, build artifacts, secrets) — root + per-app .gitignores created
- [x] Set up Flutter project skeleton (folder structure: features/, core/, shared/) — lib/ restructured, main.dart replaced, core/config, core/errors, core/utils, shared/theme, shared/widgets created
- [x] Set up Next.js project skeleton for dashboard — ziren_dashboard/ scaffolded with Next.js 15 + TypeScript + Tailwind, app/(auth), app/(dashboard), lib/api, lib/types added
- [x] Set up FastAPI project skeleton (routers/, services/, models/, core/) — ziren_backend/ created with full folder structure, stubs for auth/incidents/dispatch routers, config, security, dependencies
- [x] Set up Supabase project (dev + staging environments, separate from production) — dev project (trajycnqsgoplscpmjbj) + staging project (yzqxlobjutnedfyjwuyf) created by Kurt
- [x] Configure environment variable management (.env.example committed, real .env gitignored) for all three apps — .env.example in ziren_mobile/, ziren_backend/, ziren_dashboard/; dart_defines.json created and gitignored for Flutter
- [ ] Set up CI basics (lint + test run on push) if time allows
- [x] **Security checkpoint:** confirm no API keys/secrets exist in any committed file — scanned 31 source files, 0 secrets found ✅

### Phase 0.5 — Design System & Dashboard UI **[RETROACTIVE — added per Rule 0.6]**
> All items below were built during Phase 6A implementation but were never itemized as checklist tasks. Added retroactively so the work is traceable and defensible. Single source of truth for the web surface is `ziren_dashboard/app/globals.css`; keep in sync with `ziren_mobile/lib/shared/theme/app_tokens.dart`.

**0.5.1 — Design tokens (globals.css)**
- [x] Define brand color (`#FC5A05`) and usage rule — CTAs, active nav, primary actions only; never for severity or errors
- [x] Define surface tokens (base, card, raised, overlay, border) for light theme
- [x] Define text scale tokens (primary, secondary, muted, disabled, inverse) with contrast ratios documented
- [x] Define 4-tier severity color system (critical/high/medium/low) — each tier has foreground, background, and border token; rule: always pair with icon + label, never color alone
- [x] Define workflow status color system (received/processing/dispatched/resolved/cancelled) — explicitly separated from severity tokens
- [x] Define system/validation tokens (success, warning, error, info)
- [x] Define agency identity tokens (BFP coral-red, PNP sky-blue, MDRRMO emerald) — locked hues, not to be repurposed for severity or status
- [x] Define AI-suggested token (purple, `#7C3AED`) — reserved for machine output only, never decorative
- [x] Define connectivity mode tokens (online/offline) — a third "sms" token existed briefly and was removed with the SMS gateway fallback (Deviations Log 2026-09-24)
- [x] Define typography scale (display, h1–h3, body-lg/body/body-sm, label, label-sm) with Nunito as primary font
- [x] Define spacing scale (2–64px, matching Flutter tokens)
- [x] Define border radius scale (sm/md/lg/xl/2xl/3xl/full)
- [x] Define shadow scale (sm/md/lg)
- [ ] **[2026-08-02, from 0.5.5 build]** Add `--color-brand-active: #C94600` token — active-nav-state text color, paired with the existing brand orange for pill backgrounds; mirror in `app_tokens.dart` to keep web/mobile in sync
- [ ] **[2026-08-02, from 0.5.5 build]** Resolve `--radius-2xl` (currently 20px) vs. the eGov-reference nav row radius (24px, Tailwind's default `rounded-2xl`) — before changing the shared token, audit existing usages of `--radius-2xl` across `ziren_dashboard`. If nothing else depends on 20px specifically, update the token to 24px. If something does, keep the token at 20px and use `rounded-2xl` as a documented one-off exception for the 0.5.5 sidebar nav rows only, noted here as to why.

**0.5.2 — Utility CSS classes**
- [x] Severity card pattern classes (`.severity-critical/high/medium/low`) — tinted bg + matching border + colored text
- [x] AI badge classes (`.badge-ai`, `.badge-confirmed`) — pill shape, purple/orange respectively
- [x] Typography utility classes (`.text-display`, `.text-h1`–`.text-h3`, `.text-body*`, `.text-label*`, `.text-mono`)

**0.5.3 — UI component library (`components/ui/`)**
- [x] `Button` — 4 variants (primary/outline/ghost/danger), 3 sizes (sm/md/lg), loading state with spinner, disabled state, focus ring using brand token; danger variant uses system-error not severity-critical
- [x] `Input` — label, error, helperText, leftIcon, rightElement slots; error state uses system-error border; focus ring uses brand token
- [x] `Alert` — 4 variants (error/warning/success/info), icon + message, all tokens from system palette; brand orange explicitly excluded per color rules

**0.5.4 — Dashboard shell & layout**
- [x] Sidebar shell (`app/(dashboard)/layout.tsx`) — fixed 56px-wide sidebar, wordmark + role label, nav items with active state, user email footer, sign-out action
- [x] Role-conditional nav — Accounts link shown only to Super Admin; sidebar label switches between "Dispatch Portal" and "Super Admin"
- [x] Client-side auth guard in layout — redirects to `/login` if no token or non-admin role
- [x] Severity color strip pattern on incident cards — 1.5px top border in severity color as visual anchor
- [x] Agency color coding throughout — BFP/PNP/MDRRMO badges consistently use locked agency tokens
- [x] Status pill pattern — rounded-full pill with status-specific bg/text token pair
- [x] Consistent card pattern — `surface-card` bg, `surface-border` border, `radius-lg`, `shadow-md` on hover

**0.5.5 — Sidebar redesign, eGov PH-inspired (decided in design review, not yet built)**
> **Gap found 2026-08-02, per Rule 0.6:** Kurt referenced the eGov PH app (by Bryl Lim) as the layout inspiration for Ziren's dashboard sidebar — this was discussed and a reference mockup was built, but the decision was never written into this plan, so the current 0.5.4 sidebar (56px, icon-rail width) still doesn't reflect it. Documenting it now so it's an explicit, trackable task instead of a chat-only decision that quietly didn't make it into the codebase.
>
> **Decision:** keep eGov PH's structural pattern — full labeled sidebar (not an icon-only rail), a primary nav list of icon+label rows, a "recent items" list section beneath the nav, and a bottom account footer with avatar + name + role + sign-out — but restyled entirely in Ziren's own light/orange design system (0.5.1 tokens), not eGov's dark theme. eGov PH is a layout/structure reference only, not a visual/color reference.
- [x] Widen the sidebar from the current 56px icon-rail to a full labeled sidebar (~256px) with icon + text label per nav row, matching eGov PH's structural pattern
- [x] Logo block at top: Ziren mark + wordmark, same position as eGov PH's app logo
- [x] Primary nav as icon+label rows (not icon-only), active state using a soft orange tint pill (bg `#FFF0E6` / text a darkened brand-orange shade) instead of the current active-state treatment — pull the exact tokens from 0.5.1, don't introduce new ones
- [x] Add a "Recent incidents" list section beneath the primary nav, mirroring eGov PH's "previous conversations" list — truncated title + timestamp/agency subtext per row, matching card pattern from 0.5.4
  - **Spec (confirmed 2026-08-02):** reuse `fetchQueue()` from `lib/api/dispatch.ts` (same `/dispatch/queue` endpoint as the queue page, already agency-scoped server-side) — no new endpoint. Show the **top 5 most recent by `created_at`** (time-sorted, newest first — not severity-sorted like the main queue). Each row: severity color dot + truncated report text + time-ago label, no agency badge (redundant given existing scoping). Super Admin sees cross-agency top 5, same scope as their main queue view — no agency selector in the sidebar.
- [x] Rebuild the bottom account footer to match eGov PH's account row: avatar circle (initials, brand-orange bg), name, role label, sign-out icon — replacing the current plain "user email footer"
  - **Spec (confirmed 2026-08-02):** `useAuth()` doesn't expose `full_name`. Fetch `GET /users/me` for the name (reuse the existing Resident-settings `/users/me` pattern/types if already shared); fall back to the email-prefix (part before `@`) for initials if `full_name` is null.
- [x] Confirm role-conditional nav (Super Admin vs. Agency Admin) still works correctly under the new layout — don't regress the 0.5.4 behavior while restyling
- [x] **Security checkpoint:** confirm no new nav item or recent-incidents entry exposes cross-agency data to an Agency Admin who shouldn't see it (same scoping rule as 6A.1)

### Phase 1 — Authentication & User Management (Login / Register)
This is the foundation everything else depends on — treat it as security-critical, not boilerplate.

- [x] Design `users` table schema (role: **resident / responder / agency_admin / super_admin**; agency affiliation — required for responder & agency_admin, null for resident & super_admin; verified/approval status — responders require agency approval before going on-duty, per old spec's approval_status pattern) — migration 001 + 001b; badge_id, approval_status, agency_required CHECK constraints all in place
- [x] Design RLS policies for `users` table (users can only read/edit their own row; Responders scoped to their own assigned incidents; Agency Admins scoped to their own agency's users/incidents only; Super Admin has cross-agency read/write) — 6 RLS policies in migration 001b
- [x] Implement Supabase Auth integration (email/phone + password, or OTP — decide based on rural connectivity realities) — email+password chosen; an SMS-based OTP would face the same outbound-SMS-credit blocker documented in Deviations Log 2026-09-24, so a future OTP would need a paid SMS API, not the phone-gateway approach
- [x] Build Register flow (Flutter): input validation, password strength rules, duplicate-account prevention — covers Resident and Responder signup (Responder signup includes agency + badge ID, pending approval) — register_screen.dart with role selector + conditional Responder fields
- [x] Build Login flow (Flutter): secure token storage (flutter_secure_storage, not shared_preferences), session handling — shared by Resident and Responder, role-based redirect after login (pending → pending screen, rejected → rejected screen, admin → dashboard notice)
- [x] Build password reset / account recovery flow — forgot_password_screen.dart, Supabase resetPasswordForEmail
- [x] Implement role-based access control (RBAC) middleware in FastAPI — resident vs responder vs agency_admin vs super_admin — require_role() + require_approved_responder() in core/dependencies.py
- [x] Build Agency Admin / Super Admin login for the Next.js dashboard (separate flow from Resident/Responder mobile login, stricter — consider 2FA for Agency Admin/Super Admin accounts). Role-based redirect: Agency Admin → own agency dashboard, Super Admin → cross-agency dashboard — app/(auth)/login/page.tsx enforces agency_admin/super_admin roles
- [x] Add session expiry + refresh token handling — /auth/refresh endpoint + Supabase session auto-refresh in Flutter
- [x] Add rate limiting on login/register endpoints (brute-force protection) — slowapi 10/minute on login/register, 5/minute on password reset
- [x] Write test cases: invalid input, duplicate registration, expired session, wrong-role access attempts (all 4 roles), Agency Admin attempting to access another agency's data, Responder attempting to self-approve — 15 tests, all passing ✅
- [x] **Security checkpoint:** attempt to access another user's/agency's data using a valid-but-wrong-role token — must fail for all 4 roles — resident→dispatch 403, pending responder→dispatch 403, agency_admin→dispatch 200, super_admin→dispatch 200 ✅

### Phase 2 — Database Schema & Core Data Model
- [x] Design `incidents` table (report text, location as PostGIS point, timestamp, reporter_id, status, agency routing, severity, signals JSON) — migration 002, all 15 signal columns in JSONB, spatial index on location
- [x] Design `agencies` / `stations` table (BFP, PNP, MDRRMO, coverage area as PostGIS polygon) — migration 002, GEOMETRY(POLYGON, 4326) with GIST index
- [x] Design `dispatch_log` table (audit trail — who dispatched, when, override history) — migration 002, append-only, records suggested vs chosen severity/agency, override flag + reason
- [x] Write RLS policies for every table above — agencies (auth read, admin update), incidents (resident own, responder/admin all, no delete), dispatch_log (agency_admin/super_admin read/insert only, no update/delete)
- [x] Set up PostGIS extension and spatial indexes for location queries — PostGIS enabled in migration 002, GIST indexes on incidents.location, agencies.coverage_area, stations.location
- [x] Seed test data (fake stations, coverage areas for Biliran's municipalities) — all 8 municipalities seeded × 3 agency types each; Naval stations seeded
- [x] **Security checkpoint:** verify a citizen account cannot query another citizen's raw incident report, and cannot alter `dispatch_log` — enforced by RLS: incidents SELECT checks reporter_id = auth.uid() OR responder/admin role; dispatch_log has no UPDATE/DELETE policy ✅

### Phase 3 — Core Incident Reporting (Mobile, Flutter)
- [x] Build incident report form (free-text input, language-agnostic — Filipino/Bisaya/Waray/English) — report_form_screen.dart with multilingual hint text
- [x] Integrate location capture (GPS with permission handling + graceful fallback if denied) — geolocator + permission_handler, location chip shows status, fallback if denied
- [x] Integrate speech-to-text for voice reports (if in current scope) — speech_to_text package, mic permission handling, Filipino English locale
- [x] Build report submission flow → FastAPI endpoint — IncidentRepository → POST /incidents/, auth token attached, reporter_id from server-side token
- [x] Build report status tracking screen (citizen sees their own report's status) — my_reports_screen.dart with status badges, pull-to-refresh, severity badges
- [x] Input validation & sanitization on both client and server — server: min 10 chars, max 5000 chars, lat/lng range check; reporter_id cannot be spoofed from client
- [x] **Security checkpoint:** confirm large/malformed payloads and script-injection attempts in free text are rejected safely server-side — 10 tests passing: oversized payload (422), empty text (422), lat/lng out-of-range (422), script injection stored as plain text not executed, reporter_id spoof ignored ✅
- [x] **[NEW]** Build station/agency selector as first step of report flow — station_selector_screen.dart, StationRepository (Supabase direct), grouped by BFP/PNP/MDRRMO with agency color coding, station_id required in IncidentSubmitRequest, agency resolved server-side from station
- [x] **[NEW]** Build photo/video attachment upload (Supabase Storage) — image_picker, MediaUploadService, media_urls JSONB column (migration 003b), max 5 files/50MB each, thumbnails in form, NOT fed into NLP
- [x] **[NEW]** Build Resident Home/Dashboard screen — resident_home_screen.dart with quick-action cards (Report/My Reports), recent incidents summary, greeting, replaces form-only /home route
- [x] **[NEW]** **Security checkpoint:** confirm uploaded media is scoped to the reporting Resident + assigned agency only, not publicly accessible via direct URL — bucket is private, 3 RLS policies verified (upload/read/delete), media_urls + station_id columns confirmed ✅
- [ ] **[NEW — 2026-07-22]** Replace single free-text report field with structured 5W1H wizard — ✅ All sub-tasks complete (see checked items below)
  - [x] Build incident-type category selector screen (Fire, Medical/Trauma, Vehicular, Flood/Landslide/Calamity, Domestic Dispute/Crime, HAZMAT, Missing Person, Other) — `wizard_category_screen.dart`, 8-category grid with agency/severity color tokens
  - [x] Build category-specific follow-up question screens (3–5 quick-choice questions per category + optional free-text catch-all) — `wizard_questions_screen.dart`, Filipino-language chip questions per all 8 categories, voice-to-text catch-all
  - [x] Build multi-select "may kasama pa bang..." step for overlapping-concern flagging (feeds Phase 6A/Phase 9 multi-agency routing — not a new pipeline) — `wizard_overlap_screen.dart`
  - [x] Add optional landmark-note field alongside auto-captured GPS location — `wizard_who_screen.dart` step 4
  - [x] Add relationship-to-victim question to the Who step (ako mismo / kamag-anak / kakilala / estranghero) — `wizard_who_screen.dart` step 4
  - [x] Build 5W1H review/summary screen shown before final submit — `wizard_review_screen.dart`, all sections with "Baguhin" edit links; media attachment picker added in this session
  - [x] Route "Other"/catch-all free text through the existing Phase 4 NLP pipeline, flagged low-confidence for dispatcher review — `nlp_review_needed=True` set server-side for category=other, confirmed by tests
  - [x] Update/rewrite existing Phase 3 test suite to cover the new wizard flow — `test_incidents.py` 36 tests (27 original + 9 new security checkpoint), all passing; `conftest.py` rate-limiter reset fixture added
  - [x] **Security checkpoint:** confirm all new wizard endpoints keep the same auth/validation guarantees as the original free-text submission — `TestWizardSecurityCheckpoint` (9 tests): role blocking, reporter_id spoof prevention, XSS plain-text storage, enum enforcement, nlp_review_needed server-side computation ✅
This is a parallel, faster path alongside the regular multi-step report — not a replacement. See cross-check doc (`ZIREN_PLAN_CROSS_CHECK.md`) for full design rationale.

- [x] Build SOS button UI (prominent, accessible from Resident home/dashboard) — `_SosActionCard` in resident_home_screen.dart; red critical color, cooldown state displayed inline
- [x] Auto-suggest station based on GPS + PostGIS coverage-area lookup (reuses Phase 9 logic) — implemented as Haversine nearest-station in `_resolve_nearest_station()`; Phase 9 PostGIS upgrade noted in code comment
- [x] Build minimal confirmation screen ("Send SOS to [Agency - Station]?") with legal-consequence warning text — `sos_confirm_screen.dart`; GPS status, optional description (max 500 chars), legal checkbox required before submit
- [x] Attach full verified reporter identity automatically (name, phone, account status, report history) — reporter_id always from server-side JWT; `sos_warning_count`, `is_verified`, `sos_suspended_until` fetched in `submit_sos()` before writing
- [x] Implement SOS-specific rate limiting/cooldown (max submissions per account per time window) — server-side: 30-min cooldown via `sos_last_submitted_at`, IP-level: `3/hour` via slowapi; client-side advisory cooldown in `SosProvider`
- [x] Build trust/history indicator for dispatcher view (flags new accounts, accounts with past flagged false reports) — `sos_flagged` column on `incidents` set to `true` when `sos_warning_count >= 1`; informational only, does not auto-reject
- [x] Build follow-up details prompt (shown *after* SOS is dispatched, only if connectivity/time allows) — `sos_success_screen.dart` follow-up section; non-blocking, SOS already sent before this appears
- [x] Implement escalating consequences logic (warning → SOS-access suspension → full account suspension) for confirmed false SOS reports — `record_false_sos()` in service layer; `sos_warning_count` increments, `sos_suspended_until` set at threshold 3 (+30 days); Super Admin clears suspension
- [x] Write test cases: rate limit enforcement, identity attachment, coverage-area mismatch handling — 26 tests in test_sos.py, all passing ✅
- [x] **Security checkpoint:** confirm SOS reports cannot be submitted without a verified, authenticated account; confirm rate limiting cannot be bypassed by rapid re-registration — no-auth → 403, responder/admin → 403, cooldown bypass via body injection → 429, station_id/sos_flagged not in request model confirmed ✅

### Phase 4 — NLP Signal Extraction Pipeline
> **⚠️ BLOCKED (as of 2026-07-27):** Labeled dataset (~800–1000 rows) is not yet obtainable — station-level incident data is confidential and it is not certain the stations will release it at all. Do not stall the project waiting on this. **Phase 5 (Severity Rubric) does not depend on this phase being complete** — the rubric only needs the *shape* of the 15 signals (already finalized as a schema, see Phase 2/Section 1), not a trained model. Build and test Phase 5 against hand-authored/mocked signal payloads now; wire in the real NLP output later as a drop-in replacement once (or if) a dataset materializes. If no dataset is ever obtained, on-device/manual signal tagging by dispatchers (Phase 6A "Incident Detail View") can serve as the signal source instead of trained NLP — flag this as a fallback scope decision to make during Phase 14 defense prep if Phase 4 remains unresolved.

- [ ] Prepare/finalize labeled dataset (~800–1000 rows, multilingual, augmented) — **blocked, see note above**
- [ ] Train TF-IDF + Logistic Regression multi-label model for the 15 signals
- [ ] Wrap model behind a FastAPI internal service/endpoint
- [ ] Add model versioning (so retraining doesn't silently break production)
- [ ] Add confidence thresholds — low-confidence extractions should be flagged for dispatcher review, not silently trusted
- [ ] Write evaluation tests (precision/recall per signal, not just overall accuracy)
- [ ] **Security checkpoint:** confirm the NLP service cannot be reached directly by unauthenticated clients (internal-only)

### Phase 5 — Severity Rubric Engine (Rule-Based)
> **Status: unblocked, proceed now — no longer waiting on Phase 4.** This engine is a **rule-based decision system** (an explicit, traceable expert-system-style scoring engine), not a placeholder for missing ML. Treat its rigor as a first-class CS contribution of the capstone, not a workaround — it must be defensible to a panel on its own terms: explainable, testable, and empirically grounded in the field interviews, independent of whether Phase 4's dataset ever arrives.

**5.1 — Rubric design & structure**
- [x] Define the rubric as a **decision table / weighted scoring structure**, not nested if-else — one table per agency (BFP / PNP / MDRRMO), each row mapping a signal condition (or combination of signals) to a severity contribution — `app/rubric_configs/BFP_v1.json`, `PNP_v1.json`, `MDRRMO_v1.json` (10/12/15 rules, versioned JSON); `app/models/rubric.py` (RubricRule, RubricCondition, RubricConfig, SEVERITY_RANK)
- [x] Define the severity output scale explicitly (`critical/high/medium/low`) and aggregation rule — **max-of-triggered-rules** selected and justified: conservative for life safety, consistent with CAP; `SEVERITY_RANK` dict in `rubric.py`, aggregation in `rubric_service.py`
- [x] Store each rubric as **versioned config** (DB table `rubric_configs` + JSON seed fallback) — migration 007, `RubricConfigUploadRequest`/`RubricConfigActivateRequest` API
- [x] Encode field-validated rules per agency as explicit, readable rules — all 37 rules visible in JSON files with clear `description` and `conditions` fields

**5.2 — Traceability to field research**
- [x] For every rule, attach a short provenance note — all 37 rules carry `provenance` field with `TODO: cite [agency] field interview date/station — [what dispatch practice it encodes]`; startup provenance checker warns on every unfilled TODO; `KNOWN_SCENARIOS` placeholder in `rubric_traceability.py`
- [x] Cross-check encoded rules against real dispatch-failure case — `KNOWN_SCENARIOS` list in `rubric_traceability.py` with 3 placeholder entries (BFP/PNP/MDRRMO); `TestKnownScenarios` in `test_rubric_engine.py` skips with explicit message until Kurt fills in field interview values

**5.3 — Engine implementation**
- [x] Build rubric evaluation service — `app/services/rubric_service.py`: `evaluate()`, `upload_config()`, `activate_config()`, `get_active_config()`, `get_audit_log()`; `app/routers/rubric.py`: 7 endpoints
- [x] Accept hand-authored/mocked signal payloads (Phase 4 blocked) — `evaluate()` accepts `dict`, `ExtractedSignals`, or any object with `__dict__`/`model_dump()`
- [x] Signal source is swappable — `_normalise_signals()` normalises all input types; rubric logic unchanged regardless of source

**5.4 — Testing rigor**
- [x] Write test cases for every rubric branch — 220 rubric tests across 4 files: `test_rubric_engine.py`, `test_rubric_bfp.py`, `test_rubric_pnp.py`, `test_rubric_mdrrmo.py`
- [x] Edge cases: conflicting signals, missing/null signals, boundary conditions — `TestNullAndMissingSignals`, `TestConflictingSignals`, `TestBoundaryConditions` in engine tests
- [x] Test matrix per agency — `TestBFPMatrix`, `TestPNPMatrix`, `TestMDRRMOMatrix` parametrized tables (signal combination → expected severity), reviewable as defense exhibit

**5.5 — Security & governance**
- [x] **Security checkpoint:** confirm only authorized roles can modify rubric configuration, every change is logged — `tests/test_rubric_security.py`: 10 security claims, 48 tests, all passing ✅

**5.6 — Defense prep (feeds Phase 14)**
- [ ] Draft the "why rule-based, not ML" explanation now while the reasoning is fresh: explainability requirement for life-critical dispatch, alignment with each agency's existing CAP standards, dataset unavailability/confidentiality as a contributing (not sole) factor, and the architecture's built-in path to layer ML on top later (Phase 15 model feedback loop) if data becomes available

### Phase 6A — Agency Admin Dashboard (Next.js) **[RENAMED from Phase 6]**
> **Scope note:** this phase must deliver Section 1.5 Feature #15 in full — "Agency Admin Panel: manage accounts, coverage areas, rubric config" — not just the incident queue/dispatch slice. Sub-sections 6A.1–6A.4 below break that out explicitly so none of it gets silently dropped.

**6A.0 — Menu / Navigation Structure (Reference — locked, do not add items without flagging)**
> This is the authoritative sidebar/nav structure for the dashboard shell (`app/(dashboard)/layout.tsx`). Every item here maps 1:1 to a sub-phase already scoped below (6A.1–6A.5) and to a Section 1.5 Core Feature. **Kiro must not add a menu item beyond this list without first flagging it as a scope change per Rule 0.1** — the earlier draft explored during planning (resource inventory, in-app chat, escalation buttons, public transparency page, backup/DR settings, etc.) was **not adopted**; those either duplicate an existing mechanism, belong to a different phase, or were never locked in Section 1.5 and are explicitly out of scope unless added here first.

| # | Menu Item | Route | Visible To | Feeds Feature(s) | Purpose — why this item exists |
|---|---|---|---|---|---|
| 1 | **Incident Queue** (dashboard landing page) | `/queue` | Agency Admin (agency-scoped), Super Admin (all agencies) | #11 Live Incident Queue | This is the operational front line — a real-time, severity-sorted list of what needs a human decision *right now*. Without this as the landing page, a dispatcher has to go looking for urgent work instead of it surfacing to them. Severity-sort exists because in an emergency system, the cost of a dispatcher scrolling past a critical case to reach a low one is measured in response time, not UX friction. |
| 2 | *(drill-down, not a nav item)* Incident Detail | `/incidents/[id]` | Same as above | #12 Incident Detail View | Not a menu item on purpose — reached only by clicking a queue row. Shows raw report, extracted signals, suggested severity/agency, map, reporter trust/history. Purpose: the dispatcher needs to see *why* the AI suggested what it suggested before confirming or overriding it — this is what makes Rule 0.3 (AI is assistive, human has final say) actually enforceable in the UI, not just in the backend. |
| 2.5 | **Incident History** | `/incidents` | Agency Admin (agency-scoped), Super Admin (all agencies) | #12 Incident Detail View (extended), Section 0.2 audit traceability | `/queue` deliberately excludes `resolved`/`cancelled` incidents (see `get_incident_queue()`) so the live queue stays focused on incidents that still need action. But that means a resolved/cancelled incident becomes unreachable from anywhere in the dashboard unless a separate history view exists. This page is that view — same underlying data, no status filter applied, with a filter dropdown covering all 7 statuses. Purpose: without it, the append-only `dispatch_log` (Section 0.2) has no matching UI to actually browse past cases — auditability would exist only in the raw database, not for a dispatcher or Super Admin doing a real review. |
| 3 | **Responders** | `/responders` | Agency Admin only (own agency roster) | #15 Agency Admin Panel (accounts, own-agency scope) | An Agency Admin's dispatch decisions in the queue depend on knowing who's available *right now*. This page is where that roster, badge IDs, and availability live — separated from the queue so the "who can I assign" question doesn't clutter the "what needs attention" queue view. |
| 4 | **Accounts** | `/accounts` (Agency Admins tab + All Accounts tab) | Super Admin only | #15 Agency Admin Panel (cross-agency scope) | Replaces "Responders" in the Super Admin's nav — a Super Admin doesn't manage one agency's field roster, they manage *who has Agency Admin power at all three agencies*, plus need a searchable cross-agency directory for oversight/audit purposes. Kept as a separate route from `/responders` because the permission boundary (own-agency vs. cross-agency) is a security boundary, not just a UI preference — see the 6A.2 security checkpoint. |
| 5 | **Coverage** | `/coverage` | Agency Admin (own agency's stations), Super Admin (all stations) | #14 Cross-Jurisdiction & Multi-Agency Routing, #19 Coverage-Area Validation | This is the maintenance UI for the polygons that feed `check_station_coverage()` (Phase 9). Without an editable, visible coverage map, jurisdiction boundaries silently rot as barangays get added/reassigned, and the coverage-mismatch warning banner on the Resident's report form becomes unreliable. Stations with no polygon are flagged, not hidden, because a silent gap here is a silent gap in dispatch accuracy. |
| 6 | **Rubric** | `/rubric` bare route auto-redirects Agency Admin to `/rubric/[their-agency]`; Super Admin sees a 3-card agency selector at `/rubric` and navigates to `/rubric/[agency]` | Agency Admin (own agency only, no selector shown), Super Admin (agency selector, all three) | #17 Rule-Based Severity Rubric | Severity is a rule-based rubric per Rule 0.3, not an ML output — which means it must be inspectable and versioned by a human, not a black box. This page is where a rule set is viewed, uploaded/activated, and audited, so the rubric stays defensible ("show us exactly which rule fired and why") rather than being a hardcoded value nobody can trace. Agency Admin is auto-redirected rather than shown a selector because they only ever have one valid option — presenting the other two agencies' cards (which the backend would 403 on anyway) surfaces a choice that was never really available, which is confusing rather than flexible. |
| 7 | **Settings** | `/settings` | Agency Admin (own agency profile + notification toggles), Super Admin (agency selector + station roster add/deactivate) | #9 Settings/Profile Management (Agency Admin/Super Admin scope) | Agency identity data (name, contact, coverage municipalities) and per-severity alert preferences need to live somewhere outside the operational flow. Station add/deactivate is Super-Admin-only here (not on `/coverage`, which only edits *polygons* of existing stations) because creating/retiring a station is an organizational change, not a boundary edit — different blast radius, different permission. |

**6A.1 — Incident queue & dispatch (built)**
- [x] Build incident queue view (sorted by severity, live updates) — `app/(dashboard)/queue/page.tsx`, 15s auto-refresh, severity-sorted, agency-scoped for Admin / all for Super Admin
- [x] Build incident detail view (raw report, extracted signals, suggested severity/agency, map location, reporter identity + trust/history indicators) — `app/(dashboard)/incidents/[id]/page.tsx`, full 5W1H wizard answers, dispatch log, reporter trust indicators
- [x] Build dispatch action UI — Agency Admin confirms/overrides AI suggestion, then assigns a Responder — `_DispatchModal` with severity selector, responder list, override reason enforcement
- [x] Build dispatcher override logging (what was suggested vs. what was chosen, and why) — `dispatch_service.py` writes to `dispatch_log` on every action; `was_override` flag + `override_reason` required
- [x] Real-time updates (Supabase realtime or websockets) for new incidents — 15s polling (Supabase Realtime subscription is Phase 10 infrastructure — dashboard uses polling for simplicity)
- [x] **[NEW]** Build Super Admin cross-agency view (all agencies, not scoped to one) — `dispatch_service.get_incident_queue()` returns all incidents when role=super_admin; Agency Admin filtered by agency_id
- [x] **[NEW]** Role-based conditional rendering: Agency Admin view vs. Super Admin view sharing the same dashboard shell — `app/(dashboard)/layout.tsx` shared shell, sidebar shows role
- [x] Build resolve + cancel incident actions — `POST /dispatch/queue/{id}/resolve` + `POST /dispatch/queue/{id}/cancel`; both logged in dispatch_log
- [x] Build flag-false-SOS action — `POST /dispatch/queue/{id}/flag-false-sos`; delegates to `incident_service.record_false_sos()`
- [x] **Security checkpoint:** confirm dispatch actions are only possible by authenticated Agency Admin/Super Admin roles — `require_role("agency_admin", "super_admin")` on all `/dispatch/*` routes; client-side session guard in layout.tsx
- [x] **Security checkpoint:** confirm Super Admin queries return cross-agency data while Agency Admin queries remain agency-scoped — service-layer check: Agency Admin filtered by `agency_id`, Super Admin unfiltered; backed by RLS ✅

**6A.2 — Account management (complete)**
- [x] Responder management page: list, approve, reject, revoke — built during 6A, recorded per Rule 0.6
- [x] Agency Admin: view/manage own agency's Responder roster in one place (status, badge ID, availability, assigned incidents count) — existing `/responders` page covers this; availability and badge ID shown per row
- [x] Super Admin: view/manage Agency Admin accounts across all three agencies (create, deactivate, reassign agency) — `/accounts` page, Agency Admins tab; `POST /users/super/agency-admins`, `PATCH /users/super/agency-admins/{id}` backend endpoints
- [x] Super Admin: cross-agency account directory (all roles, all agencies, filterable) — `/accounts` page, All Accounts tab; `GET /users/super/directory?role=&agency_id=` backend endpoint
- [x] **Security checkpoint:** confirm Agency Admin account actions stay scoped to their own agency; only Super Admin can act on Agency Admin accounts — `_super_admin_only` dependency on all `/super/*` endpoints; `_admin_only` on `/agency/*` endpoints; agency scope enforced in service layer ✅

**6A.3 — Coverage area management (complete)**
- [x] Build a view of each station's coverage-area polygon on a map (Agency Admin: own agency's stations; Super Admin: all stations) — `/coverage` page, stations grouped by agency with polygon status indicator (defined/missing)
- [x] Build edit UI for a station's coverage-area polygon (feeds the existing `check_station_coverage()` PostGIS function from Phase 9 — no change to that function's logic, only to how its input polygons are maintained) — inline coordinate editor (textarea, one `lng, lat` per line); `PATCH /stations/{id}/coverage` backend endpoint; `TODO 6C.3` marker left for MapLibre upgrade
- [x] Show stations with no coverage polygon defined yet as a flagged/incomplete state, not a silent gap — `AlertTriangle` icon + "No polygon" badge + page-level missing-count alert
- [x] **Security checkpoint:** confirm only Agency Admin (own agency) or Super Admin can edit coverage polygons; Responders/Residents have no access to this view — `_admin_only` dependency on all `/stations/*` endpoints; agency scope enforced in `update_coverage()` service layer ✅

**6A.4 — Rubric configuration UI ✅ Complete**
- [x] Build a rubric rule viewer: list the active rule set per agency (BFP/PNP/MDRRMO) in readable form, not raw JSON — `app/(dashboard)/rubric/[agency]/page.tsx` RulesTab with expandable rule cards, condition table, severity badges, TODO-provenance warnings
- [x] Build rubric config upload/activate UI wired to the existing `rubric_service.py` endpoints (`upload_config`, `activate_config`, `get_active_config`, `get_audit_log`) — JSON file upload, version list (VersionsTab), confirmation dialog with audit-log reason field; Agency Admin scope enforced server-side via `_assert_agency_scope()`
- [x] Build rubric change audit log view (who changed what rule set, when) surfaced from `get_audit_log()` — AuditTab with event-type badges, timestamps, actor IDs, notes
- [x] **Security checkpoint:** upload/activate actions require `agency_admin`/`super_admin` token — `require_role` + `_assert_agency_scope` enforced at API layer; dashboard passes token directly, 403 surfaces as Alert; Resident/Responder tokens cannot reach any rubric endpoint

**6A.5 — Agency Admin & Super Admin settings ✅ Complete**
- [x] Agency Admin: agency profile edit screen (agency name, coverage municipalities, contact info, email) — `PATCH /stations/agencies/{id}` backend; `AgencyProfileCard` in `/settings` page
- [x] Agency Admin: notification rules config (per-severity alert toggles: critical/high/medium/low) — `notification_rules JSONB` on agencies table (migration 009); `NotificationRulesCard` with toggle switches, persisted via `PATCH /stations/agencies/{id}`
- [x] Super Admin: agency selector + per-agency profile/notification settings across all agencies — `SuperAdminSection` with agency dropdown wired to same profile/notification cards
- [x] Super Admin: station roster management (add station `POST /stations/`, soft-deactivate `PATCH /stations/{id}/deactivate`) — `StationManagementSection` with create form + per-agency grouped list; separate from 6A.3 coverage polygons
- [x] **Security checkpoint:** `_assert_agency_write_scope()` blocks Agency Admin from writing to a different agency's profile; `_super_admin_only` dependency on create/deactivate station endpoints; RLS policy "agencies: admin updates own agency" enforces scope at DB level as second layer

### Phase 6B — Responder Mobile Experience (Flutter) **[NEW PHASE]**
No dedicated phase previously covered this — Responder is a mobile-first role per Section 1 and needs its own build-out, distinct from the Agency Admin web dashboard.

> **Scope note (added 2026-08-02, per Rule 0.6):** split into 6B.1–6B.3 so the Profile tab and the notification gap don't stay hidden inside a "Complete" checkbox the way 6A's account/coverage/rubric gaps did.

**6B.1 — Queue, detail, status FSM, navigation (built)**
- [x] Build Responder incident queue view (mobile) — `responder_home_screen.dart`, assigned incidents only, severity-sorted, availability toggle, active incident badge
- [x] Build incident detail view (mobile) — `responder_incident_detail_screen.dart`, full detail + reporter identity + emergency contacts + trust indicators
- [x] Build accept/decline assignment action — status advance FSM: dispatched → en_route → arrived → resolved; confirmation dialogs before each transition
- [x] Build status update actions (en route → arrived → resolved) — `PATCH /responder/queue/{id}/status`; forward-only FSM validated server-side
- [x] Build availability toggle (on-duty/off-duty) — `responder_home_screen.dart` availability banner + switch; `PATCH /responder/availability`
- [x] Integrate navigation/routing to incident location — tap-to-launch via `geo:` URI (Google Maps / native maps)
- [x] Build separate Responder shell with own nav bar (Queue / Map / Profile, no SOS FAB) — `responder_shell.dart`, 3-tab nav, badge count on Queue tab
- [x] Wire Responder routing in auth — `auth_provider.navigateAfterAuth()` sends approved Responders to `/responder/queue`
- [x] Add `availability` column to `users` + `assigned_responder_id` + `en_route`/`arrived` status values — migration 008_responder_fields.sql
- [x] **Security checkpoint:** confirm Responder can only view/update incidents assigned to them — `responder_service.get_my_queue()` filters by `assigned_responder_id = responder_id`; detail endpoint raises 403 if not assigned ✅

**6B.2 — Profile tab content (complete)**
- [x] Build the actual Profile screen behind the existing "Profile" tab in `responder_shell.dart` — `responder_profile_screen.dart` created
- [x] Show profile/credentials: name, badge ID, agency, approval status — read-only `_CredentialCard` section
- [x] Allow Responder to edit their own editable profile fields (reuse the `PATCH /users/me` pattern from Phase 10.5 Resident settings, same allowlist-based restriction) — reuses `ProfileProvider.saveProfile()`, passes through all non-editable fields unchanged
- [x] **Security checkpoint:** confirm Responder can only view/edit their own profile fields, same guarantee as Rule already enforced for Resident settings — `user_id` always from JWT in `PATCH /users/me`; `_ALLOWED_UPDATE_FIELDS` allowlist on server unchanged ✅

**6B.3 — Push notification on new assignment (complete)**
- [x] Notify the Responder in real time when a new incident is dispatched to them — `ResponderNotificationProvider` created with Supabase Realtime subscription
- [x] Reuse the Supabase Realtime pattern from Phase 10 (`postgres_changes` subscription), filtered by `assigned_responder_id`, instead of relying on the Responder manually refreshing the queue — INSERT event triggers `onNewAssignment` callback which calls `ResponderProvider.loadQueue()` automatically
- [x] In-app banner + badge on the Queue tab, consistent with how Resident notifications work — `_AssignmentBanner` on `responder_home_screen.dart`; Queue tab badge already driven by `provider.activeCount` which updates on queue reload
- [x] **Security checkpoint:** confirm the Realtime channel is filtered server-side by `assigned_responder_id = auth.uid()`, same guarantee as the Resident-facing channel from Phase 10 — `PostgresChangeFilter(type: eq, column: assigned_responder_id, value: userId)` on both INSERT and UPDATE events ✅

### Phase 6C — Mapping Infrastructure (MapLibre + OpenStreetMap) **[NEW PHASE — 2026-08-02]**
> Cuts across `ziren_mobile` and `ziren_dashboard`, so it gets its own phase rather than being buried inside 6A or 6B. See Section 1 for the Mapbox-vs-OSM decision and rationale. Feeds the map views already referenced in 6A.1 (incident detail map), 6A.3 (coverage-area polygon view/edit), and Resident/Responder incident-location display.

**6C.1 — Offline tile pipeline**
- [ ] Generate a Biliran-only offline MBTiles package from OpenStreetMap data (expect tens of MB, not gigabytes, for an island this size)
- [ ] Decide where the tile package lives: bundled with the app build vs. served from Ziren's own backend/Supabase Storage — document the choice and why
- [ ] Define the update/refresh process for the tile package (OSM data changes over time — decide how often to regenerate, not a one-time static asset with no refresh path)

**6C.2 — Mobile integration (`ziren_mobile`)**
> **Pre-work finding (2026-08-02, flagged by Kiro before writing code, per Rule 0.1):** an existing `map_screen.dart` already uses `flutter_map` (not `maplibre_gl`) and calls `tile.openstreetmap.org` directly at runtime. This was never itemized in this plan — same class of undocumented drift as the account-management/coverage-area gaps found in 6A. It conflicts with the locked mapping stack (Section 1) and independently violates 6C.5 (no runtime third-party tile dependency) even though it's OSM and not Mapbox — the public OSM tile server has a usage policy that production apps aren't meant to hit directly, and every map open currently sends incident/reporter location to that third-party server over the network. **Resolution: 6C.2 replaces `map_screen.dart`'s `flutter_map` implementation — it is not an addition alongside it.**
- [ ] Remove `flutter_map` dependency and its direct `tile.openstreetmap.org` calls from `map_screen.dart` — do not leave both implementations running side by side
- [ ] Wire `maplibre_gl` into Flutter; render the offline Biliran tile package
- [ ] Resident: show incident location on a map (report form / My Reports / incident detail), not just raw lat/lng
- [ ] Responder: show incident location on a map in `responder_incident_detail_screen.dart`, alongside the existing tap-to-launch external-navigation `geo:` link (6B.1) — the embedded map is for context, not a navigation-SDK replacement
- [ ] Confirm the map renders correctly fully offline (core requirement — this is the whole point of self-hosting the tiles)
- [ ] **Security checkpoint:** confirm no remaining code path in `ziren_mobile` calls `tile.openstreetmap.org` or any other third-party tile host at runtime

**6C.3 — Dashboard integration (`ziren_dashboard`)**
- [ ] Wire `maplibre-gl` into Next.js; render the same Biliran tile package
- [ ] Incident detail view (6A.1): replace/upgrade the current map location display with the MapLibre map
- [ ] Coverage-area management (6A.3): build the polygon viewer/editor on top of this MapLibre integration, not a separate map library
- [ ] Confirm no external API key or network call to a third-party tile host is required at runtime

**6C.4 — Routing (only if a genuine turn-by-turn need is confirmed — do not build speculatively)**
- [ ] Confirm with Kurt whether straight-line distance/ETA estimates are sufficient, or whether Responders genuinely need turn-by-turn routing
- [ ] If needed: stand up a lightweight self-hosted OSRM (or Valhalla) instance for Biliran's road network — do not pull in Mapbox's Navigation SDK, per the locked mapping-stack decision
- [ ] If not needed: leave this sub-section unbuilt and note the decision in the Deviations Log rather than leaving it silently unaddressed

**6C.5 — Security & governance**
- [ ] **Security checkpoint:** confirm the app/dashboard never makes a runtime network call to a third-party map/tile provider that could leak incident location or reporter location data externally
- [ ] **Security checkpoint:** confirm offline tile packages and any self-hosted OSRM instance don't expose Ziren's internal network or credentials

### Phase 7 — Connectivity Handling
- [x] Implement internet-based submission (already covered in Phase 3, this is the "happy path")
- [x] Implement an honest online/offline check against the real backend (not just the phone's radio state) — see Deviations Log 2026-09-24
- [x] **Descoped, not built:** SMS gateway integration. Built end-to-end (resident-side send, backend `/sms/inbound` webhook, a MacroDroid-based gateway phone) and tested on real hardware — the send path itself is sound, but sending an SMS from the resident's own phone always costs money against that SIM's balance, which is a carrier-billing fact no app code can remove or work around. Removed rather than left half-working. See Deviations Log 2026-09-24 for the full reasoning and what a proper paid-SMS-API alternative would need.
- [ ] Implement on-device NLP fallback (lightweight local model or rule-based extraction when the internet is unavailable) — never built; remains a legitimate option if this is revisited, independent of the SMS decision above
- [ ] Implement store-and-forward (queue reports locally on device, sync when connectivity returns) — never built
- [ ] **[NEW]** Implement draft/save for incomplete reports (shares local-storage mechanism with store-and-forward queue)
- [x] Write tests simulating the failure modes that exist today (no internet, the server refusing a report, a save that succeeds but whose reply is unreadable) — see `test/incident_repository_test.dart`, `test/backend_health_test.dart`, `test/media_upload_error_test.dart`
- [ ] **Security checkpoint:** confirm queued/offline reports are stored securely on-device (encrypted local storage) and not lost or corrupted on sync — not applicable until store-and-forward is built

### Phase 8 — ResQ AI Chat (Claude API, Assistive Only)
> **Positioning note (see Deviations Log 2026-07-22):** This is an **alternate entry point** into the same 5W1H schema the Phase 3 wizard produces — not a separate reporting path. Default for most Residents is the structured wizard (faster, works offline, no AI cost); AI Chat is opt-in for Residents who prefer natural conversation, find the wizard hard to navigate, or have an ambiguous/multi-incident situation that doesn't map cleanly to fixed categories. Output from either path must converge on the same review screen and the same NLP/severity pipeline — no special bypass for AI-originated reports.
- [ ] Design chat UI for citizens (guides them through providing a clear report — 5W1H framework)
- [ ] Integrate Claude API for conversational assistance only — no autonomous decisions
- [ ] Ensure chat output feeds into the *same* human-reviewed pipeline as any other report (no special bypass)
- [ ] Add clear UI signaling to the user that they're talking to an AI assistant, not a live dispatcher
- [ ] **Security checkpoint:** confirm the Claude API key is server-side only, never exposed to the client; confirm chat cannot trigger a dispatch action directly

### Phase 9 — Multi-Agency Routing Logic **[REDEFINED — see Deviations Log 2026-07-10]**
> **Role change:** Originally designed as the *primary* agency router. Since station selection is now manual (Resident-driven, see Phase 3), this phase is now a **coverage-area validation/backup layer**, not the primary routing mechanism.

- [x] Implement PostGIS coverage-area check that validates the Resident's manually-selected station against actual location coverage — `check_station_coverage()` SQL function (migration 005), `GET /incidents/coverage-check` endpoint, `checkStationCoverage()` in `IncidentRepository`, `checkCoverage()` in `IncidentProvider`, `_CoverageMismatchBanner` on report form — fail-open ✅
- [x] Flag mismatches for dispatcher review (e.g., Resident selected a station outside their actual coverage area) rather than silently auto-correcting — warning banner shown in report form UI, never blocks submission ✅
- [x] Retain agency-matching logic (incident type + coverage area) as a *fallback suggestion* only — used for SOS auto-suggestion (Phase 3B) and for flagged mismatches — Haversine nearest-station in `_resolve_nearest_station()`; Phase 9 PostGIS RPC now available for upgrade ✅
- [ ] Handle multi-agency incidents (e.g., fire with injuries → BFP + MDRRMO) — still relevant as a suggestion layer for the dispatcher (Phase 6A concern, not Resident)
- [ ] Handle cross-jurisdiction routing when the nearest station isn't the "owning" jurisdiction (Phase 6A concern)
- [x] **Security checkpoint:** confirm agency accounts only see incidents routed to them, not the full incident database — enforced by RLS from Phase 2; coverage-check endpoint requires auth, read-only, returns no user data ✅

### Phase 10 — Notifications
- [x] Push notifications to citizen (report received, status updates) — Supabase Realtime `postgres_changes` subscription on `incidents` table filtered by `reporter_id`; `NotificationProvider` manages unread list; in-app banner on home screen ✅
- [x] Push/alert notifications to dispatcher/agency (new incident, high severity alert) — deferred to Phase 6A (dispatcher dashboard); Realtime infrastructure now in place
- [ ] Fallback notification for agencies with unreliable data connectivity — never built. Was scoped as "via SMS, riding on Phase 7's gateway"; that gateway was descoped (Deviations Log 2026-09-24), so this would need its own mechanism (most likely a paid outbound SMS API, since an agency's phone sending itself has the same cost as any other outbound SMS) if it is ever picked up
- [x] **Security checkpoint:** confirm notification payloads don't leak sensitive report details to lock screens/unauthorized viewers — Realtime channel filtered server-side by `reporter_id = auth.uid()`; in-app only, no lock-screen payload ✅

### Phase 10.5 — Settings & Profile Management (All Roles) **[NEW PHASE]**
Cross-cutting phase — does not block the core loop, but needed before the app feels complete for any role.

- [x] Resident: profile edit, notification preferences, emergency contacts management — `SettingsScreen`, `ProfileProvider`, `ProfileRepository`, `GET /users/me`, `PATCH /users/me`; migration 005 adds phone, barangay, municipality_address, preferred_language, push_notifications_enabled, emergency_contact_name/number ✅
- [x] Responder: profile/credentials view, availability status settings — availability toggle built in 6B.1; profile/credentials view built in 6B.2 (`responder_profile_screen.dart`) ✅
- [x] Agency Admin (Phase 6A.5): agency profile edit (name, coverage municipalities, contact info), notification rules config — built in `/settings` page, `AgencyProfileCard` + `NotificationRulesCard`, `PATCH /stations/agencies/{id}` backend ✅
- [x] Super Admin (Phase 6A.5): station/agency roster management, cross-agency notification settings — built in `/settings` page, `StationManagementSection`, `SuperAdminSection` ✅
- [x] **Security checkpoint:** confirm users can only view/edit their own profile, never another account's — `user_id` always from JWT token; `_ALLOWED_UPDATE_FIELDS` allowlist strips any sensitive fields; RLS on `public.users` blocks cross-user updates ✅

### Phase 11 — Testing & QA
- [ ] Unit tests for auth, rubric engine, NLP service, dispatch routing
- [ ] Integration tests across the full pipeline: report → signals → severity → routing → dispatch
- [ ] Manual field-style testing simulating rural connectivity conditions
- [ ] Load/rate-limit testing on public endpoints
- [ ] **Security checkpoint:** run through OWASP Top 10 checklist against the API (injection, broken auth, sensitive data exposure, access control, etc.)

### Phase 12 — Security Audit & Hardening (Dedicated Pass)
- [ ] Review all RLS policies end-to-end with test accounts of every role
- [ ] Review all API endpoints for missing auth/authz checks
- [ ] Review secret management across all three apps
- [ ] Review logging — confirm no PII/sensitive data leakage
- [ ] Penetration-test the auth flow (brute force, token replay, session fixation)
- [ ] Document known limitations/residual risks (be honest — panelists will ask)

### Phase 13 — Deployment
- [ ] Deploy FastAPI backend (staging first, then production)
- [ ] Deploy Next.js dashboard
- [ ] Build and prepare Flutter app (APK for testing devices, then release build)
- [ ] Set production environment variables/secrets properly (never reuse dev keys)
- [ ] Set up basic monitoring/error tracking
- [ ] Final smoke test on real devices (including the TECNO KJ6 test device) under real network conditions

### Phase 14 — Documentation & Defense Prep
- [ ] Keep `ZIREN_KIRO_SPEC_V2.md` updated to match what was actually built
- [ ] Prepare architecture diagrams reflecting final implementation
- [ ] Prepare a clear explanation of the rule-based severity decision (why, and why not ML) for panel defense
- [ ] Prepare a clear explanation of originality vs. existing triage systems
- [ ] Prepare a clear explanation of ML strategy (unified vs. per-agency models, retraining approach)
- [ ] Prepare a security summary (what was protected against, and how) — panelists increasingly ask about this for systems handling location + personal data

### Phase 15 — Extended Features (Optional, Only If Core Is Done and Stable)
Do not start this phase until Phases 0–14 are stable and tested. These are stretch goals — build them only if time/scope allows.

- [ ] Analytics/reporting dashboard (incident trends, response time metrics per municipality)
- [ ] Report history / heatmap visualization
- [ ] **[NEW]** Live map of Responder en route (real-time location sharing, Resident-facing — privacy-sensitive, higher complexity)
- [ ] **[NEW]** Post-resolution rating/feedback (citizen rates the response after an incident is resolved)
- [ ] Model feedback loop (dispatcher flags bad NLP extractions → retraining dataset)
- [ ] Onboarding/tutorial flow for first-time mobile users
- [ ] Emergency contacts / quick-dial hotline fallback
- [ ] **Security checkpoint:** any new feature here still follows Section 0 rules (RLS, auth checks, no secret leakage) — extended features don't get a security pass just because they're optional

---

## 3. Deviations Log

*(Every time implementation diverges from this plan, record it here with a reason and date.)*

| Date | Phase/Task | What changed | Why |
|---|---|---|---|
| 2026-09-24 | Phase 7, Section 0.2, Section 0.3, Phase 10 | **Removed the SMS gateway fallback entirely** rather than leaving it half-working. What existed and was tested first: the resident-side send (`SmsFallbackService`, a direct `android.telephony.SmsManager` platform channel with real send-confirmation via `PendingIntent`, GSM-7 encoding and JSON-escaping for the gateway's forwarder), the backend webhook (`POST /sms/inbound`, `X-Webhook-Key` auth, sender-to-resident phone matching, duplicate-report suppression), and a gateway phone running MacroDroid to forward received texts to that webhook. On real hardware (Wi-Fi off, mobile data on but non-functional — the actual "signal but no internet" condition this layer exists for), the send path worked correctly end-to-end up to the carrier: the radio was invoked, the message was correctly formed, and the OS-level send-confirmation callback correctly reported the outcome. It failed at the one step no app code can reach around: the carrier returned `GENERIC_FAILURE` because the test SIM had no load, and the SIM's own network confirmed as much ("Subscribe NOW or dial *5623# for Utang-Na-Load"). Sending an SMS costs money against the *sender's* balance regardless of which app sends it — this is carrier billing, not a Ziren defect, and it applies to every resident's phone, not just the test device. Replacing MacroDroid with a purpose-built receiver app (discussed as a next step) would only have improved the *receiving* side; it does nothing for the sending side, where the actual blocker lives. Decision: remove `SmsFallbackService`, the `/sms/inbound` router, the `SmsInboundRequest`/`SubmissionChannel.sms` models, the dashboard's SMS Gateway settings panel, the `SEND_SMS` manifest permission, and every connectivity string/token that promised a text-message fallback (`connectivitySms`, `homeRoutingSms`, `reportSentViaSms*`, `sosSentViaSms*`, the Terms of Use's SMS clause — bumped to Terms v1.1 since the connectivity claim changed). The app is internet-only: a report that cannot reach the backend says so plainly and tells the resident to call 911, rather than silently retrying or claiming a fallback that cannot be relied on for every resident's SIM. A real de-duplication bug (a lost HTTP reply could double-submit the same report on retry) and a real online/offline-check bug (the check counted a tunnel's own error page as "online") were found and fixed *during* this work and are kept — see the code comments in `incident_service.py` and `BackendHealth` respectively; only the SMS-specific plumbing was removed. On-device NLP and store-and-forward, Phase 7's other two never-built layers, are unaffected — they do not depend on outbound SMS credit and remain legitimate options if this is revisited. | Kurt asked to test the SMS fallback specifically for the "mobile data present but not actually working" case, which is exactly the scenario that exposed a serious pre-existing bug (in airplane mode, with the radio fully off, the app was claiming the report had been sent — verified false via the phone's own radio log). Fixing that bug required building out real send-confirmation, which then surfaced the SIM-load blocker above. Kurt's own framing once the blocker was found: "since it's not achievable to ziren we should remove the sms approach" — rather than keep code and infrastructure (gateway phone, MacroDroid, webhook secret, dashboard panel) alive for a fallback that cannot be relied on for the resident population this app is for. |
| 2026-08-02 | Phase 6A (6A.0 update) | Kiro audited the built dashboard nav against the newly-added 6A.0 table and found 3 mismatches. Resolved: (1) `/responders` was visible to Super Admin — fixed in code, now Agency Admin only, matching the documented security boundary. (2) `/incidents` nav link had no corresponding 6A.0 entry — confirmed as a genuine gap (`/queue` excludes `resolved`/`cancelled` by design, so those incidents were otherwise unreachable from the dashboard) and added as new item #2.5 "Incident History," formalizing what was already built rather than removing it. (3) `/rubric` bare route showed all three agency cards to Agency Admin even though two would 403 on click — resolved by auto-redirecting Agency Admin straight to their own agency's rubric page (Super Admin still sees the 3-card selector); 6A.0's Rubric row updated to document this behavior. | This is the first real-world test of 6A.0 as a spec — it caught one actual security scope leak and one actual UX/audit gap that existed in the code but weren't documented anywhere, which is exactly what the table is for. |
| 2026-08-02 | Phase 6A (new 6A.0) | Added 6A.0 — Menu/Navigation Structure, a reference table listing every Agency Admin/Super Admin dashboard nav item (Queue, Responders, Accounts, Coverage, Rubric, Settings, plus the Incident Detail drill-down), each mapped to its route, visible role(s), the Section 1.5 feature it feeds, and a one-line purpose explaining why it exists. No new functionality added — this documents the nav structure implicit in 6A.1–6A.5's already-built routes, and explicitly notes that an earlier planning-stage brainstorm (resource inventory, in-app chat, escalation buttons, public transparency page, backup/DR settings) was not adopted and stays out of scope unless added here first. | Kurt had been informally exploring a broader menu-item list outside this plan and asked for it to be reconciled with the actual locked/built structure, with purpose stated per item so Kiro isn't just implementing menu items with no documented reason behind them. |
| 2026-08-02 | Phase 0.5 (new 0.5.5) | Kurt pointed out that the eGov PH (by Bryl Lim)-inspired sidebar redesign — discussed in an earlier design review, with a reference mockup built (full labeled sidebar, icon+label nav, recent-incidents list, avatar+name+role+sign-out footer, restyled in Ziren's light/orange tokens) — was never written into this plan. Added 0.5.5 documenting the decision and itemizing it as a not-yet-built task; corrected Phase 0.5's status from Complete to Partial. Also corrected a stale 10.5 status line that hadn't been updated after 6A.5/6B.2 shipped. | Same class of gap as the Rule 0.6 findings in 6A/6B/6C: a real decision existed but lived only in chat, so the plan silently didn't reflect it. This entry closes that gap and makes 0.5.5 trackable like any other task. |
| 2026-08-02 | Phase 0.5 (new, retroactive) | Added Phase 0.5 — Design System & Dashboard UI — to document the design token system, utility CSS classes, UI component library (Button/Input/Alert), and dashboard shell that were built during Phase 6A but never itemized as checklist tasks. Single source of truth is `globals.css` (web) kept in sync with `app_tokens.dart` (mobile). | Rule 0.6 requires built features not already in the plan to be added retroactively before marking anything done. Kurt asked why there was no design task in the plan — this entry closes that gap. |
| 2026-07-06 | Section 1 (Locked Architecture), Feature List, Phase 1, Phase 6 | Corrected user roles from 3 (citizen/dispatcher/agency_admin) to the confirmed 4 (Resident/Responder/Agency Admin/Super Admin). This plan had drifted from the earlier spec, which already had 4 roles. | Kurt confirmed the 4-role structure is current; the dev plan's Phase 1 auth design had only accounted for 3 and never got updated. |
| 2026-07-10 | Phase 3, Phase 9, Feature List | Changed station/agency selection from automatic (NLP + PostGIS routing) to **manual** — Resident selects station before describing the incident. Phase 9 role changed from primary router to coverage-area validation/backup layer. | Kurt confirmed detailed, accountable reporting is a higher priority than automatic convenience — manual selection adds friction that discourages prank/false reports, consistent with the existing anti-prank layer (verification, mandatory evidence, legal confirmation). |
| 2026-07-11 | Phase 10 | Push notifications implemented via **Supabase Realtime** (`postgres_changes` on `incidents` table) instead of FCM/Firebase. In-app only — no device push tokens, no `google-services.json` required. | No Firebase project was set up for this project. Supabase Realtime achieves the same Resident-facing goal (status update notifications) with zero additional infrastructure and stays within the existing Supabase connection. FCM can be layered on top later if background/lock-screen notifications are needed. |
| 2026-07-11 | Phase 9 (Resident scope) | Coverage-area validation implemented as a `GET /incidents/coverage-check` endpoint + `check_station_coverage()` PostGIS RPC function. `StationModel` now parses lat/lng from Supabase PostGIS POINT. Mismatch shown as a warning banner on the report form — never blocks submission. | Phase 9's multi-agency and cross-jurisdiction routing tasks remain for Phase 6A (dispatcher concern, not Resident). |
| 2026-07-11 | Phase 3 / Phase 3B (shared internals) | Shared `_create_incident_row()` internal function handles the DB write for both the regular report path and the SOS path, but the two endpoints remain separate — SOS has fundamentally different validation rules (no station_id, no min-char, no media), different rate limiting (3/hour IP + 30-min account cooldown), and different anti-abuse logic (mandatory identity attachment, rate limiting, trust indicators, escalating consequences). | Kurt identified a genuine need for a low-friction emergency path (life-threatening situations can't wait for a multi-step form), while requiring a way to prevent this same low-friction path from being spammed or used for pranks — resolved via mandatory identity attachment rather than reduced detail. Merging the two endpoints into one via branching would make both paths fragile and harder to maintain; separation keeps each path's contract explicit and independently testable. |
| 2026-07-10 | Phase 6 → 6A/6B split | Split "Dispatcher Dashboard" into Phase 6A (Agency Admin Dashboard, Next.js) and new Phase 6B (Responder Mobile Experience, Flutter). Added explicit Super Admin cross-agency view tasks to 6A. | The original plan had no dedicated phase for the Responder's mobile app experience, despite Responder being a mobile-first role per the locked architecture (Section 1). Super Admin's cross-agency view was also never made explicit. |
| 2026-07-10 | Phase 3, Phase 7, Phase 10.5 (new) | Added Resident Home/Dashboard, photo/video attachment, and draft/save-incomplete-report to core scope. Added new Phase 10.5 for cross-role Settings/Profile Management. Moved live map (Responder tracking) and post-resolution rating/feedback to Extended (Phase 15). | Cross-check against the feature priority roadmap surfaced that the original plan was reporting-form-only for Resident, with no dashboard, settings, or supporting UX — a gap identified before this would have become visible only during defense prep. |
| 2026-07-20 | Phase 3 (Resident Home dashboard) | Home screen content revised: (1) added a persistent, non-alarming connectivity-mode status chip near the greeting header (replaces the raw "Could not reach the server" error text), (2) added a "Near you" section showing 1–2 nearby incidents with severity tag and timestamp for situational awareness before the user acts, (3) added a false-report disclaimer line under the SOS button, (4) "My Reports" empty state changed from a generic server-error message to a neutral first-time-user message ("You haven't submitted any reports yet"). | These were gaps against the app's own design principles (offline states must be first-class UI, not error states; severity/context should be visually present, not just action buttons) — surfaced while reviewing the built Home screen against ziren-design-prompt.md. |
| 2026-07-27 | Phase 4, Phase 5 | Phase 5 (Severity Rubric Engine) unblocked from Phase 4 (NLP dataset) — no longer waiting for the labeled dataset before starting rubric work. Phase 5 expanded into sub-sections (5.1–5.6) covering rubric structure as a decision table, provenance/traceability to field interviews, mocked-input testability, a per-agency test matrix, and defense-prep notes. Phase 5 complete (5.1–5.5): 37 rules across BFP/PNP/MDRRMO, versioned DB config + JSON seed fallback, max-of-triggered-rules aggregation, 331 tests passing. | Kurt confirmed the station dataset is not yet available and may not be obtainable at all (confidential station data, still ongoing). Severity was never meant to be an ML output (Section 0.3), so the rubric only needs the already-finalized 15-signal schema, not a trained model — it can be built and tested against mocked signal payloads now, with real NLP output wired in later as a drop-in replacement. Kurt also wants the rubric treated as a rigorous CS component in its own right, defensible independent of Phase 4's status. |
| 2026-08-02 | Phase 6C.2 | Kiro flagged, before writing code, that `map_screen.dart` already uses `flutter_map` + direct `tile.openstreetmap.org` calls — undocumented in this plan, conflicting with the Section 1 mapping-stack lock and violating 6C.5. Resolved: 6C.2 replaces this implementation rather than adding a second one alongside it; added an explicit removal task and security checkpoint to 6C.2. | Kurt confirmed `flutter_map` was an earlier interim choice, superseded by the formal MapLibre + self-hosted OSM decision — same undocumented-drift pattern as the 6A/6B findings, caught this time before code was written instead of after. |
| 2026-08-02 | Section 1 (new architecture row + rationale), Section 0.3, new Phase 6C | Locked the mapping/geospatial stack: MapLibre GL + self-hosted OpenStreetMap vector tiles (Biliran-only offline MBTiles package), explicitly not Mapbox. Added Phase 6C (6C.1–6C.5) covering the offline tile pipeline, mobile integration, dashboard integration, optional self-hosted routing, and security checkpoints — feeds the map views already referenced in 6A.1, 6A.3, and Responder/Resident incident-location display. | Kurt weighed Mapbox (polished styling, built-in turn-by-turn nav SDK, but usage-based billing with no hard cap and a foreign-company pricing dependency) against OSM+MapLibre (free forever, no API key, no billing risk, offline-capable for an island-sized coverage area, full styling control) and decided OSM+MapLibre is the better philosophical and practical fit for a public-safety tool serving Biliran — a disaster-response map layer shouldn't degrade because a bill wasn't paid during a crisis surge. |
| 2026-08-02 | Phase 6B (split into 6B.1–6B.3), Phase 10.5 | Phase 6B was marked "✅ Complete" in the Quick Status Snapshot while the Profile tab in `responder_shell.dart` had no built screen behind it, and no phase anywhere covered notifying a Responder in real time when a new incident is assigned to them (Phase 10's notification checklist only covers citizen-facing and dispatcher/agency-facing alerts). Split Phase 6B into 6B.1 (queue/detail/status FSM/navigation, built), 6B.2 (Profile tab content, not started), 6B.3 (push notification on new assignment, not started). Corrected status in Section 4 from Complete to Partial. | Kurt asked whether the Responder mobile side had gotten the same full-scope review as the Agency Admin dashboard (2026-08-01 entry) — it hadn't; this entry brings it to parity. |
| 2026-08-01 | Section 0 (new Rule 0.6), Phase 6A (split into 6A.1–6A.5), Phase 10.5 | Phase 6A was marked "✅ Complete" in the Quick Status Snapshot while only covering the incident queue/dispatch slice and the Responder approve/reject/revoke action — Feature #15 (accounts, coverage areas, rubric config) was never fully itemized as checklist tasks, so the gap wasn't visible. Split Phase 6A into 6A.1 (queue/dispatch, built), 6A.2 (account management, partial), 6A.3 (coverage area management, not started), 6A.4 (rubric config UI, not started), 6A.5 (Agency Admin/Super Admin settings, not started). Corrected both phases' status in Section 4 from Complete to Partial. Added Rule 0.6 requiring every phase to be cross-checked against Section 1.5 before being marked done. | Kurt noticed that finished tasks (e.g. the admin dashboard) kept shipping with only a narrow slice of the intended functionality — the checklist itself didn't force full-scope coverage per role, so partial work could get checked off as if it were the whole feature. |
| 2026-08-02 | Phase 6A (nav reconciliation — 6A.0 cross-check) | Cross-checked `app/(dashboard)/layout.tsx` against 6A.0 table. Found and resolved three mismatches: (1) `/incidents` nav item renamed "Incident History" and retained for both roles — confirmed real gap (resolved/cancelled incidents disappear from `/queue`; the history page is the only way to retrieve them for audit); 6A.0 updated to add item #2.5. (2) `/responders` was shown to Super Admin in violation of 6A.0 row #3 (Agency Admin only) — removed from Super Admin nav (one-line fix in layout.tsx). (3) `/rubric` bare route showed all three agency cards to Agency Admin, two of which would 403 — added auto-redirect via `/users/me` → `agency_type` for Agency Admin; Super Admin 3-card selector unchanged. Backend: added `agencies(agency_type)` join to `_PROFILE_SELECT` in `user_service.py` and `agency_type` field to `UserProfile` to support the redirect without a second API call. | Kurt confirmed decisions: (1) and (3) were implementation gaps, (2) was a clear security-boundary violation per 6A.0's own note that the Responders/Accounts split is a security boundary not just a UI preference. |
| 2026-08-02 | Phase 0.5 — Design System (Phase 1 design upgrade) | Executed Phase 1 of the Admin Dashboard Design Upgrade per `ZIREN_Admin_Design_Upgrade_Prompt.md`. Changes: (1) Font switched from Nunito to **Plus Jakarta Sans** — updated `app/layout.tsx` (next/font/google swap), removed Nunito `@import` from `globals.css`, updated `--font-sans` token comment, added web/mobile sync note to `app_tokens.dart`. (2) Added `--color-status-critical/pending/progress/resolved` semantic alias tokens to `globals.css` (map to existing severity/status tokens — no new hex values). (3) Audited `--radius-2xl`: already 24px in the live file (the open 0.5.1 audit note was stale — token was corrected without closing the plan item). (4) Built five new `components/ui/` components: `Card` (+ CardHeader/CardBody/CardFooter), `Badge` (SeverityBadge/AgencyBadge/StatusBadge/RoleBadge/AiBadge/Badge), `Table` (+ TableHead/TableBody/TableRow/TableHeader/TableCell/TableEmptyState/TableSkeleton), `StatusPill` (critical/pending/progress/resolved/cancelled/online/offline/syncing), `Modal` (accessible overlay with Escape close, scroll lock, aria-dialog). Route group migration (`(agency-admin)`/`(super-admin)`) deferred by Kurt — keep single `(dashboard)` group for now. | Kurt confirmed Decision A (Plus Jakarta Sans), Decision B (no route group migration for Phase 1–4). Tailwind v4 has no `tailwind.config.ts` — all tokens live in `globals.css` `@theme inline` as they already did; the design prompt's instruction to use `tailwind.config.ts` was adapted accordingly. |
| 2026-08-02 | Phase 0.5.5 — Sidebar & shell (Design upgrade Phase 2) | Completed Phase 2 of Admin Dashboard Design Upgrade. Built `components/ui/top-bar.tsx`: sticky top bar with contextual page title/subtitle (resolved from route via `lib/utils/route-meta.ts`), live connectivity status pill (navigator.onLine + online/offline events, syncing state on reconnect), notification bell with unread badge, global search bar slot. Rebuilt `app/(dashboard)/layout.tsx`: replaced all inline `style={}` with design-token classes, added `<Image>` logo block with Siren-icon fallback, token-based active nav state, nav divider, role-contextual footer label (shows "BFP Admin" / "Super Admin" using `agency_type` from `/users/me`). Added `_LoadingSkeleton` loading state (replaces blank-screen flash during auth hydration). Copied `Ziren_Logo.png` → `public/ziren-logo.png`; added favicon in root `app/layout.tsx`. Closed all Phase 0.5.5 checklist items. Fixed sidebar width regression (Tailwind v4 class not applying) by using inline `style={{ width: '256px' }}` for structural dimensions, consistent with the original layout pattern. | Design upgrade Phase 2 aligns with the already-planned 0.5.5 sidebar redesign — this closes it rather than introducing new scope. Top bar is new (not previously planned); added here as the natural counterpart to the sidebar in a standard SaaS shell. |
| 2026-08-02 | Design upgrade Phase 3 — Auth pages | Redesigned all three auth pages to match the split-screen layout direction from `ZIREN_Admin_Design_Upgrade_Prompt.md`. Login: added feature pills, radial pattern overlay, "Forgot password?" link, "Keep me signed in" checkbox, improved urgency copy ("Request an account" vs "Create account"). Signup: full rewrite to "Request Access" flow — form (name, position, agency, email, password) submits to existing `/auth/register`, but shows a `ConfirmationScreen` instead of auto-logging in, making the verification-pending posture explicit; "What happens next" numbered steps reinforce security for the defense panel. Accept-invite: matched to split-screen layout, added success state with auto-redirect after 1.8s. No backend changes — all three pages use existing endpoints unchanged. | Design prompt specified "Request Access" flow for Sign Up; implemented as a UX wrapper over the existing registration endpoint rather than a new endpoint (no backend work needed for the defense scope). |
| 2026-08-02 | Design upgrade Phase 4 — Priority screens | Upgraded queue page (`/queue`): skeleton loaders replace spinner, urgency time-based color shift on timestamp (amber after 15 min unacknowledged, red after 45 min), compact stat chips in header bar, improved incident card with 3px severity strip, cleaner badge layout, trust indicator section. Built new Super Admin overview dashboard (`/overview`): cross-agency stat cards (active/critical/high/pending), recent incidents feed (6 newest, cross-agency), per-agency breakdown cards (BFP/PNP/MDRRMO active + critical counts). Incident detail page (`/incidents/[id]`) left structurally unchanged — all dispatch logic is working; visual polish deferred to avoid regression risk on working modals. | Super Admin overview is a new page not in 6A.0 — it's a UI-only addition, no new endpoint, uses existing `/dispatch/queue` data already scoped to super_admin. Added to route-meta.ts for top bar title resolution. |
| 2026-07-22 | Phase 3 (Resident report form), Phase 8 (positioning only, no scope change) | Replaced the single free-text report field with a **structured 5W1H wizard**: (1) after station selection, Resident picks an incident-type category (Fire, Medical/Trauma, Vehicular, Flood/Landslide/Calamity, Domestic Dispute/Crime, HAZMAT, Missing Person, Other); (2) category-specific follow-up screen with 3–5 quick-choice questions (severity-relevant details — e.g., victim count, "may nasugatan?", "nakaharang ba sa daan?" — plus an optional free-text catch-all for anything not covered); (3) a multi-select "may kasama pa bang..." step to flag overlapping concerns (e.g., a fire report with an injury) for multi-agency routing (feeds Phase 6A/Phase 9, not a new pipeline); (4) Where/When remain auto-captured, with an added optional landmark-note field; (5) Who remains auto-attached identity, plus a new relationship-to-victim question (ako mismo / kamag-anak / kakilala / estranghero); (6) new review screen summarizing all 5W1H fields before submit. Free-text ("Other"/catch-all) answers still flow through the Phase 4 NLP pipeline and are flagged low-confidence for dispatcher review — no bypass. Phase 8 (ResQ AI Chat) is unchanged in scope but is now explicitly documented as an **alternate entry point into the same 5W1H schema**, not a separate reporting path — for Residents who prefer natural conversation over selecting chips (e.g., ambiguous/multi-incident situations, or users who find the wizard hard to navigate). | Kurt's field interviews (BFP/PNP/PNP-Cabucgayan/Culaba BFP/PNP) independently confirmed all stations follow a 5W1H (locally called "5 wives and 1 husband") completeness standard, and repeatedly named incomplete detail and unclear landmarks as their top reporting complaint. A single free-text box does not guarantee this structure is actually captured. This is a scope reopening of a phase already marked Complete (27/27 tests) — existing Phase 3 tests and UI components will need to be revisited, not just extended. |

---

## 4. Quick Status Snapshot

*(Update this at the top level so you can see progress at a glance without scrolling.)*

- Phase 0 — Project Setup: ✅ Complete (CI skipped for now)
- Phase 0.5 — Design System & Dashboard UI: ⚠️ **Partial** — 0.5.1–0.5.4 complete (design tokens, utility classes, Button/Input/Alert components, current sidebar shell all built and documented). 0.5.5 (eGov PH-inspired sidebar redesign — full labeled sidebar, recent-incidents list, redesigned account footer) is **not started**; discussed and mocked up in design review but never previously written into this plan. Corrected from a prior "Complete" per Rule 0.6.
- Phase 1 — Auth (Login/Register): ✅ Complete — 15/15 tests passing, manually verified on device
- Phase 2 — Database Schema: ✅ Migration written and verified — run migration 002 in Supabase to activate
- Phase 3 — Incident Reporting (Mobile): ✅ Complete — 36/36 backend tests passing (27 wizard contract + 9 security checkpoint), all wizard screens built and routed (category → questions → overlap → who → review), media attachment picker wired into review screen, `conftest.py` rate-limiter reset added to test suite
- Phase 3B — SOS Quick-Report: ✅ Complete — 26/26 tests passing, all checklist items done ✅
- Phase 4 — NLP Pipeline: ☐ Not started — ⚠️ **Blocked**: labeled dataset not yet obtainable (confidential station data, still ongoing). Does not block Phase 5.
- Phase 5 — Severity Rubric: ✅ Complete (5.1–5.5) — 37 rules across BFP/PNP/MDRRMO, max-of-triggered-rules aggregation, versioned DB config + JSON seed fallback, 331 tests passing (220 rubric + 48 security + 63 existing), provenance startup checker active ⚠️ 37 TODO provenance fields remain — fill in field interview references before defense; 3 KNOWN_SCENARIOS in rubric_traceability.py need real incident data from interviews
- Phase 6A — Agency Admin Dashboard (Next.js): ✅ **Complete** — 6A.1 (incident queue/dispatch/resolve/cancel/flag-false-SOS), 6A.2 (Responder roster, Super Admin Agency Admin management + cross-agency directory), 6A.3 (`/coverage` page — station list, polygon status, inline coordinate editor, `PATCH /stations/{id}/coverage` backend; TODO 6C.3 MapLibre marker), 6A.4 (rubric config UI — rule viewer, upload/activate, audit log), 6A.5 (`/settings` page — Agency Admin profile edit + notification rules toggles; Super Admin agency selector + station add/deactivate; migration 009 `notification_rules` JSONB + `email` on agencies table) all complete.
- Phase 6B — Responder Mobile Experience (Flutter): ✅ **Complete** — 6B.1 (queue/detail/status FSM/navigation), 6B.2 (`responder_profile_screen.dart` — credentials view + editable name/phone), 6B.3 (`ResponderNotificationProvider` — Supabase Realtime filtered by `assigned_responder_id`, `_AssignmentBanner` on queue screen, auto queue reload on new assignment) all complete.
- Phase 6C — Mapping Infrastructure (MapLibre + OSM): ☐ Not started — new phase; locked architecture decision (MapLibre GL + self-hosted OSM tiles, not Mapbox) recorded in Section 1
- Phase 7 — Connectivity Handling: ⚠️ **Partial by decision** — internet-only submission with an honest online/offline check is complete; the SMS gateway fallback was built, tested on real hardware, and deliberately descoped (Deviations Log 2026-09-24); on-device NLP and store-and-forward remain not started and unaffected by that decision
- Phase 8 — ResQ AI Chat: ☐ Not started
- Phase 9 — Multi-Agency Routing (Resident coverage validation): ✅ Complete (Resident scope) — PostGIS `check_station_coverage()` RPC, `GET /incidents/coverage-check`, mismatch warning banner on report form, station lat/lng now parsed from Supabase. Multi-agency/cross-jurisdiction tasks remain for Phase 6A.
- Phase 10 — Notifications: ✅ Complete (Resident scope) — Supabase Realtime subscription, `NotificationProvider`, in-app banner + notifications screen + bell badge. An SMS fallback for agencies was never built and has no planned mechanism now that Phase 7's gateway is descoped (Deviations Log 2026-09-24).
- Phase 10.5 — Settings & Profile Management: ⚠️ **Partial** — Resident scope complete (`GET`/`PATCH /users/me`, migration 005 profile columns, `SettingsScreen` with profile/address/preferences/emergency contacts). Responder profile/credentials view complete via 6B.2 (`responder_profile_screen.dart`). Agency Admin and Super Admin settings complete via 6A.5 (`/settings` page). Remaining gap: none currently tracked — reconfirm this line stays accurate as 6A.5/6B.2 evolve.
- Phase 11 — Testing & QA: ☐ Not started
- Phase 12 — Security Audit: ☐ Not started
- Phase 13 — Deployment: ☐ Not started
- Phase 14 — Documentation & Defense Prep: ☐ Not started
- Phase 15 — Extended Features (Optional): ☐ Not started