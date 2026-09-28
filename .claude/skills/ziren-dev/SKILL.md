---
name: ziren-dev
description: Run, restart, and visually verify Ziren's three apps — the FastAPI backend (ziren_backend), the Next.js dashboard (ziren_dashboard), and the Flutter mobile app (ziren_mobile) — including the sessionStorage auth seeding and backend mocking needed to screenshot dashboard pages. Use whenever the user asks to run, start, launch, restart, or screenshot any part of Ziren, to check that a change actually works in the app, or reports that a page looks empty, blank, or unchanged after an edit.
---

# Running the Ziren stack

Three apps, started independently. Backend first when anything talks to it —
the dashboard and mobile both render empty shells against a dead backend, and
an empty shell looks exactly like a broken UI.

## Backend — FastAPI on :8000

```powershell
cd c:\Dev\Ziren\ziren_backend
.venv\Scripts\activate
uvicorn app.main:app --reload
```

Config comes from `ziren_backend/.env` (see `.env.example` for the full list).
The backend connects to Supabase as **service_role**, which bypasses RLS by
design — so a permission failure in the backend is almost always a missing
`GRANT`, not a policy problem. See the `supabase-migration` skill.

Two settings cause most "why can't the frontend reach it" confusion:

- `CORS_ORIGINS_RAW` — must contain the exact origin the browser uses. If you
  serve the dashboard on a LAN address, `http://localhost:3000` alone is not
  enough.
- `DASHBOARD_BASE_URL` — where invite and password-reset emails point. It must
  be reachable *by the device that opens the email*; `localhost` on a phone
  resolves to the phone. Any LAN address used here must also be registered in
  Supabase → Authentication → URL Configuration → Redirect URLs, or Supabase
  silently ignores it.

Tests:

```powershell
cd c:\Dev\Ziren\ziren_backend
.venv\Scripts\python.exe -m pytest -q
```

`tests/conftest.py` resets the shared rate limiter before every test. If you
see an unexplained `429` in a test, check that the code under test uses the
shared `app.core.rate_limit` limiter rather than constructing its own.

## Dashboard — Next.js on :3000

```powershell
cd c:\Dev\Ziren\ziren_dashboard
npm run dev
```

Reads `NEXT_PUBLIC_API_BASE_URL` from `.env.local` (defaults to
`http://localhost:8000`).

**If a change doesn't appear on screen, suspect the build cache before
suspecting your edit.** The dev server can keep serving stale compiled output:

```powershell
Remove-Item -Recurse -Force c:\Dev\Ziren\ziren_dashboard\.next
npm run dev
```

Concluding "my change didn't work" from a stale bundle wastes more time here
than any other single mistake.

**Never run `npm run build` while `npm run dev` is up.** They share `.next`,
and the build overwrites artefacts the dev server is still serving from — the
running server starts returning 500 on every route, with no error that points
at the cause. Stop the dev server, build, then delete `.next` and restart it.
If a dev server that was working suddenly 500s everywhere, this is why.

## Mobile — Flutter

```powershell
cd c:\Dev\Ziren\ziren_mobile
flutter run --dart-define-from-file=dart_defines.json
```

The dart-define file is **required** — `AppConfig.validate()` throws at startup
without it, and the values are deliberately not hardcoded in
`lib/core/config/app_config.dart`.

**Its values are baked in at compile time.** `String.fromEnvironment` is a
const constructor, so editing `dart_defines.json` does nothing for a running
app — not on hot reload, not on hot restart. Stop the app and run it again or
you will be reading stale config while looking at fresh JSON.

**The backend must be started with `--host 0.0.0.0` for any device to reach
it.** Uvicorn defaults to `127.0.0.1`, which accepts connections from the dev
machine only. The symptom on the phone is
`NetworkFailure: Could not reach the server` with a perfectly healthy backend
that answers fine in a browser on the same machine.

`API_BASE_URL` in `dart_defines.json` is a LAN address, not `localhost`,
because a physical device or emulator resolves `localhost` to itself. If the
dev machine's IP changed, update it there **and** add the new origin to the
backend's `CORS_ORIGINS_RAW`. `AppConfig.validate()` prints a masked
diagnostic of all three values at startup — read it before debugging further.

## Screenshotting a dashboard page

Real login needs a live backend plus Supabase. For visual QA that's slow and
usually unnecessary — mock instead, using Playwright.

Two things are required or every page renders as an empty skeleton:

**1. Seed the session.** Auth state lives in `sessionStorage`, not cookies —
see `lib/hooks/useAuth.ts`. Set `access_token`, `user_role`, and `user_email`
before the app boots (`page.addInitScript`). Role controls navigation:
`super_admin` shows Overview + Accounts, `agency_admin` shows Responders.

**2. Mock the backend.** Intercept requests to `localhost:8000`. The endpoints
that gate most pages:

```
/dispatch/queue            /users/me
/users/agencies-list       /users/super/agency-admins
/users/super/directory     /stations/
/stations/agencies/{id}
```

Playwright's `chromium` is cached in `~/AppData/Local/ms-playwright`, but the
`playwright` npm package itself must be installed in the scratchpad directory.

A skeleton-only screenshot proves nothing about whether a redesign worked, so
do not accept one as evidence — fix the mocks first.

## Colours are not decoration

`ziren_dashboard/app/globals.css` documents colour rules that carry
operational meaning for dispatchers under time pressure. Keep them intact
through any restyle: brand orange `#FC5A05` is CTAs and active nav only, red
is reserved strictly for critical severity, severity is always paired with an
icon and label (never colour alone), agency hues are fixed (BFP red-coral,
PNP sky-blue, MDRRMO emerald), and purple marks machine output only. The
mobile equivalents live in `ziren_mobile/lib/shared/theme/app_tokens.dart` and
are meant to stay in sync.

## Quick triage

| Symptom | Look here first |
|---|---|
| Dashboard says "Could not reach …" | Backend down, **or** origin missing from `CORS_ORIGINS_RAW`. `lib/api/client.ts` distinguishes the two — read the actual message. |
| Page renders but all panels empty | Backend up but returning errors, or session not seeded. Check the network tab / mock coverage. |
| Edit has no visible effect | Stale `.next` — delete and restart before anything else. |
| Mobile throws at startup | Missing `--dart-define-from-file`. |
| Mobile can't reach API | `API_BASE_URL` points at `localhost` or a stale LAN IP. |
| Invite email link dead on phone | `DASHBOARD_BASE_URL` is `localhost`, or the URL isn't in Supabase's redirect allow-list. |
