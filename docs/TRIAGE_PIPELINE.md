# How a report is triaged, stage by stage

Written for whoever has to find out why a report got the severity, category or
agency it got. It follows one report from the resident's phone to the
dispatcher's screen, names the file and function at each step, and says what
each step leaves behind to look at. (Evaluator finding #28, 2026-10-05.)

## The short version: where to look first

1. **Open the incident on the dashboard.** "Why this severity" shows the rule
   (for example `SR002`) and its reason. That comes from `incidents.signals`.
2. **Read `incidents.signals.pipeline_trace`.** It lists every stage that ran
   and how long each took, in order:
   `normalise → classify → signals → wizard → verify → severity → routing`.
   A report with no text starts at `wizard`.
3. **Search the backend log for the incident.**
   - `triage.completed` has the stages, total time, severity, rule and
     verification status.
   - `triage.failed` names the stage that raised (`stage=`) and the stages
     that had finished (`completed=`). When it fails, the report is still
     saved with no severity and is flagged for a person to triage.

## The path, end to end

| # | Where | File / function | What it does | What it leaves behind |
|---|---|---|---|---|
| 1 | Phone | `ziren_mobile/lib/features/incident_report/domain/incident_provider.dart` → `submitIncident()` | Uploads photos and video to the `incident-media` bucket, then sends the report. | Storage paths in `media_urls`. |
| 2 | Phone | `.../data/incident_repository.dart` → `submitIncident()` | `POST /incidents/` with the text, category, wizard answers, landmark and GPS. | HTTP log line on the backend. |
| 3 | API | `ziren_backend/app/routers/incidents.py` → `submit_incident()` | Checks auth and the request shape, then calls the service. Schedules voice transcription when a recording is attached. | `422` for a malformed body. |
| 4 | Service | `app/services/incident_service.py` → `submit_incident()` → `_create_incident_row()` | Refuses a suspended account, resolves the station, runs triage inline, then inserts the row. Triage never blocks the save. | The `incidents` row. `nlp_review_needed` is true when a person must check the result. |
| 5 | Triage | `app/services/triage_service.py` → `triage()` → `_triage_inner()` | Runs the stages below, then records `pipeline_trace`. | `incidents.signals` (JSONB), `incidents.severity`. |
| 6 | Voice | `app/services/transcription_service.py` → `schedule()` | After the response, transcribes the recording and re-runs triage on the transcript. | Transcript in `signals.transcript`. Updated severity. |
| 7 | Dashboard | `ziren_dashboard/components/ui/severity-rationale.tsx` | Shows the rule, the reason and the verification message to the dispatcher. | — |
| 8 | Dispatch | `app/routers/dispatch.py` → `assign_responder()` | The dispatcher confirms the severity and its reason (finding #4) and chooses who to send. | `dispatch_log` row, plus a note when the severity was overridden. |

## The triage stages (step 5)

| Stage | Code | Reads | Produces | When it is wrong, suspect… |
|---|---|---|---|---|
| `normalise` | `normalise_text()`, `_collapse_immediate_repeats()` | The report text | Corrected text for signal extraction. Speech-to-text fixes, local words, aliases. | A local word that is missing from `app/ml/06_DICTIONARY` or the alias list. |
| `classify` | `_MODEL.predict_proba()` | The ORIGINAL text, with place names stripped | Predicted category, confidence, runner-up | The model itself (`app/ml/07_MODELS`, version in `app/ml/VERSION`). |
| `signals` | `Z.extract()` (`app/ml/tools/predict.py`) | The normalised text | Injured, fatalities, entrapment, weapon, location… | The extractor's patterns, or a number the recogniser welded into a word (`signals.count_uncertain`). |
| `wizard` | `_chips_from_wizard()` | The resident's wizard answers and overlap flags | Signals set from the answers. The resident's answers win over the text. | The wizard answer strings. They are a contract with this code and must not be translated (see the wizard string contract). |
| `verify` | inline | The chosen category against the predicted one | `verification_status`: `AGREE`, `MISMATCH_FLAGGED`, `UNCERTAIN`, `NO_SELECTION` or `NO_TEXT` | The confidence threshold (`FLAG_THRESHOLD`). |
| `severity` | `Z.severity()` | The signals, the routing category and the confidence | Severity level, rule id, reason | The SR rules in `predict.py`. The highest rule that fires wins. |
| `routing` | inline | The routing category and the signals | Suggested agencies, and whether the dispatcher must choose (`needs_manual_agency`) | `Z.AGENCY`. Entrapment adds BFP; injuries add MDRRMO. |

## Reproducing a result locally

```powershell
cd ziren_backend
.venv\Scripts\python -c "from app.services import triage_service as t; import json; r = t.triage(report_text='May sunog sa bahay, may naipit'); print(json.dumps(r['signals']['pipeline_trace'], indent=1)); print(r['severity'], r['signals']['severity_rule'], r['signals']['severity_reason'])"
```

The same function the API calls, with the same model, prints the stage trace
and the rule. Tests that pin this behaviour are in `tests/test_triage_trace.py`,
`tests/test_rubric_engine.py` and `tests/test_triage_stt.py`.
