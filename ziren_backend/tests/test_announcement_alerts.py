"""Safety alerts (migration 043): aimed at places, answered by residents.

Every test runs on FakeDB, which actually evaluates the queries - "who does an
evacuation order for two barangays reach" is a question about rows, and a mock
would agree with any answer.

The province in these tests:

  Naval    stations: MDRRMO (admin NM), BFP (admin NB, responder RSP_N)
           residents: R_ATI (Atipolo), R_CAR (Caraycaray), R_UNK (barangay
           unknown), R_LAR (Larrazabal)
  Almeria  station: MDRRMO (admin AM, responder RSP_A); resident R_ALM
  nowhere  resident R_NONE (no address)

Run with: pytest tests/test_announcement_alerts.py -v
"""

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import announcement_service as svc
from tests.fake_db import FakeDB

client = TestClient(app)

P = "00000000-0000-0000-0000-0000000000p1"
P2 = "00000000-0000-0000-0000-0000000000p2"
NM, NB, AM = "u-admin-naval-mdrrmo", "u-admin-naval-bfp", "u-admin-almeria"
RSP_N, RSP_A = "u-resp-naval", "u-resp-almeria"
R_ATI, R_CAR, R_UNK, R_LAR, R_ALM, R_NONE = "r-ati", "r-car", "r-unk", "r-lar", "r-alm", "r-none"
AG_NM, AG_NB, AG_AM = "ag-naval-mdrrmo", "ag-naval-bfp", "ag-almeria-mdrrmo"
B_ATI, B_CAR, B_LAR, B_POB = "b-atipolo", "b-caraycaray", "b-larrazabal", "b-poblacion-almeria"

ACTOR = {"id": P, "role": "provincial_admin", "agency_type": "MDRRMO", "full_name": "Prov Admin"}
PNP = {"id": P2, "role": "provincial_admin", "agency_type": "PNP", "full_name": "Prov Admin PNP"}
BFP = {"id": P2, "role": "provincial_admin", "agency_type": "BFP", "full_name": "Prov Admin BFP"}


def _resident(uid, town, barangay_id=None, name=None):
    return {
        "id": uid, "role": "resident", "full_name": name or uid, "phone_number": "0917" + uid[-3:],
        "municipality_address": town, "barangay_id": barangay_id,
    }


def _db():
    return FakeDB({
        "users": [
            {"id": P, "role": "provincial_admin", "full_name": "Prov Admin"},
            {"id": P2, "role": "provincial_admin", "full_name": "Prov Admin BFP"},
            {"id": NM, "role": "agency_admin", "agency_id": AG_NM, "full_name": "Naval MDRRMO"},
            {"id": NB, "role": "agency_admin", "agency_id": AG_NB, "full_name": "Naval BFP"},
            {"id": AM, "role": "agency_admin", "agency_id": AG_AM, "full_name": "Almeria MDRRMO"},
            {"id": RSP_N, "role": "responder", "agency_id": AG_NB},
            {"id": RSP_A, "role": "responder", "agency_id": AG_AM},
            _resident(R_ATI, "Naval", B_ATI, "Ana Atipolo"),
            _resident(R_CAR, "Naval", B_CAR, "Carlo Caraycaray"),
            _resident(R_UNK, "Naval", None, "Una Unknown"),
            _resident(R_LAR, "Naval", B_LAR, "Lara Larrazabal"),
            _resident(R_ALM, "Almeria", B_POB, "Alma Almeria"),
            _resident(R_NONE, None, None, "Nora Nowhere"),
        ],
        "agencies": [
            {"id": AG_NM, "name": "Naval MDRRMO", "municipality": "Naval"},
            {"id": AG_NB, "name": "Naval Fire Station", "municipality": "Naval"},
            {"id": AG_AM, "name": "Almeria MDRRMO", "municipality": "Almeria"},
        ],
        "barangays": [
            {"id": B_ATI, "name": "Atipolo", "municipality": "Naval"},
            {"id": B_CAR, "name": "Caraycaray", "municipality": "Naval"},
            {"id": B_LAR, "name": "Larrazabal", "municipality": "Naval"},
            {"id": B_POB, "name": "Poblacion", "municipality": "Almeria"},
        ],
        "announcements": [], "announcement_responses": [], "notifications": [], "audit_logs": [],
    })


@contextmanager
def _on(db):
    with patch("app.services.announcement_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.get_supabase", return_value=db), \
         patch("app.services.audit_service.get_supabase", return_value=db):
        yield


