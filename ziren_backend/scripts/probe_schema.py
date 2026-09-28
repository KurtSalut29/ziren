"""
Work out which migrations are actually live, by probing for the columns and
tables each one is supposed to have added.

Why this exists
---------------
The migrations folder is a record of intent, not of what was applied. There is
no ledger, and at least two manual steps (the resident-ids bucket in 015, and
015's own DDL) turned out never to have been carried out -- discovered only
when migration 020 failed on a column 015 was supposed to create.

Guessing which of the others landed is not acceptable when the next step is
DDL, so this asks the database.

Method
------
PostgREST cannot query information_schema, but it reports a distinct error for
an unknown column, so `select=<column>&limit=0` is a reliable existence probe
that costs one round trip and reads no data.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# What each migration should have left behind on public.users.
USER_COLUMNS = {
    "001": ["id", "email", "full_name", "role", "agency_id", "is_verified"],
    "008": ["availability"],
    "009 (agencies)": [],
    "011": [],
    "012": [
        "barangay_id", "verification_level", "verification_method",
        "verified_at", "valid_id_type", "valid_id_number", "is_pwd",
        "pwd_id_number", "disability_types", "accessibility_notes",
        "preferred_contact_mode", "registered_by",
    ],
    "015": ["valid_id_image_path"],
    "020": [
        "terms_accepted_at", "terms_version", "privacy_version",
        "consent_locale", "first_name", "middle_name", "last_name",
        "name_suffix", "date_of_birth", "sex", "purok_sitio",
        "street_address", "selfie_image_path", "liveness_asserted_at",
        "liveness_method", "residency_proof_type", "rank_or_position",
        "unit_assignment", "date_joined", "agency_id_image_path",
    ],
}

# Columns other migrations added to other tables, and whole tables.
OTHER = [
    ("incidents", "station_id", "003"),
    ("incidents", "media_urls", "003b"),
    ("incidents", "assigned_responder_id", "008"),
    ("agencies", "notification_rules", "009"),
    ("agencies", "email", "009"),
    ("users", "location", "011"),
]

TABLES = [
    ("barangays", "012"),
    ("access_requests", "016"),
    ("rubric_configs", "007"),
    ("schema_migrations", "runner bootstrap"),
]


def probe_column(client, table: str, column: str) -> bool:
    try:
        client.table(table).select(column).limit(0).execute()
        return True
    except Exception as e:
        msg = str(e)
        if "42703" in msg or "does not exist" in msg:
            return False
        # Anything else (permissions, network) is not a "missing column"
        # answer, and pretending otherwise would be worse than saying so.
        print(f"    ? {table}.{column}: {msg[:100]}")
        return False


def probe_table(client, table: str) -> bool:
    try:
        client.table(table).select("*").limit(0).execute()
        return True
    except Exception:
        return False


def main() -> int:
    from app.db.supabase_client import get_supabase

    client = get_supabase()

    print("Probing public.users columns\n")
    verdicts = {}
    for migration, columns in USER_COLUMNS.items():
        if not columns:
            continue
        present = [c for c in columns if probe_column(client, "users", c)]
        missing = [c for c in columns if c not in present]
        state = (
            "APPLIED" if not missing
            else "MISSING" if not present
            else "PARTIAL"
        )
        verdicts[migration] = state
        print(f"  {state:8} {migration:16} {len(present)}/{len(columns)} columns")
        if missing and state == "PARTIAL":
            print(f"           missing: {', '.join(missing)}")

    print("\nProbing other tables\n")
    for table, migration in TABLES:
        ok = probe_table(client, table)
        print(f"  {'EXISTS ' if ok else 'MISSING'}  {table:20} ({migration})")

    print("\nProbing columns on other tables\n")
    for table, column, migration in OTHER:
        ok = probe_column(client, table, column)
        print(f"  {'OK     ' if ok else 'MISSING'}  {table}.{column:24} ({migration})")

    print("\n" + "=" * 60)
    unapplied = [m for m, v in verdicts.items() if v != "APPLIED"]
    if unapplied:
        print("NOT fully applied:", ", ".join(unapplied))
        print("\nApply these in order before migration 020. Each is idempotent,")
        print("so re-running one that partially landed is safe.")
    else:
        print("All probed migrations are applied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
