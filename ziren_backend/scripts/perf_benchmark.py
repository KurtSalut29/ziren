"""
App-side performance benchmark at realistic and stressed data volumes.

Evaluator findings #14, #15 and #38 (2026-10-05): performance was only seen
with a small dataset. This times the parts of the backend that do work in
Python on every row they read - the Operational Area statistics, the Incident
Records summary fallback, the map's row shaping and triage - against synthetic
incidents at 1,000 / 20,000 / 100,000 rows, and prints the times next to the
targets in docs/PERFORMANCE.md.

It touches no database and no network: the database's own share (the
queries, now indexed by migration 045) is measured with scripts/load_test.py
against a non-production deployment.

    .venv\\Scripts\\python scripts\\perf_benchmark.py
"""

from __future__ import annotations

import random
import statistics
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services import operational_area_service as oas  # noqa: E402

SEVERITIES = ["critical", "high", "medium", "low"]
STATUSES = ["resolved"] * 7 + ["cancelled", "received", "dispatched", "en_route", "arrived"]
CATEGORIES = ["fire", "medical_trauma", "vehicular", "flood_landslide_calamity", "domestic_dispute_crime", "other"]
BARANGAYS = [f"Barangay {i}" for i in range(1, 33)]
OUTCOMES = [None, "handled_on_scene", "transported", "turned_over", "false_alarm"]


def synthetic(n: int, days: int = 365, seed: int = 7) -> list[dict]:
    rnd = random.Random(seed)
    now = datetime.now(timezone.utc)
    rows = []
    for i in range(n):
        created = now - timedelta(minutes=rnd.randint(0, days * 24 * 60))
        dispatched = created + timedelta(minutes=rnd.uniform(1, 25)) if rnd.random() < 0.85 else None
        accepted = dispatched + timedelta(minutes=rnd.uniform(0.2, 4)) if dispatched else None
        resolved = (dispatched + timedelta(minutes=rnd.uniform(10, 120))) if dispatched and rnd.random() < 0.8 else None
        rows.append({
            "id": f"inc-{i}",
            "record_number": f"ZIR-2026-{i:06d}",
            "status": rnd.choice(STATUSES),
            "severity": rnd.choice(SEVERITIES),
            "incident_category": rnd.choice(CATEGORIES),
            "created_at": created.isoformat(),
            "dispatched_at": dispatched.isoformat() if dispatched else None,
            "accepted_at": accepted.isoformat() if accepted else None,
            "resolved_at": resolved.isoformat() if resolved else None,
            "location": {"type": "Point", "coordinates": [124.40 + rnd.uniform(-0.1, 0.2), 11.56 + rnd.uniform(-0.1, 0.25)]},
            "location_address": f"{rnd.choice(BARANGAYS)}, Naval, Biliran",
            "assigned_agency_id": "ag-1",
            "assigned_responder_id": f"r{rnd.randint(1, 40)}",
            "station_id": f"st-{rnd.randint(1, 3)}",
            "outcome": rnd.choice(OUTCOMES),
            "casualties_injured": rnd.choice([None, 0, 1, 2]),
            "casualties_fatal": rnd.choice([None, 0, 0, 1]),
            "casualties_transported": rnd.choice([None, 0, 1]),
            "sos_flagged": rnd.random() < 0.03,
            "submitted_via": "internet",
            "overlap_agencies": None,
            "report_text": "May sunog sa bahay malapit sa simbahan",
        })
    rows.sort(key=lambda r: r["created_at"], reverse=True)
    return rows


def timed(fn, repeat: int = 3) -> float:
    """Median wall time in milliseconds."""
    samples = []
    for _ in range(repeat):
        t = time.perf_counter()
        fn()
        samples.append((time.perf_counter() - t) * 1000)
    return statistics.median(samples)


def operational_area_figures(rows: list[dict]) -> None:
    now = datetime.now(timezone.utc)
    oas.build_trend(rows, 365, now)
    oas.build_time_patterns(rows)
    oas.build_response(rows)
    oas.build_outcomes(rows)
    oas.build_mix(rows)
    oas.build_hotspots(rows, [], BARANGAYS)
    oas.build_recent(rows, BARANGAYS, [])


def map_shaping(rows: list[dict]) -> None:
    out = []
    for r in rows[:1500]:  # the map's cap (routers/map.py MAP_INCIDENT_MAX)
        c = r["location"]["coordinates"]
        out.append({"id": r["id"], "lng": c[0], "lat": c[1], "severity": r["severity"],
                    "report_text": (r["report_text"] or "")[:120]})


def main() -> None:
    print(f"{'rows':>8}  {'operational area figures':>26}  {'map shaping (capped)':>22}")
    for n in (1_000, 20_000, 100_000):
        rows = synthetic(n)
        oa = timed(lambda: operational_area_figures(rows))
        mp = timed(lambda: map_shaping(rows))
        print(f"{n:>8}  {oa:>23.0f} ms  {mp:>19.1f} ms")

    try:
        from app.services import triage_service
        if triage_service.load():
            text = "May sunog sa bahay malapit sa simbahan, may naipit na tao"
            triage_service.triage(report_text=text)  # warm
            ms = timed(lambda: triage_service.triage(report_text=text), repeat=20)
            print(f"\ntriage, one report: {ms:.0f} ms (median of 20)")
    except Exception as e:  # pragma: no cover - environment without the model
        print(f"\ntriage not measured: {e}")


if __name__ == "__main__":
    main()