EVAC = dict(
    title="Forced evacuation: Atipolo and Caraycaray",
    body="Umalis na po. Tumataas ang tubig sa ilog.",
    category="evacuation",
    target_type="resident",
    details={"kind": "forced", "centers": [{"name": "Naval Central School", "place": "P. Inocentes St."}]},
    target_municipalities=["Naval"],
    target_barangay_ids=[B_ATI, B_CAR],
    asks_response=True,
)


def _publish(db, actor=ACTOR, **kw):
    with _on(db):
        return svc.publish(actor, **{**EVAC, **kw})


def _notified(db, type_="announcement.published"):
    return {n["recipient_id"] for n in db.rows("notifications") if n["type"] == type_}


def _user(uid, role, agency_id=None):
    return {"id": uid, "role": role, "agency_id": agency_id}


# ── Who it reaches ───────────────────────────────────────────────────────────

def test_an_evacuation_order_reaches_only_the_picked_barangays():
    db = _db()
    row = _publish(db)
    # Atipolo and Caraycaray, and the Naval resident whose barangay is unknown
    # (one person too many beats missing the one in the flood zone). Not
    # Larrazabal in the same town, not Almeria, not someone with no address.
    assert _notified(db) == {R_ATI, R_CAR, R_UNK}
    assert row["reach"]["resident"] == 3 and row["reach"]["total"] == 3


def test_the_notification_carries_what_the_phone_needs_to_pop_it_up():
    db = _db()
    row = _publish(db)
    n = db.rows("notifications")[0]
    assert n["is_important"] is True
    assert n["title"].startswith("Evacuation order: ")
    assert n["metadata"]["announcement_id"] == str(row["id"])
    assert n["metadata"]["urgent"] is True and n["metadata"]["asks_response"] is True
    assert n["metadata"]["category"] == "evacuation"
    assert n["metadata"]["title"] == EVAC["title"]


def test_a_whole_town_reaches_its_residents_and_its_stations_but_not_the_next_town():
    db = _db()
    _publish(db, target_type="all", target_barangay_ids=None, asks_response=False,
             category="weather", details={"signal": 3, "storm_name": "Ada"})
    assert _notified(db) == {R_ATI, R_CAR, R_UNK, R_LAR, NM, NB, RSP_N, P2}
    assert not {R_ALM, AM, RSP_A, R_NONE} & _notified(db)


def test_no_place_is_still_the_whole_province():
    db = _db()
    _publish(db, target_municipalities=None, target_barangay_ids=None)
    assert _notified(db) == {R_ATI, R_CAR, R_UNK, R_LAR, R_ALM, R_NONE}


def test_barangays_alone_imply_their_municipality():
    db = _db()
    row = _publish(db, target_municipalities=None, target_barangay_ids=[B_LAR])
    assert row["target_municipalities"] == ["Naval"]
    assert _notified(db) == {R_LAR, R_UNK}


def test_the_preview_counts_the_same_people_and_publishes_nothing():
    db = _db()
    with _on(db):
        preview = svc.preview_audience(
            ACTOR, **{**EVAC, "expires_at": None, "target_agency_id": None, "ends_announcement_id": None},
        )
    assert preview["resident"] == 3 and preview["total"] == 3
    assert db.rows("announcements") == [] and db.rows("notifications") == []


# ── What a draft must say ────────────────────────────────────────────────────

@pytest.mark.parametrize("change, words", [
    ({"details": {"kind": "forced"}}, "where to go"),
    ({"target_municipalities": ["Tacloban"]}, "Unknown municipality"),
    ({"target_municipalities": ["Almeria"]}, "not in the municipalities"),
    ({"category": "road_closure", "details": {"road": "Naval-Caibiran road"}}, "Only these can ask"),
    ({"target_type": "responder"}, "Only residents answer"),
    ({"category": "weather", "details": {"storm_name": "Ada"}}, "wind signal or a rainfall"),
    ({"expires_at": "2020-01-01T00:00:00Z"}, "already past"),
    ({"target_barangay_ids": ["no-such-barangay"]}, "does not exist"),
    ({"category": "missing_person", "asks_response": False, "details": {"name": "Jun"}, "actor": PNP}, "last seen"),
])
def test_a_draft_that_would_mislead_is_refused(change, words):
    db = _db()
    with pytest.raises(ValueError, match=words):
        _publish(db, **change)
    assert db.rows("announcements") == []


