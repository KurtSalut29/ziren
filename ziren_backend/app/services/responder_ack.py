"""
Acceptance state — the one question the dispatch system could not answer.

`incidents.status = 'dispatched'` has only ever meant "a dispatcher pressed a
button". Whether a crew ever SAW the assignment was unrepresented, so an alert
that reached a phone in a locker looked exactly like one a truck was already
rolling on. Migration 024 adds `accepted_at` / `declined_at`; this module turns
those columns into the verdict both screens render.

WHY THIS IS ITS OWN MODULE

Two callers need the identical answer from opposite sides of the product: the
responder's queue (`responder_service.get_my_queue`) and the dispatcher's board
(`dispatch_service.get_queue`). If each computed its own deadline they would
drift — and the failure mode of that drift is a board showing OVERDUE in red
while the responder's phone still shows a running timer, which is worse than
having no timer at all.

Pure functions over dicts. No database, no clock of its own beyond an injected
`now`, so the deadline policy can be tested directly instead of through two
services and a fixture.
"""

from datetime import datetime, timezone

#: How long an assignment may sit unaccepted before the board escalates it.
#:
#: Scaled by severity because the cost of waiting is. Sixty seconds is roughly
#: how long it takes to pull over, read a screen and press a button — short
#: enough that a phone nobody is holding trips it, long enough that a crew who
#: is genuinely responding does not.
#:
#: NOT STORED ON THE ROW. Freezing the policy into every historical incident
#: would mean that tuning these numbers later leaves the board judging old
#: incidents by a rule nobody remembers writing. See migration 024.
_ACK_DEADLINE_SECONDS: dict[str, int] = {
    "critical": 60,
    "high": 120,
    "medium": 180,
    "low": 180,
}

#: Used when severity is absent. An unscored incident is not a low-priority
#: one — it is one the rubric could not read — so it gets the strictest
#: treatment rather than the most forgiving.
_DEFAULT_DEADLINE_SECONDS = 60

#: Statuses where acceptance is still a live question. Once a crew is en_route
#: they have plainly received it, and once it is closed the question is moot.
_AWAITING_STATUSES = frozenset({"dispatched"})


def deadline_seconds(severity: str | None) -> int:
    """How long this severity may go unaccepted before it is overdue."""
    if not severity:
        return _DEFAULT_DEADLINE_SECONDS
    return _ACK_DEADLINE_SECONDS.get(severity, _DEFAULT_DEADLINE_SECONDS)


def _parse(value) -> datetime | None:
    """Postgres timestamps arrive as strings through PostgREST, but tests and
    callers may pass real datetimes. Accept both rather than making every call
    site remember which."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def ack_state(incident: dict, now: datetime | None = None) -> dict:
    """Derive the acceptance verdict for one incident row.

    Returns a dict that is merged into the incident payload by both services:

        state              'accepted' | 'declined' | 'pending' | 'overdue'
                           | 'not_applicable'
        seconds_waiting    whole seconds since dispatch, while unaccepted
        seconds_remaining  countdown to the deadline; 0 once overdue
        deadline_seconds   the policy that applied, so the UI can render a
                           proportion without hardcoding the same numbers a
                           third time
        decline_count      carried through for the board's coverage warning

    'not_applicable' covers incidents that were never dispatched and closed
    ones. It is deliberately NOT 'accepted': a resolved incident nobody ever
    accepted really did happen that way, and flattening it to accepted would
    erase the very evidence this feature exists to collect.
    """
    now = now or datetime.now(timezone.utc)

    accepted_at = _parse(incident.get("accepted_at"))
    declined_at = _parse(incident.get("declined_at"))
    dispatched_at = _parse(incident.get("dispatched_at"))
    status = incident.get("status")
    limit = deadline_seconds(incident.get("severity"))

    base = {
        "deadline_seconds": limit,
        "decline_count": incident.get("decline_count") or 0,
        "seconds_waiting": None,
        "seconds_remaining": None,
    }

    if accepted_at is not None:
        return {**base, "state": "accepted"}

    # A refusal that has not yet been reassigned. Checked after acceptance so
    # that a reassignment which cleared accepted_at but left the previous
    # decline on the row reads as pending, not as still-declined.
    if declined_at is not None and incident.get("assigned_responder_id") is None:
        return {
            **base,
            "state": "declined",
            "declined_reason": incident.get("declined_reason"),
        }

    if status not in _AWAITING_STATUSES or dispatched_at is None:
        return {**base, "state": "not_applicable"}

    waiting = int((now - dispatched_at).total_seconds())
    # Clock skew between the app server and Postgres can produce a small
    # negative here. Clamping keeps a "-3 seconds waiting" out of the UI.
    waiting = max(waiting, 0)
    remaining = limit - waiting

    return {
        **base,
        "state": "pending" if remaining > 0 else "overdue",
        "seconds_waiting": waiting,
        "seconds_remaining": max(remaining, 0),
    }


def annotate(rows: list[dict], now: datetime | None = None) -> list[dict]:
    """Attach `ack` to every row in a queue result, in place.

    Called by both queue builders. Mutates rather than copies because these
    rows are already throwaway PostgREST dicts on their way to a JSON encoder,
    and copying a queue on every poll is a cost with no reader.
    """
    now = now or datetime.now(timezone.utc)
    for row in rows:
        row["ack"] = ack_state(row, now=now)
    return rows
