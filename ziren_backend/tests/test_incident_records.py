"""Incident Records — what /dispatch/history returns and how it is looked up.

The Incident History page became a records table (one row per incident, one
column per fact), so the endpoint behind it now carries the fields a record
needs and a lookup by record number.

Properties worth pinning:

  1. The row carries what a record needs: the record number, the accepted
     time, and the responder's NAME (the queue shape only has an id). It asks
     only for columns that exist — see the phantom-column test below.
  2. `record_no` finds a record by number wherever it sits — it takes over from
     the time window, the way an explicit date range already does. A record
     filed a year ago must be found, not hidden by "last 30 days".
  3. `record_no` never widens the caller's scope. It narrows within it.
  4. Every query that describes the window — the page, the counts, the
     response-time average, the station tally — sees the same filters, so the
     summary line can never disagree with the table.

Run with: pytest tests/test_incident_records.py -v
"""

from unittest.mock import MagicMock, patch

import pytest

from app.services import dispatch_service


def _row(rid="i1"):
    return {
        "id": rid,
        "record_number": "ZIR-2026-000123",
        "report_text": "House fire",
        "status": "resolved",
        "severity": "high",
        "location_address": "Poblacion",
        "signals": None,
        "incident_category": "fire",
        "sos_flagged": False,
        "nlp_review_needed": False,
        "overlap_agencies": None,
        "wizard_answers": {},
        "media_urls": [],
        "station_id": "st1",
        "latitude": 11.5,
        "longitude": 124.4,
        "created_at": "2026-01-01T00:00:00+00:00",
        "accepted_at": "2026-01-01T00:05:00+00:00",
        "dispatched_at": "2026-01-01T00:02:00+00:00",
        "resolved_at": "2026-01-01T01:00:00+00:00",
        "assigned_responder_id": "r1",
        "responder": {"full_name": "Juan Dela Cruz"},
        "stations": None,
        "users": None,
    }


def _history(rows=None, *, role="agency_admin", agency_id="ag-1", **kwargs):
    rows = [_row()] if rows is None else rows
    result = MagicMock()
    result.data = rows
    result.count = len(rows)

    query = MagicMock()
    # Every builder returns the same mock, so all four incidents queries the
    # service makes resolve against one object and the call lists cover them all.
    for name in ("select", "eq", "in_", "gte", "lt", "order", "range", "like"):
        getattr(query, name).return_value = query
    query.not_.is_.return_value = query
    query.not_.in_.return_value = query
    query.execute.return_value = result

    agencies_result = MagicMock()
    agencies_result.data = [{"id": "ag-1"}]
    agencies_query = MagicMock()
    agencies_query.select.return_value = agencies_query
    agencies_query.eq.return_value = agencies_query
    agencies_query.execute.return_value = agencies_result

    narrative_result = MagicMock()
    narrative_result.data = []
    narrative_query = MagicMock()
    narrative_query.select.return_value = narrative_query
    narrative_query.in_.return_value = narrative_query
    narrative_query.execute.return_value = narrative_result

    tables = {"agencies": agencies_query, "incident_narrative_reports": narrative_query}
    db = MagicMock()
    db.table.side_effect = lambda name: tables.get(name, query)

    with patch("app.services.dispatch_service.get_supabase", return_value=db):
        out = dispatch_service.get_incident_history(
            {"id": "u1", "role": role, "agency_id": agency_id, "agency_type": "BFP"},
            **kwargs,
        )
    return out, query


