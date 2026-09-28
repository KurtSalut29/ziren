"""
Apply Ziren's Supabase migrations.

Why this exists
---------------
The service key talks to PostgREST, which cannot execute DDL. Running schema
changes therefore needs a real Postgres connection, which is what DATABASE_URL
in .env provides.

It is deliberately NOT required. If DATABASE_URL is absent or unreachable this
script degrades to telling you exactly which files are pending and where to
paste them, and exits 0. Migrations 001-019 were applied that way and the
project has to keep working for whoever does not have the password.

What it will not do
-------------------
There is a well-known trick for running DDL through PostgREST: create an
`exec_sql(text)` SECURITY DEFINER function and call it as an RPC. That is an
arbitrary-SQL-execution endpoint sitting permanently in the database. In a
project whose migrations 012 and 013 exist specifically to close privilege
escalation paths, installing one to save a manual step would be self-defeating.
So: a real connection, or the SQL Editor. No third option.

Baseline
--------
The versions in BASELINE_APPLIED are already live and are recorded as applied
without being run. Replaying them is not always safe -- 019 runs an UPDATE over
incidents, and 012/014/020 drop and recreate RLS policies, so a replay in the
wrong order silently reverts a policy to an older definition.

That set is a measurement, not an assumption: run scripts/probe_schema.py to
check what the database actually has before trusting it.

Usage
-----
    python scripts/migrate.py             # apply everything pending
    python scripts/migrate.py --status    # show state, change nothing
    python scripts/migrate.py --dry-run   # print what would run
"""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import re
import sys
import urllib.parse

# Versions confirmed already applied, recorded without being executed.
#
# This was a version cutoff ("everything <= 019") until scripts/probe_schema.py
# proved the assumption false: 012 had been applied from an earlier revision of
# its own file and was missing two columns, and 015 had never been run at all.
# A cutoff encodes a guess about history; this set encodes a measurement. If
# you add to it, probe first.
#
# 012, 015 and 020 are deliberately absent -- they are pending.
BASELINE_APPLIED = {
    "001", "001b", "001c", "001d",
    "002", "002b", "002c",
    "003", "003b",
    "004", "005", "006", "007", "008", "009", "010", "011",
    "013", "014", "016", "017", "018", "019",
}

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = ROOT / "supabase" / "migrations"
ENV_FILE = ROOT / ".env"

BOOTSTRAP = """
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version     TEXT PRIMARY KEY,
    filename    TEXT NOT NULL,
    checksum    TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    applied_by  TEXT NOT NULL DEFAULT CURRENT_USER,
    -- TRUE for the 001-019 baseline: recorded, but never executed by this
    -- script. Keeps "we think it ran" honestly distinct from "we ran it".
    out_of_band BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE public.schema_migrations IS
    'Applied migration ledger for scripts/migrate.py. Rows with '
    'out_of_band = TRUE were pasted into the Supabase SQL Editor by hand '
    'before the runner existed and were never executed by it.';
"""


def version_of(path: pathlib.Path) -> str:
    """Leading numeric-ish version, e.g. 001b_foo.sql -> '001b'."""
    m = re.match(r"^(\d+[a-z]?)_", path.name)
    return m.group(1) if m else path.stem


