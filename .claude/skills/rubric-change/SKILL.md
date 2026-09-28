---
name: rubric-change
description: Change Ziren's rubric severity engine safely — the per-agency JSON rule configs (BFP/PNP/MDRRMO), rubric_service evaluation logic, condition schema, provenance, audit trail, and the version/activation flow. Use whenever the user edits a rubric rule, adds a signal or condition operator, changes how severity is decided or which agency is recommended, touches app/rubric_configs/*.json, rubric_service.py, rubric_traceability.py or the /rubric endpoints, or asks why an incident got a particular severity.
---

# Changing the rubric engine

The rubric is the thesis. It is not a placeholder for missing ML — it is the
system's severity decision, and the defense will centre on whether its rules
are grounded in real dispatch practice and whether changes to them are
traceable. Treat every edit as touching a life-safety component with an audit
requirement, because that is what it is.

## How it works, in the order the code runs

`rubric_service.evaluate(signals, agency_type, db=None)`:

1. **Load config** — in-process cache → DB active config (authoritative) →
   bundled JSON seed file in `app/rubric_configs/{AGENCY}_v1.json`.
2. **Match** every active rule's conditions against the flat signal dict.
3. **Aggregate by max-of-triggered-rules** — if any rule fires `critical`, the
   result is `critical`, regardless of how many lower rules also fired. This is
   the conservative choice for life safety and is a confirmed design decision;
   do not "improve" it into an average or a weighted score.
4. **No rules matched** → severity defaults to `low` with
   `no_rules_triggered=True`, logged for dispatcher manual review.

Two behaviours that shape everything else:

**The seed fallback hides DB problems.** When no active config exists in the
DB, the engine loads the JSON seed and keeps working — writing a
`fallback_to_seed` row to `rubric_audit_log` every time. Scoring therefore
looks healthy while the config layer is completely broken. Migration 018 exists
because of exactly this. If a change seems to have no effect, check
`config_source` in the result before assuming your edit was wrong.

**The seed is never cached.** A DB hit is cached until `invalidate_cache()`;
the seed deliberately is not, so the fallback state stays visible in the audit
log until an admin activates a real config.

## Editing rules

Rules live as JSON, per agency, per version:

```json
{
  "rule_id": "BFP-001",
  "description": "Structure fire with confirmed fatalities",
  "conditions": { "incident_type_in": ["fire"], "dead_count_gte": 1 },
  "severity_contribution": "critical",
  "recommended_agency": "BFP",
  "provenance": "...",
  "active": true
}
```

- **`rule_id` is permanent.** It appears in `triggered_rules` on stored
  evaluations and in audit rows. Never renumber an existing rule; add a new id.
- **Retire with `"active": false`, don't delete.** Past evaluations reference
  it, and the deactivation is itself the evidence of a policy change.
- **`provenance` is the defense exhibit.** Every rule must eventually cite a
  field interview: date, station, and the dispatch practice it encodes. A
  `TODO:` prefix is caught at startup by `check_provenance()` in
  `rubric_traceability.py`, which logs one structured warning per offending
  rule. Most seed rules still carry TODOs — that is deliberate honesty, so
  **never invent a provenance to silence the warning.** Filling one in requires
  the user's actual interview notes; ask for them.

Conditions are a **closed schema**, not free-form. Supported keys today:

```
incident_type / incident_type_in      fire_type / fire_type_in
casualty_mentioned                    injured_count_gte / injured_count_lte
dead_count_gte                        weapon_mentioned / weapon_type_in
structure_type_in                     children_involved
urgency_level_in                      multi_agency_needed
why_category_in / how_category_in     incident_category_in
```

Unspecified conditions do not constrain the match; **all** specified ones must
pass. A missing or `None` signal fails any condition testing it — unknown is
not treated as present, which is the conservative reading for triage.

**Adding a new operator or signal means editing two places**: the
`RubricCondition` model in `app/models/rubric.py` *and* `_condition_matches()`
in `rubric_service.py`. Miss the second and the condition is silently ignored —
Pydantic accepts the field, no rule ever fires on it, and no error appears
anywhere. Add a test that fails before the matcher change.

Keep `_condition_matches()` explicit: no `eval`, no dynamic dispatch, one
`if` per operator. It is written that way so a panel member can read a rule
and predict the outcome. Explainability beats cleverness here.

## Versioning and activation

Editing a seed JSON only changes the fallback. The DB is authoritative, and
config changes there are a two-step flow on purpose:

```
POST /rubric/{agency_type}/configs                    → upload (inactive)
POST /rubric/{agency_type}/configs/{id}/activate      → activate
```

Upload never auto-activates, so a bad config cannot go live by accident.
Activation deactivates the current version, activates the new one, writes an
audit row for each step, and calls `invalidate_cache()` so the next evaluation
picks up the new rules.

Bump `version` semantically when scoring behaviour changes — a version string
that stays put while rules move makes stored `rubric_config_version` values
meaningless as an audit trail.

`activate_config()` has a known limitation documented in the source: the
Supabase client cannot wrap the deactivate/activate pair in one transaction, so
a mid-flight failure leaves the old version deactivated and the new one not yet
active. If that state ever appears, flag it rather than patching around it.

## Audit writes have two different failure policies

This asymmetry is intentional — match it in any new code:

- `write_fallback_audit_event()` — **never raises.** A system fallback must not
  take the engine down if the audit table is unreachable. Logs the failure.
- `write_config_audit_event()` — **raises**, aborting the change. A human
  config change without an audit record is a security problem, so the change
  is refused rather than recorded silently.

## Security

Every `/rubric/*` endpoint requires `agency_admin` or `super_admin`, and
`_assert_agency_scope()` additionally blocks an `agency_admin` from touching
another agency's configs — a role check alone is not enough. `/rubric/evaluate`
is admin-only too, so the scoring logic is not externally queryable. Keep both
checks on any endpoint you add, and cover them in `test_rubric_security.py`.

## After any change

```powershell
cd c:\Dev\Ziren\ziren_backend
.venv\Scripts\python.exe -m pytest tests/test_rubric_engine.py tests/test_rubric_bfp.py tests/test_rubric_pnp.py tests/test_rubric_mdrrmo.py tests/test_rubric_security.py -q
```

Then check:

- The rule you changed fires on the case you intended **and** stops firing on
  the case you didn't — a too-broad condition is invisible in a passing suite
  that only asserts positives.
- `config_source` is what you expect (`db` vs `seed_fallback`).
- `check_provenance()` shows no *new* TODOs.
- `KNOWN_SCENARIOS` in `rubric_traceability.py` still pass, if they've been
  filled in. These are the field-interview cases and the strongest evidence
  that the rubric reproduces real practice — they are still TODO placeholders
  until the user supplies the interview data.
