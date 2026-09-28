# Ziren

Emergency incident reporting and dispatch for Biliran. Three apps, one backend.

| | | |
|---|---|---|
| [`ziren_backend`](ziren_backend/) | FastAPI + Supabase | Submission, dispatch, rubric engine, triage model |
| [`ziren_dashboard`](ziren_dashboard/) | Next.js | Dispatcher console |
| [`ziren_mobile`](ziren_mobile/) | Flutter | Residents and responders |

[`branding/`](branding/) holds the source artwork: the Ziren logo and the
BFP, PNP and MDRRMO icons. The apps do not load these files; they ship their
own copies (the dashboard's logo files come from
`ziren_dashboard/scripts/make-logo-assets.mjs`).

A resident files a report; the trained triage model scores it inline at
submission; the dispatcher sees a severity **with the numbered rule that
produced it**, and validates before anyone is sent. Details in
[`ziren_backend/README.md`](ziren_backend/README.md).

For the defense walkthrough, see [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md).

---

## Setting up a fresh clone

Do these in order. Every step below exists because a cold-start test on a
clean machine failed without it.

### 1. Backend

```powershell
cd ziren_backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env          # then fill in the Supabase values
uvicorn app.main:app --reload --host 0.0.0.0
```

Verify before moving on:

```powershell
.venv\Scripts\python.exe -m pytest -q     # expect: 1549 passed, 3 skipped
curl http://127.0.0.1:8000/health         # expect: "model_loaded": true
```

**The `.env` step is not optional and its failure is misleading.** Without it
the server dies with `SupabaseException: supabase_url is required`, raised
from the rubric provenance check in `lifespan()` — so it reads like a crash in
the rubric engine rather than a missing file.

**If `/health` reports `"model_loaded": false`**, the trained model did not
come along. It lives at `ziren_backend/app/ml/07_MODELS/ziren_model.joblib`
and is committed on purpose despite the `*.joblib` ignore rule — see the
backend README. Without it the API starts cleanly and triages nothing: every
report saved with `severity NULL`, and the only sign is one startup warning.

### 2. Dashboard

```powershell
cd ziren_dashboard
npm install
npm run dev
```

`NEXT_PUBLIC_API_BASE_URL` defaults to `http://localhost:8000`. Set it in
`.env.local` only if the backend is somewhere else.

### 3. Mobile

Point the phone at the backend over USB, once per session:

```powershell
adb reverse tcp:8000 tcp:8000
cd ziren_mobile
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

With that forward in place `API_BASE_URL` is `http://localhost:8000` and stays
correct forever, because the phone's port 8000 is tunnelled to the laptop's
over the cable. No IP is involved, so nothing breaks when the laptop changes
network — and it works with Wi-Fi switched off entirely, which is a state
worth testing in an emergency app.

Re-run `adb reverse` after unplugging the cable or rebooting the phone. Check
it with `adb reverse --list`; it prints `UsbFfs tcp:8000 tcp:8000` when the
forward is up.

Or let the script do it, which is the same three commands plus the two checks
worth making before waiting on a build:

```powershell
.\tools\run_mobile.ps1
```

It re-creates the tunnel every run, refuses to start without an attached
device, and warns if nothing is listening on port 8000. `-CheckOnly` runs the
checks without launching.

**"Walang signal" and an empty My Reports, with the backend running,** is
almost always this forward being gone. The phone's `localhost:8000` refuses,
so the 30-second health ping fails and `/incidents/my` fails with it — one
cause, two symptoms that look unrelated. `adb reverse --list` tells you in a
second; an empty result is the answer.

**Why not the LAN IP.** It works, and it kept breaking. The address came from
DHCP and changed twice in one day here — once because the laptop moved between
saved Wi-Fi networks (`192.168.1.x` to `192.168.100.x`, different routers,
different subnets) and DHCP never promises the same address back even on the
same router. The failure is expensive out of proportion to the cause: the app
builds, the phone looks fine, a whole report can be filled in, and only the
submit fails — reading exactly like a backend fault. And because these are
compile-time constants, every fix costs a full rebuild.

If you must use the LAN address (testing untethered, or a second device),
`flutter run --dart-define=API_BASE_URL=http://<lan-ip>:8000` still works.
Take the IP from `ipconfig` — `localhost` alone resolves to the phone itself.

`dart_defines.json` is gitignored, so a fresh clone has none — pass the values
on the command line or recreate the file. `AppConfig.validate()` throws at
startup if they are missing, and prints a masked diagnostic of what it got.

The values are compile-time constants (`String.fromEnvironment`), so editing
them does nothing to a running app: stop it and run again.

---

## Testing

Every suite runs offline. None of them needs a `.env`, a Supabase project or a
running backend: the backend tests replace Supabase with an in-memory fake
([`ziren_backend/tests/fake_db.py`](ziren_backend/tests/fake_db.py)) or mocks,
and the mobile tests never reach a server.

