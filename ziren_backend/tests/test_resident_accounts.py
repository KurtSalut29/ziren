"""A resident's standing: warnings, suspension from reporting, reinstatement.

What has to be true, and is pinned here against a database double that really
evaluates the queries (tests/fake_db.py), not a mock that only records calls:

  1. A warning raises the count, is written to the audit trail, and is told to
     the RESIDENT as a notification of its own type.
  2. The third warning suspends the account by itself.
  3. A suspended resident cannot send ANY report - ordinary or SOS - and the
     refusal names an emergency number. An expired suspension blocks nothing.
  4. The check fails OPEN: a lookup that breaks must never refuse a report.
  5. Reinstating lifts the block and tells the resident.
  6. An Agency Admin can act on their own municipality's residents and on
     anyone who reported to their agency - nobody else.
  7. A notification that cannot be written never undoes the action.

Run with: pytest tests/test_resident_accounts.py -v
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.services import incident_service, resident_account_service as svc
from tests.fake_db import FakeDB

RES = "a0000000-0000-0000-0000-000000000001"
OTHER = "a0000000-0000-0000-0000-000000000002"
RESPONDER = "a0000000-0000-0000-0000-000000000003"
AGENCY = "b0000000-0000-0000-0000-000000000001"
PROV = {"id": "d0000000-0000-0000-0000-000000000001", "role": "provincial_admin", "full_name": "Prov Admin"}
ADMIN = {"id": "d0000000-0000-0000-0000-000000000002", "role": "agency_admin", "full_name": "Naval Admin", "agency_id": AGENCY}


def _user(uid=RES, **kw):
    return {
        "id": uid, "role": "resident", "full_name": "Maria Santos", "email": "maria@example.test",
        "phone_number": "09171234567", "municipality_address": "Naval", "verification_level": 2,
        "verified_at": "2026-09-01T00:00:00+00:00", "created_at": "2026-08-01T00:00:00+00:00",
        "sos_warning_count": 0, "sos_suspended_until": None, "is_verified": True, **kw,
    }


@pytest.fixture
def db():
    fake = FakeDB({"users": [_user()], "incidents": [], "audit_logs": [], "notifications": []})
    with patch("app.services.resident_account_service.get_supabase", return_value=fake), \
         patch("app.services.audit_service.get_supabase", return_value=fake), \
         patch("app.services.notification_service.get_supabase", return_value=fake):
        yield fake


def _row(db, uid=RES):
    return next(r for r in db.rows("users") if r["id"] == uid)


def _notes(db, uid=RES):
    return [n for n in db.rows("notifications") if n["recipient_id"] == uid]


# ── Warning ──────────────────────────────────────────────────────────────────

def test_warning_is_counted_audited_and_told_to_the_resident(db):
    out = svc.warn(RES, violation="false_report", note="Reported a fire that did not exist.", incident_id="inc-9", actor=PROV)

    assert out["warning_count"] == 1 and out["standing"] == "warned"
    assert _row(db)["sos_warning_count"] == 1
    assert _row(db)["sos_suspended_until"] is None

    audit = db.rows("audit_logs")
    assert [a["action"] for a in audit] == ["resident.warned"]
    assert audit[0]["target_id"] == RES and audit[0]["actor_name"] == "Prov Admin"
    assert audit[0]["new_value"]["violation"] == "false_report"
    assert audit[0]["new_value"]["incident_id"] == "inc-9"

    notes = _notes(db)
    assert [n["type"] for n in notes] == ["account.warned"]
    assert notes[0]["is_important"] is True
    assert "false or prank report" in notes[0]["body"].lower()
    assert "did not exist" in notes[0]["body"]
    meta = notes[0]["metadata"]
    assert meta["violation"] == "false_report" and meta["warning_count"] == 1 and meta["warnings_left"] == 2
    assert meta["incident_id"] == "inc-9"
    # The admin is never told about their own action.
    assert not [n for n in db.rows("notifications") if n["recipient_id"] == PROV["id"]]


def test_third_warning_suspends_by_itself(db):
    for i in range(2):
        out = svc.warn(RES, violation="spam", note="Sent the same report again.", actor=PROV)
        assert out["suspension"]["active"] is False
    out = svc.warn(RES, violation="spam", note="Sent the same report again.", actor=PROV)

    assert out["warning_count"] == 3 and out["standing"] == "suspended"
    until = datetime.fromisoformat(_row(db)["sos_suspended_until"])
    assert timedelta(days=29) < until - datetime.now(timezone.utc) <= timedelta(days=30)
    assert [n["type"] for n in _notes(db)] == ["account.warned"] * 3 + ["account.suspended"]
    assert _notes(db)[-1]["metadata"]["automatic"] is True
    assert [a["action"] for a in db.rows("audit_logs")][-1] == "resident.suspended"


@pytest.mark.parametrize("violation,note,code", [
    ("not_a_violation", "Something happened here.", 422),
    ("false_report", "   ", 422),
    ("false_report", "no", 422),
])
def test_a_warning_needs_a_known_violation_and_a_real_note(db, violation, note, code):
    with pytest.raises(HTTPException) as e:
        svc.warn(RES, violation=violation, note=note, actor=PROV)
    assert e.value.status_code == code
    assert _row(db)["sos_warning_count"] == 0 and not db.rows("notifications")


def test_every_listed_violation_can_be_used(db):
    for key in svc.VIOLATIONS:
        db.tables["users"] = [_user()]
        out = svc.warn(RES, violation=key, note="Recorded for the test of this violation.", actor=PROV)
        assert out["warning_count"] == 1
        assert _notes(db)[-1]["metadata"]["violation_label"] == svc.VIOLATIONS[key]


def test_only_a_resident_can_be_warned(db):
    db.tables["users"].append(_user(RESPONDER, role="responder"))
    with pytest.raises(HTTPException) as e:
        svc.warn(RESPONDER, violation="spam", note="Should never apply.", actor=PROV)
    assert e.value.status_code == 422
    with pytest.raises(HTTPException) as e:
        svc.warn("a0000000-0000-0000-0000-00000000dead", violation="spam", note="Nobody here.", actor=PROV)
    assert e.value.status_code == 404


def test_a_failed_notification_does_not_undo_the_warning(db):
    db.fail_on_insert.add("notifications")
    out = svc.warn(RES, violation="abusive_language", note="Threatened the dispatcher.", actor=PROV)
    assert out["warning_count"] == 1 and _row(db)["sos_warning_count"] == 1


# ── Suspension ───────────────────────────────────────────────────────────────

def test_suspending_for_days_sets_the_end_and_tells_the_resident(db):
    out = svc.suspend(RES, violation="false_report", note="Third prank call this month.", days=7, actor=PROV)

    assert out["standing"] == "suspended" and out["suspension"]["indefinite"] is False
    until = datetime.fromisoformat(_row(db)["sos_suspended_until"])
    assert timedelta(days=6, hours=23) < until - datetime.now(timezone.utc) <= timedelta(days=7)
    note = _notes(db)[0]
    assert note["type"] == "account.suspended"
    assert note["metadata"]["suspended_until"] == out["suspension"]["until"]
    assert "cannot send reports until" in note["body"]
    assert db.rows("audit_logs")[0]["action"] == "resident.suspended"
    # A suspension by hand is not a warning.
    assert _row(db)["sos_warning_count"] == 0


def test_suspending_without_days_is_until_further_notice(db):
    out = svc.suspend(RES, violation="fake_identity", note="Account uses someone else's ID.", days=None, actor=PROV)
    assert out["suspension"] == {"active": True, "indefinite": True, "until": None}
    assert datetime.fromisoformat(_row(db)["sos_suspended_until"]).year == 9999
    assert "until further notice" in _notes(db)[0]["body"]
    assert _notes(db)[0]["metadata"]["indefinite"] is True


@pytest.mark.parametrize("days", [0, -3, 366])
def test_suspension_length_is_bounded(db, days):
    with pytest.raises(HTTPException) as e:
        svc.suspend(RES, violation="spam", note="Too many duplicate reports.", days=days, actor=PROV)
    assert e.value.status_code == 422
    assert _row(db)["sos_suspended_until"] is None


# ── The block itself ─────────────────────────────────────────────────────────

def test_a_suspended_resident_cannot_report_and_is_told_who_to_call(db):
    svc.suspend(RES, violation="false_report", note="Third prank call this month.", days=7, actor=PROV)
    with pytest.raises(HTTPException) as e:
        incident_service.ensure_reporting_allowed(db, RES)
    assert e.value.status_code == 403
    assert "suspended from sending reports until" in e.value.detail
    assert "911" in e.value.detail

    # The SOS path reads the same date through the same check.
    with pytest.raises(HTTPException) as e:
        incident_service._refuse_if_suspended(_row(db)["sos_suspended_until"])
    assert e.value.status_code == 403


def test_until_further_notice_is_worded_as_such(db):
    svc.suspend(RES, violation="fake_identity", note="Account uses someone else's ID.", days=None, actor=PROV)
    with pytest.raises(HTTPException) as e:
        incident_service.ensure_reporting_allowed(db, RES)
    assert "until further notice" in e.value.detail and "9999" not in e.value.detail


def test_an_expired_suspension_blocks_nothing(db):
    _row(db)["sos_suspended_until"] = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    incident_service.ensure_reporting_allowed(db, RES)
    assert svc.suspension_of(_row(db))["active"] is False
    assert svc.standing_of(_row(db)) == "good"


def test_a_resident_in_good_standing_can_report(db):
    incident_service.ensure_reporting_allowed(db, RES)


def test_the_check_fails_open_when_the_lookup_breaks(db):
    svc.suspend(RES, violation="spam", note="Too many duplicate reports.", days=7, actor=PROV)
    db.fail_on_select.add("users")
    incident_service.ensure_reporting_allowed(db, RES)  # no exception: never block on an outage


@pytest.mark.parametrize("value", [None, "", "not a date", 12345, object()])
def test_only_a_real_future_date_is_a_suspension(value):
    incident_service._refuse_if_suspended(value)


# ── Reinstatement ────────────────────────────────────────────────────────────

def test_reinstating_lifts_the_block_and_tells_the_resident(db):
    svc.suspend(RES, violation="false_report", note="Third prank call this month.", days=30, actor=PROV)
    out = svc.reinstate(RES, note="Appeal accepted.", clear_warnings=False, actor=PROV)

    assert out["suspension"]["active"] is False and out["standing"] == "good"
    assert _row(db)["sos_suspended_until"] is None
    incident_service.ensure_reporting_allowed(db, RES)
    assert _notes(db)[-1]["type"] == "account.reinstated"
    assert "Appeal accepted." in _notes(db)[-1]["body"]
    assert db.rows("audit_logs")[-1]["action"] == "resident.reinstated"


def test_reinstating_can_clear_the_warnings(db):
    for _ in range(3):
        svc.warn(RES, violation="spam", note="Sent the same report again.", actor=PROV)
    out = svc.reinstate(RES, note=None, clear_warnings=True, actor=PROV)
    assert out == {"id": RES, "warning_count": 0, "suspension": {"active": False, "indefinite": False, "until": None}, "standing": "good"}
    assert _row(db)["sos_warning_count"] == 0
    # Without clearing, the very next warning would have suspended again.
    assert svc.warn(RES, violation="spam", note="Sent the same report again.", actor=PROV)["suspension"]["active"] is False


def test_keeping_the_warnings_leaves_the_resident_warned(db):
    for _ in range(3):
        svc.warn(RES, violation="spam", note="Sent the same report again.", actor=PROV)
    out = svc.reinstate(RES, note=None, clear_warnings=False, actor=PROV)
    assert out["warning_count"] == 3 and out["standing"] == "warned"


def test_reinstating_someone_who_is_not_suspended_is_refused(db):
    with pytest.raises(HTTPException) as e:
        svc.reinstate(RES, note=None, clear_warnings=False, actor=PROV)
    assert e.value.status_code == 409
    assert not db.rows("notifications")


# ── Scope ────────────────────────────────────────────────────────────────────

def test_agency_admin_acts_on_their_own_municipality(db):
    with patch.object(svc, "_own_municipality", return_value="Naval"):
        assert svc.warn(RES, violation="spam", note="Sent the same report again.", actor=ADMIN)["warning_count"] == 1


def test_agency_admin_cannot_reach_a_stranger_in_another_town(db):
    db.tables["users"].append(_user(OTHER, municipality_address="Kawayan"))
    with patch.object(svc, "_own_municipality", return_value="Naval"):
        for call in (
            lambda: svc.warn(OTHER, violation="spam", note="Sent the same report again.", actor=ADMIN),
            lambda: svc.suspend(OTHER, violation="spam", note="Sent the same report again.", days=3, actor=ADMIN),
            lambda: svc.get_resident(OTHER, current_user=ADMIN),
        ):
            with pytest.raises(HTTPException) as e:
                call()
            assert e.value.status_code == 403
    assert _row(db, OTHER)["sos_warning_count"] == 0


def test_agency_admin_can_act_on_an_outsider_who_reported_to_them(db):
    db.tables["users"].append(_user(OTHER, municipality_address="Kawayan"))
    db.tables["incidents"].append({"id": "inc-1", "reporter_id": OTHER, "assigned_agency_id": AGENCY})
    with patch.object(svc, "_own_municipality", return_value="Naval"):
        assert svc.warn(OTHER, violation="false_report", note="Prank report to our station.", actor=ADMIN)["warning_count"] == 1


# ── Reading ──────────────────────────────────────────────────────────────────

def test_list_counts_every_bucket_and_puts_the_suspended_first(db):
    future = (datetime.now(timezone.utc) + timedelta(days=5)).isoformat()
    db.tables["users"] = [
        _user("u-good", full_name="Ana Good"),
        _user("u-warn", full_name="Ben Warned", sos_warning_count=2),
        _user("u-susp", full_name="Cara Suspended", sos_warning_count=3, sos_suspended_until=future),
        _user("u-unver", full_name="Dan Unverified", verification_level=0, verified_at=None),
        _user("u-staff", role="responder", full_name="Not A Resident"),
    ]
    db.tables["incidents"] = [{"id": "i1", "reporter_id": "u-warn"}, {"id": "i2", "reporter_id": "u-warn"}]

    out = svc.list_residents(standing="verified", current_user=PROV)
    assert out["counts"] == {"all": 4, "verified": 3, "unverified": 1, "warned": 2, "suspended": 1}
    assert [r["id"] for r in out["items"]] == ["u-susp", "u-warn", "u-good"]
    assert out["total"] == 3
    warned = next(r for r in out["items"] if r["id"] == "u-warn")
    assert warned["report_count"] == 2 and warned["standing"] == "warned" and warned["warning_count"] == 2
    # The raw column names never leave the service.
    assert "sos_warning_count" not in warned and "sos_suspended_until" not in warned

    assert [r["id"] for r in svc.list_residents(standing="suspended", current_user=PROV)["items"]] == ["u-susp"]
    assert [r["id"] for r in svc.list_residents(standing="unverified", current_user=PROV)["items"]] == ["u-unver"]
    assert [r["id"] for r in svc.list_residents(standing="all", q="ben", current_user=PROV)["items"]] == ["u-warn"]
    with pytest.raises(HTTPException):
        svc.list_residents(standing="nonsense", current_user=PROV)


def test_list_is_locked_to_the_agency_admins_municipality(db):
    db.tables["users"] = [_user("u-naval"), _user("u-kaw", municipality_address="Kawayan")]
    with patch.object(svc, "_own_municipality", return_value="Naval"):
        out = svc.list_residents(standing="all", current_user=ADMIN)
    assert [r["id"] for r in out["items"]] == ["u-naval"] and out["counts"]["all"] == 1


def test_detail_carries_reports_and_the_history_newest_first(db):
    db.tables["incidents"] = [
        {"id": "i1", "reporter_id": RES, "report_text": "Sunog", "status": "cancelled", "review_status": "rejected", "created_at": "2026-09-02T00:00:00+00:00"},
        {"id": "i2", "reporter_id": RES, "report_text": "Baha", "status": "resolved", "review_status": "accepted", "created_at": "2026-09-05T00:00:00+00:00"},
    ]
    clock = iter(datetime(2026, 9, 10 + i, tzinfo=timezone.utc) for i in range(20))
    db.clock = lambda: next(clock)
    svc.warn(RES, violation="false_report", note="Reported a fire that did not exist.", actor=PROV)
    svc.suspend(RES, violation="false_report", note="Did it again the next day.", days=3, actor=PROV)
    svc.reinstate(RES, note="Apologised in person.", clear_warnings=False, actor=PROV)
    out = svc.get_resident(RES, current_user=PROV)

    assert out["report_count"] == 2 and out["rejected_report_count"] == 1
    assert [r["id"] for r in out["recent_reports"]] == ["i2", "i1"]
    assert [h["kind"] for h in out["history"]] == ["reinstated", "suspended", "warned"]
    assert out["history"][2]["violation_label"] == svc.VIOLATIONS["false_report"]
    assert out["history"][2]["note"] == "Reported a fire that did not exist."
    assert out["history"][1]["by"] == "Prov Admin"
    assert out["standing"] == "warned" and out["warning_count"] == 1
    assert {v["key"] for v in out["violations"]} == set(svc.VIOLATIONS)


# ── The false-SOS flag, which used to change the record in silence ───────────

def test_false_sos_flag_is_now_audited_and_told_to_the_resident(db):
    svc.announce_false_sos(RES, incident_id="inc-7", result={"warning_count": 1, "suspended_until": None}, actor=ADMIN)
    assert [n["type"] for n in _notes(db)] == ["account.warned"]
    assert _notes(db)[0]["metadata"]["violation"] == "false_sos"
    assert db.rows("audit_logs")[0]["new_value"]["incident_id"] == "inc-7"


def test_false_sos_that_suspends_says_so(db):
    until = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
    svc.announce_false_sos(RES, incident_id="inc-7", result={"warning_count": 3, "suspended_until": until}, actor=ADMIN)
    assert [n["type"] for n in _notes(db)] == ["account.warned", "account.suspended"]
    assert [a["action"] for a in db.rows("audit_logs")] == ["resident.warned", "resident.suspended"]


def test_announcing_a_false_sos_never_raises(db):
    db.fail_on_insert.update({"notifications", "audit_logs"})
    svc.announce_false_sos(RES, incident_id="inc-7", result={"warning_count": 1}, actor=ADMIN)


# ── The Ziren ID card's photo (user request 2026-10-08) ─────────────────────

def test_a_verified_residents_card_photo_is_a_short_lived_link(db):
    _row(db)["selfie_image_path"] = "selfies/a01.jpg"
    with patch("app.services.user_service._signed_url", return_value="https://signed/a01") as sign:
        out = svc.get_resident(RES, current_user=PROV)
    assert out["photo_url"] == "https://signed/a01"
    assert sign.call_args.args[:2] == ("resident-ids", "selfies/a01.jpg")
    assert "selfie_image_path" not in out, "the storage path itself is never sent"


def test_no_card_photo_for_an_account_not_verified(db):
    _row(db).update(selfie_image_path="selfies/a01.jpg", verification_level=1)
    with patch("app.services.user_service._signed_url", return_value="https://signed/a01") as sign:
        out = svc.get_resident(RES, current_user=PROV)
    assert out["photo_url"] is None
    sign.assert_not_called()


def test_no_photo_on_file_is_no_photo(db):
    out = svc.get_resident(RES, current_user=PROV)
    assert out["photo_url"] is None


def test_the_card_photo_is_the_2x2_photo_when_there_is_one(db):
    """2026-10-08: the 2x2 ID photo is the card's picture. The selfie is only
    the fallback for residents approved before it existed."""
    _row(db).update(
        selfie_image_path="selfies/a01.jpg",
        id_checks={"portrait": {"path": f"{RES}/portrait_9.jpg", "verdict": "match"}},
    )
    with patch("app.services.user_service._signed_url", return_value="https://signed/p") as sign:
        out = svc.get_resident(RES, current_user=PROV)
    assert out["photo_url"] == "https://signed/p"
    assert sign.call_args.args[:2] == ("resident-ids", f"{RES}/portrait_9.jpg")
    assert "id_checks" not in out


def test_the_list_says_when_an_unverified_residents_week_ends(db):
    """The admin sees who is about to be, or already is, refused for not
    being verified (resident_trust.GRACE_DAYS)."""
    joined = datetime.now(timezone.utc) - timedelta(days=9)
    _row(db).update(verification_level=0, created_at=joined.isoformat())
    out = svc.get_resident(RES, current_user=PROV)
    assert out["reporting_locked"] is True
    assert out["reporting_grace_ends_at"].startswith((joined + timedelta(days=7)).date().isoformat())
    _row(db).update(verification_level=2)
    out = svc.get_resident(RES, current_user=PROV)
    assert out["reporting_locked"] is False and out["reporting_grace_ends_at"] is None
