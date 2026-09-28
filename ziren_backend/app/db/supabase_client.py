"""
Supabase client singleton.

Uses the service role key (server-side only) for full DB access.
This module must NEVER be imported by any client-facing code that
could leak the service key.
"""

import httpx
import structlog
from supabase import Client, create_client

from app.core.config import settings

log = structlog.get_logger()

_client: Client | None = None

# Methods that may be replayed after a dropped connection. A GET can be sent
# twice with no consequence; a POST cannot, because a connection that dies
# mid-response is indistinguishable from one that died before the write, and
# retrying the second case would file the same incident twice.
_REPLAYABLE = frozenset({"GET", "HEAD", "OPTIONS"})


class _RetryStaleConnection(httpx.HTTPTransport):
    """
    Retry a read once when the pooled connection turns out to be dead.

    THE FAILURE THIS FIXES

        httpx.RemoteProtocolError: Server disconnected
          File "app/routers/users.py", line 716, in list_barangays
            .execute()

    reaching the dashboard as a bare 500 on whatever the operator clicked
    first after a quiet stretch.

    It is not a bug in any one endpoint. Every call in this app goes through
    one long-lived Supabase client with an httpx connection pool, and a pooled
    connection can be closed by the far end at any moment. httpx checks a
    connection looks alive, writes to it, and only then discovers Supabase had
    already closed it — a window that exists no matter how the keep-alive is
    tuned, because the two ends cannot agree on the instant a socket dies.

    httpx's own `HTTPTransport(retries=...)` does not cover this: it retries
    connect failures only, and by this point the connection had already been
    established. So the retry has to live here.

    Deliberately once, and deliberately reads only. A single replay is enough
    for a stale socket — the second attempt opens a fresh connection — while a
    loop would turn a genuine outage into a slow one.
    """

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        try:
            return super().handle_request(request)
        except (httpx.RemoteProtocolError, httpx.ReadError) as exc:
            if request.method not in _REPLAYABLE:
                raise
            log.warning(
                "supabase.stale_connection_retried",
                method=request.method,
                url=str(request.url),
                error=str(exc),
            )
            return super().handle_request(request)


def _install_retry_transport(client: Client) -> Client:
    """
    Swap the retrying transport into the sub-clients that talk to Postgres.

    Reaches for a private attribute because supabase-py 2.11 exposes no way to
    supply an httpx client or transport through ClientOptions — the dataclass
    has no field for it. Guarded and best-effort on purpose: if a later version
    changes the internals, the app keeps working exactly as it does today
    rather than failing to start over a resilience nicety.
    """
    for name in ("postgrest", "storage"):
        sub = getattr(client, name, None)
        session = getattr(sub, "session", None)
        if session is None or not hasattr(session, "_transport"):
            continue
        try:
            session._transport = _RetryStaleConnection()
        except Exception:  # noqa: BLE001 - never block startup for this
            log.warning("supabase.retry_transport_not_installed", sub_client=name)
    return client


def get_supabase() -> Client:
    """
    Return the shared Supabase client, creating it on first call.

    Service-key scoped. Safe for database reads/writes and admin API calls —
    but see new_supabase_client() before doing anything that SIGNS A USER IN
    through it.
    """
    global _client
    if _client is None:
        _client = _install_retry_transport(
            create_client(settings.supabase_url, settings.supabase_service_key)
        )
    return _client


def new_supabase_client() -> Client:
    """
    A fresh, unshared client for operations that establish a user session.

    sign_in_with_password() and set_session() mutate the auth state of the
    client they are called on. Doing that to the singleton above replaces its
    service-key authorization with the signed-in user's JWT for the remainder
    of the process, so every later admin call inherits a random user's
    identity. That surfaced as:

        Could not set password: User from sub claim in JWT does not exist

    on an admin.update_user_by_id() — the singleton was still carrying the
    session of a user that had since been deleted.

    It is a process-wide, cross-request contamination: one login can break
    admin operations for every subsequent request. Use this factory for any
    user-scoped auth call and let the result be garbage collected; keep the
    singleton service-key-only.

    Short-lived, so the stale-connection retry above is not needed here.
    """
    return create_client(settings.supabase_url, settings.supabase_service_key)
