# ziren_backend

FastAPI backend for the Ziren Emergency Reporting & Dispatch System.

## Project structure

```
ziren_backend/
├── app/
│   ├── main.py              # FastAPI app entry point, startup checks, /health
│   ├── core/
│   │   ├── config.py        # Environment-based settings (pydantic-settings)
│   │   ├── rate_limit.py    # The shared limiter — never construct a second one
│   │   ├── geo.py           # Geodesic distance, PostGIS point parsing
│   │   └── dependencies.py  # Auth (Supabase token -> profile), role checks
│   ├── routers/             # one module per URL prefix; the main ones:
│   │   ├── auth.py          # /auth/*
│   │   ├── incidents.py     # /incidents/*      (mobile app)
│   │   ├── dispatch.py      # /dispatch/*       (dashboard)
│   │   ├── responder.py     # /responder/*
│   │   ├── rubric.py        # /rubric/*         (admin only)
│   │   ├── stations.py      # /stations/*
│   │   ├── users.py         # /users/*
│   │   └── map.py           # /map/*
│   ├── services/            # business logic behind the routers; the main ones:
│   │   ├── auth_service.py
│   │   ├── incident_service.py     # submit/fetch; calls triage_service inline
│   │   ├── triage_service.py       # Phase 4 — the trained model
│   │   ├── dispatch_service.py
│   │   ├── proximity.py            # responders near an incident
│   │   ├── responder_service.py
│   │   ├── rubric_service.py       # rule engine behind /rubric/evaluate
│   │   ├── rubric_traceability.py  # provenance checks, audit helpers
│   │   └── user_service.py
│   ├── models/
│   │   ├── user.py
│   │   ├── incident.py      # IncidentCategory, SeverityLevel, TriageSignals
│   │   └── rubric.py
│   ├── rubric_configs/      # Per-agency seed rules (BFP/PNP/MDRRMO)
│   ├── ml/                  # The triage model — see below
│   └── db/
│       └── supabase_client.py
├── supabase/migrations/
├── tests/
├── .env.example
├── requirements.txt
└── pyproject.toml
```