def test_details_are_kept_to_what_the_kind_knows():
    db = _db()
    row = _publish(db, details={"kind": "forced", "centers": [{"name": "  Gym  ", "junk": 1}, {"name": ""}], "junk": "x"})
    assert row["details"] == {"kind": "forced", "centers": [{"name": "Gym"}]}


# ── Who issues what ──────────────────────────────────────────────────────────

def test_each_office_issues_only_its_own_kinds():
    db = _db()
    with pytest.raises(PermissionError, match="PDRRMO"):
        _publish(db, actor=PNP)  # an evacuation order from the police
    with pytest.raises(PermissionError, match="PNP"):
        _publish(db, category="missing_person", asks_response=False,
                 details={"name": "Jun Reyes", "last_seen": "Naval port", "contact": "0921-555-3961"})
    assert db.rows("announcements") == [] and db.rows("notifications") == []
    # Their own kind, and the ones open to all three, go through.
    assert _publish(db, actor=PNP, category="missing_person", asks_response=False,
                    details={"name": "Jun Reyes", "last_seen": "Naval port", "contact": "0921-555-3961"})["id"]
    assert _publish(db, actor=BFP, category="road_closure", asks_response=False, details={"road": "Km 12"})["id"]
    assert _publish(db, actor=BFP, category="emergency", asks_response=False, details=None)["id"]


def test_the_preview_refuses_the_same_way():
    db = _db()
    with _on(db), pytest.raises(PermissionError):
        svc.preview_audience(PNP, **{**EVAC, "expires_at": None, "target_agency_id": None, "ends_announcement_id": None})


def test_only_the_issuing_office_ends_or_takes_down_an_alert():
    db = _db()
    warning = _publish(db)  # MDRRMO
    with _on(db):
        with pytest.raises(PermissionError, match="PDRRMO"):
            svc.publish(BFP, title="All clear", body="x", category="all_clear", target_type="all",
                        ends_announcement_id=warning["id"])
        with pytest.raises(PermissionError):
            svc.deactivate(warning["id"], BFP)
        assert db.rows("announcements")[0]["is_active"] is True
        svc.publish(ACTOR, title="All clear", body="x", category="all_clear", target_type="all",
                    ends_announcement_id=warning["id"])
    assert db.rows("announcements")[0]["is_active"] is False


def test_an_announcement_from_before_043_can_be_taken_down_by_any_office():
    db = _db()
    db.tables["announcements"].append({"id": "old", "title": "Old", "category": "general", "is_active": True})
    with _on(db):
        svc.deactivate("old", BFP)
    assert db.rows("announcements")[0]["is_active"] is False


# ── What each person sees ────────────────────────────────────────────────────

def test_feeds_follow_the_place():
    db = _db()
    _publish(db)
    with _on(db):
        assert len(svc.list_for_user(_user(R_ATI, "resident"))) == 1
        assert len(svc.list_for_user(_user(R_UNK, "resident"))) == 1
        assert svc.list_for_user(_user(R_LAR, "resident")) == []
        assert svc.list_for_user(_user(R_ALM, "resident")) == []


def test_an_expired_announcement_leaves_the_feed():
    """The docstring always said "not expired"; nothing checked expires_at."""
    db = _db()
    row = _publish(db, category="general", asks_response=False, details=None,
                   target_municipalities=None, target_barangay_ids=None)
    db.rows("announcements")[0]["expires_at"] = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    with _on(db):
        assert svc.list_for_user(_user(R_ALM, "resident")) == []
    assert row["id"]


def test_a_station_sees_what_was_announced_to_its_town_even_if_not_addressed_to_it():
    db = _db()
    _publish(db)
    with _on(db):
        naval = svc.list_for_station(_user(NM, "agency_admin", AG_NM))
        almeria = svc.list_for_station(_user(AM, "agency_admin", AG_AM))
    assert len(naval) == 1 and naval[0]["for_you"] is False
    assert naval[0]["response_counts"] == {"safe": 0, "need_help": 0, "need_help_open": 0, "audience": 3}
    assert almeria == []


def test_the_management_list_counts_who_was_asked_and_who_answered():
    db = _db()
    row = _publish(db)
    with _on(db):
        svc.respond(row["id"], _user(R_ATI, "resident"), status="need_help")
        svc.respond(row["id"], _user(R_CAR, "resident"), status="safe")
        listed = svc.list_all()
    assert listed[0]["response_counts"] == {"safe": 1, "need_help": 1, "need_help_open": 1, "audience": 3}


