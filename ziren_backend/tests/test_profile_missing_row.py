"""What GET /users/me does when the profile row is not there.

This is a real state, not a hypothetical. Every account created before the
trigger in migration 013 has an entry in auth.users and no row in
public.users, and two such accounts are still in this project's database. The
person can sign in — Supabase issues them a perfectly valid token — and then
every profile request fails.

The failure used to be a 500, because the 404 written for exactly this case
could never execute: PostgREST's `single` raises PGRST116 on zero rows rather
than returning an empty result, so the guard beneath it was unreachable. What
the person saw was "Details below may be out of date." next to a Retry button,
which is wrong twice over — nothing is stale, and no amount of retrying will
create a row.

Run with: pytest tests/test_profile_missing_row.py -v
"""

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError

from app.services import user_service


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    """The fluent chain user_service builds, stopping at the terminal call."""

    def __init__(self, outcome):
        self._outcome = outcome

    def select(self, *_a, **_k):
        return self

    def eq(self, *_a, **_k):
        return self

    def single(self):
        # What the real client does with no rows.
        raise APIError({
            "code": "PGRST116",
            "details": "The result contains 0 rows",
            "hint": None,
            "message": "Cannot coerce the result to a single JSON object",
        })

    def maybe_single(self):
        return self

    def execute(self):
        return self._outcome


class _Db:
    def __init__(self, outcome):
        self._outcome = outcome

    def table(self, _name):
        return _Query(self._outcome)


@pytest.mark.parametrize(
    "outcome",
    [
        # maybe_single returns None itself on an empty result in this client
        # version — not a response object carrying None.
        None,
        _Result(None),
        _Result([]),
    ],
    ids=["none-response", "null-data", "empty-list"],
)
def test_a_missing_profile_is_a_404_not_a_500(monkeypatch, outcome):
    monkeypatch.setattr(user_service, "get_supabase", lambda: _Db(outcome))

    with pytest.raises(HTTPException) as exc:
        user_service.get_my_profile(user_id="2d8885e6-0000-0000-0000-000000000000")

    assert exc.value.status_code == 404


def test_the_message_says_what_is_wrong_and_who_can_fix_it(monkeypatch):
    """The person is not offline and cannot fix this by retrying.

    They need to know the account is real, the profile is not, and that it
    takes an administrator — otherwise the only signal is a Retry button that
    fails forever.
    """
    monkeypatch.setattr(user_service, "get_supabase", lambda: _Db(None))

    with pytest.raises(HTTPException) as exc:
        user_service.get_my_profile(user_id="2d8885e6-0000-0000-0000-000000000000")

    detail = str(exc.value.detail).lower()
    assert "profile" in detail
    assert "administrator" in detail


def test_a_profile_that_exists_is_still_returned(monkeypatch):
    """The guard must not swallow the ordinary case."""
    row = {
        "id": "6c2f7cde-0000-0000-0000-000000000000",
        "email": "resident@example.com",
        "full_name": "Marjon Vera",
        "role": "resident",
        "approval_status": "not_required",
        "agency_id": None,
        "badge_id": None,
        "is_verified": True,
        "created_at": "2026-08-25T13:28:54.066170+00:00",
    }
    monkeypatch.setattr(user_service, "get_supabase", lambda: _Db(_Result(row)))

    profile = user_service.get_my_profile(user_id=row["id"])
    assert profile.full_name == "Marjon Vera"
    assert profile.email == "resident@example.com"
