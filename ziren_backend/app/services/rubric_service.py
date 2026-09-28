"""
Rubric evaluation engine — Phase 5.3.

This is the rule-based severity decision engine for Ziren.
It is NOT a placeholder for missing ML (Section 0.3). It is the system.

Architecture:
  evaluate(signals, agency_type, db?)
    → load active config from DB (authoritative)
    → if no active DB config: load seed file + write fallback audit record
    → iterate active rules, test each condition against signals
    → aggregate by max-of-triggered-rules
    → return RubricEvaluationResult

Signal source contract:
  The engine accepts signals as a plain dict OR as an ExtractedSignals object.
  This makes the source swappable:
    - Today: hand-authored / mocked dicts (Phase 4 blocked)
    - Later: ExtractedSignals output from the NLP service (drop-in replacement)
    - Future fallback: manually-tagged signals from dispatcher Phase 6A view
  Rubric logic does not care which source produced the signals.

Aggregation rule: max-of-triggered-rules (see design proposal, confirmed 5.1).
  Conservative choice for life-safety: if any rule fires Critical, the result
  is Critical, regardless of how many lower-severity rules also fired.

Config cache:
  Configs are loaded fresh from DB on each evaluation call by default.
  A simple in-process cache (agency_type → RubricConfig) is populated on
  first load and invalidated when a new config is activated via the router.
  The cache avoids a DB round-trip on every incident submission while keeping
  the config authoritative (cache miss = DB fetch, not seed fallback).
"""

from __future__ import annotations

import structlog
from typing import Any

from app.db.supabase_client import get_supabase
from app.models.rubric import (
    AgencyType,
    AuditEventType,
    RubricCondition,
    RubricConfig,
    RubricEvaluationResult,
    RubricRule,
    SeverityLevel,
    SEVERITY_RANK,
    RubricConfigUploadRequest,
)
from app.services.rubric_traceability import (
    load_seed_config,
    write_fallback_audit_event,
    write_config_audit_event,
)

log = structlog.get_logger()

# ── In-process config cache ───────────────────────────────────────────────────
# Maps AgencyType → currently active RubricConfig.
# Populated lazily on first evaluate() call for each agency.
# Invalidated (key deleted) when activate_config() is called.
_config_cache: dict[AgencyType, RubricConfig] = {}


def invalidate_cache(agency_type: AgencyType) -> None:
    """
    Drop the cached config for an agency.
    Called by activate_config() so the next evaluation picks up the new rules.
    """
    _config_cache.pop(agency_type, None)
    log.info("rubric.cache_invalidated", agency_type=agency_type.value)


# =============================================================================
# Public interface — evaluation
# =============================================================================

