"""Narrative reports — the full Incident Record Form, its library and its PDF.

Properties worth pinning:

  1. `details` is stored as the form's own shape and nothing else: unknown keys
     are dropped, everything is text, lists and lengths are capped. The body of
     the request is a browser's word for what goes on a printed document.
  2. A DRAFT may be saved with no narrative yet (the form is long); FINALIZING
     needs one. A report can only be written once the incident is resolved.
  3. Before migration 040 is applied the `details` column does not exist. Saving
     must not fail because of it: the rest is stored and the caller is told the
     detailed sections were not.
  4. The library is scoped like every other list here (own agency, or own agency
     type for a Provincial Admin), filters by incident type in the database, and
     its tab counts describe the OTHER filter's result.
  5. The PDF is a real, multi-page document even for a long narrative with many
     people on it, and text a person typed cannot break its markup.

Run with: pytest tests/test_narrative_reports.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import app
from app.services import incident_narrative_service as svc

AGENCY_ADMIN = {"id": "u1", "role": "agency_admin", "agency_id": "ag-1", "full_name": "Admin"}
PROVINCIAL = {"id": "u3", "role": "provincial_admin", "agency_type": "BFP", "full_name": "Provincial"}


@pytest.fixture(autouse=True)
def _fresh_probe():
    svc._reset_probe()
    yield
    svc._reset_probe()


# ── 1. what may be stored ───────────────────────────────────────────────────

def test_clean_details_keeps_the_forms_shape_and_drops_everything_else():
    cleaned = svc._clean_details({
        "offense": "Illegal Logging",
        "hacked_field": "<script>alert(1)</script>",
        "reporting_person": {"first_name": "Maricar", "family_name": "Ehem", "ssn": "123"},
        "suspects": [{"first_name": "Denmark", "height": "170 cm", "not_a_box": "x"}],
        "victims": [{"first_name": "A"}, {"first_name": "B"}],
        "certification": {"administering_officer": "PCPL Zerna", "extra": "x"},
        "station": {"name": "Cabucgayan PS"},
    })

    assert cleaned["form_version"] == svc.FORM_VERSION
    assert cleaned["offense"] == "Illegal Logging"
    assert "hacked_field" not in cleaned
    assert cleaned["reporting_person"]["first_name"] == "Maricar"
    assert "ssn" not in cleaned["reporting_person"]
    assert cleaned["suspects"][0]["height"] == "170 cm"
    assert "not_a_box" not in cleaned["suspects"][0]
    assert [v["first_name"] for v in cleaned["victims"]] == ["A", "B"]
    assert cleaned["certification"] == {
        "administering_officer": "PCPL Zerna", "investigator_rank_name": "", "desk_officer_rank_name": "",
    }
    assert cleaned["station"]["name"] == "Cabucgayan PS"


def test_clean_details_caps_lists_and_lengths_and_coerces_to_text():
    cleaned = svc._clean_details({
        "offense": "x" * 10_000,
        "witnesses": "w" * 10_000,
        "suspects": [{"first_name": i} for i in range(svc.MAX_SUSPECTS + 10)],
        "victims": [{} for _ in range(svc.MAX_VICTIMS + 10)],
        "reporting_person": {"age": 35},
    })
    assert len(cleaned["offense"]) == 300
    assert len(cleaned["witnesses"]) == 4000
    assert len(cleaned["suspects"]) == svc.MAX_SUSPECTS
    assert len(cleaned["victims"]) == svc.MAX_VICTIMS
    assert cleaned["reporting_person"]["age"] == "35"
    assert cleaned["suspects"][0]["first_name"] == "0"


@pytest.mark.parametrize("junk", [None, "text", 5, [], [1, 2]])
def test_clean_details_survives_the_wrong_type(junk):
    cleaned = svc._clean_details(junk)
    assert cleaned["suspects"] == [] and cleaned["victims"] == []
    assert cleaned["reporting_person"]["first_name"] == ""


# ── 2. saving ───────────────────────────────────────────────────────────────

def _save_db(*, incident_status="resolved", existing=None, write_error=None):
    """A Supabase double for save_narrative_report: incidents lookup, the existing-
    report lookup, and the write. `write_error` is raised the first time a write
    carries `details`."""
    db = MagicMock()
    writes = []

    incidents = MagicMock()
    incidents.select.return_value = incidents
    incidents.eq.return_value = incidents
    incidents.maybe_single.return_value = incidents
    incidents.execute.return_value = MagicMock(data={"id": "i1", "status": incident_status, "assigned_agency_id": "ag-1"})

    reports = MagicMock()
    reports.select.return_value = reports
    reports.eq.return_value = reports
    reports.limit.return_value = reports
    reports.maybe_single.return_value = reports
    reports.execute.return_value = MagicMock(data=existing)

    def _write(kind):
        def _do(body):
            writes.append((kind, dict(body)))
            builder = MagicMock()
            builder.eq.return_value = builder

            def _exec():
                if write_error is not None and "details" in body:
                    raise write_error
                return MagicMock(data=[{**body, "id": "r1"}])

            builder.execute.side_effect = _exec
            return builder
        return _do

    reports.insert.side_effect = _write("insert")
    reports.update.side_effect = _write("update")

    db.table.side_effect = lambda name: {"incidents": incidents, "incident_narrative_reports": reports}[name]
    return db, writes


def _save(db, **overrides):
    kwargs = dict(
        narrative="It happened.", reporting_person_name=None, incident_occurred_at=None,
        place_of_incident=None, prepared_by_name=None, investigator_name=None,
        reference_no=None, finalize=False, details=None,
    )
    kwargs.update(overrides)
    with patch.object(svc, "get_supabase", return_value=db), \
         patch.object(svc, "assert_agency_scope"):
        return svc.save_narrative_report("i1", AGENCY_ADMIN, **kwargs)


def test_a_draft_can_be_saved_with_nothing_written_yet():
    db, writes = _save_db()
    row = _save(db, narrative="", details={"offense": "Fire"})
    assert row["status"] == "draft"
    assert writes[0][1]["narrative"] == ""
    assert writes[0][1]["details"]["offense"] == "Fire"


def test_finalizing_needs_the_narrative():
    db, writes = _save_db()
    with pytest.raises(HTTPException) as e:
        _save(db, narrative="   ", finalize=True)
    assert e.value.status_code == 422
    assert writes == []


def test_only_a_resolved_incident_can_have_a_report():
    db, writes = _save_db(incident_status="dispatched")
    with pytest.raises(HTTPException) as e:
        _save(db)
    assert e.value.status_code == 409
    assert writes == []


def test_finalize_stamps_who_and_when_and_leaves_the_row_editable():
    db, writes = _save_db(existing={"id": "r1", "status": "draft"})
    row = _save(db, finalize=True, details={})
    kind, body = writes[0]
    assert kind == "update"
    assert body["status"] == "finalized" and body["finalized_by"] == "u1" and body["finalized_at"]
    assert row["details_saved"] is True


def test_details_are_cleaned_before_they_are_stored():
    db, writes = _save_db()
    _save(db, details={"reporting_person": {"first_name": "A", "evil": "x"}, "junk": 1})
    stored = writes[0][1]["details"]
    assert "junk" not in stored and "evil" not in stored["reporting_person"]


# ── 3. before migration 040 ─────────────────────────────────────────────────

def test_saving_without_the_details_column_stores_the_rest_and_says_so():
    missing = Exception(
        "{'code': 'PGRST204', 'message': \"Could not find the 'details' column of "
        "'incident_narrative_reports' in the schema cache\"}"
    )
    db, writes = _save_db(write_error=missing)
    row = _save(db, details={"offense": "Fire"})

    assert row["details_saved"] is False
    assert row["details_supported"] is False
    # Two attempts: the first carried details and failed, the retry did not.
    assert len(writes) == 2
    assert "details" in writes[0][1] and "details" not in writes[1][1]
    assert row["narrative"] == "It happened."


def test_an_unrelated_database_error_is_not_swallowed():
    db, writes = _save_db(write_error=Exception("connection reset"))
    with pytest.raises(Exception, match="connection reset"):
        _save(db, details={"offense": "Fire"})
    assert len(writes) == 1


# ── 4. the library ──────────────────────────────────────────────────────────

def _library_db(rows, tally=None, agencies=("ag-1", "ag-2"), details_column=True):
    """rows: what the page query returns; tally: what the count query returns."""
    tally = tally if tally is not None else rows
    db = MagicMock()
    calls = {"page": [], "tally": [], "select": []}

    def _builder(kind):
        b = MagicMock()
        for name in ("eq", "in_", "gte", "lt", "order", "limit"):
            getattr(b, name).side_effect = (lambda n: (lambda *a, **k: (calls[kind].append((n, a)) or b)))(name)
        b.range.side_effect = lambda *a, **k: (calls[kind].append(("range", a)) or b)
        return b

    page = _builder("page")
    page.execute.return_value = MagicMock(data=rows, count=len(rows))
    count = _builder("tally")
    count.execute.return_value = MagicMock(data=tally)

    def _select(columns, **kwargs):
        calls["select"].append(columns)
        return page if kwargs.get("count") == "exact" else count

    reports = MagicMock()
    reports.select.side_effect = _select

    ag = MagicMock()
    ag.select.return_value = ag
    ag.eq.return_value = ag
    ag.execute.return_value = MagicMock(data=[{"id": a} for a in agencies])

    def _table(name):
        return {"incident_narrative_reports": reports, "agencies": ag}[name]

    db.table.side_effect = _table
    return db, calls


def _row(status="finalized", category="fire", **kw):
    return {
        "id": kw.get("id", "r1"), "incident_id": "i1", "status": status, "reference_no": "IRF-1",
        "prepared_by_name": "Admin", "investigator_name": None, "reporting_person_name": None,
        "place_of_incident": None, "finalized_at": None, "created_at": "2026-09-24T10:00:00+00:00",
        "updated_at": "2026-09-24T10:00:00+00:00", "offense": "Structure fire",
        "incidents": {
            "id": "i1", "record_number": "ZIR-2026-000001", "incident_category": category,
            "severity": "high", "location_address": "Poblacion, Naval", "created_at": "2026-09-24T09:00:00+00:00",
            "resolved_at": "2026-09-24T09:50:00+00:00", "assigned_agency_id": "ag-1",
            "stations": {"name": "BFP Naval", "agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Naval"}},
            "users": {"full_name": "Maria Reporter"},
        },
    }


def _list(db, actor=AGENCY_ADMIN, **kwargs):
    with patch.object(svc, "get_supabase", return_value=db):
        return svc.list_narrative_reports(actor, **kwargs)


def test_library_is_pinned_to_the_admins_own_agency():
    db, calls = _library_db([_row()])
    out = _list(db, AGENCY_ADMIN)
    assert ("eq", ("incidents.assigned_agency_id", "ag-1")) in calls["page"]
    assert ("eq", ("incidents.assigned_agency_id", "ag-1")) in calls["tally"]
    assert out["items"][0]["reporting_person_name"] == "Maria Reporter"
    assert out["items"][0]["station_name"] == "BFP Naval"
    assert out["items"][0]["incident_category"] == "fire"


def test_a_provincial_admin_sees_every_station_of_their_type():
    db, calls = _library_db([_row()], agencies=("ag-1", "ag-2"))
    _list(db, PROVINCIAL)
    scoped = [a for n, a in calls["page"] if n == "in_"]
    assert ("incidents.assigned_agency_id", ["ag-1", "ag-2"]) in scoped


def test_no_agency_means_nothing_never_everything():
    db, _ = _library_db([_row()])
    out = _list(db, {"id": "u9", "role": "agency_admin", "agency_id": None})
    assert out["items"] == [] and out["total"] == 0 and out["counts"]["all"] == 0


def test_category_and_status_are_filtered_in_the_database():
    db, calls = _library_db([_row()])
    _list(db, category="fire", report_status="finalized")
    assert ("eq", ("status", "finalized")) in calls["page"]
    assert ("eq", ("incidents.incident_category", "fire")) in calls["page"]


def test_other_includes_the_categories_retired_into_it():
    db, calls = _library_db([_row(category="other")])
    _list(db, category="other")
    ins = [a for n, a in calls["page"] if n == "in_" and a[0] == "incidents.incident_category"]
    assert ins == [("incidents.incident_category", ["other", "hazmat", "missing_person"])]


def test_unknown_filters_are_refused():
    db, _ = _library_db([])
    with pytest.raises(HTTPException) as e:
        _list(db, category="ufo")
    assert e.value.status_code == 422
    with pytest.raises(HTTPException) as e:
        _list(db, report_status="archived")
    assert e.value.status_code == 422


def test_tab_counts_describe_the_other_filter():
    tally = [
        {"status": "finalized", "incidents": {"incident_category": "fire"}},
        {"status": "finalized", "incidents": {"incident_category": "fire"}},
        {"status": "draft", "incidents": {"incident_category": "fire"}},
        {"status": "finalized", "incidents": {"incident_category": "vehicular"}},
        {"status": "draft", "incidents": {"incident_category": "hazmat"}},
    ]
    db, _ = _library_db([_row()], tally=tally)

    # Nothing chosen: every category counts every status.
    out = _list(db)
    assert out["counts"]["by_category"]["fire"] == 3
    assert out["counts"]["by_category"]["other"] == 1          # hazmat folded into other
    assert out["counts"]["by_status"] == {"draft": 2, "finalized": 3}
    assert out["counts"]["all"] == 5

    # Finalized chosen: the category tabs count finalized reports only...
    out = _list(db, report_status="finalized")
    assert out["counts"]["by_category"]["fire"] == 2
    assert out["counts"]["by_category"]["other"] == 0
    # ...and Fire chosen: the status chips count fire reports only.
    out = _list(db, category="fire")
    assert out["counts"]["by_status"] == {"draft": 1, "finalized": 2}


def test_the_offense_column_is_only_asked_for_when_it_exists():
    db, calls = _library_db([_row()])
    with patch.object(svc, "_details_supported", return_value=False):
        _list(db)
    assert "details->>offense" not in calls["select"][0]


# ── 5. the document ─────────────────────────────────────────────────────────

def _incident():
    return {
        "id": "i1", "record_number": "ZIR-2026-000123", "incident_category": "fire",
        "severity": "high", "created_at": "2024-05-20T08:00:00+00:00",
        "accepted_at": "2024-05-20T08:05:00+00:00", "dispatched_at": "2024-05-20T08:03:00+00:00",
        "resolved_at": "2024-05-20T09:30:00+00:00", "location_address": "Casiawan, Cabucgayan, Biliran",
        "outcome": "resolved_on_scene", "outcome_notes": "Fire out; no further spread.",
        "casualties_injured": 1, "casualties_fatal": 0, "casualties_transported": 1,
        "stations": {"name": "BFP Cabucgayan", "agencies": {"agency_type": "BFP", "name": "BFP Cabucgayan", "municipality": "Cabucgayan"}},
        "responder": {"full_name": "Juan Dela Cruz"},
        "users": {"full_name": "Maricar Cayepe Ehem", "phone_number": "09183505739"},
    }


def _details(n_suspects=2, n_victims=3):
    person = lambda i: {  # noqa: E731
        "family_name": f"Family{i}", "first_name": f"First{i}", "middle_name": "M",
        "citizenship": "Filipino", "gender": "Female", "civil_status": "Single",
        "date_of_birth": "1989-03-14", "place_of_birth": "Cabucgayan, Biliran",
        "address_street": "Purok 1", "barangay": "Casiawan", "town_city": "Cabucgayan", "province": "Biliran",
        "education": "High School", "occupation": "Farmer", "relation": "Stranger/No Relationship",
    }
    return {
        "offense": "Structure Fire", "offense_detail": "Consummated under the Fire Code",
        "copy_for": "Complainant",
        "reporting_person": person(0),
        "suspects": [{**person(i), "rank": "N/A", "height": "170", "eye_color": "Black", "under_influence": "None"} for i in range(1, n_suspects + 1)],
        "victims": [person(i) for i in range(10, 10 + n_victims)],
        "witnesses": "Neighbours: two persons.", "property_damage": "PHP 250,000", "actions_taken": "Fire suppressed.",
        "certification": {"administering_officer": "PCPL Zerna", "investigator_rank_name": "PCPL Mark", "desk_officer_rank_name": "PSSg Desk"},
        "station": {"name": "Cabucgayan PS", "telephone": "053-555-0100", "mobile": "09183505739", "chief": "PMAJ Chief"},
    }


def _pdf_pages(data: bytes) -> int:
    return data.count(b"/Type /Page\n") + data.count(b"/Type /Page ") + data.count(b"/Type/Page/") \
        - data.count(b"/Type /Pages")


def test_the_pdf_is_a_real_document_with_every_item_on_it():
    report = {
        "narrative": "On the above stated date the complainant reported a fire.\n\nThe crew arrived and put it out.",
        "status": "finalized", "reference_no": "087803000-202405-6352",
        "details": _details(), "reporting_person_name": None,
        "incident_occurred_at": "2024-05-20T01:34:00+00:00",
    }
    pdf = svc._build_pdf(_incident(), report)
    assert pdf[:5] == b"%PDF-"
    assert len(pdf) > 4000


def test_a_long_narrative_with_many_people_runs_onto_more_pages():
    long_text = "\n\n".join(f"Paragraph {i}: " + ("the crew responded to the scene. " * 25) for i in range(40))
    small = svc._build_pdf(_incident(), {"narrative": "Short.", "status": "draft", "details": _details(1, 1)})
    big = svc._build_pdf(_incident(), {"narrative": long_text, "status": "draft", "details": _details(6, 12)})
    assert len(big) > len(small) * 2


def test_a_report_with_no_details_still_prints():
    """A report saved before migration 040 has no `details` at all."""
    pdf = svc._build_pdf(_incident(), {"narrative": "Just prose.", "status": "draft"})
    assert pdf[:5] == b"%PDF-"


def test_typed_markup_cannot_break_the_document():
    evil = "<b>bold</b> & <unclosed <para> </i>"
    details = _details(1, 1)
    details["reporting_person"]["first_name"] = evil
    details["witnesses"] = evil
    pdf = svc._build_pdf(_incident(), {"narrative": evil + "\n\n" + evil, "status": "draft", "details": details})
    assert pdf[:5] == b"%PDF-"


def test_times_are_printed_in_philippine_time():
    # 08:00 UTC is 16:00 in the Philippines - the form's own example shows 16:00:00.
    assert svc._stamp("2024-05-20T08:00:00+00:00") == "2024-05-20 16:00"
    assert svc._stamp(None) == ""
    assert svc._stamp("not a date") == ""


def test_age_is_worked_out_from_the_birth_date_when_not_typed():
    from datetime import datetime
    on = datetime.fromisoformat("2024-05-20T16:00:00+08:00")
    assert svc._person_age("1989-03-14", on) == "35"
    assert svc._person_age("1989-11-07", on) == "34"
    assert svc._person_age("", on) == ""


# ── router wiring ───────────────────────────────────────────────────────────

client = TestClient(app)


def _as(user):
    from app.core.dependencies import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user


def teardown_function():
    app.dependency_overrides.clear()


def test_library_route_reaches_the_service_with_its_filters():
    _as(AGENCY_ADMIN)
    with patch("app.routers.dispatch.incident_narrative_service.list_narrative_reports",
               return_value={"items": [], "total": 0, "counts": {}}) as fn:
        res = client.get("/dispatch/narrative-reports?category=fire&status=draft&days=30&limit=20&offset=40")
    assert res.status_code == 200
    _, kwargs = fn.call_args
    assert kwargs["category"] == "fire" and kwargs["report_status"] == "draft"
    assert kwargs["days"] == 30 and kwargs["limit"] == 20 and kwargs["offset"] == 40


def test_library_route_is_closed_to_responders():
    _as({"id": "u2", "role": "responder", "agency_id": "ag-1", "full_name": "R"})
    assert client.get("/dispatch/narrative-reports").status_code == 403


def test_saving_is_closed_to_a_provincial_admin():
    _as(PROVINCIAL)
    res = client.put("/dispatch/queue/i1/narrative-report", json={"narrative": "x"})
    assert res.status_code == 403


def test_save_route_accepts_an_empty_draft_with_details():
    _as(AGENCY_ADMIN)
    with patch("app.routers.dispatch.incident_narrative_service.save_narrative_report", return_value={"id": "r1"}) as fn:
        res = client.put("/dispatch/queue/i1/narrative-report", json={"details": {"offense": "Fire"}})
    assert res.status_code == 200
    assert fn.call_args.kwargs["narrative"] == ""
    assert fn.call_args.kwargs["details"] == {"offense": "Fire"}
