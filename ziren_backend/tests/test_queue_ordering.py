"""The order the dispatch queue comes back in, and why it is that order.

Two rules, and both were broken in ways that only show on a busy day — which
is the only day they matter.

  1. SEVERITY FIRST, using the EFFECTIVE severity. The sort used to read the
     `severity` column, which is NULL on every incident no dispatcher has
     ranked yet — that is, on every incident still awaiting a decision. So the
     rubric could call a brand-new report CRITICAL and it would still sort
     below every already-dispatched `low`. The rows most in need of attention
     were the ones the ordering pushed furthest down.

  2. OLDEST FIRST within a severity. First come, first served among reports in
     equal danger. The console states this rule on screen and numbers the cards
     from it, so the server has to actually follow it.

And one property of the cap: at QUEUE_MAX the rows that survive must be the
NEWEST ones. The query used to fetch oldest-first, so a province with more open
incidents than the cap silently dropped the reports that had just come in.

Run with: pytest tests/test_queue_ordering.py -v
"""

from unittest.mock import MagicMock, patch

import pytest

from app.services import dispatch_service


def _row(rid, *, severity=None, created, status="received", category="fire"):
    return {
        "id": rid,
        "report_text": f"report {rid}",
        "status": status,
        "severity": severity,
        "location_address": None,
        "signals": None,
        "incident_category": category,
        "sos_flagged": False,
        "nlp_review_needed": False,
        "overlap_agencies": None,
        "wizard_answers": {},
        "landmark_note": None,
        "victim_relationship": None,
        "created_at": created,
        "dispatched_at": None,
        "assigned_responder_id": None,
        "stations": None,
        "users": None,
    }


def _queue(rows, role="provincial_admin", agency_id=None, agency_type="BFP"):
    """Run get_incident_queue against a fixed row set.

    Defaults to a provincial_admin (migration 034's replacement for the old
    unconditionally-unscoped super_admin) with a real agency_type, since
    get_incident_queue now resolves that type to a list of agency ids
    (dispatch_service._agency_ids_for_type) before it can even reach the
    incidents query this file's ordering assertions care about.
    """
    result = MagicMock()
    result.data = rows

    query = MagicMock()
    # Every builder method returns the same mock, so the chain in the service
    # resolves regardless of how it is ordered.
    for name in ("select", "in_", "order", "limit", "eq"):
        getattr(query, name).return_value = query
    query.execute.return_value = result

    # The two-step agencies lookup a provincial_admin's request makes hits a
    # DIFFERENT table than the incidents query above, so it needs its own
    # node returning a non-empty id list -- otherwise
    # "if not agency_ids: return []" would short-circuit before the
    # incidents query this file is actually testing ever runs.
    agencies_result = MagicMock()
    agencies_result.data = [{"id": "any-agency-of-this-type"}]
    agencies_query = MagicMock()
    agencies_query.select.return_value = agencies_query
    agencies_query.eq.return_value = agencies_query
    agencies_query.execute.return_value = agencies_result

    db = MagicMock()
    db.table.side_effect = lambda name: agencies_query if name == "agencies" else query

    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        out = dispatch_service.get_incident_queue(
            {"id": "u1", "role": role, "agency_id": agency_id, "agency_type": agency_type}
        )
    return out, query


class TestSeverityFirst:
    def test_critical_outranks_low_whatever_the_arrival_order(self):
        rows = [
            _row("low-first", severity="low", created="2026-01-01T00:00:00+00:00"),
            _row("crit-later", severity="critical", created="2026-01-01T05:00:00+00:00"),
        ]
        out, _ = _queue(rows)
        assert [r["id"] for r in out] == ["crit-later", "low-first"]

    def test_a_rubric_suggestion_ranks_as_high_as_a_set_severity(self):
        """The regression. An untriaged incident has severity NULL.

        Sorting on the column instead of the effective value filed every
        undecided report — the only kind a dispatcher can still act on — below
        every decided one.
        """
        rows = [
            _row("decided-low", severity="low", created="2026-01-01T00:00:00+00:00"),
            _row("untriaged", severity=None, created="2026-01-01T01:00:00+00:00"),
        ]
        with patch.object(dispatch_service, "_suggest_severity", return_value="critical"):
            out, _ = _queue(rows)
        assert out[0]["id"] == "untriaged"
        assert out[0]["suggested_severity"] == "critical"

    def test_an_unrankable_incident_sorts_last_not_first(self):
        """No severity and no suggestion is the least information, not the most."""
        rows = [
            _row("unknown", severity=None, created="2026-01-01T00:00:00+00:00"),
            _row("medium", severity="medium", created="2026-01-01T09:00:00+00:00"),
        ]
        with patch.object(dispatch_service, "_suggest_severity", return_value=None):
            out, _ = _queue(rows)
        assert [r["id"] for r in out] == ["medium", "unknown"]