def evaluate(
    signals: dict[str, Any] | object,
    agency_type: AgencyType,
    db=None,
) -> RubricEvaluationResult:
    """
    Evaluate a set of signals against the active rubric for an agency.

    Parameters:
        signals     : dict of signal name → value (or an ExtractedSignals
                      Pydantic object — both are normalised to a flat dict
                      internally). Unknown keys are silently ignored.
        agency_type : which agency's rubric to run (BFP / PNP / MDRRMO).
        db          : optional Supabase client. If None, a new client is
                      obtained from get_supabase(). Pass a mock in tests.

    Returns:
        RubricEvaluationResult with:
          - severity         : max severity across all triggered rules
          - recommended_agencies : deduplicated list, priority-ordered
          - triggered_rules  : list of rule_ids that fired
          - no_rules_triggered : True if no rules matched (default to 'low')
          - rubric_config_version : version string of the config used
          - config_source    : 'db' or 'seed_fallback'

    Signal source swapping — how to use with different sources:
        # Mocked payload (current, Phase 4 blocked):
        result = evaluate({"incident_type": "fire", "casualty_mentioned": True}, AgencyType.BFP)

        # NLP output (Phase 4, future drop-in):
        signals_obj = nlp_service.extract(report_text)
        result = evaluate(signals_obj, AgencyType.BFP)

        # Dispatcher-tagged signals (Phase 6A fallback):
        result = evaluate(dispatcher_form_data, AgencyType.PNP)
    """
    if db is None:
        db = get_supabase()

    # Normalise signals to a flat dict
    flat_signals = _normalise_signals(signals)

    # Load config (cache → DB → seed)
    config, source = _load_config(agency_type, db)

    # Evaluate rules
    triggered: list[RubricRule] = []
    for rule in config.active_rules():
        if _condition_matches(rule.conditions, flat_signals):
            triggered.append(rule)

    # Aggregate: max-of-triggered-rules
    if not triggered:
        result = RubricEvaluationResult(
            severity=SeverityLevel.low,
            recommended_agencies=[],
            triggered_rules=[],
            no_rules_triggered=True,
            rubric_config_version=config.version,
            agency_type=agency_type,
            config_source=source,
        )
        log.info(
            "rubric.no_rules_triggered",
            agency_type=agency_type.value,
            config_version=config.version,
            config_source=source,
            note="Defaulting to severity=low. Flag for dispatcher manual review.",
        )
        return result

    # Find the maximum severity level across all triggered rules
    max_rule = max(triggered, key=lambda r: SEVERITY_RANK[r.severity_contribution])
    final_severity = max_rule.severity_contribution

    # Collect recommended agencies — preserve insertion order, deduplicate
    seen: set[AgencyType] = set()
    recommended: list[AgencyType] = []
    # Sort triggered rules by severity descending so highest-priority agency comes first
    for rule in sorted(triggered, key=lambda r: SEVERITY_RANK[r.severity_contribution], reverse=True):
        if rule.recommended_agency and rule.recommended_agency not in seen:
            recommended.append(rule.recommended_agency)
            seen.add(rule.recommended_agency)

    result = RubricEvaluationResult(
        severity=final_severity,
        recommended_agencies=recommended,
        triggered_rules=[r.rule_id for r in triggered],
        no_rules_triggered=False,
        rubric_config_version=config.version,
        agency_type=agency_type,
        config_source=source,
    )

    log.info(
        "rubric.evaluated",
        agency_type=agency_type.value,
        severity=final_severity.value,
        triggered_rule_count=len(triggered),
        triggered_rules=[r.rule_id for r in triggered],
        recommended_agencies=[a.value for a in recommended],
        config_version=config.version,
        config_source=source,
    )

    return result


# =============================================================================
# Public interface — config management (called by rubric router)
# =============================================================================

def get_active_config(agency_type: AgencyType, db=None) -> RubricConfig | None:
    """
    Return the currently active config for an agency from the DB.
    Returns None if no active config exists (seed fallback not triggered here —
    that only happens during evaluate()).
    """
    if db is None:
        db = get_supabase()
    return _fetch_active_config_from_db(agency_type, db)


def list_configs(agency_type: AgencyType, db=None) -> list[RubricConfig]:
    """Return all config versions for an agency, newest first."""
    if db is None:
        db = get_supabase()
    result = (
        db.table("rubric_configs")
        .select("*")
        .eq("agency_type", agency_type.value)
        .order("created_at", desc=True)
        .execute()
    )
    return [_row_to_config(row) for row in (result.data or [])]


def get_config_by_id(config_id: str, db=None) -> RubricConfig | None:
    """Return a single config version by its UUID."""
    if db is None:
        db = get_supabase()
    result = (
        db.table("rubric_configs")
        .select("*")
        .eq("id", config_id)
        .single()
        .execute()
    )
    return _row_to_config(result.data) if result.data else None


