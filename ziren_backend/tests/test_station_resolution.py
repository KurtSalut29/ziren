"""
Regression tests for nearest/fallback station resolution.

Background — the bug these guard against:

`_resolve_nearest_station()` falls back to the Naval MDRRMO station when an
SOS arrives without GPS. The fallback query filtered on an EMBEDDED resource:

    .select("... agencies(agency_type, municipality, name)")
    .eq("agencies.municipality", "Naval")
    .eq("agencies.agency_type", "MDRRMO")

In PostgREST a condition on an embedded resource does NOT filter the parent
rows unless the embed is an inner join (`agencies!inner(...)`). With a plain
embed the API returns every active station and merely sets `agencies` to null
on rows that don't match. Combined with `.limit(1)`, the query returned an
arbitrary station — verified against the live database as "BFP Naval Main
Station" with `agencies: None` — so a GPS-less SOS was routed to the WRONG
agency, and `_extract_station_tuple()`'s `or {}` coerced the missing embed
into agency_type="" / municipality="", hiding the failure behind a 201.

These tests cannot be written against a MagicMock database, because a mock
returns whatever it is told to return and therefore cannot reproduce
PostgREST's join semantics — which is precisely why the existing mocked SOS
tests passed while production was misrouting. They assert on the query source
and on the fail-loud contract instead.
"""

import inspect

import pytest
from fastapi import HTTPException

from app.services import incident_service


# ── The embed must be an inner join ───────────────────────────────────────────

def test_fallback_station_query_uses_inner_join():
    """
    The fallback query must use `agencies!inner(...)`. Without it, PostgREST
    returns non-matching stations with a null embed instead of excluding them.
    """
    src = inspect.getsource(incident_service._resolve_nearest_station)

    assert "agencies!inner(" in src, (
        "The fallback station query must embed agencies with an INNER join "
        "(`agencies!inner(...)`). A plain `agencies(...)` embed does not "
        "filter parent rows, so .limit(1) returns an arbitrary station."
    )


def test_no_plain_embed_is_filtered_in_station_resolution():
    """
    Guard the general pattern: if any query in this function filters on
    `agencies.<field>`, its embed must be an inner join.
    """
    src = inspect.getsource(incident_service._resolve_nearest_station)

    filters_on_embed = '.eq("agencies.' in src
    if filters_on_embed:
        assert "agencies!inner(" in src, (
            "A query filters on an embedded `agencies.<field>` but does not "
            "use `agencies!inner(...)`. PostgREST will not filter parent rows."
        )


# ── Missing embed must fail loudly, not degrade to empty strings ──────────────

def test_extract_station_tuple_raises_when_agency_embed_missing():
    """
    A row whose `agencies` embed is null must raise, not silently produce
    agency_type="". Coercing to empty strings is what let the misrouting go
    unnoticed in production.
    """
    row = {
        "id": "bbbbbbbb-0000-0000-0000-000000000001",
        "agency_id": "aaaaaaaa-0000-0000-0000-000000000001",
        "name": "BFP Naval Main Station",
        "agencies": None,           # what the broken query actually returned
    }

    with pytest.raises(HTTPException) as exc:
        incident_service._extract_station_tuple(row)

    assert exc.value.status_code == 503


def test_extract_station_tuple_raises_when_agency_key_absent():
    """Same contract when the key is missing entirely rather than null."""
    row = {
        "id": "bbbbbbbb-0000-0000-0000-000000000001",
        "agency_id": "aaaaaaaa-0000-0000-0000-000000000001",
        "name": "BFP Naval Main Station",
    }

    with pytest.raises(HTTPException) as exc:
        incident_service._extract_station_tuple(row)

    assert exc.value.status_code == 503


def test_extract_station_tuple_returns_populated_agency_fields():
    """The happy path must still return agency_type and municipality."""
    row = {
        "id": "bbbbbbbb-0000-0000-0000-000000000001",
        "agency_id": "aaaaaaaa-0000-0000-0000-000000000001",
        "name": "MDRRMO Naval Office",
        "agencies": {
            "agency_type": "MDRRMO",
            "municipality": "Naval",
            "name": "MDRRMO Naval",
        },
    }

    station_id, agency_id, station_name, agency_type, municipality = \
        incident_service._extract_station_tuple(row)

    assert station_name == "MDRRMO Naval Office"
    assert agency_type  == "MDRRMO"
    assert municipality == "Naval"
