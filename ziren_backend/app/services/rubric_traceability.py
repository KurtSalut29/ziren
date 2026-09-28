"""
Rubric traceability service — Phase 5.2.

Responsibilities:
  1. On startup, scan every active rubric config for rules that still
     have TODO provenance and emit a structured warning per rule.
     This is the mechanism that keeps the "empirically grounded" claim
     honest — every unfilled TODO is visible at startup, not buried in
     source files.

  2. Write a rubric_audit_log row whenever the engine falls back to a
     JSON seed file because the DB had no active config for an agency.
     This is NOT only a console warning — every fallback is a
     persistent audit record (per confirmed design in 5.1).

  3. Provide a cross-check function that verifies a known real-world
     dispatch scenario produces the expected severity from the rubric.
     Leave the actual scenario values as TODO placeholders — Kurt fills
     in the real field-interview case before defense.

Architecture note — what this module does NOT do:
  - It does not evaluate signals. That is rubric_service.py (5.3).
  - It does not load configs from DB. That is rubric_service.py (5.3).
  - It only reads already-loaded RubricConfig objects and writes audit rows.
  - The DB write uses the Supabase service-role client directly (actor_id=None)
    because fallback events are system-generated, not user-initiated.
"""

from __future__ import annotations

import json
import pathlib
import structlog

from app.models.rubric import (
    AgencyType,
    AuditEventType,
    RubricAuditEvent,
    RubricConfig,
)

log = structlog.get_logger()

# Path to the bundled seed files — relative to the package root
_SEED_DIR = pathlib.Path(__file__).parent.parent / "rubric_configs"

# ── Provenance check ──────────────────────────────────────────────────────────

class ProvenanceCheckResult:
    """
    Result of scanning all loaded rubric configs for TODO provenance.

    Attributes:
        todo_rules  : list of (agency_type, rule_id, provenance_snippet)
                      for every active rule whose provenance starts with TODO
        clean       : True if no TODO provenance found across all agencies
    """

    def __init__(self) -> None:
        self.todo_rules: list[tuple[str, str, str]] = []

    @property
    def clean(self) -> bool:
        return len(self.todo_rules) == 0

    def add(self, agency_type: str, rule_id: str, provenance: str) -> None:
        snippet = provenance[:120].rstrip()
        self.todo_rules.append((agency_type, rule_id, snippet))

    def __repr__(self) -> str:
        if self.clean:
            return "ProvenanceCheckResult(clean=True)"
        return (
            f"ProvenanceCheckResult(clean=False, "
            f"todo_count={len(self.todo_rules)})"
        )


def check_provenance(configs: list[RubricConfig]) -> ProvenanceCheckResult:
    """
    Scan every active rule in every loaded config for TODO provenance.

    Emits one structured log warning per offending rule — not a single
    bulk warning — so log aggregation tools can filter by rule_id.

    Called from the FastAPI lifespan startup event (main.py).
    Does NOT raise an exception — a TODO provenance is a quality warning,
    not a fatal error. The rubric still evaluates. The warning is the
    mechanism that keeps provenance debt visible.

    Returns a ProvenanceCheckResult the caller can inspect (e.g., for
    integration tests that assert provenance cleanliness before defense).
    """
    result = ProvenanceCheckResult()

    for cfg in configs:
        for rule in cfg.active_rules():
            if rule.provenance.strip().upper().startswith("TODO"):
                result.add(cfg.agency_type.value, rule.rule_id, rule.provenance)
                log.warning(
                    "rubric.provenance_todo",
                    agency_type=cfg.agency_type.value,
                    rule_id=rule.rule_id,
                    version=cfg.version,
                    provenance_snippet=rule.provenance[:120],
                    action_required=(
                        "Replace this TODO with the field interview date, "
                        "station name, and the dispatch practice it encodes "
                        "before the defense presentation."
                    ),
                )

    if result.clean:
        log.info(
            "rubric.provenance_check_passed",
            agency_count=len(configs),
            message="All active rubric rules have non-TODO provenance.",
        )
    else:
        log.warning(
            "rubric.provenance_check_summary",
            todo_rule_count=len(result.todo_rules),
            agencies_affected=list({t[0] for t in result.todo_rules}),
            message=(
                f"{len(result.todo_rules)} active rule(s) still have TODO provenance. "
                "Fill these in before the defense — they are the evidence that the "
                "rubric is empirically grounded, not guessed."
            ),
        )

    return result


# ── Fallback audit writer ─────────────────────────────────────────────────────

