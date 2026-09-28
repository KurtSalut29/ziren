"""
Rubric engine Pydantic models — Phase 5.

These models define the contract for:
  - RubricCondition   : the signal-matching conditions a rule checks
  - RubricRule        : one row in a per-agency decision table
  - RubricConfig      : a complete, versioned rule-set for one agency
  - RubricEvaluationResult : the engine's output (severity + recommended agency)
  - RubricAuditEvent  : written to rubric_audit_log on every change or fallback

Design constraints (Section 0.3):
  - Severity is NEVER an ML output. These models are the only permitted
    path to a severity value — the engine that uses them is purely rule-based.
  - Conditions use a deliberately limited operator set (exact match, boolean,
    numeric threshold, null check) so no arbitrary logic can be embedded in a
    stored config row.
"""

from __future__ import annotations

from enum import Enum
from typing import Any
from uuid import UUID
from datetime import datetime

from pydantic import BaseModel, field_validator, model_validator


# ── Enumerations ──────────────────────────────────────────────────────────────

class SeverityLevel(str, Enum):
    critical = "critical"
    high     = "high"
    medium   = "medium"
    low      = "low"


class AgencyType(str, Enum):
    BFP    = "BFP"
    PNP    = "PNP"
    MDRRMO = "MDRRMO"


class AuditEventType(str, Enum):
    config_created    = "config_created"
    config_activated  = "config_activated"
    config_deactivated = "config_deactivated"
    rule_updated      = "rule_updated"
    fallback_to_seed  = "fallback_to_seed"


# ── Severity ordering (for max-of-triggered-rules aggregation) ────────────────
# Higher index = higher severity. Used by the engine to find the maximum.
SEVERITY_RANK: dict[SeverityLevel, int] = {
    SeverityLevel.low:      0,
    SeverityLevel.medium:   1,
    SeverityLevel.high:     2,
    SeverityLevel.critical: 3,
}


# ── Rule condition model ──────────────────────────────────────────────────────

class RubricCondition(BaseModel):
    """
    Specifies which signal values trigger this rule.

    All fields are optional — only fields present are tested.
    A rule with no conditions would match everything; such rules are
    rejected at config-load time.

    Operator semantics:
      incident_type         — exact string match against ExtractedSignals.incident_type
      incident_type_in      — any-of list match
      fire_type             — exact string match
      fire_type_in          — any-of list match
      casualty_mentioned    — boolean match
      injured_count_gte     — injured_count >= N
      injured_count_lte     — injured_count <= N
      dead_count_gte        — dead_count >= N
      weapon_mentioned      — boolean match
      weapon_type_in        — any-of list
      children_involved     — boolean match
      urgency_level_in      — any-of list
      structure_type_in     — any-of list
      multi_agency_needed   — boolean match
      why_category_in       — any-of list
      how_category_in       — any-of list
      incident_category_in  — matches wizard incident_category field (string enum)

    Null-handling:
      If a signal field is None/null in the payload and the rule tests that
      field for a specific value, the condition evaluates to False (no match).
      To explicitly require null, set `<field>_is_null: true`.
    """

    # incident_type (Signal 1)
    incident_type:        str         | None = None
    incident_type_in:     list[str]   | None = None

    # fire_type (Signal 2)
    fire_type:            str         | None = None
    fire_type_in:         list[str]   | None = None

    # casualty_mentioned (Signal 3)
    casualty_mentioned:   bool        | None = None

    # injured_count (Signal 4)
    injured_count_gte:    int         | None = None
    injured_count_lte:    int         | None = None

    # dead_count (Signal 5)
    dead_count_gte:       int         | None = None

    # weapon_mentioned (Signal 6)
    weapon_mentioned:     bool        | None = None

    # weapon_type (Signal 7)
    weapon_type_in:       list[str]   | None = None

    # children_involved (Signal 11)
    children_involved:    bool        | None = None

    # urgency_level (Signal 12)
    urgency_level_in:     list[str]   | None = None

    # structure_type (Signal 10)
    structure_type_in:    list[str]   | None = None

    # multi_agency_needed (Signal 14)
    multi_agency_needed:  bool        | None = None

    # why_category (Signal 8) — cause/motive
    why_category_in:      list[str]   | None = None

    # how_category (Signal 9) — method/means
    how_category_in:      list[str]   | None = None

    # incident_category — from the 5W1H wizard (pre-NLP structured input)
    incident_category_in: list[str]   | None = None

    @model_validator(mode="after")
    def at_least_one_condition(self) -> "RubricCondition":
        """Reject condition objects that test nothing — they would match all inputs."""
        values = self.model_dump(exclude_none=True)
        if not values:
            raise ValueError(
                "A RubricCondition must specify at least one field to test. "
                "An empty condition would match all signals and is not permitted."
            )
        return self


