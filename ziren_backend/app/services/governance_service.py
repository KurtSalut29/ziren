"""
governance_service — System Governance (spec Section 11): incident
configuration (read-only, from code), account policies, notification
policies (both in system_config), and configuration history (a filtered
view over the general audit_logs table). Severity Configuration itself is
untouched — it stays exactly what rubric_service/rubric.py already do.
"""

from typing import Any

from app.db.supabase_client import get_supabase
from app.models.incident import IncidentCategory, IncidentStatus
from app.services import audit_service

_POLICY_KEYS = ("account_policies", "notification_policies")


def get_incident_configuration() -> dict[str, Any]:
    """
    Read-only. These are code-enforced enums, not editable rows — showing a
    second, editable copy here would let the two drift, which is exactly the
    failure mode a governance page for these fields exists to prevent.
    """
    return {
        "incident_categories": [c.value for c in IncidentCategory],
        "incident_statuses": [s.value for s in IncidentStatus],
        "editable": False,
        "note": "Defined in code (app/models/incident.py) — changing these requires a deployment, not a form.",
    }


def get_policy(key: str) -> dict[str, Any]:
    if key not in _POLICY_KEYS:
        raise ValueError(f"Unknown policy key: {key}")
    db = get_supabase()
    result = db.table("system_config").select("*").eq("key", key).maybe_single().execute()
    if not result or not result.data:
        return {"key": key, "value": {}, "updated_at": None}
    return result.data


def update_policy(key: str, value: dict[str, Any], actor: dict) -> dict[str, Any]:
    if key not in _POLICY_KEYS:
        raise ValueError(f"Unknown policy key: {key}")
    db = get_supabase()

    previous = get_policy(key)

    result = (
        db.table("system_config")
        .update({"value": value, "updated_by": actor.get("id")})
        .eq("key", key)
        .execute()
    )
    if not result.data:
        raise RuntimeError(f"Failed to update {key}.")

    audit_service.record(
        actor=actor,
        action="system_config.updated",
        target_type="system_config",
        target_id=key,
        target_label=key.replace("_", " "),
        previous={"value": previous.get("value")},
        new={"value": value},
    )

    return result.data[0]


def get_configuration_history(limit: int = 50, offset: int = 0) -> dict[str, Any]:
    """
    Every critical configuration change: system_config updates AND rubric
    activations, both of which already land in audit_logs (the latter via
    the extra audit_service.record() call rubric.py's activate_config
    endpoint makes — see Task 5). One query, not a union across two tables.
    """
    db = get_supabase()
    result = (
        db.table("audit_logs")
        .select("*", count="exact")
        .in_("action", ["system_config.updated", "rubric.activated"])
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )
    return {"items": result.data or [], "total": result.count or 0}