class TestRecordFields:
    def test_the_page_query_selects_what_a_record_needs(self):
        _, query = _history()
        columns = query.select.call_args_list[0].args[0]
        for needed in ("record_number", "accepted_at"):
            assert needed in columns, f"{needed} missing from the history select"

    def test_the_page_query_selects_the_after_action_fields(self):
        """The Outcome column and the casualty tally on Incident Records read
        these off each row. They were once missing from the select, so every row
        came back without them and the column sat blank for months."""
        _, query = _history()
        columns = query.select.call_args_list[0].args[0]
        for needed in (
            "outcome", "outcome_notes", "casualties_injured",
            "casualties_fatal", "casualties_transported",
        ):
            assert needed in columns, f"{needed} missing from the history select"

    def test_the_select_does_not_ask_for_columns_that_do_not_exist(self):
        """latitude/longitude are fields of the request model, not columns —
        the point lives in one `location` column. Asking for them is Postgres
        42703 and a 500, and a mocked database cannot notice: this was found
        only by running the query against the real schema."""
        _, query = _history()
        columns = query.select.call_args_list[0].args[0]
        for phantom in ("latitude", "longitude"):
            assert phantom not in columns

    def test_the_responder_is_joined_by_name_not_just_id(self):
        """incidents has three foreign keys to users (reporter, responder,
        reviewer), so the join has to name its constraint or PostgREST answers
        with an ambiguity error and the endpoint 500s."""
        _, query = _history()
        columns = query.select.call_args_list[0].args[0]
        assert "incidents_assigned_responder_id_fkey" in columns

    def test_the_row_comes_back_with_the_new_fields(self):
        out, _ = _history()
        row = out["items"][0]
        assert row["record_number"] == "ZIR-2026-000123"
        assert row["responder"]["full_name"] == "Juan Dela Cruz"


class TestRecordLookup:
    def test_a_record_number_is_matched_as_an_uppercase_prefix(self):
        _, query = _history(record_no="zir-2026-0001")
        query.like.assert_any_call("record_number", "ZIR-2026-0001%")

    def test_surrounding_whitespace_is_ignored(self):
        _, query = _history(record_no="  ZIR-2026-000123 ")
        query.like.assert_any_call("record_number", "ZIR-2026-000123%")

    def test_without_a_record_number_no_lookup_filter_is_applied(self):
        _, query = _history()
        query.like.assert_not_called()

    def test_a_lookup_takes_over_from_the_time_window(self):
        """A record from last year has to be findable. Left under the default
        30-day window it would come back as 'no results' for a number that
        exists — the same trap the explicit date range already avoids."""
        _, query = _history(record_no="ZIR-2025-000010", days=30)
        query.gte.assert_not_called()
        query.lt.assert_not_called()

    def test_the_time_window_still_applies_without_a_lookup(self):
        _, query = _history(days=30)
        assert query.gte.called

    def test_every_window_query_sees_the_lookup(self):
        """Page, critical/resolved/cancelled counts share one builder, plus the
        response-time and station queries: if any skipped the filter the
        summary line would describe a different set than the table shows."""
        _, query = _history(record_no="ZIR-2026-000123")
        # main page + 3 head counts + response query + stations query
        assert query.like.call_count == 6


class TestAllTimeWindow:
    """`days=0` — the same All-time sentinel Operational Area's own
    get_operational_area uses — added 2026-09-19 so the dashboard's Period
    control offers the same five presets (7/30/90/365/All time) everywhere
    a date-range filter appears, not just on /geographic."""

    def test_days_zero_applies_no_time_filter(self):
        _, query = _history(days=0)
        query.gte.assert_not_called()
        query.lt.assert_not_called()

    def test_days_zero_still_returns_rows(self):
        out, _ = _history(days=0)
        assert out["total"] == 1

    def test_an_explicit_range_still_wins_over_days_zero(self):
        """days=0 must not be mistaken for "no range given" — an explicit
        date_from/date_to takes over from `days` exactly as it does from any
        other value, all-time included."""
        _, query = _history(days=0, date_from="2026-01-01", date_to="2026-01-31")
        query.gte.assert_any_call("created_at", "2026-01-01")
        assert query.lt.called

    def test_a_positive_days_window_is_unaffected(self):
        """Guards against a sign or off-by-one slip in the new `days <= 0`
        branch changing what a normal, already-working rolling window does."""
        _, query = _history(days=30)
        assert query.gte.called
        query.lt.assert_not_called()  # no upper bound on a rolling window


