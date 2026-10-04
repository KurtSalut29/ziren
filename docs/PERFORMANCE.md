# Performance: expected volumes, targets, limits and how they are checked

Written for the team and the evaluators. It answers findings #14, #15 and #38
of the 2026-10-05 ISO / white-box evaluation: Ziren had only been seen working
with a small dataset, and nobody had written down how much it is expected to
carry or how fast it must stay.

## 1. Expected volumes

| What | Expected | Planned for (2x margin) | Basis |
|---|---|---|---|
| Province population | about 180,000 | — | PSA 2020 census, Biliran |
| Reports per year, province | up to 10,000 | 20,000 | No published figure exists. This is an upper bound of about 27 per day for the whole province across the three agencies. |
| Reports in a typhoon peak hour | up to 250 | 500 | One surge over all 8 municipalities. |
| Stored incidents after 5 years | up to 50,000 | 100,000 | The yearly figure kept indefinitely; nothing is deleted. |
| Dashboard consoles open at once | 24 agency + 3 provincial | 30 | One per office, plus the three provincial admins. |
| Responders on duty at once | up to 150 | 300 | Each pings its position every 2 min, or every 30 s on a call. |
| Residents with the app open in a surge | up to 2,000 | 4,000 | They poll their own report's status. |

## 2. Targets (95th percentile, on the deployed backend)

| Action | Target p95 | Why this number |
|---|---|---|
| Live queue poll (`/dispatch/queue`) | 800 ms | Polled every 10 s by every console; must never fall behind its own poll. |
| Open a report (`/dispatch/queue/{id}`) | 1,000 ms | A dispatcher waits on this before acting. |
| Incident Records page, any depth (`/dispatch/history`) | 1,500 ms | A look-up, not a live screen. |
| Map (`/map/data`) | 1,500 ms | Capped at 1,500 pins (finding #17). |
| Operational Area, a 1-year window | 3,000 ms | Reporting screen. Capped at 20,000 reports, and says so when it is (finding #16). |
| Submit a report (`POST /incidents/`) | 2,000 ms | Includes triage, which takes about 4 ms (measured below). |
| Responder position ping | 800 ms | 300 responders at a 30 s cadence is about 10 requests per second. |

## 3. Built-in limits (and where they are said out loud)

| Limit | Value | Where | What the user sees |
|---|---|---|---|
| Operational Area rows | 20,000 newest | `operational_area_service._MAX_ROWS` | "These figures use the newest N of M reports…" banner. |
| Map incident pins | 1,500 newest | `routers/map.py MAP_INCIDENT_MAX` | "Showing the newest N of M reports." notice. |
| Incident Records page size | 100 | `dispatch_service.HISTORY_PAGE_MAX` | Paged, with the total shown. |
| Attachments per report | 5 files, 50 MB each, video up to 2 min | `MediaUploadService` | Shown on the form and checked on selection (#20, #21). |
| Live queue | `QUEUE_MAX` | `dispatch_service.QUEUE_MAX` | Shown in Settings → System. |

## 4. Measured: the backend's own processing (2026-10-05)

`ziren_backend/scripts/perf_benchmark.py`, synthetic incidents spread over one
year, run on the development laptop. This covers Python's share of the work.
The database's share is in section 5.

| Rows | Operational Area figures | Map shaping (capped) |
|---|---|---|
| 1,000 | 16 ms | 0.4 ms |
| 20,000 (the cap) | 503 ms | 2.1 ms |
| 100,000 (uncapped, for comparison) | 2,749 ms | 2.3 ms |

Triage of one report takes 4 ms (median of 20).

The 20,000-row figure was 869 ms before the place-name matching was cached.
The cap exists because this cost grows linearly. At the cap it stays well
inside the 3,000 ms target, together with the reads.

Changes made for these findings:
- **Indexes shaped like the queries** (migration 045): agency + newest first, agency + status, status + newest first, and responder + status.
- **Incident Records summary in one query** (`incident_window_counts`, migration 045). It replaces five queries per page, two of which silently stopped at 1,000 rows.
- **Operational Area pages read in parallel,** with the total counted, instead of one page after another.
- **Map pins capped** and the cap reported.

## 5. Load test: many users at once

`ziren_backend/scripts/load_test.py` runs N simulated consoles for a fixed
time. Each polls the queue, opens records, loads the map, distress and
notifications with human-like pauses. It reports p50, p95 and p99 against the
targets above and exits non-zero on a miss.

It is read-only. It refuses the production URL unless given
`--allow-production`. Run it against a staging deployment seeded with
`scripts/seed_demo_data.py` (800 or more incidents, or more with a larger seed).
It has **not yet been run against a deployment.** That needs a staging
environment, which is a decision for the team and is not provisioned here.

Simultaneous actions (finding #13) are handled in code and covered by tests:
- **Two dispatchers pressing Dispatch on one report:** the second is refused with "dispatched by someone else" (conditional update, `assign_responder`).
- **Two admins accepting and rejecting one report:** the second is told another admin decided (`_claim_review`).
- **Chat messages and notes sent together:** each is its own insert. They cannot overwrite each other.

## 6. When to re-check (finding #38)

- **Run** `perf_benchmark.py` after any change to Operational Area, Incident Records or the map. It takes under a minute and needs no network.
- **Run** `load_test.py` against staging before each release that changes those screens, and when stored incidents pass each 25,000 mark.
- **Revisit section 1** after the first full year of real use, with real counts instead of the estimates.
