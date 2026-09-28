"""
Move every DEMO incident/responder whose location fell outside Biliran's real
coastline back onto the island — IN PLACE, without touching row count.

    python scripts/fix_demo_incident_coords.py --dry-run   # report only
    python scripts/fix_demo_incident_coords.py              # apply the fix

WHY THIS EXISTS

seed_demo_data.py used to jitter a demo incident's location up to ~0.02 deg
(about 3km at the corners) from its station, on a plain circle that never
checked whether the result was still on Biliran — for any station near the
coast (most of them; this is a small island), that circle's edge crosses into
open water, and a report drawn from it landed there as often as on land.
seed_demo_data.py itself is fixed (see its own _jitter()), but that only
protects incidents seeded AFTER the fix — it does nothing for the ones already
sitting in the database with a bad location, and re-running the seeder with
--clean --then-seed would also change the total count and every other random
detail of the dataset, which is a bigger change than "put the existing reports
on land".

This script is the narrow fix: for each demo-tagged row whose current
location is NOT on Biliran, draw a new one from the SAME on-land-guaranteed
_jitter() the seeder now uses, anchored on that row's own station (incidents)
or a station of its own agency (responders) — and update only the `location`
column of only that row. Nothing is inserted or deleted; a row already on
land is never touched.

Idempotent: a second run finds nothing left to fix and changes nothing.
"""

from __future__ import annotations

import argparse
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.core.geo import parse_point  # noqa: E402
from app.db.supabase_client import get_supabase  # noqa: E402
# Reuses the seeder's own account-identification helper (reporter_id IN the
# @seed.ziren.test accounts) rather than re-deriving it — this is the exact
# set `--clean` deletes, so "which incidents are demo data" can never drift
# between the two scripts.
from seed_demo_data import _BILIRAN_LAND, _jitter, seed_user_ids  # noqa: E402

from shapely.geometry import Point  # noqa: E402


def _on_land(lat: float | None, lng: float | None) -> bool:
    if lat is None or lng is None:
        return False
    return _BILIRAN_LAND.contains(Point(lng, lat))


def fix_incidents(db, rng: random.Random, apply: bool) -> int:
    reporter_ids = seed_user_ids(db)
    if not reporter_ids:
        print("  no demo accounts found — nothing to do")
        return 0
    rows: list[dict] = []
    for i in range(0, len(reporter_ids), 100):
        chunk = reporter_ids[i:i + 100]
        rows += (
            db.table("incidents")
            .select("id, location, station_id, stations(location)")
            .in_("reporter_id", chunk)
            .execute()
            .data
            or []
        )
    fixed = 0
    for row in rows:
        lat, lng = parse_point(row.get("location"))
        if _on_land(lat, lng):
            continue
        station = row.get("stations") or {}
        s_lat, s_lng = parse_point(station.get("location"))
        if s_lat is None:
            print(f"  incident {row['id']}: in water, but its station has no location — skipped")
            continue
        new_lat, new_lng = _jitter(s_lat, s_lng, rng)
        fixed += 1
        print(f"  incident {row['id']}: ({lat:.5f},{lng:.5f}) -> ({new_lat:.5f},{new_lng:.5f})")
        if apply:
            db.table("incidents").update({
                "location": f"SRID=4326;POINT({new_lng:.6f} {new_lat:.6f})",
            }).eq("id", row["id"]).execute()
    return fixed


def fix_responders(db, rng: random.Random, apply: bool) -> int:
    rows = (
        db.table("users")
        .select("id, location, agency_id")
        .eq("role", "responder")
        .like("email", "%@seed.ziren.test")
        .execute()
        .data
        or []
    )
    # One anchor station per agency, fetched once rather than per row.
    station_by_agency: dict[str, tuple[float, float]] = {}
    fixed = 0
    for row in rows:
        lat, lng = parse_point(row.get("location"))
        if _on_land(lat, lng):
            continue
        agency_id = row.get("agency_id")
        if not agency_id:
            continue
        if agency_id not in station_by_agency:
            st = (
                db.table("stations")
                .select("location")
                .eq("agency_id", agency_id)
                .eq("is_active", True)
                .limit(1)
                .execute()
                .data
            )
            if not st:
                continue
            s_lat, s_lng = parse_point(st[0].get("location"))
            if s_lat is None:
                continue
            station_by_agency[agency_id] = (s_lat, s_lng)
        s_lat, s_lng = station_by_agency[agency_id]
        new_lat, new_lng = _jitter(s_lat, s_lng, rng, radius_km=0.3)
        fixed += 1
        print(f"  responder {row['id']}: ({lat:.5f},{lng:.5f}) -> ({new_lat:.5f},{new_lng:.5f})")
        if apply:
            db.table("users").update({
                "location": f"SRID=4326;POINT({new_lng:.6f} {new_lat:.6f})",
            }).eq("id", row["id"]).execute()
    return fixed


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="Report what would change; write nothing.")
    ap.add_argument("--seed", type=int, default=1, help="RNG seed, for a repeatable dry run.")
    args = ap.parse_args()

    db = get_supabase()
    rng = random.Random(args.seed)
    apply = not args.dry_run

    print("Incidents:")
    n_inc = fix_incidents(db, rng, apply)
    print("Responders:")
    n_resp = fix_responders(db, rng, apply)

    verb = "Fixed" if apply else "Would fix"
    print(f"\n{verb} {n_inc} incident(s) and {n_resp} responder(s).")
    if args.dry_run and (n_inc or n_resp):
        print("Re-run without --dry-run to apply.")


if __name__ == "__main__":
    main()