def upload_config(
    agency_type: AgencyType,
    request: RubricConfigUploadRequest,
    actor_id: str,
    db=None,
) -> RubricConfig:
    """
    Store a new config version. Does NOT activate it automatically —
    activation is a separate explicit action to avoid accidents.

    Writes a config_created audit record before returning.
    Raises if the audit write fails (config is still stored — the caller
    may retry the audit write, but the config row is committed).
    """
    if db is None:
        db = get_supabase()

    rules_payload = [r.model_dump(mode="json") for r in request.rules]

    insert_result = (
        db.table("rubric_configs")
        .insert({
            "agency_type": agency_type.value,
            "version":     request.version,
            "rules":       rules_payload,
            "is_active":   False,
            "created_by":  actor_id,
        })
        .execute()
    )

    if not insert_result.data:
        raise RuntimeError("Failed to store rubric config.")

    row = insert_result.data[0]
    config = _row_to_config(row)

    write_config_audit_event(
        event_type=AuditEventType.config_created,
        agency_type=agency_type,
        actor_id=actor_id,
        db=db,
        rubric_config_id=str(config.id),
        config_version=config.version,
        previous_value=None,
        new_value={"version": config.version, "rule_count": len(request.rules)},
        notes=f"New config version {config.version} uploaded for {agency_type.value}.",
    )

    log.info(
        "rubric.config_uploaded",
        agency_type=agency_type.value,
        version=config.version,
        config_id=str(config.id),
        actor_id=actor_id,
    )
    return config


def activate_config(
    agency_type: AgencyType,
    config_id: str,
    actor_id: str,
    reason: str | None,
    db=None,
) -> RubricConfig:
    """
    Atomically activate a config version:
      1. Deactivate the currently active version (if any) — writes deactivated audit row
      2. Activate the new version — writes activated audit row
      3. Invalidate the in-process cache so the next evaluate() picks up the new rules

    Both audit writes must succeed before activation proceeds.
    If either fails, raises RuntimeError and the transaction is NOT rolled back
    at the DB level (Supabase client doesn't support multi-statement transactions
    in the same call). The partial state is: old deactivated, new not yet activated.
    In practice this would require manual intervention — flag it if it ever occurs.

    TODO: wrap in a DB-level transaction once Supabase adds transaction support
    to the client library, or use a Postgres function via .rpc().
    """
    if db is None:
        db = get_supabase()

    # 1. Fetch the config to activate — confirm it belongs to this agency
    target = get_config_by_id(config_id, db)
    if not target:
        raise ValueError(f"Config {config_id} not found.")
    if target.agency_type != agency_type:
        raise ValueError(
            f"Config {config_id} belongs to {target.agency_type.value}, "
            f"not {agency_type.value}. Cannot activate across agencies."
        )
    if target.is_active:
        raise ValueError(f"Config {config_id} is already active.")

    # 2. Deactivate current active (if any)
    current = _fetch_active_config_from_db(agency_type, db)
    if current:
        db.table("rubric_configs") \
          .update({"is_active": False}) \
          .eq("id", str(current.id)) \
          .execute()

        write_config_audit_event(
            event_type=AuditEventType.config_deactivated,
            agency_type=agency_type,
            actor_id=actor_id,
            db=db,
            rubric_config_id=str(current.id),
            config_version=current.version,
            previous_value={"is_active": True},
            new_value={"is_active": False},
            notes=f"Deactivated in favour of version {target.version}.",
        )

    # 3. Activate target
    db.table("rubric_configs") \
      .update({"is_active": True, "activated_by": actor_id}) \
      .eq("id", config_id) \
      .execute()

    write_config_audit_event(
        event_type=AuditEventType.config_activated,
        agency_type=agency_type,
        actor_id=actor_id,
        db=db,
        rubric_config_id=config_id,
        config_version=target.version,
        previous_value={"is_active": False},
        new_value={"is_active": True},
        notes=reason or f"Config version {target.version} activated for {agency_type.value}.",
    )

    # 4. Invalidate cache — next evaluate() will fetch fresh from DB
    invalidate_cache(agency_type)

    # 5. Return updated config
    updated = get_config_by_id(config_id, db)
    log.info(
        "rubric.config_activated",
        agency_type=agency_type.value,
        version=target.version,
        config_id=config_id,
        actor_id=actor_id,
    )
    return updated


