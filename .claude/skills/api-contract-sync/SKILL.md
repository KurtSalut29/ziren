---
name: api-contract-sync
description: Keep Ziren's three codebases in agreement when a FastAPI endpoint changes — backend router/model, the dashboard's lib/api client and TypeScript types, and the Flutter repository and model that consume the same endpoint. Use whenever the user adds, renames, or changes an endpoint, request/response field, enum value, or status code in ziren_backend/app/routers or app/models, and whenever a client reports a missing field, a null where data was expected, an unexpected 422, or a screen that renders blank after a backend change.
---

# Keeping the API contract in sync

One FastAPI backend serves two independently written clients. Nothing enforces
agreement between them: the dashboard's TypeScript types are hand-maintained,
the Flutter models parse JSON by hand, and neither is generated from the
backend schema. A renamed response field therefore compiles cleanly on all
three sides and fails only at runtime — usually as a blank panel or a silent
`null`, not as an error anyone can trace back to the change.

**So a backend change is not finished until both clients have been checked.**
Not "updated if convenient" — checked, and the check reported.

## The three sides

**Backend** — `ziren_backend/app/routers/*.py` with Pydantic models in
`app/models/*.py`. The response model is the contract.

**Dashboard** — `ziren_dashboard/lib/api/*.ts` (`dispatch.ts`, `map.ts`,
`rubric.ts`) built on `lib/api/client.ts`, with shared shapes in
`lib/types/*.ts`. Calls look like:

```ts
apiClient.get<IncidentSummary[]>('/dispatch/queue', token)
```

The generic is a **claim**, not a check — `client.ts` casts
`response.json()` straight to `T`. A stale type here produces `undefined` at
render time and no compile error whatsoever.

**Mobile** — `ziren_mobile/lib/features/<feature>/data/*_repository.dart` with
models in `../domain/*_model.dart`. Calls use `package:http` against
`AppConfig.apiBaseUrl`, parse with `Model.fromJson(...)`, and read errors as
`err['detail']`. `fromJson` is where drift actually bites: a missing key
becomes `null` and then either a null-check crash or an empty widget.

## Checklist for an endpoint change

Work outward from the backend:

1. **Backend** — router + Pydantic request/response model updated; the
   response model actually reflects what is returned.
2. **Grep both clients for the path string.** The route literal is the most
   reliable thing to search for, since names diverge across languages:
   ```
   rg -n "'/dispatch/queue'|\"/dispatch/queue\"" ziren_dashboard/lib ziren_mobile/lib
   ```
   Only one client may consume it — confirm that rather than assume it.
3. **Dashboard** — update the TS interface *and* every component reading the
   changed field. Renaming a field in the interface does not flag the old
   accessor if the property was optional.
4. **Mobile** — update the model's `fromJson` (and `toJson` if it posts), plus
   the widgets reading it.
5. **Error shape** — both clients read `detail` from an error body. If you
   raise something that isn't a FastAPI `HTTPException`, or return a bare
   string, both clients display a useless message.
6. **Status codes** — the dashboard's `ApiError` carries `status` and callers
   branch on it (401 in particular); mobile branches on `statusCode == 200` and
   treats everything else as a `ServerFailure`. A new 2xx that isn't 200 will
   be read as a failure on mobile.
7. **Auth** — dashboard sends `Authorization: Bearer <token>` from
   sessionStorage; mobile sends the Supabase session token. An endpoint that
   newly requires a role must be checked against the role each client actually
   holds.

## Enum values are the quiet killer

Severity levels, incident statuses, agency types and roles are duplicated as
string literals in all three languages. Adding a value backend-side does not
break a client — it falls through whatever switch or map exists and renders
nothing, or renders a default that is *wrong rather than absent*, which is
worse in a dispatch UI.

When you add or rename an enum value, search all three codebases for the
existing values, not just the new one, and update every exhaustive mapping:
status pills, severity colours, filter lists, sort orders.

Severity in particular is bound to the colour rules documented in
`ziren_dashboard/app/globals.css` — red is reserved strictly for critical, and
severity must always carry an icon and label alongside the colour. A new
severity tier needs a deliberate colour decision, not a leftover default.

## Verify, don't assume

Static agreement isn't evidence. After the change:

- Hit the endpoint directly (curl / `/docs`) and read the actual JSON body —
  compare it field by field with both client models.
- Render the dashboard page that uses it. A blank panel means the contract is
  still broken; see the `ziren-dev` skill for seeding auth and mocking the
  backend, and remember to clear `.next` if the page looks unchanged.
- For mobile, `AppConfig.validate()` prints the API base URL at startup — a
  "contract" bug is sometimes just the app talking to the wrong host.

## When drift is what you're debugging

Symptoms and where they usually come from:

| Symptom | Likely cause |
|---|---|
| Field is `undefined` in the dashboard, no error | TS interface claims a field the backend no longer returns |
| Flutter throws a null-check error in a widget | `fromJson` key renamed backend-side |
| Screen renders empty, network tab shows 200 | Response shape changed (list vs object, or a wrapper key added) |
| 422 from a POST | Client sends a body the Pydantic request model no longer accepts |
| Error message reads "Failed to load …" with no detail | Backend returned a non-`HTTPException` error |

Each of these is a genuine defect with a clean root cause and a wrong-subsystem
symptom — good material for the weekly report. Capture the evidence string when
you find one.