## Running locally

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows
pip install -r requirements.txt
copy .env.example .env            # then fill in the Supabase values
uvicorn app.main:app --reload --host 0.0.0.0
```

**The `.env` step is not optional.** `.env` is gitignored, so a fresh clone
does not have one, and the server will not start without it. The failure is
not obviously about configuration:

```
supabase._sync.client.SupabaseException: supabase_url is required
ERROR:    Application startup failed. Exiting.
```

That is raised from the rubric provenance check in `lifespan()`, which runs
before the triage model loads — so a missing `.env` looks like a startup crash
somewhere in the rubric engine, not a missing file. (Verified by cold-start
test, and the reason this step is spelled out.)

`--host 0.0.0.0` matters whenever a phone or emulator has to reach the API.
Uvicorn's default binds to `127.0.0.1`, which accepts connections from this
machine only; the symptom on a device is a network failure against a backend
that answers perfectly in a browser here.

### Verifying a fresh clone

Do this on any new machine before you rely on it:

```powershell
.venv\Scripts\python.exe -m pytest -q          # expect: 1527 passed, 3 skipped
# start the server, then:
curl http://127.0.0.1:8000/health
```

`/health` must report `"model_loaded": true`. If it reports `false`, the
`.joblib` did not come along — see *The .joblib is committed on purpose*
below.

---

## The triage model (Phase 4)

Every incident is scored at submission time. `incident_service._create_incident_row()`
calls `triage_service.triage()` before the insert, so `severity` and `signals`
are populated on the row itself — there is no background pass and no second
write. The dispatcher queue is ordered by severity from the moment a report
lands.

### Layout

`app/ml/` reproduces the folder layout the dataset release expects, so
`predict.py` can be copied in **verbatim and never edited**:

```
app/ml/
├── VERSION                        # dataset release, e.g. 2.1.4
├── tools/predict.py               # verbatim copy — do not modify
├── 06_DICTIONARY/*.csv            # Waray/Bisaya normalisation dictionaries
└── 07_MODELS/ziren_model.joblib   # the trained pipeline (~560 KB)
```

Anything Ziren-specific lives in `app/services/triage_service.py`: the
taxonomy mapping between the model's six classes and `IncidentCategory`, the
wizard-answer → chip translation, and the fail-safe wrapper. Keeping the
release file untouched means upgrading is a copy, not a re-patch.

### Upgrading to a new dataset release

1. Extract the release zip.
2. Copy `tools/predict.py`, `VERSION`, and `06_DICTIONARY/*.csv` into `app/ml/`.
3. **Retrain in this venv** (see the rule below), then copy the resulting
   `07_MODELS/ziren_model.joblib` into `app/ml/07_MODELS/`.
4. Check `severity()`'s signature — it has gained arguments before. The call
   site is in `triage_service._triage_inner()`.
5. `pytest -q`, then start the server and confirm the startup line reads
   `startup.triage_ready model_loaded=True` with the new version.

### Rule: the model must be built by the environment that serves it

**`ziren_model.joblib` must be produced by this venv.** A pickle trained under
a different scikit-learn version still unpickles here, still passes startup,
and still reports `model_loaded=True` — then raises inside `predict_proba` on
the first real report. That is the worst possible failure shape: silent until
an actual emergency.

This bit us once already. The model shipped in release 2.1.3 was trained on
scikit-learn 1.9.0 while `requirements.txt` pinned 1.6.1; loading succeeded
with only an `InconsistentVersionWarning`, and the first prediction died with
`'LogisticRegression' object has no attribute 'multi_class'`.

Two defences are now in place, and both should stay:

- `requirements.txt` pins `scikit-learn` and `joblib` to the versions the model
  was built with, with a comment saying why.
- `triage_service.load()` runs a throwaway `predict_proba(["smoke test"])`
  immediately after loading, so a skewed artefact fails at startup — loudly and
  in one place — instead of degrading every report.

To retrain, run the dataset's own tool with **this** interpreter, from the
extracted dataset directory (the repo deliberately does not carry
`03_CLASSIFICATION/splits/train.csv`, which holds incident data):

```powershell
cd C:\Users\kurts\Downloads\Ziren_Dataset_vX.Y.Z\ZIREN_DATASET
C:\Dev\Ziren\ziren_backend\.venv\Scripts\python.exe tools\predict.py --retrain "may sunog didi"
copy 07_MODELS\ziren_model.joblib C:\Dev\Ziren\ziren_backend\app\ml\07_MODELS\
```

### The .joblib is committed on purpose

`ziren_backend/.gitignore` excludes `*.joblib` as a general rule, with an
explicit exception for `app/ml/07_MODELS/*.joblib`.

It is 560 KB, and without it a fresh clone gives you a backend that starts
cleanly and triages nothing: `train_if_needed()` falls back to retraining from
a `train.csv` this repo does not carry, so every report is saved with
`severity NULL` and the only sign is one startup warning. Committing it also
pins provenance — `app/ml/VERSION` records which release produced the model
that produced a given severity.

### Failure behaviour

Triage never blocks a submission. `triage()` returns `None` rather than
raising, and the incident is saved with `severity NULL` and
`nlp_review_needed = True`, which the dashboard renders as
*"Not triaged · needs manual review"*. An emergency report must never fail
because a classifier is unavailable.

`GET /health` reports the model's state without affecting the status code:

```json
{"status":"ok","service":"ziren-api",
 "triage":{"model_loaded":true,"version":"2.1.4","flag_threshold":0.6,"error":null}}
```

### Model vs rubric

Both exist and they are not the same thing.

- **The model** (`triage_service`) scores every incident at submission. Its
  severity comes from the numbered rules `SR001`–`SR012` inside `predict.py`,
  and the rule id and its plain-language reason are stored in
  `incidents.signals` so the dashboard can answer *"why is this CRITICAL"*.
- **The rubric** (`rubric_service`) is the per-agency configurable engine
  behind `/rubric/evaluate`. It is admin-facing and is not on the submission
  path. See the `rubric-change` skill before editing it.

## Tests

```powershell
.venv\Scripts\python.exe -m pytest -q
```