def get_audit_log(
    agency_type: AgencyType,
    limit: int = 50,
    db=None,
) -> list[dict]:
    """Return recent audit log entries for an agency, newest first."""
    if db is None:
        db = get_supabase()
    result = (
        db.table("rubric_audit_log")
        .select("*")
        .eq("agency_type", agency_type.value)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


# =============================================================================
# Internal helpers
# =============================================================================

def _load_config(
    agency_type: AgencyType,
    db,
) -> tuple[RubricConfig, str]:
    """
    Load the active config for an agency.

    Priority order (confirmed design — Section 0 / Phase 5 design proposal):
      1. In-process cache (avoids DB round-trip on hot path)
      2. DB active config (authoritative)
      3. JSON seed file (fallback — always writes a rubric_audit_log row)

    Returns (RubricConfig, source_label) where source_label is
    'db' or 'seed_fallback'.
    """
    # 1. Cache hit
    if agency_type in _config_cache:
        return _config_cache[agency_type], "db"

    # 2. DB lookup
    db_config = _fetch_active_config_from_db(agency_type, db)
    if db_config:
        _config_cache[agency_type] = db_config
        return db_config, "db"

    # 3. Seed fallback — always write a persistent audit record
    reason = (
        f"No active rubric config found in DB for {agency_type.value}. "
        "Falling back to bundled JSON seed file. "
        "Run the seed-loader or activate a config via POST /rubric/{agency_type}/configs/{id}/activate."
    )
    seed_config = load_seed_config(agency_type)
    write_fallback_audit_event(
        agency_type=agency_type,
        reason=reason,
        seed_version=seed_config.version,
        db=db,
    )
    # Do NOT cache the seed — we want to retry DB on every call until an admin
    # activates a proper config, so the fallback state is visible in the audit log.
    return seed_config, "seed_fallback"


def _fetch_active_config_from_db(
    agency_type: AgencyType,
    db,
) -> RubricConfig | None:
    """
    Query rubric_configs for the single active row for this agency.
    Returns None if no active config exists — does NOT fall back to seed.
    """
    try:
        result = (
            db.table("rubric_configs")
            .select("*")
            .eq("agency_type", agency_type.value)
            .eq("is_active", True)
            .limit(1)
            .execute()
        )
        if result.data:
            return _row_to_config(result.data[0])
    except Exception as exc:
        log.error(
            "rubric.db_fetch_failed",
            agency_type=agency_type.value,
            error=str(exc),
        )
    return None


def _row_to_config(row: dict) -> RubricConfig:
    """Convert a rubric_configs DB row to a RubricConfig model."""
    import json as _json

    rules_raw = row.get("rules", [])
    # Supabase returns JSONB columns as Python objects already, but handle
    # the case where it's a string (shouldn't happen with supabase-py, but
    # defensive coding for any future client changes).
    if isinstance(rules_raw, str):
        rules_raw = _json.loads(rules_raw)

    return RubricConfig(
        id=row.get("id"),
        agency_type=row["agency_type"],
        version=row["version"],
        rules=rules_raw,
        is_active=row.get("is_active", False),
        created_by=row.get("created_by"),
        activated_by=row.get("activated_by"),
        activated_at=row.get("activated_at"),
        created_at=row.get("created_at"),
    )


# =============================================================================
# Condition evaluation — the core matching logic
# =============================================================================

def _condition_matches(condition: RubricCondition, signals: dict[str, Any]) -> bool:
    """
    Test whether a RubricCondition matches a flat signal dict.

    Returns True only if ALL specified conditions are satisfied.
    Unspecified conditions (None) are skipped — they do not constrain the match.
    If a required signal field is missing/None in the payload, conditions
    testing that field return False (conservative — unknown ≠ present).

    This function is the only place where signal values are compared to
    rule conditions. It uses no eval(), no exec(), no dynamic dispatch —
    every operator is an explicit Python comparison. This is deliberate:
    explainability over cleverness.
    """

    # ── Signal 1: incident_type (exact match) ─────────────────────────────
    if condition.incident_type is not None:
        if signals.get("incident_type") != condition.incident_type:
            return False

    # ── Signal 1: incident_type (any-of list) ─────────────────────────────
    if condition.incident_type_in is not None:
        val = signals.get("incident_type")
        if val is None or val not in condition.incident_type_in:
            return False

    # ── Signal 2: fire_type (exact match) ─────────────────────────────────
    if condition.fire_type is not None:
        if signals.get("fire_type") != condition.fire_type:
            return False

    # ── Signal 2: fire_type (any-of list) ─────────────────────────────────
    if condition.fire_type_in is not None:
        val = signals.get("fire_type")
        if val is None or val not in condition.fire_type_in:
            return False

    # ── Signal 3: casualty_mentioned (boolean) ────────────────────────────
    if condition.casualty_mentioned is not None:
        val = signals.get("casualty_mentioned", False)
        if bool(val) != condition.casualty_mentioned:
            return False

    # ── Signal 4: injured_count >= N ──────────────────────────────────────
    if condition.injured_count_gte is not None:
        val = signals.get("injured_count")
        if val is None or int(val) < condition.injured_count_gte:
            return False

    # ── Signal 4: injured_count <= N ──────────────────────────────────────
    if condition.injured_count_lte is not None:
        val = signals.get("injured_count")
        if val is None or int(val) > condition.injured_count_lte:
            return False

    # ── Signal 5: dead_count >= N ─────────────────────────────────────────
    if condition.dead_count_gte is not None:
        val = signals.get("dead_count")
        if val is None or int(val) < condition.dead_count_gte:
            return False

    # ── Signal 6: weapon_mentioned (boolean) ──────────────────────────────
    if condition.weapon_mentioned is not None:
        val = signals.get("weapon_mentioned", False)
        if bool(val) != condition.weapon_mentioned:
            return False

    # ── Signal 7: weapon_type (any-of list) ───────────────────────────────
    if condition.weapon_type_in is not None:
        val = signals.get("weapon_type")
        if val is None or val not in condition.weapon_type_in:
            return False

    # ── Signal 10: structure_type (any-of list) ───────────────────────────
    if condition.structure_type_in is not None:
        val = signals.get("structure_type")
        if val is None or val not in condition.structure_type_in:
            return False

    # ── Signal 11: children_involved (boolean) ────────────────────────────
    if condition.children_involved is not None:
        val = signals.get("children_involved", False)
        if bool(val) != condition.children_involved:
            return False

    # ── Signal 12: urgency_level (any-of list) ────────────────────────────
    if condition.urgency_level_in is not None:
        val = signals.get("urgency_level")
        if val is None or val not in condition.urgency_level_in:
            return False

    # ── Signal 14: multi_agency_needed (boolean) ──────────────────────────
    if condition.multi_agency_needed is not None:
        val = signals.get("multi_agency_needed", False)
        if bool(val) != condition.multi_agency_needed:
            return False

    # ── Signal 8: why_category (any-of list) ──────────────────────────────
    if condition.why_category_in is not None:
        val = signals.get("why_category")
        if val is None or val not in condition.why_category_in:
            return False

    # ── Signal 9: how_category (any-of list) ──────────────────────────────
    if condition.how_category_in is not None:
        val = signals.get("how_category")
        if val is None or val not in condition.how_category_in:
            return False

    # ── incident_category (5W1H wizard, any-of list) ──────────────────────
    if condition.incident_category_in is not None:
        val = signals.get("incident_category")
        if val is None or val not in condition.incident_category_in:
            return False

    # All specified conditions passed
    return True


def _normalise_signals(signals: dict[str, Any] | object) -> dict[str, Any]:
    """
    Accept signals as a plain dict or as any object with a model_dump() method
    (e.g., ExtractedSignals Pydantic model).

    Returns a flat dict of signal_name → value.
    Unknown keys are retained — _condition_matches() ignores them.
    """
    if isinstance(signals, dict):
        return signals
    if hasattr(signals, "model_dump"):
        return signals.model_dump()
    # Fallback: try __dict__ for any other object type
    return vars(signals)