# ── Rule model ────────────────────────────────────────────────────────────────

class RubricRule(BaseModel):
    """
    One row in the per-agency decision table.

    rule_id is a human-readable stable identifier (e.g., 'BFP-001').
    It is used in audit logs and test assertions — do not reuse IDs.

    provenance must explain which field interview or dispatch practice
    this rule encodes. 'TODO' values are valid at development time and
    must be filled in before the defense — the engine logs a warning
    on startup if any active rule still has 'TODO' in its provenance.

    recommended_agency is the agency type this rule suggests dispatching.
    It can differ from the agency whose rubric this rule belongs to
    (e.g., a BFP rule might recommend MDRRMO for a flood-related overlap).
    """
    rule_id:              str
    description:          str
    conditions:           RubricCondition
    severity_contribution: SeverityLevel

    # Recommended agency for this scenario — may be same as rubric owner or different
    recommended_agency:   AgencyType | None = None

    # Traceability: which field interview / dispatch practice is this based on?
    # Must be filled in before defense. Engine warns on startup if 'TODO' found.
    provenance:           str

    # Whether this rule is currently evaluated by the engine.
    # Inactive rules are retained in the config for audit purposes.
    active:               bool = True

    @field_validator("rule_id")
    @classmethod
    def rule_id_format(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("rule_id cannot be empty.")
        return v

    @field_validator("provenance")
    @classmethod
    def provenance_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError(
                "provenance cannot be empty. Use 'TODO: [description]' "
                "if the field interview reference is not yet available."
            )
        return v


# ── Config model ──────────────────────────────────────────────────────────────

class RubricConfig(BaseModel):
    """
    A complete, versioned rule-set for one agency.

    This is what is stored in rubric_configs.rules (as JSONB) and in the
    JSON seed files. The agency_type and version fields at the top level
    are also stored as dedicated columns for fast lookup and uniqueness
    enforcement.
    """
    agency_type: AgencyType
    version:     str
    rules:       list[RubricRule]

    # DB-assigned fields — present when loaded from DB, absent in seed files
    id:           UUID    | None = None
    is_active:    bool           = False
    created_by:   UUID    | None = None
    activated_by: UUID    | None = None
    activated_at: datetime | None = None
    created_at:   datetime | None = None

    @field_validator("version")
    @classmethod
    def version_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("version cannot be empty.")
        return v

    @field_validator("rules")
    @classmethod
    def rules_not_empty(cls, v: list[RubricRule]) -> list[RubricRule]:
        if not v:
            raise ValueError(
                "A RubricConfig must contain at least one rule. "
                "An empty rule-set would always produce severity=low."
            )
        return v

    def active_rules(self) -> list[RubricRule]:
        """Returns only rules where active=True."""
        return [r for r in self.rules if r.active]

    def has_todo_provenance(self) -> list[str]:
        """Returns rule_ids of active rules that still have TODO provenance."""
        return [
            r.rule_id for r in self.active_rules()
            if r.provenance.strip().upper().startswith("TODO")
        ]


# ── Engine output model ───────────────────────────────────────────────────────

class RubricEvaluationResult(BaseModel):
    """
    Output of the rubric engine for a single incident's signals.

    severity is always present — defaults to 'low' if no rules fire.
    recommended_agencies is an ordered list (highest-priority first) of
    agency types suggested by triggered rules — for multi-agency routing.

    triggered_rules lists the rule_ids that fired, for full traceability.
    If triggered_rules is empty, no_rules_triggered=True and the incident
    should be flagged for manual dispatcher review.

    The rubric_config_version field records which config version produced
    this result — essential for post-incident audit and model drift analysis.
    """
    severity:               SeverityLevel
    recommended_agencies:   list[AgencyType]   = []
    triggered_rules:        list[str]          = []   # rule_ids
    no_rules_triggered:     bool               = False
    rubric_config_version:  str               | None = None
    agency_type:            AgencyType        | None = None

    # Whether the config was loaded from DB (authoritative) or JSON seed (fallback)
    config_source:          str                = "db"  # "db" | "seed_fallback"


# ── Audit event model ─────────────────────────────────────────────────────────

class RubricAuditEvent(BaseModel):
    """
    Written to rubric_audit_log for every rubric change and every fallback event.

    For human-initiated events (config_created, config_activated, etc.):
      - actor_id is the authenticated user's UUID
      - previous_value / new_value are JSONB snapshots of the changed data

    For system-generated fallback events (fallback_to_seed):
      - actor_id is None
      - notes must explain why the fallback occurred (required)
      - previous_value / new_value are None (no config change happened)
    """
    event_type:       AuditEventType
    agency_type:      AgencyType
    rubric_config_id: UUID    | None = None
    config_version:   str     | None = None
    rule_id:          str     | None = None
    previous_value:   dict[str, Any] | None = None
    new_value:        dict[str, Any] | None = None
    actor_id:         UUID    | None = None   # None for system events
    notes:            str     | None = None

    @model_validator(mode="after")
    def fallback_requires_notes(self) -> "RubricAuditEvent":
        """
        fallback_to_seed events must always include a note explaining
        why the DB lookup failed. This is the persistent audit record
        that replaces 'log a console warning'.
        """
        if self.event_type == AuditEventType.fallback_to_seed:
            if not self.notes or not self.notes.strip():
                raise ValueError(
                    "notes is required for fallback_to_seed audit events. "
                    "Explain why the DB config was unavailable."
                )
        return self


# ── Admin API request/response models ────────────────────────────────────────

class RubricConfigUploadRequest(BaseModel):
    """
    Body for POST /rubric/{agency_type}/configs
    Agency Admins upload a new version for their own agency; Provincial Admin
    can upload for any agency of their own agency_type.
    """
    version:  str
    rules:    list[RubricRule]

    @field_validator("version")
    @classmethod
    def version_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("version cannot be empty.")
        return v

    @field_validator("rules")
    @classmethod
    def rules_not_empty(cls, v: list[RubricRule]) -> list[RubricRule]:
        if not v:
            raise ValueError("Must provide at least one rule.")
        return v


class RubricConfigActivateRequest(BaseModel):
    """Body for POST /rubric/{agency_type}/configs/{config_id}/activate"""
    # Optional reason for activation — stored in audit log notes
    reason: str | None = None


class RubricConfigResponse(BaseModel):
    """Public representation of a rubric config row."""
    id:           UUID
    agency_type:  AgencyType
    version:      str
    is_active:    bool
    created_by:   UUID
    activated_by: UUID    | None
    activated_at: datetime | None
    created_at:   datetime
    # rules omitted by default — fetch individually to avoid large payloads
    # Use GET /rubric/{agency_type}/configs/{id}/rules to retrieve rule detail


class RubricConfigDetailResponse(RubricConfigResponse):
    """Extended response that includes the full rule list."""
    rules: list[RubricRule]


class RubricAuditLogResponse(BaseModel):
    """One row from rubric_audit_log."""
    id:               UUID
    event_type:       AuditEventType
    agency_type:      AgencyType
    rubric_config_id: UUID    | None
    config_version:   str     | None
    rule_id:          str     | None
    previous_value:   dict[str, Any] | None
    new_value:        dict[str, Any] | None
    actor_id:         UUID    | None
    notes:            str     | None
    created_at:       datetime