def test_someone_it_did_not_reach_cannot_open_it():
    db = _db()
    row = _publish(db)
    with _on(db):
        assert svc.get_one(row["id"], _user(R_ATI, "resident"))["is_open"] is True
        with pytest.raises(LookupError):
            svc.get_one(row["id"], _user(R_LAR, "resident"))
        with pytest.raises(LookupError):
            svc.get_one(row["id"], _user(AM, "agency_admin", AG_AM))


# ── Answering ────────────────────────────────────────────────────────────────

def test_i_need_help_tells_the_stations_of_my_town_and_the_issuer():
    db = _db()
    row = _publish(db)
    with _on(db):
        svc.respond(row["id"], _user(R_ATI, "resident"), status="need_help", note="Nasa bubong kami", latitude=11.56, longitude=124.39)
    assert _notified(db, "announcement.help_requested") == {NM, NB, P}
    alert = next(n for n in db.rows("notifications") if n["type"] == "announcement.help_requested")
    assert "Ana Atipolo" in alert["title"] and "Brgy. Atipolo" in alert["body"] and "Nasa bubong kami" in alert["body"]
    assert alert["is_important"] is True
    saved = db.rows("announcement_responses")
    assert len(saved) == 1 and saved[0]["status"] == "need_help" and saved[0]["latitude"] == 11.56


def test_answering_again_replaces_the_answer_and_does_not_ring_twice():
    db = _db()
    row = _publish(db)
    me = _user(R_ATI, "resident")
    with _on(db):
        svc.respond(row["id"], me, status="need_help")
        svc.respond(row["id"], me, status="need_help")
        assert len(_notified(db, "announcement.help_requested")) == 3
        n_before = len(db.rows("notifications"))
        svc.respond(row["id"], me, status="safe")
        assert len(db.rows("notifications")) == n_before
        svc.respond(row["id"], me, status="need_help")
    assert len(db.rows("announcement_responses")) == 1
    assert db.rows("announcement_responses")[0]["status"] == "need_help"
    assert len([n for n in db.rows("notifications") if n["type"] == "announcement.help_requested"]) == 6


def test_my_answer_comes_back_with_the_feed():
    db = _db()
    row = _publish(db)
    with _on(db):
        svc.respond(row["id"], _user(R_CAR, "resident"), status="safe")
        feed = svc.list_for_user(_user(R_CAR, "resident"))
    assert feed[0]["my_response"]["status"] == "safe"


def test_who_may_answer():
    db = _db()
    row = _publish(db)
    with _on(db):
        with pytest.raises(LookupError):
            svc.respond(row["id"], _user(R_LAR, "resident"), status="safe")  # not in the area
        with pytest.raises(PermissionError):
            svc.respond(row["id"], _user(RSP_N, "responder", AG_NB), status="safe")
        with pytest.raises(ValueError):
            svc.respond(row["id"], _user(R_ATI, "resident"), status="maybe")
        with pytest.raises(ValueError):
            svc.respond(row["id"], _user(R_ATI, "resident"), status="safe", latitude=11.5)


def test_an_alert_that_does_not_ask_cannot_be_answered():
    db = _db()
    row = _publish(db, category="road_closure", asks_response=False, details={"road": "Naval-Caibiran road"})
    with _on(db), pytest.raises(ValueError, match="does not ask"):
        svc.respond(row["id"], _user(R_ATI, "resident"), status="safe")


# ── The board ────────────────────────────────────────────────────────────────

def test_the_board_puts_the_open_calls_first_and_counts_the_silent():
    db = _db()
    row = _publish(db)
    with _on(db):
        svc.respond(row["id"], _user(R_CAR, "resident"), status="safe")
        svc.respond(row["id"], _user(R_ATI, "resident"), status="need_help", note="Tubig hanggang tuhod")
        board = svc.responses(row["id"], ACTOR)
    assert board["tally"] == {"audience": 3, "safe": 1, "need_help": 1, "need_help_open": 1, "no_answer": 1}
    assert [i["user_id"] for i in board["items"]] == [R_ATI, R_UNK, R_CAR]
    top = board["items"][0]
    assert top["barangay"] == "Atipolo" and top["phone_number"] and top["note"] == "Tubig hanggang tuhod"


