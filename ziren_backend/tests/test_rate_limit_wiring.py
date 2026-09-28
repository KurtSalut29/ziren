"""
Regression tests for rate-limiter wiring.

Background: main.py, routers/auth.py and routers/incidents.py each used to
construct their own Limiter(). Each Limiter owns an independent storage
backend, so:

  * app.state.limiter (used by the RateLimitExceeded handler and by the
    test-suite reset fixture) was NOT the object enforcing the endpoints, and
  * the conftest reset fixture cleared counters that guarded nothing.

The visible symptom was a 429 in an unrelated security test once the module
accumulated enough requests — a test that silently stopped asserting what it
claimed to assert. These tests lock the wiring down so it cannot regress.
"""

import app.main as main_module
from app.core.rate_limit import limiter as shared_limiter
from app.routers import auth as auth_router
from app.routers import incidents as incidents_router


def test_all_modules_share_one_limiter_instance():
    """Every module must reference the same Limiter object, not a copy."""
    assert main_module.limiter is shared_limiter
    assert auth_router.limiter is shared_limiter
    assert incidents_router.limiter is shared_limiter


def test_app_state_limiter_is_the_shared_instance():
    """
    app.state.limiter is what slowapi's exception handler consults. If it is
    a different object from the one the decorators use, limits and error
    handling disagree.
    """
    assert main_module.app.state.limiter is shared_limiter


def test_reset_actually_clears_the_enforcing_storage():
    """
    The reset helper must clear the storage that the endpoint decorators
    consult — the exact property that was broken before.
    """
    storage = shared_limiter._storage
    storage.incr("regression-probe-key", 60, 1)
    assert storage.get("regression-probe-key") >= 1

    from app.core.rate_limit import reset
    reset()

    assert storage.get("regression-probe-key") == 0


def test_no_module_constructs_its_own_limiter():
    """
    Guard against someone re-adding `Limiter(key_func=...)` in a router.
    Scans the app package source rather than trusting import-time identity,
    so a newly added router is caught too.
    """
    import pathlib

    app_dir = pathlib.Path(main_module.__file__).parent
    offenders = []
    for py in app_dir.rglob("*.py"):
        if py.name == "rate_limit.py":
            continue  # the one legitimate construction site
        text = py.read_text(encoding="utf-8")
        if "Limiter(" in text:
            offenders.append(str(py.relative_to(app_dir)))

    assert offenders == [], (
        "These modules construct their own Limiter instead of importing the "
        f"shared one from app.core.rate_limit: {offenders}"
    )