def write_fallback_audit_event(
    agency_type: AgencyType,
    reason: str,
    seed_version: str,
    db,  # supabase.Client — passed in to avoid circular import with db module
) -> None:
    """
    Write a rubric_audit_log row for a fallback-to-seed event.

    Called by rubric_service.py whenever it cannot load an active config
    from the DB and falls back to the bundled JSON seed file.

    This write uses the Supabase service-role client (actor_id=None)
    because there is no authenticated user — this is a system event.
    If the audit write itself fails, we log the error but do NOT raise
    an exception: the rubric engine must still function even if the audit
    table is temporarily unreachable.

    Parameters:
        agency_type  : which agency's config was missing from DB
        reason       : human-readable explanation of why fallback occurred
        seed_version : version string from the seed file that was loaded
        db           : active Supabase client (service role)
    """
    # Validate the event model before attempting DB write
    event = RubricAuditEvent(
        event_type=AuditEventType.fallback_to_seed,
        agency_type=agency_type,
        config_version=seed_version,
        rubric_config_id=None,
        rule_id=None,
        previous_value=None,
        new_value=None,
        actor_id=None,  # system event — no authenticated user
        notes=reason,
    )

    log.warning(
        "rubric.fallback_to_seed",
        agency_type=agency_type.value,
        seed_version=seed_version,
        reason=reason,
        persistent_audit="writing to rubric_audit_log",
    )

    try:
        db.table("rubric_audit_log").insert({
            "event_type":       event.event_type.value,
            "agency_type":      event.agency_type.value,
            "rubric_config_id": None,
            "config_version":   event.config_version,
            "rule_id":          None,
            "previous_value":   None,
            "new_value":        None,
            "actor_id":         None,
            "notes":            event.notes,
        }).execute()
    except Exception as exc:
        # Non-fatal — rubric must still function if audit table is unreachable.
        # Log the failure explicitly so it's visible in monitoring.
        log.error(
            "rubric.fallback_audit_write_failed",
            agency_type=agency_type.value,
            error=str(exc),
            message=(
                "Could not write fallback_to_seed audit event to rubric_audit_log. "
                "The rubric engine is still operational using the seed file."
            ),
        )


# ── Human-authored change audit writer ───────────────────────────────────────

def write_config_audit_event(
    event_type: AuditEventType,
    agency_type: AgencyType,
    actor_id: str,
    db,
    *,
    rubric_config_id: str | None = None,
    config_version: str | None = None,
    rule_id: str | None = None,
    previous_value: dict | None = None,
    new_value: dict | None = None,
    notes: str | None = None,
) -> None:
    """
    Write a rubric_audit_log row for a human-initiated config event.

    Called by rubric_service.py when:
      - A new config version is uploaded (config_created)
      - A config version is activated   (config_activated)
      - A config version is deactivated (config_deactivated)
      - A rule within a version is updated (rule_updated)

    actor_id is the authenticated dispatcher's UUID — never None for
    human-initiated events.

    Raises on failure (unlike write_fallback_audit_event) because a
    failed audit write on a human config change is a security concern —
    we must not allow a config change to proceed without an audit record.
    """
    if not actor_id:
        raise ValueError(
            "actor_id is required for human-initiated audit events. "
            "Use write_fallback_audit_event() for system events."
        )

    try:
        db.table("rubric_audit_log").insert({
            "event_type":       event_type.value,
            "agency_type":      agency_type.value,
            "rubric_config_id": rubric_config_id,
            "config_version":   config_version,
            "rule_id":          rule_id,
            "previous_value":   previous_value,
            "new_value":        new_value,
            "actor_id":         actor_id,
            "notes":            notes,
        }).execute()
    except Exception as exc:
        log.error(
            "rubric.config_audit_write_failed",
            event_type=event_type.value,
            agency_type=agency_type.value,
            actor_id=actor_id,
            error=str(exc),
        )
        raise RuntimeError(
            f"Audit write failed for {event_type.value} on {agency_type.value}. "
            "Config change aborted to preserve audit integrity."
        ) from exc


# ── Field-interview cross-check ───────────────────────────────────────────────

class DispatchScenario:
    """
    A hand-authored real-world scenario used to validate that the rubric
    produces the correct severity for a known case from field research.

    Kurt fills in the `signals` dict and `expected_severity` from the actual
    field interview before the defense. The TODO markers here are intentional —
    do not invent values.

    How to use:
        from app.services.rubric_traceability import KNOWN_SCENARIOS
        for scenario in KNOWN_SCENARIOS:
            result = rubric_service.evaluate(scenario.signals, scenario.agency_type)
            assert result.severity == scenario.expected_severity, scenario.description
    """

    def __init__(
        self,
        scenario_id: str,
        description: str,
        agency_type: AgencyType,
        signals: dict,
        expected_severity: str,
        field_interview_reference: str,
    ):
        self.scenario_id = scenario_id
        self.description = description
        self.agency_type = agency_type
        self.signals = signals
        self.expected_severity = expected_severity
        self.field_interview_reference = field_interview_reference


