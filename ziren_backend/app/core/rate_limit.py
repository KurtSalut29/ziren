"""
Shared rate-limiter instance.

There must be exactly ONE Limiter in the process. Each Limiter owns its own
storage backend, so constructing a second one silently creates a second,
independent set of counters.

This module exists because that is exactly what had happened: main.py,
routers/auth.py, and routers/incidents.py each constructed their own
Limiter(). The app registered main.py's instance on app.state (which is what
the RateLimitExceeded handler and the test-suite reset fixture reach), while
the @limiter.limit(...) decorators that actually guard the endpoints belonged
to the router-local instances. Resetting one had no effect on the others.

Import the `limiter` defined here everywhere. Do not call Limiter() again.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

# The single process-wide limiter. Both the app (app.state.limiter) and every
# @limiter.limit(...) decorator must reference this same object.
limiter = Limiter(key_func=get_remote_address)


def reset() -> None:
    """
    Clear all rate-limit counters.

    Intended for the test suite, which issues many requests from a single
    synthetic client far faster than any real caller would. Calling this in
    production would defeat the limiter, so it is only invoked from the
    autouse fixture in tests/conftest.py.
    """
    limiter._storage.reset()
