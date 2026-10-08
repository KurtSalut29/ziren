"""
The resident's 2x2 ID photo: the picture on their Ziren ID card.

User request 2026-10-08: the card should carry a proper ID-style photo (front
facing, plain background, like a 2x2), not the verification selfie, and the
face in it has to be the resident's own - "baka mag upload lang sya ng kahit
ano".

WHERE IT LIVES

In `users.id_checks` under the key "portrait", next to the other on-device
checks of the verification evidence. Migration 023 made that column open-shaped
precisely so that a new check is not a migration, and its RLS freeze applies:
once an administrator has approved the resident, the portrait and its verdict
can no longer be rewritten by the resident.

    id_checks.portrait = {
        "path": "<user id>/portrait_<ms>.jpg",   # resident-ids bucket
        "verdict": "match" | "uncertain" | "unavailable",
        "score": 0.71,                           # against the live selfie
        "model": "buffalo_s/w600k_mbf",
        "checked_at": "...",
        "frontal": true, "plain_background": true, "face_ratio": 0.22,
    }

The phone refuses a portrait with no face, more than one face, a turned head,
a busy background, or a face that does not match the liveness-checked selfie
("no_match"), so none of those reach this column. What reaches it is still
client-computed and therefore advisory: an administrator looks at the photo
beside the selfie before approving.

THE PATH IS CHECKED, NOT TRUSTED

The resident writes this JSON themselves. The service role signs any path it
is given, so a path into somebody else's folder would show an administrator
another person's photo on this resident's card. Only a path inside the
resident's own folder - the one storage RLS lets them upload to - is used.
"""

from __future__ import annotations

from typing import Any, Mapping

KEY = "portrait"
BUCKET = "resident-ids"


def _meta(row: Mapping[str, Any] | None) -> dict | None:
    if not row:
        return None
    checks = row.get("id_checks")
    if not isinstance(checks, Mapping):
        return None
    meta = checks.get(KEY)
    return dict(meta) if isinstance(meta, Mapping) else None


def portrait_path(row: Mapping[str, Any] | None) -> str | None:
    """The storage path of this resident's 2x2 photo, if it is really theirs."""
    meta = _meta(row)
    if not meta:
        return None
    path = meta.get("path")
    owner = str((row or {}).get("id") or "")
    if not isinstance(path, str) or not owner or not path.startswith(owner + "/"):
        return None
    if ".." in path:
        return None
    return path


def portrait_summary(row: Mapping[str, Any] | None) -> dict | None:
    """What the reviewing administrator reads about the photo: everything but
    the storage path, which only ever leaves as a signed link."""
    meta = _meta(row)
    if not meta or portrait_path(row) is None:
        return None
    meta.pop("path", None)
    return meta


def without_portrait(id_checks: Any) -> dict | None:
    """id_checks with the portrait removed, for a rejected submission."""
    if not isinstance(id_checks, Mapping):
        return None
    rest = {k: v for k, v in id_checks.items() if k != KEY}
    return rest or None
