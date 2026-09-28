"""
Regression tests for GET /users/agency/responders/{responder_id}.

Background — the two defects these guard against:

Week 2 closed with a known bug: the endpoint answered HTTP 500 for a responder
id that did not exist, where it should have answered 404. Chasing that turned
up a second, quieter defect sitting on top of it.

(1) `.single()` raises on zero rows. PostgREST answers a single-object request
    with HTTP 406 / PGRST116 when the filter matches nothing, and postgrest-py
    turns that into an APIError. The endpoint's `if not result.data: 404` line
    is therefore unreachable — the exception is raised before it, escapes the
    handler, and FastAPI returns 500. `.maybe_single()` is the call that
    returns data=None instead of raising.

(2) The scope check read a column the query never asked for. The SELECT
    projection listed nine columns and `agency_id` was not among them, so
    `result.data.get("agency_id")` was always None, never equalled the caller's
    real agency id, and every Agency Admin was refused their OWN responders
    with 403 "This Responder does not belong to your agency."

    Nothing crashed. The endpoint failed closed and blamed the data. The same
    check two functions below, in update_responder_approval, selects
    "id, role, agency_id, approval_status" and works — the difference between
    the two is one column name in a string.

The lesson worth keeping: a SELECT projection is an implicit contract with
every line that reads the row afterwards, and Python's .get() breaks that
contract silently by handing back None instead of failing.
"""

import re
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

ROUTER = Path(__file__).resolve().parents[1] / "app" / "routers" / "users.py"

ADMIN_AGENCY = "a0000001-0000-0000-0000-000000000001"
OTHER_AGENCY = "b0000002-0000-0000-0000-000000000002"
RESPONDER_ID = "c0000003-0000-0000-0000-000000000003"

ADMIN = {
    "id": "d0000004-0000-0000-0000-000000000004",
    "role": "agency_admin",
    "agency_id": ADMIN_AGENCY,
    "email": "admin@bfp.gov.ph",
}


class _FakeQuery:
    """
    A Supabase query that honours the SELECT projection.

    This is the whole point of the double: MagicMock would hand back a row
    containing every key the test author thought to put in it, which is exactly
    how defect (2) survived. PostgREST returns ONLY the requested columns, so
    this does too.
    """

    def __init__(self, row, raise_on_single_miss=True):
        self._row = row
        self._cols = None
        self._filters = {}
        self._raise_on_single_miss = raise_on_single_miss
        self._single = False
        self._maybe = False

    def select(self, cols, *a, **k):
        self._cols = [c.strip() for c in cols.split(",")]
        return self

    def eq(self, col, val):
        self._filters[col] = val
        return self

    def single(self):
        self._single = True
        return self

    def maybe_single(self):
        self._maybe = True
        return self

    def _matches(self):
        if self._row is None:
            return None
        return all(str(self._row.get(k)) == str(v) for k, v in self._filters.items())

    def execute(self):
        hit = self._matches()
        if not hit:
            if self._single and self._raise_on_single_miss:
                # What postgrest-py actually raises for a 0-row single().
                from postgrest.exceptions import APIError
                raise APIError({
                    "code": "PGRST116",
                    "details": "The result contains 0 rows",
                    "hint": None,
                    "message": "JSON object requested, multiple (or no) rows returned",
                })
            return MagicMock(data=None)

        projected = {c: self._row.get(c) for c in self._cols} if self._cols else dict(self._row)
        return MagicMock(data=projected)


def _fake_db(row):
    db = MagicMock()
    db.table.return_value = _FakeQuery(row)
    return db


def _responder(agency_id=ADMIN_AGENCY):
    return {
        "id": RESPONDER_ID,
        "email": "responder@bfp.gov.ph",
        "full_name": "Juan Dela Cruz",
        "badge_id": "BFP-0042",
        "role": "responder",
        "agency_id": agency_id,
        "approval_status": "approved",
        "availability": "available",
        "is_verified": True,
        "phone_number": "+639171234567",
        "created_at": "2026-08-01T00:00:00Z",
    }


def _auth(db):
    """Patch both the auth dependency's client and the router's."""
    return (
        patch("app.core.dependencies.get_current_user", return_value=ADMIN),
        patch("app.routers.users.get_supabase", return_value=db),
    )


def _get(db):
    dep, router_db = _auth(db)
    app.dependency_overrides[__import__("app.core.dependencies", fromlist=["x"]).get_current_user] = lambda: ADMIN
    try:
        with router_db:
            return client.get(f"/users/agency/responders/{RESPONDER_ID}")
    finally:
        app.dependency_overrides.clear()


# ── Defect 2: the projection must carry the column the scope check reads ──────

def test_admin_can_view_own_agency_responder():
    """
    The failing case. Before the fix this returned 403 for a responder that
    genuinely belongs to the caller's agency, because agency_id was absent
    from the SELECT and .get() returned None.
    """
    res = _get(_fake_db(_responder(agency_id=ADMIN_AGENCY)))
    assert res.status_code == 200, (
        f"Agency Admin refused their own responder: {res.status_code} {res.text}"
    )
    assert res.json()["id"] == RESPONDER_ID


def test_admin_cannot_view_other_agency_responder():
    """The scope check must still refuse a responder from another agency."""
    res = _get(_fake_db(_responder(agency_id=OTHER_AGENCY)))
    assert res.status_code == 403


def test_projection_includes_every_column_the_handler_reads():
    """
    Static guard. Any column the handler reads off the row must appear in the
    SELECT that produced it, or the read silently yields None.
    """
    src = ROUTER.read_text(encoding="utf-8")
    fn = src.split("def get_responder_profile(")[1].split("\n@router")[0]

    select = re.search(r'\.select\(\s*"([^"]+)"', fn)
    assert select, "get_responder_profile has no literal .select() to check"
    projected = {c.strip() for c in select.group(1).split(",")}

    read = set(re.findall(r'\.data\.get\(\s*"(\w+)"', fn)) | set(
        re.findall(r'result\.data\[\s*"(\w+)"\s*\]', fn)
    )
    missing = read - projected
    assert not missing, f"handler reads {sorted(missing)} but the SELECT does not fetch them"


# ── Defect 1: a missing responder is 404, not 500 ─────────────────────────────

def test_missing_responder_is_404_not_500():
    """
    An id that matches nothing must answer 404. `.single()` raises APIError
    here, which escaped the handler and became a 500; `.maybe_single()`
    returns data=None so the handler's own 404 branch is reachable.
    """
    res = _get(_fake_db(None))
    assert res.status_code == 404, (
        f"expected 404 for an unknown responder id, got {res.status_code} {res.text}"
    )


def test_handler_uses_maybe_single():
    """The 404 branch is only reachable if the query does not raise on 0 rows."""
    src = ROUTER.read_text(encoding="utf-8")
    fn = src.split("def get_responder_profile(")[1].split("\n@router")[0]
    assert ".maybe_single()" in fn, (
        "get_responder_profile must use .maybe_single(); .single() raises "
        "PGRST116 on 0 rows and makes the 404 branch dead code"
    )
