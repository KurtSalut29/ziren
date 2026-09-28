"""
get_current_user remembers who a token belongs to for a few seconds.

Why: every authenticated request used to pay for two Supabase round trips (a
token check on a brand-new client, then a read of the caller's profile row)
before doing any work of its own - roughly 800-1000 ms each, on every request,
which is what made every dashboard page take seconds to appear. See the note
above _USER_CACHE_TTL_S in app/core/dependencies.py.

What must stay true while it is cached:
  - a burst of requests with one token validates it ONCE;
  - different tokens never share an answer;
  - a rejected token is never remembered (so a 401 stays a 401);
  - an answer expires;
  - signing out forgets it immediately;
  - the caller gets a copy, so one request cannot edit another's profile.
"""

import threading
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.core import dependencies

USER = {
    "id": "00000000-0000-0000-0000-0000000000aa", "email": "a@example.com", "full_name": "A",
    "role": "agency_admin", "approval_status": "not_required", "agency_id": "ag1",
    "agency_type": None, "badge_id": None, "is_verified": True,
}


def _creds(token="tok-1"):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


@pytest.fixture
def supabase(monkeypatch):
    """A Supabase whose calls are counted."""
    auth = MagicMock()
    auth.auth.get_user.return_value = SimpleNamespace(user=SimpleNamespace(id=USER["id"]))
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = (
        SimpleNamespace(data=dict(USER))
    )
    monkeypatch.setattr(dependencies, "new_supabase_client", lambda: auth)
    monkeypatch.setattr(dependencies, "get_supabase", lambda: db)
    return SimpleNamespace(auth=auth, db=db)


def test_the_second_request_does_not_go_back_to_supabase(supabase):
    first = dependencies.get_current_user(_creds())
    second = dependencies.get_current_user(_creds())

    assert first == second == USER
    assert supabase.auth.auth.get_user.call_count == 1
    assert supabase.db.table.call_count == 1


def test_different_tokens_do_not_share_an_answer(supabase):
    dependencies.get_current_user(_creds("tok-1"))
    dependencies.get_current_user(_creds("tok-2"))
    assert supabase.auth.auth.get_user.call_count == 2


def test_a_rejected_token_is_not_remembered(supabase):
    supabase.auth.auth.get_user.side_effect = RuntimeError("invalid JWT")
    for _ in range(2):
        with pytest.raises(HTTPException) as exc:
            dependencies.get_current_user(_creds())
        assert exc.value.status_code == 401
    # Asked again each time: a bad token never becomes a good one by being cached.
    assert supabase.auth.auth.get_user.call_count == 2


def test_an_answer_expires(supabase, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(dependencies.time, "monotonic", lambda: now[0])

    dependencies.get_current_user(_creds())
    now[0] += dependencies._USER_CACHE_TTL_S - 1
    dependencies.get_current_user(_creds())
    assert supabase.auth.auth.get_user.call_count == 1

    now[0] += 2  # past the TTL
    dependencies.get_current_user(_creds())
    assert supabase.auth.auth.get_user.call_count == 2


def test_signing_out_forgets_the_token_at_once(supabase):
    dependencies.get_current_user(_creds())
    dependencies.forget_token("tok-1")
    dependencies.get_current_user(_creds())
    assert supabase.auth.auth.get_user.call_count == 2


def test_the_caller_gets_a_copy(supabase):
    mine = dependencies.get_current_user(_creds())
    mine["role"] = "provincial_admin"  # a request editing its own copy...
    assert dependencies.get_current_user(_creds())["role"] == "agency_admin"  # ...changes nothing for the next


def test_a_burst_of_simultaneous_requests_validates_once(supabase):
    # A dashboard page load: six requests, one token, the same instant.
    gate = threading.Barrier(6)
    results = []

    def request():
        gate.wait()
        results.append(dependencies.get_current_user(_creds()))

    threads = [threading.Thread(target=request) for _ in range(6)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()

    assert len(results) == 6 and all(r == USER for r in results)
    assert supabase.auth.auth.get_user.call_count == 1


def test_the_cache_holds_a_hash_not_the_token(supabase):
    dependencies.get_current_user(_creds("super-secret-token"))
    assert all("super-secret-token" not in key for key in dependencies._user_cache)
