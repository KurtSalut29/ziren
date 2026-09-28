"""
ai_monitoring_service — AI & Classification Monitoring (spec Section 12).

Read-only. A Provincial Admin can see how the triage model is doing for
their own agency_type's incidents; nothing here lets the dashboard touch
the model itself — that stays a deployment concern, not a form.

All the numbers below come from data the triage pipeline already writes to
every incident's `signals` JSONB column (see TriageSignals in
app/models/incident.py) — this module adds no new instrumentation, it reads
what's already there.
"""

from collections import Counter
from typing import Any

from app.db.supabase_client import get_supabase
from app.services import triage_service

_CONFIDENCE_BUCKETS = [
    ("0.0-0.5", 0.0, 0.5),
    ("0.5-0.7", 0.5, 0.7),
    ("0.7-0.9", 0.7, 0.9),
    ("0.9-1.0", 0.9, 1.01),  # 1.01 so a perfect 1.0 confidence lands in the top bucket
]


def _bucket_for(confidence: float) -> str:
    for label, low, high in _CONFIDENCE_BUCKETS:
        if low <= confidence < high:
            return label
    return _CONFIDENCE_BUCKETS[-1][0]


def get_stats(sample_size: int = 20, agency_type: str | None = None) -> dict[str, Any]:
    """
    agency_type, when given, scopes every figure to incidents assigned to an
    agency of that type — a Provincial Admin's own agency_type, resolved by
    the router via the same two-step agencies lookup
    dispatch_service._agency_ids_for_type uses. None (the router's
    agency_admin/legacy path) reads every incident, unscoped.
    """
    db = get_supabase()
    query = (
        db.table("incidents")
        .select("id, created_at, signals, assigned_agency_id")
        .not_.is_("signals", "null")
        .order("created_at", desc=True)
    )
    if agency_type:
        agency_ids = [
            row["id"] for row in (
                db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
            )
        ]
        if not agency_ids:
            agency_ids = ["00000000-0000-0000-0000-000000000000"]  # match nothing
        query = query.in_("assigned_agency_id", agency_ids)
    rows = query.execute().data or []

    confidence_distribution: Counter[str] = Counter({label: 0 for label, _, _ in _CONFIDENCE_BUCKETS})
    verification_breakdown: Counter[str] = Counter()
    sample_corrections: list[dict[str, Any]] = []
    total_classifications = 0

    for row in rows:
        signals = row.get("signals")
        if not isinstance(signals, dict) or not signals.get("engine"):
            # A row can have a `signals` shell without the model ever having
            # run (e.g. triage was unavailable at filing time) — that's not
            # an AI-assisted classification and must not be counted as one.
            continue

        total_classifications += 1

        confidence = signals.get("model_confidence")
        if isinstance(confidence, (int, float)):
            confidence_distribution[_bucket_for(float(confidence))] += 1

        verification_status = signals.get("verification_status")
        if verification_status:
            verification_breakdown[verification_status] += 1

        if len(sample_corrections) < sample_size:
            sample_corrections.append({
                "incident_id": row.get("id"),
                "created_at": row.get("created_at"),
                "predicted": signals.get("model_predicted_category"),
                "selected": signals.get("user_selected"),
                "result": verification_status,
            })

    model_status = triage_service.status()

    return {
        "model_version": model_status.get("version") or "unknown",
        "model_status": "active" if model_status.get("model_loaded") else "unavailable",
        "total_classifications": total_classifications,
        "confidence_distribution": dict(confidence_distribution),
        "verification_breakdown": dict(verification_breakdown),
        "sample_corrections": sample_corrections,
    }
