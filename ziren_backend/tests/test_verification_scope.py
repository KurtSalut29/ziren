"""
Resident verification is scoped to one municipality for an agency_admin —
Naval's station verifies Naval residents, never Kawayan's or Almeria's. See
user_service._agency_admin_municipality / _assert_verification_scope.

Toggled both ways per row: an agency_admin acting on their OWN municipality's
resident must still succeed, and acting on ANOTHER municipality's must 403 —
a test that only checks the block could pass by accident if the function
always raised.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from tests.audit_helpers import patch_audit_action
from app.services import user_service

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
NAVAL_ADMIN = {"id": "d0000004-0000-0000-0000-000000000004", "role": "agency_admin", "agency_id": AGENCY_ID}
PROVINCIAL_ADMIN = {"id": "e0000005-0000-0000-0000-000000000005", "role": "provincial_admin", "agency_type": "BFP"}

NAVAL_RESIDENT = "f0000006-0000-0000-0000-000000000006"
KAWAYAN_RESIDENT = "f0000007-0000-0000-0000-000000000007"


class _FakeQuery:
    """A chainable fake that flattens `.eq(field, value)` calls onto a
    caller-owned list regardless of how deep or in what order they're chained
    — list_verification_queue chains a variable number of them
    (role, then verification_level + not_.is_, then municipality_address), and
    asserting against a `MagicMock`'s auto-generated `.eq.return_value.eq...`
    chain shape breaks the moment that order changes for an unrelated reason.
    Every other method (.order/.limit/.single/.maybe_single/.not_/.is_/...)
    just returns self so any chain length terminates at .execute()."""

    def __init__(self, eq_calls, result):
        self._eq_calls = eq_calls
        self._result = result

    def eq(self, field, value):
        self._eq_calls.append((field, value))
        return self

    def execute(self):
        return self._result

    def __call__(self, *a, **k):
        return self

    def __getattr__(self, _name):
        # Covers both property-style chaining (`.not_.is_(...)`) and
        # method-style chaining (`.single()`) — this object IS the next link
        # either way, and is itself callable via __call__ above.
        return self


def _db(*, agency_municipality="Naval", resident_municipality="Naval", resident_row=None, users_eq_calls=None):
    """Routes db.table("agencies")... and db.table("users")... independently,
    the same per-table MagicMock routing test_incident_review.py uses — but
    the users table is the eq-call-flattening fake above, since
    list_verification_queue's tests need to see every filter applied."""
    agencies_table = MagicMock()
    agencies_result = MagicMock()
    agencies_result.data = {"municipality": agency_municipality}
    agencies_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = agencies_result

    users_result = MagicMock()
    users_result.data = resident_row if resident_row is not None else {
        "id": NAVAL_RESIDENT, "role": "resident", "municipality_address": resident_municipality,
        "valid_id_image_path": None, "selfie_image_path": None,
        "barangays": None,
    }
    eq_calls = users_eq_calls if users_eq_calls is not None else []
    users_table = MagicMock()
    users_table.select.return_value = _FakeQuery(eq_calls, users_result)
    # decide_verification's final .update(...).eq(...).execute()
    users_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": NAVAL_RESIDENT}])

    db = MagicMock()
    db.table.side_effect = lambda name: {"agencies": agencies_table, "users": users_table}.get(name, MagicMock())
    return db


# ── _agency_admin_municipality ───────────────────────────────────────────

def test_agency_admin_municipality_resolves_own_agency():
    db = _db(agency_municipality="Naval")
    with patch("app.services.geographic_service.get_supabase", return_value=db):
        assert user_service._agency_admin_municipality(NAVAL_ADMIN) == "Naval"


def test_provincial_admin_has_no_municipality_lock():
    # Should not even query the agencies table for a role with no single agency.
    assert user_service._agency_admin_municipality(PROVINCIAL_ADMIN) is None


# ── get_verification_detail ──────────────────────────────────────────────

def test_get_verification_detail_allows_own_municipality():
    db = _db(agency_municipality="Naval", resident_municipality="Naval")
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db):
        row = user_service.get_verification_detail(NAVAL_RESIDENT, current_user=NAVAL_ADMIN)
    assert row["municipality_address"] == "Naval"


def test_get_verification_detail_blocks_other_municipality():
    db = _db(agency_municipality="Naval", resident_municipality="Kawayan")
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            user_service.get_verification_detail(KAWAYAN_RESIDENT, current_user=NAVAL_ADMIN)
    assert exc.value.status_code == 403


def test_get_verification_detail_unscoped_for_provincial_admin():
    # A provincial_admin has no municipality lock, so a Kawayan resident is
    # not blocked for them the way it is for the Naval agency_admin above.
    db = _db(resident_municipality="Kawayan")
    with patch("app.services.user_service.get_supabase", return_value=db):
        row = user_service.get_verification_detail(KAWAYAN_RESIDENT, current_user=PROVINCIAL_ADMIN)
    assert row["municipality_address"] == "Kawayan"


# ── decide_verification ──────────────────────────────────────────────────

def test_decide_verification_allows_own_municipality():
    resident_row = {
        "id": NAVAL_RESIDENT, "role": "resident", "municipality_address": "Naval",
        "valid_id_image_path": None, "selfie_image_path": None,
    }
    db = _db(agency_municipality="Naval", resident_row=resident_row)
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db), \
         patch_audit_action() as audit:
        result = user_service.decide_verification(
            NAVAL_RESIDENT, approve=True, method="barangay_official",
            reviewer_id=NAVAL_ADMIN["id"], purge_images=False, current_user=NAVAL_ADMIN,
        )
    assert result["verification_level"] == 2
    # Finding #7: the decision names who made it, on the resident and in the log.
    assert result["reviewed_by"] == NAVAL_ADMIN["id"]
    assert result["decision"] == "approved"
    assert audit.call_args.kwargs["action"] == "verification.approved"


def test_decide_verification_blocks_other_municipality():
    resident_row = {
        "id": KAWAYAN_RESIDENT, "role": "resident", "municipality_address": "Kawayan",
        "valid_id_image_path": None, "selfie_image_path": None,
    }
    db = _db(agency_municipality="Naval", resident_row=resident_row)
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            user_service.decide_verification(
                KAWAYAN_RESIDENT, approve=True, method="barangay_official",
                reviewer_id=NAVAL_ADMIN["id"], purge_images=False, current_user=NAVAL_ADMIN,
            )
    assert exc.value.status_code == 403


# ── list_verification_queue ──────────────────────────────────────────────

def test_list_verification_queue_forces_own_municipality_for_agency_admin():
    eq_calls = []
    db = _db(agency_municipality="Naval", users_eq_calls=eq_calls, resident_row=[])
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db):
        # Even asking for Kawayan explicitly, an agency_admin gets Naval's filter.
        user_service.list_verification_queue(municipality="Kawayan", current_user=NAVAL_ADMIN)

    assert ("municipality_address", "Naval") in eq_calls
    assert ("municipality_address", "Kawayan") not in eq_calls


def test_list_verification_queue_leaves_provincial_admin_filter_alone():
    eq_calls = []
    db = _db(users_eq_calls=eq_calls, resident_row=[])
    with patch("app.services.user_service.get_supabase", return_value=db):
        user_service.list_verification_queue(municipality="Kawayan", current_user=PROVINCIAL_ADMIN)

    assert ("municipality_address", "Kawayan") in eq_calls