class TestDateWindowHelper:
    """Unit-level coverage of _date_window itself — the (since, until)
    resolver get_incident_history calls before building any query."""

    def test_zero_days_with_no_explicit_range_is_wide_open(self):
        from app.services.dispatch_service import _date_window
        assert _date_window(0, None, None) == (None, None)

    def test_negative_days_is_treated_the_same_as_zero(self):
        """Defensive: `ge=0` at the router stops a negative value from
        reaching here, but the service itself should not misbehave — e.g.
        computing a since in the FUTURE — if it ever does."""
        from app.services.dispatch_service import _date_window
        assert _date_window(-5, None, None) == (None, None)

    def test_a_positive_days_window_is_unchanged(self):
        from app.services.dispatch_service import _date_window
        since, until = _date_window(30, None, None)
        assert since is not None
        assert until is None

    def test_an_explicit_range_ignores_days_entirely(self):
        from app.services.dispatch_service import _date_window
        since, until = _date_window(0, "2026-03-01", "2026-03-15")
        assert since == "2026-03-01"
        assert until == "2026-03-16"  # exclusive: midnight of the day AFTER date_to


class TestLookupNeverWidensScope:
    def test_agency_admin_stays_pinned_to_their_agency(self):
        _, query = _history(role="agency_admin", agency_id="ag-1", record_no="ZIR-2026-000123")
        eq_calls = [c.args for c in query.eq.call_args_list]
        assert ("assigned_agency_id", "ag-1") in eq_calls

    def test_provincial_admin_stays_pinned_to_their_agency_type(self):
        _, query = _history(role="provincial_admin", agency_id=None, record_no="ZIR-2026-000123")
        in_calls = [c.args[0] for c in query.in_.call_args_list]
        assert "assigned_agency_id" in in_calls

    def test_an_agency_admin_with_no_agency_still_gets_nothing(self):
        out, _ = _history(role="agency_admin", agency_id=None, record_no="ZIR-2026-000123")
        assert out["items"] == []
        assert out["total"] == 0


@pytest.mark.parametrize("bad", ["ZIR%", "a b", "x'; drop table", "ZIR-2026-0001%25", "../etc"])
def test_a_malformed_record_number_is_refused_not_passed_to_the_database(bad):
    """The lookup builds a LIKE pattern, so a caller-supplied % or _ would act
    as a wildcard and turn a lookup into a scan. Only the characters a record
    number can contain get through."""
    with pytest.raises(ValueError):
        _history(record_no=bad)


class TestRecordPanelDetail:
    """The record panel opens through /dispatch/queue/{id}, not the history row."""

    def _detail(self):
        row = {
            "id": "i1", "record_number": "ZIR-2026-000123", "severity": "high",
            "assigned_agency_id": "ag-1", "assigned_responder_id": "r1",
            "responder": {"full_name": "Juan Dela Cruz", "badge_id": "B-1"},
            "stations": None, "users": None,
        }
        result = MagicMock()
        result.data = row
        query = MagicMock()
        for name in ("select", "eq", "order", "single"):
            getattr(query, name).return_value = query
        query.execute.return_value = result
        empty = MagicMock()
        empty.data = []
        other = MagicMock()
        for name in ("select", "eq", "order", "in_"):
            getattr(other, name).return_value = other
        other.execute.return_value = empty
        db = MagicMock()
        db.table.side_effect = lambda n: query if n == "incidents" else other
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            out = dispatch_service.get_incident_detail_admin(
                "i1", {"id": "u1", "role": "agency_admin", "agency_id": "ag-1"}
            )
        return out, query

    def test_the_responder_is_joined_by_name(self):
        _, query = self._detail()
        columns = query.select.call_args_list[0].args[0]
        assert "incidents_assigned_responder_id_fkey" in columns

    def test_the_record_number_reaches_the_panel(self):
        """Selected with `*`, so it needs no new column — this pins that the
        select is still a wildcard and nobody narrowed it to a column list that
        would silently drop the record number."""
        _, query = self._detail()
        assert query.select.call_args_list[0].args[0].startswith("*")

    def test_the_row_carries_the_responder_name(self):
        out, _ = self._detail()
        assert out["responder"]["full_name"] == "Juan Dela Cruz"


class TestOpenNow:
    def test_open_means_neither_closed_status(self):
        _, query = _history(status="open")
        query.not_.in_.assert_any_call("status", ["resolved", "cancelled"])
        # "open" is not a status a row can have, so it must never be an equality match.
        assert not any(c.args[:2] == ("status", "open") for c in query.eq.call_args_list)

    def test_a_real_status_is_still_an_exact_match(self):
        _, query = _history(status="resolved")
        query.eq.assert_any_call("status", "resolved")
        query.not_.in_.assert_not_called()