# ── Known real-world scenarios from field interviews ─────────────────────────
#
# INSTRUCTIONS FOR KURT:
#   Each entry below is a real dispatch scenario from your BFP/PNP/MDRRMO
#   field interviews that the rubric must correctly reproduce.
#
#   For each TODO item:
#     1. Replace the signals dict with the actual signal values the incident
#        would have produced (based on the interview transcript).
#     2. Set expected_severity to the severity the station actually dispatched
#        (or should have dispatched per the correct protocol).
#     3. Replace the field_interview_reference string with the interview date,
#        station name, and a one-line description of the incident.
#
#   These scenarios are used in test_rubric_engine.py as a separate test class
#   ("known dispatch failure / validation cases") and are a defense exhibit —
#   they are the evidence that the rubric encodes real practice, not invented
#   rules.
#
# ─────────────────────────────────────────────────────────────────────────────

KNOWN_SCENARIOS: list[DispatchScenario] = [

    DispatchScenario(
        scenario_id="FIELD-BFP-001",
        description=(
            # TODO: Replace with the actual scenario description from your
            # BFP field interview (e.g., 'Residential fire, Naval barangay,
            # 2 confirmed injuries, responding units delayed due to incomplete report').
            "TODO: BFP field scenario — describe the actual incident here."
        ),
        agency_type=AgencyType.BFP,
        signals={
            # TODO: Replace with actual signal values from the incident.
            # These must match the ExtractedSignals schema (15 fields).
            # Example structure — do not use these placeholder values:
            "incident_type":      "TODO_fire_or_other",
            "fire_type":          None,
            "casualty_mentioned": False,   # TODO: was there a casualty?
            "injured_count":      None,    # TODO: actual count or None
            "dead_count":         None,
            "weapon_mentioned":   False,
            "weapon_type":        None,
            "why_category":       None,
            "how_category":       None,
            "structure_type":     None,
            "children_involved":  False,
            "urgency_level":      None,
            "location_specificity": None,
            "multi_agency_needed": False,
            "language_detected":  None,
            "incident_category":  None,
        },
        expected_severity=(
            # TODO: What severity should this have produced?
            # Use: 'critical', 'high', 'medium', or 'low'
            "TODO_critical_or_high_or_medium_or_low"
        ),
        field_interview_reference=(
            # TODO: 'BFP [Station name], [Date], [brief incident description]'
            "TODO: BFP field interview reference"
        ),
    ),

    DispatchScenario(
        scenario_id="FIELD-PNP-001",
        description=(
            "TODO: PNP field scenario — describe the actual incident here."
        ),
        agency_type=AgencyType.PNP,
        signals={
            "incident_type":      "TODO_crime_or_other",
            "fire_type":          None,
            "casualty_mentioned": False,
            "injured_count":      None,
            "dead_count":         None,
            "weapon_mentioned":   False,
            "weapon_type":        None,
            "why_category":       None,
            "how_category":       None,
            "structure_type":     None,
            "children_involved":  False,
            "urgency_level":      None,
            "location_specificity": None,
            "multi_agency_needed": False,
            "language_detected":  None,
            "incident_category":  None,
        },
        expected_severity="TODO_critical_or_high_or_medium_or_low",
        field_interview_reference="TODO: PNP field interview reference",
    ),

    DispatchScenario(
        scenario_id="FIELD-MDRRMO-001",
        description=(
            "TODO: MDRRMO field scenario — describe the actual incident here."
        ),
        agency_type=AgencyType.MDRRMO,
        signals={
            "incident_type":      "TODO_flood_or_medical_or_other",
            "fire_type":          None,
            "casualty_mentioned": False,
            "injured_count":      None,
            "dead_count":         None,
            "weapon_mentioned":   False,
            "weapon_type":        None,
            "why_category":       None,
            "how_category":       None,
            "structure_type":     None,
            "children_involved":  False,
            "urgency_level":      None,
            "location_specificity": None,
            "multi_agency_needed": False,
            "language_detected":  None,
            "incident_category":  None,
        },
        expected_severity="TODO_critical_or_high_or_medium_or_low",
        field_interview_reference="TODO: MDRRMO field interview reference",
    ),
]


def load_seed_config(agency_type: AgencyType) -> RubricConfig:
    """
    Load the bundled JSON seed config for an agency.

    Used by rubric_service.py as the fallback path when no active config
    is found in the DB. Also used in tests that need a known-good config
    without a DB connection.

    Raises FileNotFoundError if the seed file is missing — this is a
    deployment error, not a runtime error, and must not be silenced.
    """
    filename = _SEED_DIR / f"{agency_type.value}_v1.json"
    if not filename.exists():
        raise FileNotFoundError(
            f"Rubric seed file not found: {filename}. "
            f"Expected one seed file per agency in {_SEED_DIR}. "
            "This is a deployment error — add the missing seed file."
        )
    raw = json.loads(filename.read_text(encoding="utf-8"))
    return RubricConfig(**raw)
