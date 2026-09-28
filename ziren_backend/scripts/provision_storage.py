"""
Create and audit Ziren's private storage buckets.

Migration 015 documents creating "resident-ids" by hand in the dashboard. That
was a choice, not a constraint -- bucket creation is a plain REST call the
service key can already make. Doing it in code buys two things a doc cannot:

  1. It is idempotent, so it is safe to run on any machine at any time.
  2. It AUDITS what is already there. Nothing in this repo currently checks
     that resident-ids was created correctly. If someone ticked "Public" on
     that dialog, a folder of government IDs is served on public URLs and no
     test, migration or code path would notice.

Run:
    python scripts/provision_storage.py
    python scripts/provision_storage.py --audit-only
"""

from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

MB = 1024 * 1024

BUCKETS = {
    "resident-ids": {
        "public": False,
        "file_size_limit": 10 * MB,
        "allowed_mime_types": ["image/jpeg", "image/png", "image/webp", "image/heic"],
        "why": "Resident valid-ID scans and selfies. Migration 015 + 020. "
               "Read by the owner and by verifying admins only -- never by "
               "responders, who play no part in identity verification.",
    },
    "responder-ids": {
        "public": False,
        "file_size_limit": 10 * MB,
        "allowed_mime_types": ["image/jpeg", "image/png", "image/webp", "image/heic"],
        "why": "Responder agency-ID scans. Migration 020. Separate bucket "
               "from resident-ids because the reader sets differ.",
    },
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit-only", action="store_true",
                    help="report problems, create nothing")
    args = ap.parse_args()

    try:
        from app.db.supabase_client import get_supabase
    except Exception as e:
        print(f"Could not import the Supabase client: {e}")
        print("Run this from the ziren_backend directory with the venv active.")
        return 1

    client = get_supabase()

    try:
        existing = {b.id: b for b in client.storage.list_buckets()}
    except Exception as e:
        print(f"Could not list buckets: {e}")
        return 1

    print(f"{len(existing)} bucket(s) currently exist: {', '.join(sorted(existing)) or '(none)'}\n")

    problems = 0

    for name, spec in BUCKETS.items():
        if name not in existing:
            if args.audit_only:
                print(f"MISSING  {name}")
                print(f"         {spec['why']}")
                problems += 1
                continue
            print(f"creating {name} ... ", end="", flush=True)
            try:
                client.storage.create_bucket(
                    name,
                    options={
                        "public": spec["public"],
                        "file_size_limit": spec["file_size_limit"],
                        "allowed_mime_types": spec["allowed_mime_types"],
                    },
                )
                print("OK (private)")
            except Exception as e:
                print("FAILED")
                print(f"         {type(e).__name__}: {e}")
                problems += 1
            continue

        # Already there -- audit it rather than assuming it is right.
        b = existing[name]
        is_public = bool(getattr(b, "public", False))
        if is_public:
            print(f"INSECURE {name} is PUBLIC.")
            print( "         Anyone with the URL can read every file in it.")
            print( "         Fix in the dashboard: Storage -> bucket -> Settings")
            print( "         -> uncheck Public. This script will not flip it")
            print( "         automatically, because making a bucket private can")
            print( "         break live URLs and that should be a human decision.")
            problems += 1
        else:
            limit = getattr(b, "file_size_limit", None)
            note = f", limit {limit // MB}MB" if isinstance(limit, int) else ""
            print(f"OK       {name} exists and is private{note}")

    print()
    if problems:
        print(f"{problems} problem(s) found.")
        return 1

    print("All buckets present and private.")
    print("\nNote: bucket existence is only half of it. The RLS policies on")
    print("storage.objects are what scope reads and writes to each user's own")
    print("folder -- those live in migrations 015 and 020 and are applied by")
    print("scripts/migrate.py, not here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