def checksum(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def discover() -> list[pathlib.Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"), key=lambda p: p.name)


def load_database_url() -> str | None:
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    try:
        from dotenv import dotenv_values
    except ImportError:
        return None
    if not ENV_FILE.exists():
        return None
    url = dotenv_values(ENV_FILE).get("DATABASE_URL")
    if not url or "[YOUR-PASSWORD]" in url:
        return None
    return url


def manual_instructions(pending: list[pathlib.Path], reason: str) -> None:
    print(f"\nNo usable database connection ({reason}).")
    print("Falling back to the Supabase SQL Editor path.\n")
    if not pending:
        print("Nothing pending -- every migration file is already recorded")
        print("as applied. No action needed.")
        return
    print("Apply these by hand, in this order:\n")
    for i, p in enumerate(pending, 1):
        print(f"  {i}. {p.name}")
    print("\n  Supabase dashboard -> SQL Editor -> New query")
    print("  Paste the whole file, press Run, and check the result grids at")
    print("  the bottom -- every migration here ends with verification")
    print("  SELECTs that prove the change landed.\n")
    print("  Each file is idempotent, so re-running one is safe.\n")
    print(f"  Files live in: {MIGRATIONS_DIR}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Apply Ziren Supabase migrations.")
    ap.add_argument("--status", action="store_true", help="report state, change nothing")
    ap.add_argument("--dry-run", action="store_true", help="show what would run")
    args = ap.parse_args()

    files = discover()
    if not files:
        print(f"No .sql files found in {MIGRATIONS_DIR}")
        return 1

    print(f"Found {len(files)} migration files.")

    url = load_database_url()
    if not url:
        above = [f for f in files if version_of(f) not in BASELINE_APPLIED]
        manual_instructions(above, "DATABASE_URL not set or still a placeholder")
        return 0

    try:
        import psycopg2
    except ImportError:
        manual_instructions(
            [f for f in files if version_of(f) not in BASELINE_APPLIED],
            "psycopg2 not installed",
        )
        return 0

    host = urllib.parse.urlparse(url).hostname
    try:
        conn = psycopg2.connect(url, connect_timeout=15)
    except Exception as e:
        first = str(e).strip().splitlines()[0]
        manual_instructions(
            [f for f in files if version_of(f) not in BASELINE_APPLIED],
            f"could not connect to {host}: {first}",
        )
        return 0

    conn.autocommit = False
    print(f"Connected to {host}.\n")

    try:
        with conn.cursor() as cur:
            cur.execute(BOOTSTRAP)
        conn.commit()

        with conn.cursor() as cur:
            cur.execute("SELECT version, checksum FROM public.schema_migrations")
            applied = dict(cur.fetchall())

        # Record the baseline once, without executing any of it.
        baseline = [
            f for f in files
            if version_of(f) in BASELINE_APPLIED and version_of(f) not in applied
        ]
        if baseline:
            with conn.cursor() as cur:
                for f in baseline:
                    cur.execute(
                        "INSERT INTO public.schema_migrations "
                        "(version, filename, checksum, out_of_band) "
                        "VALUES (%s, %s, %s, TRUE) ON CONFLICT (version) DO NOTHING",
                        (version_of(f), f.name, checksum(f)),
                    )
            conn.commit()
            print(f"Recorded {len(baseline)} pre-existing migrations as "
                  f"baseline (confirmed applied, not executed).")
            with conn.cursor() as cur:
                cur.execute("SELECT version, checksum FROM public.schema_migrations")
                applied = dict(cur.fetchall())

        # A file edited after being applied is worth knowing about.
        for f in files:
            v = version_of(f)
            if v in applied and applied[v] != checksum(f):
                print(f"  WARNING  {f.name} changed since it was applied "
                      f"(recorded {applied[v]}, now {checksum(f)})")

        pending = [f for f in files if version_of(f) not in applied]

        if args.status:
            print(f"\nApplied : {len(applied)}")
            print(f"Pending : {len(pending)}")
            for f in pending:
                print(f"    {f.name}")
            return 0

        if not pending:
            print("\nUp to date -- nothing to apply.")
            return 0

        print(f"\n{len(pending)} pending:")
        for f in pending:
            print(f"    {f.name}")

        if args.dry_run:
            print("\n--dry-run: nothing was executed.")
            return 0

        print()
        for f in pending:
            v = version_of(f)
            sql = f.read_text(encoding="utf-8")
            print(f"  applying {f.name} ... ", end="", flush=True)
            try:
                # One transaction per migration: a failure rolls the whole file
                # back rather than leaving the schema half-changed.
                #
                # No parameters passed to execute(), so psycopg2 does no
                # %-interpolation -- important, because these files contain
                # LIKE '%...%' patterns and regex escapes.
                with conn.cursor() as cur:
                    cur.execute(sql)
                    cur.execute(
                        "INSERT INTO public.schema_migrations "
                        "(version, filename, checksum) VALUES (%s, %s, %s)",
                        (v, f.name, checksum(f)),
                    )
                conn.commit()
                print("OK")
            except Exception as e:
                conn.rollback()
                print("FAILED")
                print(f"\n  {type(e).__name__}: {str(e).strip()}")
                print(f"\n  Rolled back. {f.name} was NOT applied and is not "
                      f"recorded.\n  Later migrations were skipped.")
                return 1

        print("\nDone.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