| App | Command (from the app folder) | Result |
|---|---|---|
| Backend | `.venv\Scripts\python.exe -m pytest -q` | 1549 passed, 3 skipped |
| Backend coverage | `.venv\Scripts\python.exe -m pytest -q --cov=app --cov-branch --cov-report=term-missing` | 77% of statements and branches |
| Dashboard | `npx tsc --noEmit` / `npx eslint .` / `npx next build` | 0 errors / 0 warnings / 35 pages built |
| Mobile | `flutter analyze` / `flutter test` | no issues / 755 passed |

**The 3 skipped tests are intentional.** They are field scenarios in
`tests/test_rubric_engine.py` (one each for BFP, PNP and MDRRMO). Each one
waits for a real dispatch case from a field interview; its expected severity
cannot be invented, so it skips until one is filled in.

**The dashboard has no unit tests.** Every rule it shows (who sees which
incident, what severity a report gets, who may dispatch) is enforced and
tested in the backend. The dashboard checks are the type check, lint and
production build above.

Where the logic lives, for reading the code:

| Concern | Code | Tests |
|---|---|---|
| Severity scoring (triage model) | `ziren_backend/app/services/triage_service.py`, `app/ml/` | `tests/test_triage*.py`, `tests/test_transcript_eval.py` |
| Severity rules (rubric engine) | `app/services/rubric_service.py`, `app/rubric_configs/*.json` | `tests/test_rubric_engine.py` |
| Report submission and routing | `app/services/incident_service.py` | `tests/test_incidents.py` |
| Dispatch queue and scoping | `app/services/dispatch_service.py` | `tests/test_queue_ordering.py`, `tests/test_incident_review.py`, `tests/test_incident_records.py` |
| Resident verification scoping | `app/services/user_service.py` | `tests/test_verification_scope.py` |
| Nearby responders | `app/services/proximity.py`, `app/core/geo.py` | `tests/test_proximity.py`, `tests/test_nearby_integration.py` |
| Authentication and roles | `app/core/dependencies.py` (Supabase Auth) | `tests/test_auth*.py` |
| New-report alert (dashboard) | `ziren_dashboard/lib/hooks/useIncidentAlerts.ts` | none (browser behaviour, checked by hand) |
| Help between stations (assist requests) | `ziren_backend/app/services/assist_request_service.py`; dashboard `lib/hooks/useAssistInbox.ts` (alert) | `tests/test_assist_requests*.py` |
| Printable reports (Incident Records, Narrative Reports) | `ziren_backend/app/services/printable_reports.py` | `tests/test_printable_reports.py` |
| Registration (mobile) | `ziren_mobile/lib/features/registration/` | `ziren_mobile/test/registration_*_test.dart` |

---

## What the cold-start test found

The repo was tested by building a clean copy from what git would actually
carry, then following these instructions on it from scratch. Four problems
surfaced, all now fixed. They are recorded here because each one is invisible
on the machine where the project was written, and each one only appears on the
*second* machine — which, for a thesis project, is usually the one you are
standing at during the defense.

**1 · The project had no commits at all.** `git log` reported
`does not have any commits yet`, with zero tracked files and no remote. Every
line of this project existed on exactly one laptop. Nothing else on this list
matters next to that.

**2 · `ziren_dashboard` was a nested git repository.** It carried its own
`.git` (one `create-next-app` scaffold commit, no remote). Git will not store
a nested repo's contents in the outer one — it warns and stores a pointer:

> *Clones of the outer repository will not contain the contents of the
> embedded repository and will not know how to obtain it.*

A clone would have arrived with an **empty `ziren_dashboard/`**. The nested
`.git` was removed so the folder is now ordinary tracked content.

**3 · `framer-motion` was never declared as a dependency.** Eight files import
it, but it was installed into a stray `package.json` at the *repo root*
instead of inside `ziren_dashboard`. Node resolves modules by walking up the
directory tree, so it worked on this machine by accident. On a clean clone
every dashboard route returned 500 with
`Module not found: Can't resolve 'framer-motion'`. It is now declared in
`ziren_dashboard/package.json` and in that lockfile.

The stray root `package.json` / `package-lock.json` have since been deleted.

**4 · The first push would have been rejected outright.** `data/` held 1.4 GB
of Planetiler downloads, including single files of 886 MB and 414 MB — GitHub
rejects anything over 100 MB, and committing them once would have put them in
history permanently. `data/` is now ignored; re-fetch it with
`tools/generate_tiles.ps1`, which downloads its own inputs. The pipeline's
*output* (`ziren_mobile/assets/map/biliran.mbtiles`, 2.3 MB) stays committed
because the app ships it.

The commit is 330 files and about 4 MB.

---

## Known issues

- **37 rubric rules still carry `TODO` provenance** (BFP 10, PNP 12,
  MDRRMO 15). The backend logs one warning per rule at startup. Each needs a
  real field-interview citation; never invent one.
- Next.js was upgraded from 15.3.3 to 15.5.26 to close CVE-2025-66478.
