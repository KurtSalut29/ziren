"""
Concurrent-user load test for the read paths a busy shift leans on.

Evaluator findings #13-#15 / #38 (2026-10-05). Simulates N dashboard consoles
polling the live queue, opening reports, paging Incident Records and loading
the map, all at once, for a fixed time, and reports p50 / p95 / p99 and errors
per endpoint against the targets in docs/PERFORMANCE.md.

READ-ONLY, and it refuses the production backend unless told otherwise:
point it at a staging deployment seeded with demo data
(scripts/seed_demo_data.py), never at the database residents report into.

    set ZIREN_API=https://<staging-backend>
    set ZIREN_TOKEN=<an agency admin access token from staging>
    .venv\\Scripts\\python scripts\\load_test.py --users 30 --seconds 120
"""

from __future__ import annotations

import argparse
import asyncio
import os
import random
import statistics
import sys
import time
from collections import defaultdict

import httpx

PRODUCTION_HOSTS = ("ziren-production.up.railway.app",)

#: (name, path, weight, p95 target in ms) — see docs/PERFORMANCE.md.
ENDPOINTS = [
    ("live queue",       "/dispatch/queue",                                  6, 800),
    ("incident records", "/dispatch/history?days=30&limit=100&offset={off}", 2, 1500),
    ("map",              "/map/data",                                        1, 1500),
    ("distress",         "/dispatch/distress",                               3, 800),
    ("notifications",    "/notifications/?unread_only=true&limit=50",        3, 800),
]


async def user(client: httpx.AsyncClient, stop_at: float, samples: dict, errors: dict) -> None:
    names = [e for e in ENDPOINTS for _ in range(e[2])]
    while time.monotonic() < stop_at:
        name, path, _, _ = random.choice(names)
        url = path.format(off=random.choice([0, 100, 500, 2000]))
        t = time.perf_counter()
        try:
            r = await client.get(url)
            ms = (time.perf_counter() - t) * 1000
            if r.status_code >= 400:
                errors[name][r.status_code] += 1
            else:
                samples[name].append(ms)
        except httpx.HTTPError as e:
            errors[name][type(e).__name__] += 1
        # A console polls every few seconds; a person clicks every few more.
        await asyncio.sleep(random.uniform(1.0, 4.0))


def pct(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    values = sorted(values)
    k = max(0, min(len(values) - 1, round(p / 100 * (len(values) - 1))))
    return values[k]


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--users", type=int, default=30)
    ap.add_argument("--seconds", type=int, default=120)
    ap.add_argument("--allow-production", action="store_true",
                    help="Only with the offices' agreement and outside an emergency.")
    args = ap.parse_args()

    base = os.environ.get("ZIREN_API", "").rstrip("/")
    token = os.environ.get("ZIREN_TOKEN", "")
    if not base or not token:
        print("Set ZIREN_API and ZIREN_TOKEN (see the docstring).")
        return 2
    if any(h in base for h in PRODUCTION_HOSTS) and not args.allow_production:
        print("Refusing to load-test the production backend. Use a staging deployment.")
        return 2

    samples: dict[str, list[float]] = defaultdict(list)
    errors: dict[str, dict] = defaultdict(lambda: defaultdict(int))
    stop_at = time.monotonic() + args.seconds
    limits = httpx.Limits(max_connections=args.users * 2)
    async with httpx.AsyncClient(base_url=base, headers={"Authorization": f"Bearer {token}"},
                                 timeout=30, limits=limits) as client:
        await asyncio.gather(*(user(client, stop_at, samples, errors) for _ in range(args.users)))

    print(f"\n{args.users} users for {args.seconds}s against {base}\n")
    print(f"{'endpoint':<18}{'n':>6}{'p50':>8}{'p95':>8}{'p99':>8}{'target p95':>12}  result")
    failed = 0
    for name, _, _, target in ENDPOINTS:
        v = samples[name]
        p95 = pct(v, 95)
        ok = v and p95 <= target and not errors[name]
        failed += 0 if ok else 1
        print(f"{name:<18}{len(v):>6}{pct(v, 50):>8.0f}{p95:>8.0f}{pct(v, 99):>8.0f}{target:>12}  "
              f"{'PASS' if ok else 'FAIL'}{'  errors ' + dict(errors[name]).__repr__() if errors[name] else ''}")
    if samples:
        allv = [x for v in samples.values() for x in v]
        print(f"\noverall: {len(allv)} requests, median {statistics.median(allv):.0f} ms")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
