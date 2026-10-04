"""
push_service — phone notifications that reach a closed app (FCM).

Evaluator findings #11 and #12 (2026-10-05): notices reached a phone only while
the app was open (Supabase Realtime). A resident whose app was closed never
heard that an admin had written to them or that a crew was on the way; a
responder never heard about a new assignment.

Every row notification_service writes is also offered here, and a dispatch
pushes to the assigned responder directly. Delivery goes through Firebase Cloud
Messaging's HTTP v1 API with a service account:

    FCM_SERVICE_ACCOUNT_JSON  the service account key, as JSON text or base64
                              of it (Firebase console -> Project settings ->
                              Service accounts -> Generate new private key)

Without it, push is OFF and everything else behaves exactly as before. Sending
never raises and never blocks the request that caused it: it runs on a small
background pool, and a dead token reported by FCM is deleted.
"""

from __future__ import annotations

import base64
import json
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Iterable

import httpx
import jwt
import structlog

from app.db.supabase_client import get_supabase

log = structlog.get_logger()

_TOKEN_URL = "https://oauth2.googleapis.com/token"
_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="push")
_lock = threading.Lock()
_cache: dict = {"token": None, "exp": 0.0}


def _service_account() -> dict | None:
    raw = os.environ.get("FCM_SERVICE_ACCOUNT_JSON", "").strip()
    if not raw:
        return None
    try:
        if not raw.startswith("{"):
            raw = base64.b64decode(raw).decode("utf-8")
        info = json.loads(raw)
        return info if info.get("private_key") and info.get("client_email") else None
    except Exception:
        log.error("push.service_account_unreadable")
        return None


def enabled() -> bool:
    return _service_account() is not None


def _access_token(info: dict) -> str:
    """An OAuth access token for FCM, cached until shortly before it expires."""
    with _lock:
        if _cache["token"] and time.time() < _cache["exp"] - 60:
            return _cache["token"]
        now = int(time.time())
        assertion = jwt.encode(
            {"iss": info["client_email"], "scope": _SCOPE, "aud": _TOKEN_URL, "iat": now, "exp": now + 3600},
            info["private_key"],
            algorithm="RS256",
        )
        r = httpx.post(_TOKEN_URL, data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion,
        }, timeout=10)
        r.raise_for_status()
        body = r.json()
        _cache["token"], _cache["exp"] = body["access_token"], now + int(body.get("expires_in", 3600))
        return _cache["token"]


# ── tokens ─────────────────────────────────────────────────────

def register_token(user_id: str, token: str, platform: str = "android") -> None:
    """Remember this phone for this account (moving it from any other)."""
    token = (token or "").strip()
    if not (20 <= len(token) <= 4096):
        raise ValueError("Not a push token.")
    if platform not in ("android", "ios", "web"):
        platform = "android"
    get_supabase().table("device_push_tokens").upsert({
        "token": token, "user_id": str(user_id), "platform": platform,
        "last_seen_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }).execute()


def forget_token(user_id: str, token: str | None = None) -> None:
    """Sign-out: this phone (or all of this account's phones) stops receiving."""
    q = get_supabase().table("device_push_tokens").delete().eq("user_id", str(user_id))
    if token:
        q = q.eq("token", token)
    q.execute()


def _tokens_for(user_ids: list[str]) -> list[str]:
    out: list[str] = []
    for start in range(0, len(user_ids), 200):
        rows = (
            get_supabase().table("device_push_tokens").select("token")
            .in_("user_id", user_ids[start:start + 200]).execute().data or []
        )
        out.extend(r["token"] for r in rows if r.get("token"))
    return out


# ── sending ────────────────────────────────────────────────────

def send_to_users(
    user_ids: Iterable[str],
    *,
    title: str,
    body: str | None = None,
    data: dict | None = None,
    important: bool = False,
    channel: str | None = None,
) -> None:
    """Queue a push to every phone of these users. Returns at once; never raises.

    `channel` is the Android notification channel. The app creates
    ziren_alerts / ziren_updates for residents; a responder's assignment uses
    the app's own dispatch channel, which sounds as an alarm through silent mode.
    """
    ids = sorted({str(u) for u in user_ids if u})
    if not ids or not enabled():
        return
    try:
        _pool.submit(_deliver, ids, title, body, data or {}, important, channel)
    except Exception:
        log.error("push.queue_failed", exc_info=True)


def _deliver(
    user_ids: list[str], title: str, body: str | None, data: dict, important: bool, channel: str | None = None,
) -> None:
    info = _service_account()
    if info is None:
        return
    try:
        tokens = _tokens_for(user_ids)
        if not tokens:
            return
        access = _access_token(info)
    except Exception:
        log.error("push.prepare_failed", exc_info=True)
        return

    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    # FCM data values must be strings.
    payload_data = {k: (v if isinstance(v, str) else json.dumps(v)) for k, v in data.items() if v is not None}
    sent = dead = 0
    with httpx.Client(timeout=10, headers={"Authorization": f"Bearer {access}"}) as client:
        for token in tokens:
            message = {
                "message": {
                    "token": token,
                    "notification": {"title": title[:200], **({"body": body[:400]} if body else {})},
                    "data": payload_data,
                    "android": {
                        "priority": "HIGH" if important else "NORMAL",
                        "notification": {"channel_id": channel or ("ziren_alerts" if important else "ziren_updates")},
                    },
                }
            }
            try:
                r = client.post(url, json=message)
            except httpx.HTTPError:
                log.warning("push.send_failed")
                continue
            if r.status_code == 200:
                sent += 1
            elif r.status_code in (400, 404) and ("UNREGISTERED" in r.text or "INVALID_ARGUMENT" in r.text):
                dead += 1
                try:
                    get_supabase().table("device_push_tokens").delete().eq("token", token).execute()
                except Exception:
                    pass
            else:
                log.warning("push.rejected", status=r.status_code, detail=r.text[:200])
    log.info("push.delivered", users=len(user_ids), sent=sent, removed=dead)
