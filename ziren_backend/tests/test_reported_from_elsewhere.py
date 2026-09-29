"""
Reporting an incident from somewhere else (migration 042).

The incident location (latitude/longitude) routes the report and is where a
crew goes. When the resident placed the incident on the map because they are
not at it, the app also sends where THEY are — stored separately so the
dispatcher sees the two differ. Before migration 042 is applied the columns
do not exist, and the report must still be saved.
"""

from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError

from app.models.incident import IncidentSubmitRequest, SosSubmitRequest
from app.services import incident_service
from app.services.incident_service import submit_incident, submit_sos

RESIDENT_UUID = "00000000-0000-0000-0000-000000000001"
INCIDENT_UUID = "11111111-0000-0000-0000-000000000001"
STATION_UUID = "bbbbbbbb-0000-0000-0000-000000000001"
AGENCY_UUID = "aaaaaaaa-0000-0000-0000-000000000001"

# Larrazabal (the incident) and Kawayan (where the caller is).
INCIDENT_AT = (11.5710, 124.4230)
REPORTER_AT = (11.6799, 124.3570)


def _row(**extra):
    row = {
        "id": INCIDENT_UUID, "reporter_id": RESIDENT_UUID,
        "station_id": STATION_UUID, "assigned_agency_id": AGENCY_UUID,
        "report_text": "[FIRE] Sunog sa Larrazabal, tawag ng kamag-anak",
        "location_address": "Larrazabal, Naval, Biliran",
        "status": "received", "severity": None, "suggested_agency_id": None,
        "signals": None, "signals_confidence": None, "submitted_via": "internet",
        "created_at": "2026-01-01T00:00:00+00:00", "updated_at": "2026-01-01T00:00:00+00:00",
        "dispatched_at": None, "resolved_at": None, "incident_category": "fire",
        "wizard_answers": None, "overlap_agencies": None,
        "landmark_note": "Larrazabal Elementary School", "victim_relationship": None,
        "nlp_review_needed": False,
    }
    row.update(extra)
    return row


def _db(insert_side_effect=None):
    """A Supabase mock: station lookup by id, and the incidents insert."""
    stations_t = MagicMock()
    stations_t.select.return_value.eq.return_value.single.return_value \
        .execute.return_value = MagicMock(data={"id": STATION_UUID, "agency_id": AGENCY_UUID})
    incidents_t = MagicMock()
    if insert_side_effect is not None:
        incidents_t.insert.return_value.execute.side_effect = insert_side_effect
    else:
        incidents_t.insert.return_value.execute.return_value = MagicMock(data=[_row()])

    def route(name):
        return {"stations": stations_t, "incidents": incidents_t}.get(name, MagicMock())

    db = MagicMock()
    db.table.side_effect = route
    db.incidents_t = incidents_t
    return db


def _request(**extra):
    body = {
        "report_text": "[FIRE] Sunog sa Larrazabal, tawag ng kamag-anak",
        "station_id": STATION_UUID,
        "incident_category": "fire",
        "landmark_note": "Larrazabal Elementary School",
        "latitude": INCIDENT_AT[0],
        "longitude": INCIDENT_AT[1],
    }
    body.update(extra)
    return IncidentSubmitRequest(**body)


def _inserted(db, call=-1):
    return db.incidents_t.insert.call_args_list[call].args[0]


@pytest.fixture(autouse=True)
def _quiet_side_effects():
    # Notifications and proximity alerts are not what these tests are about.
    with patch.object(incident_service.notification_service, "create_for_agency_role"), \
         patch.object(incident_service.proximity, "notify_nearby"):
        yield


def test_incident_location_stays_the_incident_and_reporter_is_stored_apart():
    db = _db()
    req = _request(
        reported_from_elsewhere=True,
        reporter_latitude=REPORTER_AT[0],
        reporter_longitude=REPORTER_AT[1],
        reporter_address="Kawayan, Biliran",
    )
    with patch.object(incident_service, "get_supabase", return_value=db):
        submit_incident(req, reporter_id=RESIDENT_UUID)

    payload = _inserted(db)
    # The crew goes to Larrazabal …
    assert payload["location"] == f"POINT({INCIDENT_AT[1]} {INCIDENT_AT[0]})"
    # … and the dispatcher learns the caller is in Kawayan.
    assert payload["reported_from_elsewhere"] is True
    assert payload["reporter_location"] == f"POINT({REPORTER_AT[1]} {REPORTER_AT[0]})"
    assert payload["reporter_address"] == "Kawayan, Biliran"
    assert payload["landmark_note"] == "Larrazabal Elementary School"


