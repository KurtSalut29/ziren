"""The resident is told the verification decision at once (user report
2026-10-08: an approval reached the phone only when the app was reopened, and
nothing said so). Approval is what lets a resident report since 2026-10-07."""

from unittest.mock import patch

import pytest
from fastapi import HTTPException

from tests.audit_helpers import patch_audit_action
from tests.test_verification_scope import KAWAYAN_RESIDENT, NAVAL_ADMIN, NAVAL_RESIDENT, _db
from app.services import user_service


def _decide(*, approve, resident_municipality="Naval", resident_id=NAVAL_RESIDENT, notify=None):
    row = {
        "id": resident_id, "role": "resident", "municipality_address": resident_municipality,
        "valid_id_image_path": None, "selfie_image_path": None,
    }
    db = _db(agency_municipality="Naval", resident_row=row)
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_user", side_effect=notify) as tell, \
         patch_audit_action():
        try:
            result = user_service.decide_verification(
                resident_id, approve=approve, method="government_id" if approve else None,
                reviewer_id=NAVAL_ADMIN["id"], purge_images=False, current_user=NAVAL_ADMIN,
            )
        except HTTPException as exc:
            result = exc
    return result, tell


def test_an_approval_tells_the_resident():
    result, tell = _decide(approve=True)
    assert result["verification_level"] == 2
    tell.assert_called_once()
    assert tell.call_args.args[0] == NAVAL_RESIDENT
    kw = tell.call_args.kwargs
    assert kw["type_"] == "account.verified"
    assert kw["is_important"] is True
    assert "report" in kw["body"].lower()


def test_a_rejection_tells_the_resident_what_to_do():
    result, tell = _decide(approve=False)
    assert result["verification_level"] == 0
    kw = tell.call_args.kwargs
    assert kw["type_"] == "account.verification_rejected"
    assert "photo" in kw["body"].lower()


def test_a_notice_that_fails_does_not_undo_the_decision():
    def boom(*_a, **_k):
        raise RuntimeError("notifications table unreachable")

    result, _ = _decide(approve=True, notify=boom)
    assert result["verification_level"] == 2


def test_a_refused_decision_tells_nobody():
    result, tell = _decide(approve=True, resident_municipality="Kawayan", resident_id=KAWAYAN_RESIDENT)
    assert isinstance(result, HTTPException) and result.status_code == 403
    tell.assert_not_called()


@pytest.mark.parametrize("approve", [True, False])
def test_the_bulk_decision_tells_each_resident(approve):
    calls = []
    with patch.object(user_service, "_tell_resident_of_decision", side_effect=lambda uid, **kw: calls.append(uid)):
        row = {
            "id": NAVAL_RESIDENT, "role": "resident", "municipality_address": "Naval",
            "valid_id_image_path": None, "selfie_image_path": None,
        }
        db = _db(agency_municipality="Naval", resident_row=row)
        with patch("app.services.user_service.get_supabase", return_value=db), \
             patch("app.services.geographic_service.get_supabase", return_value=db), \
             patch_audit_action():
            out = user_service.decide_verification_bulk(
                [NAVAL_RESIDENT, NAVAL_RESIDENT], approve=approve,
                method="government_id" if approve else None,
                reviewer_id=NAVAL_ADMIN["id"], purge_images=False, current_user=NAVAL_ADMIN,
            )
    assert out["decided"] == 1  # duplicates dropped
    assert calls == [NAVAL_RESIDENT]


def _decide_with_images(approve):
    row = {
        "id": NAVAL_RESIDENT, "role": "resident", "municipality_address": "Naval",
        "valid_id_image_path": "ids/n06.jpg", "selfie_image_path": "selfies/n06.jpg",
    }
    db = _db(agency_municipality="Naval", resident_row=row)
    with patch("app.services.user_service.get_supabase", return_value=db), \
         patch("app.services.geographic_service.get_supabase", return_value=db), \
         patch("app.services.notification_service.create_for_user"), \
         patch_audit_action():
        user_service.decide_verification(
            NAVAL_RESIDENT, approve=approve, method="government_id" if approve else None,
            reviewer_id=NAVAL_ADMIN["id"], purge_images=True, current_user=NAVAL_ADMIN,
        )
    removed = [c.args[0] for c in db.storage.from_.return_value.remove.call_args_list]
    written = db.table("users").update.call_args.args[0]
    return removed, written


def test_an_approval_keeps_the_selfie_for_the_id_card_and_drops_the_scan():
    removed, written = _decide_with_images(True)
    assert removed == [["ids/n06.jpg"]]
    assert written["valid_id_image_path"] is None
    assert "selfie_image_path" not in written


def test_a_rejection_keeps_neither_image():
    removed, written = _decide_with_images(False)
    assert removed == [["ids/n06.jpg"], ["selfies/n06.jpg"]]
    assert written["valid_id_image_path"] is None and written["selfie_image_path"] is None
