"""
assist_request_service — cross-agency "please help on this incident"
requests. See docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import assist_request_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"          # requesting agency
OTHER_AGENCY_ID = "b0000002-0000-0000-0000-000000000002"    # requested agency
THIRD_AGENCY_ID = "b0000003-0000-0000-0000-000000000003"    # different municipality
INCIDENT_ID = "c0000003-0000-0000-0000-000000000003"

AGENCY_ADMIN = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}
OTHER_AGENCY_ADMIN = {"id": "e0000005-0000-0000-0000-000000000005", "role": "agency_admin", "agency_id": OTHER_AGENCY_ID}


def _incident_row(assigned_agency_id=AGENCY_ID, inc_status="received"):
    return {
        "id": INCIDENT_ID, "assigned_agency_id": assigned_agency_id, "status": inc_status,
        "incident_category": "fire", "severity": "high", "location_address": "Brgy 1, Naval",
    }


def _mock_db(incident_row=None, own_agency_row=None, candidates_rows=None):
    """
    Builds a MagicMock whose .table(name) branches by table name — plain
    incident_notes_service-style single-chain mocks don't work here because
    this service queries TWO different tables (incidents, then agencies) in
    one function, and each needs its own canned .execute() result.
    """
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incidents":
            result = MagicMock()
            result.data = incident_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "agencies":
            own_result = MagicMock()
            own_result.data = own_agency_row
            cand_result = MagicMock()
            cand_result.data = candidates_rows or []
            # own-agency lookup: .select().eq("id", ...).maybe_single().execute()
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = own_result
            # candidates lookup: .select().eq("municipality",...).eq("is_active",True).neq("id",...).execute()
            m.select.return_value.eq.return_value.eq.return_value.neq.return_value.execute.return_value = cand_result
        return m

    db.table.side_effect = table
    return db


def test_owns_incident_ok_for_the_assigned_agency():
    db = _mock_db(incident_row=_incident_row())
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        incident = assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert incident["assigned_agency_id"] == AGENCY_ID


def test_owns_incident_forbidden_for_a_different_agency():
    db = _mock_db(incident_row=_incident_row(assigned_agency_id=OTHER_AGENCY_ID))
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 403


def test_owns_incident_404_when_incident_missing():
    db = _mock_db(incident_row=None)
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service._assert_owns_incident(db, INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 404


def test_list_candidate_agencies_excludes_self_and_scopes_to_municipality():
    db = _mock_db(
        incident_row=_incident_row(),
        own_agency_row={"id": AGENCY_ID, "municipality": "Naval"},
        candidates_rows=[{"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval", "agency_type": "MDRRMO", "contact_number": "0917", "email": "m@naval.gov.ph"}],
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.list_candidate_agencies(INCIDENT_ID, AGENCY_ADMIN)
    assert result == [{"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval", "agency_type": "MDRRMO", "contact_number": "0917", "email": "m@naval.gov.ph"}]


def test_list_candidate_agencies_forbidden_for_a_different_agency():
    db = _mock_db(incident_row=_incident_row(assigned_agency_id=OTHER_AGENCY_ID))
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.list_candidate_agencies(INCIDENT_ID, AGENCY_ADMIN)
    assert exc.value.status_code == 403


def _mock_db_for_create(incident_row, own_agency_row, target_agency_row, dup_rows, inserted_request, inserted_message):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incidents":
            result = MagicMock()
            result.data = incident_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "agencies":
            target_result = MagicMock()
            target_result.data = target_agency_row
            # target-agency lookup: .select().eq("id",...).maybe_single().execute()
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = target_result
            # name-backfill lookup inside _hydrate_request: .select().in_("id",...).execute()
            names_result = MagicMock()
            names_result.data = [
                {"id": incident_row["assigned_agency_id"], "name": "Requesting Agency"},
                {"id": target_agency_row["id"], "name": target_agency_row["name"]},
            ] if target_agency_row else []
            m.select.return_value.in_.return_value.execute.return_value = names_result
        elif name == "incident_assist_requests":
            dup_result = MagicMock()
            dup_result.data = dup_rows
            m.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = dup_result
            insert_result = MagicMock()
            insert_result.data = [inserted_request]
            m.insert.return_value.execute.return_value = insert_result
        elif name == "incident_assist_messages":
            insert_result = MagicMock()
            insert_result.data = [inserted_message]
            m.insert.return_value.execute.return_value = insert_result
        return m

    db.table.side_effect = table
    return db


def test_create_request_happy_path_inserts_request_and_opening_message_and_notifies():
    request_row = {
        "id": "f0000006-0000-0000-0000-000000000006", "incident_id": INCIDENT_ID,
        "requesting_agency_id": AGENCY_ID, "requested_agency_id": OTHER_AGENCY_ID,
        "overlap_flag": "fire", "status": "pending", "requested_by": AGENCY_ADMIN["id"],
        "responded_by": None, "created_at": "2026-09-20T00:00:00Z", "responded_at": None,
    }
    db = _mock_db_for_create(
        incident_row=_incident_row(),
        own_agency_row=None,
        target_agency_row={"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval", "agency_type": "MDRRMO", "municipality": "Naval", "is_active": True},
        dup_rows=[],
        inserted_request=request_row,
        inserted_message={"id": "g1", "request_id": request_row["id"], "sender_agency_id": AGENCY_ID, "sender_id": AGENCY_ADMIN["id"], "body": "Need crowd control", "created_at": "2026-09-20T00:00:00Z"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db), \
         patch("app.services.assist_request_service.create_for_agency_role") as mock_notify:
        result = assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "Need crowd control", "fire", AGENCY_ADMIN)

    assert result["id"] == request_row["id"]
    assert result["status"] == "pending"
    assert result["can_respond"] is False  # the REQUESTER is never the one who can respond
    mock_notify.assert_called_once()
    assert mock_notify.call_args.args[0] == OTHER_AGENCY_ID
    assert mock_notify.call_args.args[1] == "agency_admin"
    assert mock_notify.call_args.kwargs["is_important"] is True


def test_create_request_rejects_targeting_own_agency():
    db = _mock_db_for_create(_incident_row(), None, None, [], {}, {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, AGENCY_ID, "help", None, AGENCY_ADMIN)
    assert exc.value.status_code == 400


def test_create_request_rejects_empty_message():
    db = _mock_db_for_create(_incident_row(), None, None, [], {}, {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "   ", None, AGENCY_ADMIN)
    assert exc.value.status_code == 422


def test_create_request_rejects_inactive_target():
    db = _mock_db_for_create(
        _incident_row(), None,
        target_agency_row={"id": OTHER_AGENCY_ID, "name": "X", "agency_type": "MDRRMO", "municipality": "Naval", "is_active": False},
        dup_rows=[], inserted_request={}, inserted_message={},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "help", None, AGENCY_ADMIN)
    assert exc.value.status_code == 400


def test_create_request_rejects_duplicate_pending():
    db = _mock_db_for_create(
        _incident_row(), None,
        target_agency_row={"id": OTHER_AGENCY_ID, "name": "X", "agency_type": "MDRRMO", "municipality": "Naval", "is_active": True},
        dup_rows=[{"id": "existing"}], inserted_request={}, inserted_message={},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.create_request(INCIDENT_ID, OTHER_AGENCY_ID, "help", None, AGENCY_ADMIN)
    assert exc.value.status_code == 409


def _request_row(status_="pending", requesting=AGENCY_ID, requested=OTHER_AGENCY_ID):
    return {
        "id": "h0000007-0000-0000-0000-000000000007", "incident_id": INCIDENT_ID,
        "requesting_agency_id": requesting, "requested_agency_id": requested,
        "overlap_flag": None, "status": status_, "requested_by": AGENCY_ADMIN["id"],
        "responded_by": None, "created_at": "2026-09-20T00:00:00Z", "responded_at": None,
    }


def _mock_db_for_list(rows, agencies_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            result = MagicMock()
            result.data = rows
            m.select.return_value.eq.return_value.order.return_value.execute.return_value = result
        elif name == "agencies":
            result = MagicMock()
            result.data = agencies_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_list_for_agency_received_scope_filters_by_requested_agency_id():
    row = _request_row()
    db = _mock_db_for_list(
        rows=[row],
        agencies_rows=[{"id": AGENCY_ID, "name": "BFP Naval"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval"}],
        incidents_rows=[{"id": INCIDENT_ID, "incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"}],
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.list_for_agency(OTHER_AGENCY_ADMIN, "received")
    assert len(result) == 1
    assert result[0]["requesting_agency_name"] == "BFP Naval"
    assert result[0]["can_respond"] is True  # OTHER_AGENCY_ADMIN is the requested party, status is pending


def test_list_for_agency_rejects_bad_scope():
    db = _mock_db_for_list([], [], [])
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.list_for_agency(AGENCY_ADMIN, "everything")
    assert exc.value.status_code == 422


def _mock_db_for_thread(request_row, messages_rows, agencies_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            result = MagicMock()
            result.data = request_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "incident_assist_messages":
            result = MagicMock()
            result.data = messages_rows
            m.select.return_value.eq.return_value.order.return_value.execute.return_value = result
        elif name == "agencies":
            result = MagicMock()
            result.data = agencies_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_get_thread_marks_own_agencys_messages_mine():
    db = _mock_db_for_thread(
        request_row=_request_row(),
        messages_rows=[
            {"id": "m1", "request_id": "h1", "sender_agency_id": AGENCY_ID, "sender_id": "x", "body": "need help", "created_at": "t1", "users": {"full_name": "Alex"}},
            {"id": "m2", "request_id": "h1", "sender_agency_id": OTHER_AGENCY_ID, "sender_id": "y", "body": "on our way", "created_at": "t2", "users": {"full_name": "Bea"}},
        ],
        agencies_rows=[{"id": AGENCY_ID, "name": "BFP"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO"}],
        incidents_rows={"incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.get_thread("h1", AGENCY_ADMIN)
    assert result["messages"][0]["mine"] is True
    assert result["messages"][1]["mine"] is False
    assert result["messages"][0]["sender_name"] == "Alex"


def test_get_thread_forbidden_for_a_non_party_agency():
    third_admin = {"id": "z", "role": "agency_admin", "agency_id": THIRD_AGENCY_ID}
    db = _mock_db_for_thread(_request_row(), [], [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.get_thread("h1", third_admin)
    assert exc.value.status_code == 403


def _mock_db_for_post_message(request_row, incident_status, inserted_message):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            result = MagicMock()
            result.data = request_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = {"status": incident_status}
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        elif name == "incident_assist_messages":
            result = MagicMock()
            result.data = [inserted_message]
            m.insert.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_post_message_happy_path():
    inserted = {"id": "m3", "request_id": "h1", "sender_agency_id": AGENCY_ID, "sender_id": AGENCY_ADMIN["id"], "body": "2 units", "created_at": "t3"}
    db = _mock_db_for_post_message(_request_row(), "received", inserted)
    with patch("app.services.assist_request_service.get_supabase", return_value=db), \
         patch("app.services.assist_request_service.create_for_agency_role") as mock_notify:
        result = assist_request_service.post_message("h1", "2 units", AGENCY_ADMIN)
    assert result["body"] == "2 units"
    assert result["mine"] is True
    mock_notify.assert_not_called()


def test_post_message_rejects_empty_body():
    db = _mock_db_for_post_message(_request_row(), "received", {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.post_message("h1", "   ", AGENCY_ADMIN)
    assert exc.value.status_code == 422


def test_post_message_rejected_once_incident_resolved():
    db = _mock_db_for_post_message(_request_row(), "resolved", {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.post_message("h1", "still there?", AGENCY_ADMIN)
    assert exc.value.status_code == 409


def test_post_message_forbidden_for_a_non_party_agency():
    third_admin = {"id": "z", "role": "agency_admin", "agency_id": THIRD_AGENCY_ID}
    db = _mock_db_for_post_message(_request_row(), "received", {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.post_message("h1", "hi", third_admin)
    assert exc.value.status_code == 403


def _mock_db_for_set_status(request_row, updated_row, agencies_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "incident_assist_requests":
            get_result = MagicMock()
            get_result.data = request_row
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = get_result
            upd_result = MagicMock()
            upd_result.data = [updated_row]
            m.update.return_value.eq.return_value.execute.return_value = upd_result
        elif name == "agencies":
            result = MagicMock()
            result.data = agencies_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_set_status_acknowledged_by_requested_agency_notifies_requester():
    row = _request_row()
    updated = {**row, "status": "acknowledged", "responded_by": OTHER_AGENCY_ADMIN["id"], "responded_at": "t9"}
    db = _mock_db_for_set_status(
        row, updated,
        agencies_rows=[{"id": AGENCY_ID, "name": "BFP"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO"}],
        incidents_rows={"incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db), \
         patch("app.services.assist_request_service.create_for_agency_role") as mock_notify:
        result = assist_request_service.set_status("h1", "acknowledged", OTHER_AGENCY_ADMIN)
    assert result["status"] == "acknowledged"
    mock_notify.assert_called_once()
    assert mock_notify.call_args.args[0] == AGENCY_ID  # notifies the ORIGINAL requester's agency


def test_set_status_rejects_invalid_value():
    db = _mock_db_for_set_status(_request_row(), {}, [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.set_status("h1", "maybe", OTHER_AGENCY_ADMIN)
    assert exc.value.status_code == 422


def test_set_status_forbidden_for_the_requesting_agency_itself():
    db = _mock_db_for_set_status(_request_row(), {}, [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.set_status("h1", "acknowledged", AGENCY_ADMIN)
    assert exc.value.status_code == 403


def test_set_status_rejects_a_second_response():
    db = _mock_db_for_set_status(_request_row(status_="declined"), {}, [], {})
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.set_status("h1", "acknowledged", OTHER_AGENCY_ADMIN)
    assert exc.value.status_code == 409


# ── provincial_admin oversight read (migration 037) ─────────────────────

PROVINCIAL_ADMIN = {"id": "p0000009-0000-0000-0000-000000000009", "role": "provincial_admin", "agency_type": "BFP"}


def _mock_db_for_provincial_list(agency_ids_rows, requests_rows, agencies_names_rows, incidents_rows):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "agencies":
            ids_result = MagicMock()
            ids_result.data = agency_ids_rows
            m.select.return_value.eq.return_value.execute.return_value = ids_result
            names_result = MagicMock()
            names_result.data = agencies_names_rows
            m.select.return_value.in_.return_value.execute.return_value = names_result
        elif name == "incident_assist_requests":
            result = MagicMock()
            result.data = requests_rows
            m.select.return_value.or_.return_value.order.return_value.execute.return_value = result
        elif name == "incidents":
            result = MagicMock()
            result.data = incidents_rows
            m.select.return_value.in_.return_value.execute.return_value = result
        return m

    db.table.side_effect = table
    return db


def test_list_for_agency_provincial_admin_sees_both_sides_of_own_agency_type():
    row = _request_row()  # requesting=AGENCY_ID, requested=OTHER_AGENCY_ID, pending
    db = _mock_db_for_provincial_list(
        agency_ids_rows=[{"id": AGENCY_ID}],
        requests_rows=[row],
        agencies_names_rows=[{"id": AGENCY_ID, "name": "BFP Naval"}, {"id": OTHER_AGENCY_ID, "name": "MDRRMO Naval"}],
        incidents_rows=[{"id": INCIDENT_ID, "incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"}],
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.list_for_agency(PROVINCIAL_ADMIN, None)
    assert len(result) == 1
    assert result[0]["can_respond"] is False  # oversight is read-only, never an actor


def test_list_for_agency_provincial_admin_with_no_agencies_of_their_type_returns_empty():
    db = _mock_db_for_provincial_list(agency_ids_rows=[], requests_rows=[], agencies_names_rows=[], incidents_rows=[])
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.list_for_agency(PROVINCIAL_ADMIN, None)
    assert result == []


def test_get_thread_allows_provincial_admin_of_a_party_agency_type():
    db = _mock_db_for_thread(
        request_row=_request_row(),
        messages_rows=[],
        agencies_rows=[{"id": AGENCY_ID, "agency_type": "BFP"}, {"id": OTHER_AGENCY_ID, "agency_type": "MDRRMO"}],
        incidents_rows={"incident_category": "fire", "severity": "high", "location_address": "Brgy 1", "status": "received"},
    )
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        result = assist_request_service.get_thread("h1", PROVINCIAL_ADMIN)
    assert result["request"]["can_respond"] is False


def test_get_thread_forbidden_for_provincial_admin_of_a_different_agency_type():
    db = _mock_db_for_thread(
        request_row=_request_row(),
        messages_rows=[],
        agencies_rows=[{"id": AGENCY_ID, "agency_type": "BFP"}, {"id": OTHER_AGENCY_ID, "agency_type": "MDRRMO"}],
        incidents_rows={},
    )
    other_type_admin = {"id": "p0000010-0000-0000-0000-000000000010", "role": "provincial_admin", "agency_type": "PNP"}
    with patch("app.services.assist_request_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            assist_request_service.get_thread("h1", other_type_admin)
    assert exc.value.status_code == 403
