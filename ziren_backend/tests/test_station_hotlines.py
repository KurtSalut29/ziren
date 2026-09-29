"""
Station hotlines (agencies.contact_number, migration 042).

Residents call these from the app — offline too — so an agency admin must not
be able to save something that is not a dialable number, and every official
value migration 042 writes must pass the same check.
"""

import re
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.routers.stations import AgencyProfileUpdateRequest

MIGRATION = Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "042_station_hotlines_and_reporter_location.sql"


def _official_values() -> dict[str, str]:
    sql = MIGRATION.read_text(encoding="utf-8")
    return dict(re.findall(r"WHEN '([0-9a-f-]{36})' THEN '([^']*)'", sql))


def test_migration_sets_all_21_stations():
    values = _official_values()
    assert len(values) == 21
    # Every id in the CASE is also in the WHERE list, so none is skipped.
    sql = MIGRATION.read_text(encoding="utf-8")
    where = sql[sql.index("WHERE id IN"):]
    for agency_id in values:
        assert agency_id in where


@pytest.mark.parametrize("agency_id,value", sorted(_official_values().items()))
def test_every_official_value_is_accepted(agency_id, value):
    assert AgencyProfileUpdateRequest(contact_number=value).contact_number == value


@pytest.mark.parametrize("value", [
    "0905-480-1417",
    "Globe: 0955-723-6300; Smart: 0948-024-3466; Landline: (053) 500-9546",
    "09125878288/09173206105",
    "MDRRMO/EMS: 0969-189-2388",
    "+63 921 555 3961",
    "",
])
def test_accepts_dialable_numbers(value):
    AgencyProfileUpdateRequest(contact_number=value)


@pytest.mark.parametrize("value", [
    "N/A",
    "call the office",
    "Globe: 0955-723-6300; ask for Juan",
    "123",
    "0" * 20,
    "0905-480-1417; " * 20,
])
def test_rejects_what_cannot_be_dialled(value):
    with pytest.raises(ValidationError):
        AgencyProfileUpdateRequest(contact_number=value)