class TestFirstComeFirstServed:
    def test_equal_severity_is_ordered_oldest_first(self):
        rows = [
            _row("third", severity="high", created="2026-01-01T03:00:00+00:00"),
            _row("first", severity="high", created="2026-01-01T01:00:00+00:00"),
            _row("second", severity="high", created="2026-01-01T02:00:00+00:00"),
        ]
        out, _ = _queue(rows)
        assert [r["id"] for r in out] == ["first", "second", "third"]

    def test_the_rule_holds_inside_every_band_at_once(self):
        rows = [
            _row("c2", severity="critical", created="2026-01-01T04:00:00+00:00"),
            _row("h1", severity="high", created="2026-01-01T01:00:00+00:00"),
            _row("c1", severity="critical", created="2026-01-01T02:00:00+00:00"),
            _row("h2", severity="high", created="2026-01-01T05:00:00+00:00"),
        ]
        out, _ = _queue(rows)
        assert [r["id"] for r in out] == ["c1", "c2", "h1", "h2"]

    def test_a_missing_timestamp_does_not_raise(self):
        """created_at is NOT NULL in the schema, but the sort must not be the
        thing that discovers a row where it is missing."""
        rows = [
            _row("ok", severity="high", created="2026-01-01T01:00:00+00:00"),
            _row("broken", severity="high", created=None),
        ]
        out, _ = _queue(rows)
        assert len(out) == 2


class TestTheCapKeepsTheNewest:
    def test_rows_are_fetched_newest_first(self):
        """Which rows survive QUEUE_MAX is decided by the DB ordering.

        Ascending here means the cap throws away the newest incidents — on a
        typhoon night, the report filed thirty seconds ago — while faithfully
        returning five hundred the console already knew about.
        """
        _, query = _queue([])
        query.order.assert_called_with("created_at", desc=True)

    def test_the_cap_is_still_applied(self):
        _, query = _queue([])
        query.limit.assert_called_with(dispatch_service.QUEUE_MAX)


class TestScoping:
    def test_agency_admin_is_scoped_to_their_own_agency(self):
        _, query = _queue([], role="agency_admin", agency_id="ag-1")
        query.eq.assert_called_with("assigned_agency_id", "ag-1")

    def test_an_agency_admin_with_no_agency_gets_nothing(self):
        """Not everything. A null agency_id must fail closed."""
        out, _ = _queue([_row("x", severity="high", created="2026-01-01T00:00:00+00:00")],
                        role="agency_admin", agency_id=None)
        assert out == []

    def test_provincial_admin_is_scoped_to_their_own_agency_type(self):
        """
        Migration 034: unlike the retired cross-agency super_admin, a
        Provincial Admin's queue IS scoped -- to every agency of their own
        agency_type, via the two-step agencies lookup applied with .in_()
        (not agency_admin's single .eq()).
        """
        _, query = _queue([], role="provincial_admin", agency_type="BFP")
        query.eq.assert_not_called()
        in_calls = [c.args[0] for c in query.in_.call_args_list]
        assert "assigned_agency_id" in in_calls

    def test_a_provincial_admin_with_no_agency_type_gets_nothing(self):
        """Not everything. A null agency_type must fail closed, same as
        agency_admin's null agency_id above."""
        out, _ = _queue([_row("x", severity="high", created="2026-01-01T00:00:00+00:00")],
                        role="provincial_admin", agency_type=None)
        assert out == []


@pytest.mark.parametrize("severity", ["critical", "high", "medium", "low"])
def test_a_set_severity_is_echoed_as_the_suggestion(severity):
    """The client reads `suggested_severity ?? severity`, so a decided
    incident has to carry its own severity in that field or it would fall
    into the untriaged band on screen."""
    rows = [_row("x", severity=severity, created="2026-01-01T00:00:00+00:00")]
    out, _ = _queue(rows)
    assert out[0]["suggested_severity"] == severity
