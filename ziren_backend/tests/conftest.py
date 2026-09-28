"""
Shared pytest fixtures for the Ziren backend test suite.

autouse fixtures here apply to ALL test modules automatically.
"""

import pytest


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """
    Reset slowapi's in-memory counters before every test.

    Without this, successive POST calls to rate-limited endpoints
    (incident submit, SOS submit, login) accumulate across tests
    in the same session and produce spurious 429 responses — even
    though each individual test is well within its own limit.

    IMPORTANT: this must reset the SAME Limiter object that the
    @limiter.limit(...) decorators use. This fixture previously did
    `from app.main import limiter`, but main.py, routers/auth.py and
    routers/incidents.py each constructed their own Limiter(), each with
    its own storage. Resetting main's instance therefore cleared counters
    that guarded nothing, while the router instances accumulated across the
    whole session until a later test tripped a 429 that had nothing to do
    with the behaviour it was asserting.

    app.core.rate_limit now owns the single shared instance; reset() clears
    it. Do not reintroduce a module-local Limiter().
    """
    from app.core.rate_limit import reset
    reset()
    yield


@pytest.fixture(autouse=True)
def reset_user_cache():
    """
    Forget every cached "who is this token" answer before each test.

    get_current_user remembers a token's identity for a few seconds (see
    app.core.dependencies). The suite reuses the same fake tokens with different
    mocked profiles from one test to the next, so without this a test would be
    handed the previous test's user.
    """
    from app.core.dependencies import clear_user_cache
    clear_user_cache()
    yield


@pytest.fixture(autouse=True)
def forbid_real_supabase_clients(monkeypatch):
    """
    Fail loudly if a unit test constructs a real Supabase client.

    The Week 2 Singleton fix moved the sign-in off get_supabase() and onto
    new_supabase_client(). test_auth.py patched only get_supabase, so the
    login tests stopped consulting their mock entirely: new_supabase_client()
    built a REAL client and attempted a REAL network sign-in against the live
    Supabase project with fixture credentials. That call failed, login_user's
    `except Exception` caught it, and the suite reported

        assert 401 == 200

    which reads as "login is broken" — it was not. The test double was.

    test_login_invalid_credentials kept passing throughout, because it expects
    a 401 and a failing network call produces one. A test that asserts the
    right status for the wrong reason is what let this sit unnoticed.

    This guard makes the seam explicit: any test that reaches create_client
    has a patch pointing at a function the code no longer calls. Patch the
    factory the caller actually uses instead of loosening this.

    Derived from BaseException on purpose. login_user wraps the sign-in in a
    bare `except Exception`, so an AssertionError here would be caught and
    reshaped into the very 401 this guard exists to explain. Only something
    outside the Exception hierarchy escapes that handler and reaches pytest.
    """
    import app.db.supabase_client as supabase_client

    class RealSupabaseClientBlocked(BaseException):
        pass

    def _blocked(*args, **kwargs):
        raise RealSupabaseClientBlocked(
            "A test tried to build a real Supabase client via create_client(). "
            "Unit tests must not touch the network. Patch the factory the code "
            "under test actually calls — get_supabase() AND/OR "
            "new_supabase_client() — in the module where it is used."
        )

    monkeypatch.setattr(supabase_client, "create_client", _blocked)
    yield


@pytest.fixture(autouse=True)
def new_supabase_client_defaults_to_mocked_get_supabase(monkeypatch):
    """
    Make app.core.dependencies.new_supabase_client() fall back to whatever
    app.core.dependencies.get_supabase is currently mocked to return.

    get_current_user() used to validate every bearer token via get_supabase()
    — the one client every existing test's auth double already covers with
    patch("app.core.dependencies.get_supabase", return_value=mock_db), where
    mock_db.auth.get_user is pre-wired to return the test's fake user. It now
    calls new_supabase_client() instead, so that one request's token check
    can never race another's on a client object they'd otherwise share — a
    real concurrency fix, not a refactor (see that function's docstring for
    the live flapping-401s log it was written against).

    That correctly changed the client get_current_user() talks to, but no
    test's auth double was updated to match, because the double is built once
    per test file and this call site is two calls deep inside a dependency
    tests never invoke directly. Left alone, new_supabase_client() reaches
    the real create_client() on every authenticated TestClient request and
    trips forbid_real_supabase_clients above — this exact failure shape
    already happened once before, for auth_service.login_user's own switch
    to new_supabase_client (see that fixture's docstring), and this is the
    same seam opening a second time on a second call site.

    Rather than editing the auth double in every affected test file, this
    fixture closes the seam once: by default, new_supabase_client() just
    calls get_supabase(), looked up fresh on the dependencies module at CALL
    time — so it transparently picks up whatever a test has (or hasn't)
    patched get_supabase to, including a test that patches it mid-test. A
    test that specifically cares about the two clients being distinct (e.g.
    proving a concurrent request can't contaminate another's session) can
    still patch new_supabase_client itself; applied inside the test body,
    that patch shadows this default for its duration, same as any other
    monkeypatch layering.
    """
    import app.core.dependencies as dependencies

    monkeypatch.setattr(
        dependencies, "new_supabase_client", lambda: dependencies.get_supabase()
    )
    yield


@pytest.fixture(autouse=True)
def inert_notification_service(monkeypatch):
    """
    Give notification_service's OWN get_supabase() a harmless in-memory
    double by default.

    Dispatch, responder, and auth flows fire a best-effort notification as a
    side effect (a new incident arrived, a responder accepted, a new
    responder account awaits approval) by calling into notification_service,
    which resolves get_supabase() at ITS OWN import site — a different one
    than whatever a test's own get_supabase patch covers, per the same
    seam test_audit_wiring.py documents for audit_service. A test exercising
    submit_incident() or responder acceptance is not testing that
    notification and would otherwise trip forbid_real_supabase_clients over
    a side channel it never intended to touch.

    A test that DOES care what notification_service does (test_notifications.py)
    patches notification_service.get_supabase, or the create_for_* functions,
    itself — that local patch wins for the duration of its own `with` block
    regardless of this fixture.
    """
    import app.services.notification_service as notification_service

    class _InertResult:
        data: list = []
        count = 0

    class _InertQuery:
        def __getattr__(self, _name):
            return lambda *a, **k: self

        def execute(self):
            return _InertResult()

    class _InertTable:
        def __getattr__(self, _name):
            return lambda *a, **k: _InertQuery()

    class _InertDB:
        def table(self, _name):
            return _InertTable()

    monkeypatch.setattr(notification_service, "get_supabase", lambda: _InertDB())
    yield
