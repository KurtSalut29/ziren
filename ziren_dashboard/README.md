# ziren_dashboard

The dispatcher console for Ziren: Next.js 15 (App Router), React, TypeScript,
Tailwind CSS v4. Used by **Agency Admins** (one station: BFP, PNP or MDRRMO)
and **Provincial Admins** (every station of one agency type).

It holds no data of its own. Every read and write goes to `ziren_backend`.

## Run

```powershell
npm install
npm run dev          # http://localhost:3000
```

Environment (`.env.local`, not committed):

| Variable | Meaning |
|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | Backend base URL. `/api` sends calls through the same-origin proxy in `app/api/[...path]/route.ts`; unset defaults to `http://localhost:8000`. |
| `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase project, anon key only. Never a service-role key. |
| `NEXT_PUBLIC_ENABLE_ALERT_DEMO` | `true` shows the demo trigger for the new-report alert. Leave unset in production. |

`NEXT_PUBLIC_*` values are baked in at build time.

## Layout

```
app/
  (auth)/         login, signup, accept-invite, forgot/reset password
  (dashboard)/    every signed-in page; layout.tsx owns the shell and the new-report alert
    error.tsx     keeps the shell and alerts alive when a single page throws
  api/[...path]/  same-origin proxy to the backend
components/       UI, grouped by feature (incidents, map, settings, ...)
lib/
  api/            one typed client module per backend router
  hooks/          useAuth, useIncidentAlerts (polling + alarm), ...
  incidents/      cross-page events (arrivals, incident opened)
```

Auth state lives in `sessionStorage` (`lib/hooks/useAuth.ts`). Role decides
navigation: `agency_admin` or `provincial_admin`.

## Checks

The dashboard has no unit-test suite. The rules it relies on (scoping,
severity, dispatch) are enforced and tested in the backend. These three must
pass:

```powershell
npx tsc --noEmit     # type check: 0 errors
npx eslint .         # lint: 0 errors, 0 warnings
npx next build       # production build: 34 pages
```

Do not run `next build` while `npm run dev` is running: both use `.next`, and
the running dev server starts returning 500 on every route.