def test_a_station_sees_its_own_town_and_another_town_sees_nothing():
    db = _db()
    row = _publish(db, target_barangay_ids=None, target_municipalities=["Naval", "Almeria"])
    with _on(db):
        naval = svc.responses(row["id"], _user(NM, "agency_admin", AG_NM))
        almeria = svc.responses(row["id"], _user(AM, "agency_admin", AG_AM))
        with pytest.raises(PermissionError):
            svc.responses(row["id"], _user(R_ATI, "resident"))
    assert {i["user_id"] for i in naval["items"]} == {R_ATI, R_CAR, R_UNK, R_LAR}
    assert {i["user_id"] for i in almeria["items"]} == {R_ALM}


def test_marking_someone_reached_tells_them_and_closes_the_call():
    db = _db()
    row = _publish(db)
    with _on(db):
        svc.respond(row["id"], _user(R_ATI, "resident"), status="need_help")
        with pytest.raises(PermissionError):
            svc.mark_reached(row["id"], R_ATI, _user(AM, "agency_admin", AG_AM))
        svc.mark_reached(row["id"], R_ATI, {**_user(NM, "agency_admin", AG_NM), "full_name": "Naval MDRRMO"})
        board = svc.responses(row["id"], ACTOR)
    assert board["tally"]["need_help_open"] == 0 and board["items"][0]["handled_by_name"] == "Naval MDRRMO"
    ack = [n for n in db.rows("notifications") if n["type"] == "announcement.help_acknowledged"]
    assert [n["recipient_id"] for n in ack] == [R_ATI]
    assert "Naval MDRRMO" in ack[0]["body"]


def test_asking_for_help_again_reopens_a_reached_call():
    db = _db()
    row = _publish(db)
    me = _user(R_ATI, "resident")
    with _on(db):
        svc.respond(row["id"], me, status="need_help")
        svc.mark_reached(row["id"], R_ATI, ACTOR)
        svc.respond(row["id"], me, status="safe")
        svc.respond(row["id"], me, status="need_help")
        assert svc.responses(row["id"], ACTOR)["tally"]["need_help_open"] == 1


# ── All clear ────────────────────────────────────────────────────────────────

def test_all_clear_ends_the_warning_and_reaches_exactly_its_audience():
    db = _db()
    warning = _publish(db)
    db.tables["notifications"].clear()
    with _on(db):
        # The form says "everyone, everywhere" - the all clear ignores that and
        # reaches the people the warning reached.
        clear = svc.publish(
            ACTOR, title="All clear", body="Makakauwi na po.", category="all_clear",
            target_type="all", ends_announcement_id=warning["id"],
        )
        with pytest.raises(svc.AlertClosed):
            svc.respond(warning["id"], _user(R_ATI, "resident"), status="safe")
        with pytest.raises(ValueError, match="already ended"):
            svc.publish(ACTOR, title="Again", body="x", category="all_clear", target_type="all",
                        ends_announcement_id=warning["id"])
        ended = svc.get_one(warning["id"], _user(R_ATI, "resident"))
    assert _notified(db) == {R_ATI, R_CAR, R_UNK}
    assert clear["details"]["ends_title"] == EVAC["title"]
    assert ended["is_active"] is False and ended["is_open"] is False
    assert ended["ended_by"]["id"] == clear["id"]



def test_all_clear_needs_an_alert_to_end():
    db = _db()
    with _on(db), pytest.raises(ValueError, match="which alert"):
        svc.publish(ACTOR, title="All clear", body="x", category="all_clear", target_type="all")


# ── Before migration 043 ─────────────────────────────────────────────────────

class _OldSchemaDB(FakeDB):
    """A database that predates 043: inserting any of its columns fails the way
    PostgREST fails."""

    NEW = {"details", "target_municipalities", "target_barangays", "asks_response",
           "issuer_agency_type", "ends_announcement_id"}

    def table(self, name):
        q = super().table(name)
        if name != "announcements":
            return q
        original = q.execute

        def execute():
            if q._mode == "insert" and isinstance(q._payload, dict) and self.NEW & set(q._payload):
                raise RuntimeError("{'code': 'PGRST204', 'message': \"Could not find the 'details' column\"}")
            return original()
        q.execute = execute
        return q


def test_a_plain_announcement_still_goes_out_before_the_migration():
    db = _OldSchemaDB(_db().tables)
    with _on(db):
        row = svc.publish(ACTOR, title="Maintenance", body="Down at 2am", category="maintenance", target_type="resident")
    assert row["id"] and len(_notified(db)) == 6