def test_an_ordinary_report_writes_no_reporter_columns():
    db = _db()
    with patch.object(incident_service, "get_supabase", return_value=db):
        submit_incident(_request(), reporter_id=RESIDENT_UUID)
    payload = _inserted(db)
    for col in incident_service.REPORTER_LOCATION_COLUMNS:
        assert col not in payload


def test_reporter_fields_are_ignored_unless_the_report_says_elsewhere():
    """Stray reporter coordinates without the flag must not mark the report."""
    db = _db()
    req = _request(reporter_latitude=REPORTER_AT[0], reporter_longitude=REPORTER_AT[1])
    with patch.object(incident_service, "get_supabase", return_value=db):
        submit_incident(req, reporter_id=RESIDENT_UUID)
    assert "reported_from_elsewhere" not in _inserted(db)


def test_before_migration_042_the_report_is_still_saved():
    missing = Exception(
        "{'code': 'PGRST204', 'message': \"Could not find the 'reported_from_elsewhere' "
        "column of 'incidents' in the schema cache\"}"
    )
    db = _db(insert_side_effect=[missing, MagicMock(data=[_row()])])
    req = _request(
        reported_from_elsewhere=True,
        reporter_latitude=REPORTER_AT[0],
        reporter_longitude=REPORTER_AT[1],
    )
    with patch.object(incident_service, "get_supabase", return_value=db):
        result = submit_incident(req, reporter_id=RESIDENT_UUID)

    assert str(result.id) == INCIDENT_UUID
    assert db.incidents_t.insert.call_count == 2
    retried = _inserted(db, call=1)
    for col in incident_service.REPORTER_LOCATION_COLUMNS:
        assert col not in retried
    # The incident itself is untouched by the retry.
    assert retried["location"] == f"POINT({INCIDENT_AT[1]} {INCIDENT_AT[0]})"


def test_an_unrelated_insert_failure_is_not_retried():
    from fastapi import HTTPException

    db = _db(insert_side_effect=[Exception("connection reset")])
    req = _request(reported_from_elsewhere=True, reporter_latitude=1.0, reporter_longitude=2.0)
    with patch.object(incident_service, "get_supabase", return_value=db), \
         pytest.raises(HTTPException) as exc:
        submit_incident(req, reporter_id=RESIDENT_UUID)
    assert exc.value.status_code == 500
    assert db.incidents_t.insert.call_count == 1


@pytest.mark.parametrize("field,value", [
    ("reporter_latitude", 91.0),
    ("reporter_longitude", -181.0),
])
def test_reporter_coordinates_are_validated(field, value):
    with pytest.raises(ValidationError):
        _request(reported_from_elsewhere=True, **{field: value})


def test_reporter_address_is_clamped_not_rejected():
    req = _request(reported_from_elsewhere=True, reporter_address="x" * 400)
    assert len(req.reporter_address) == 300


# ── SOS carries the landmark the app found for it ────────────────────────────

def test_sos_accepts_and_stores_an_automatic_landmark():
    req = SosSubmitRequest(
        latitude=11.5836, longitude=124.4063,
        location_address="Caraycaray, Naval, Biliran",
        landmark_note="Near Naval Central School",
    )
    captured = {}

    def fake_create(**kwargs):
        captured.update(kwargs)
        return _row(submitted_via="sos", report_text="SOS", sos_flagged=False)

    users_t = MagicMock()
    users_t.select.return_value.eq.return_value.single.return_value.execute.return_value = MagicMock(data={
        "id": RESIDENT_UUID, "role": "resident", "sos_warning_count": 0,
        "sos_suspended_until": None, "sos_last_submitted_at": None, "is_verified": True,
    })
    stations_t = MagicMock()
    chain = stations_t.select.return_value
    chain.eq.return_value = chain
    chain.limit.return_value = chain
    chain.execute.return_value = MagicMock(data=[{
        "id": STATION_UUID, "agency_id": AGENCY_UUID, "name": "BFP Naval",
        "location": "POINT(124.4063 11.5836)",
        "agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Naval"},
    }])
    db = MagicMock()
    db.table.side_effect = lambda n: {"users": users_t, "stations": stations_t}.get(n, MagicMock())

    with patch.object(incident_service, "get_supabase", return_value=db), \
         patch.object(incident_service, "_create_incident_row", side_effect=fake_create):
        submit_sos(req, reporter_id=RESIDENT_UUID)

    assert captured["landmark_note"] == "Near Naval Central School"
    assert captured["location_address"] == "Caraycaray, Naval, Biliran"