def test_a_safety_alert_before_the_migration_says_what_to_run():
    db = _OldSchemaDB(_db().tables)
    with _on(db), pytest.raises(svc.SchemaNotReady, match="043_announcements_safety_alerts.sql"):
        svc.publish(ACTOR, **EVAC)
    assert db.rows("notifications") == []


# ── Through HTTP ─────────────────────────────────────────────────────────────

def _auth(uid, role, agency_id=None):
    user = MagicMock(); user.id = uid
    got = MagicMock(); got.user = user
    profile = MagicMock()
    profile.data = {
        "id": uid, "email": f"{uid}@example.test", "full_name": uid, "role": role,
        "approval_status": "not_required", "agency_id": agency_id, "agency_type": "MDRRMO",
        "badge_id": None, "is_verified": True,
    }
    db = MagicMock()
    db.auth.get_user.return_value = got
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


# One token per account: the auth dependency caches the profile by token.
H: dict = {}


def _auth_as(uid, agency_type):
    db = _auth(uid, "provincial_admin")
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value.data["agency_type"] = agency_type
    return db


@contextmanager
def _as(uid, role, db, agency_id=None):
    H["Authorization"] = f"Bearer token-{uid}"
    with patch("app.core.dependencies.get_supabase", return_value=_auth(uid, role, agency_id)), _on(db):
        yield


def test_http_publish_answer_board_and_reached():
    db = _db()
    body = {**EVAC}
    with _as(P, "provincial_admin", db):
        preview = client.post("/announcements/audience", json=body, headers=H)
        created = client.post("/announcements/", json=body, headers=H)
    assert preview.status_code == 200 and preview.json()["resident"] == 3
    assert created.status_code == 201, created.text
    aid = created.json()["id"]

    with _as(R_ATI, "resident", db):
        feed = client.get("/announcements/", headers=H)
        answered = client.post(f"/announcements/{aid}/respond", json={"status": "need_help", "note": "Tulong"}, headers=H)
    assert feed.status_code == 200 and [a["id"] for a in feed.json()] == [aid]
    assert answered.status_code == 200, answered.text

    with _as(R_LAR, "resident", db):
        assert client.post(f"/announcements/{aid}/respond", json={"status": "safe"}, headers=H).status_code == 404
        assert client.get(f"/announcements/{aid}/responses", headers=H).status_code == 403

    with _as(NM, "agency_admin", db, AG_NM):
        station_feed = client.get("/announcements/", headers=H)
        board = client.get(f"/announcements/{aid}/responses", headers=H)
        reached = client.post(f"/announcements/{aid}/responses/{R_ATI}/reached", json={"reached": True}, headers=H)
    assert station_feed.json()[0]["response_counts"]["need_help_open"] == 1
    assert board.status_code == 200 and board.json()["tally"]["need_help"] == 1
    assert reached.status_code == 200 and reached.json()["handled_at"]

    with _as(P, "provincial_admin", db):
        clear = client.post("/announcements/", json={
            "title": "All clear", "body": "Uwi na po", "category": "all_clear", "ends_announcement_id": aid,
        }, headers=H)
    assert clear.status_code == 201, clear.text
    with _as(R_CAR, "resident", db):
        late = client.post(f"/announcements/{aid}/respond", json={"status": "safe"}, headers=H)
    assert late.status_code == 409


def test_http_refuses_a_kind_that_is_not_the_office_s():
    db = _db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_as(P2, "PNP")), _on(db):
        H["Authorization"] = "Bearer token-pnp"
        resp = client.post("/announcements/", json=EVAC, headers=H)
    assert resp.status_code == 403 and "PDRRMO" in resp.json()["detail"]


def test_http_refuses_bad_input():
    db = _db()
    with _as(P, "provincial_admin", db):
        assert client.post("/announcements/", json={**EVAC, "category": "nope"}, headers=H).status_code == 422
        assert client.post("/announcements/", json={**EVAC, "details": {}}, headers=H).status_code == 422
    with _as(R_ATI, "resident", db):
        assert client.post("/announcements/", json=EVAC, headers=H).status_code == 403
        assert client.post("/announcements/nope/respond", json={"status": "later"}, headers=H).status_code == 422
        assert client.get("/announcements/does-not-exist", headers=H).status_code == 404
