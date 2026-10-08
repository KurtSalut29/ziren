"""The ID/selfie face comparison, and the things it must never claim.

This is a pre-screen for the verification queue, so the tests are mostly about
its LIMITS rather than its accuracy. Accuracy is a property of a published
model on a domain it was not trained for; the parts this codebase is
responsible for are:

  - the input contract, because a wrong-length buffer reshapes into noise and
    produces a confident score for nothing;
  - degradation, because the weights are an optional 13 MB download and a
    deployment without them must keep working;
  - the wording, because every message on that screen sits above two
    irreversible buttons.

Run with: pytest tests/test_face_match.py -v
"""

import base64
import os

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import face_match_service as fm

client = TestClient(app)

MODEL_PRESENT = fm.is_available()
needs_model = pytest.mark.skipif(
    not MODEL_PRESENT,
    reason="face model not installed — run scripts/fetch_face_model.py",
)


def _buf(n: int = fm.FACE_SIZE * fm.FACE_SIZE * 3) -> str:
    return base64.b64encode(os.urandom(n)).decode()


class TestTheInputContract:
    """A wrong-length buffer must be refused, not reshaped.

    numpy will happily reinterpret whatever it is given, and the model will
    happily embed the result. The failure mode without this check is not a
    crash — it is a number that looks exactly like evidence.
    """

    @pytest.mark.parametrize("length", [1, 100, 37_631, 37_633, 200_000])
    def test_a_wrong_length_buffer_is_refused(self, length):
        with pytest.raises(ValueError, match="bytes of raw RGB"):
            fm.compare(_buf(length), _buf())

    def test_the_error_names_the_field_and_the_lengths(self):
        with pytest.raises(ValueError) as exc:
            fm.compare(_buf(10), _buf())
        message = str(exc.value)
        assert "id_face" in message
        assert "37632" in message
        assert "got 10" in message

    def test_the_second_field_is_checked_too(self):
        with pytest.raises(ValueError, match="selfie_face"):
            fm.compare(_buf(), _buf(10))

    def test_non_base64_is_refused(self):
        with pytest.raises(ValueError, match="not valid base64"):
            fm.compare("not base64 at all !!", _buf())


class TestBands:
    """The verdict is a banding of the score, and the bands are ordered."""

    def test_the_thresholds_do_not_overlap(self):
        assert fm.NO_MATCH_BELOW < fm.MATCH_AT

    @needs_model
    def test_identical_input_scores_at_the_top_of_the_range(self):
        b = _buf()
        result = fm.compare(b, b)
        assert result["verdict"] == "match"
        assert result["score"] == pytest.approx(1.0, abs=0.01)

    @needs_model
    def test_every_result_names_the_model_and_the_thresholds(self):
        """A score with no model beside it is not comparable to anything.

        Two models' scores in one column look like one measurement, and a
        threshold change months later is invisible without this.
        """
        result = fm.compare(_buf(), _buf())
        # Tagged with the crop alignment it was scored from (ALIGN_VERSION).
        assert result["model"] == fm.SCORED_MODEL == "buffalo_s/w600k_mbf@align2"
        assert result["threshold_match"] == fm.MATCH_AT
        assert result["threshold_no_match"] == fm.NO_MATCH_BELOW


@needs_model
def test_the_model_cannot_tell_a_face_from_noise():
    """The documented limitation, pinned as a test so it cannot be forgotten.

    Two buffers of pure random noise — no face in either — score well ABOVE the
    match threshold against each other. ArcFace has no concept of "not a face";
    out-of-distribution input collapses toward a common direction and any two
    such inputs then look alike.

    This is not a bug to fix here. It is the reason the ML Kit detection on the
    handset is load-bearing: `compare` is called only when a face was found in
    BOTH images, and absence of a face is its own verdict decided before this
    code runs. If that gate is ever removed, this test is the record of what it
    was holding back.
    """
    score = fm.compare(_buf(), _buf())["score"]
    assert score > fm.MATCH_AT, (
        "noise no longer scores as a match — if the model changed, revisit "
        "whether the client-side detection gate is still required"
    )


class TestDescriptions:
    """Every message sits above two irreversible buttons."""

    @pytest.mark.parametrize(
        "verdict",
        ["match", "uncertain", "no_match", "no_face_on_id",
         "no_face_in_selfie", "unavailable"],
    )
    def test_every_verdict_has_a_sentence(self, verdict):
        text = fm.describe(verdict, 0.5)
        assert text and text[0].isupper() and text.endswith(".")

    def test_a_mismatch_never_reads_as_a_rejection(self):
        """It says what to do and who decides, because a person reading
        "no match" with nothing after it will assume they have been refused."""
        text = fm.describe("no_match", 0.1).lower()
        assert "admin" in text
        assert "continue" in text

    def test_an_unknown_verdict_still_returns_something_usable(self):
        assert fm.describe("something_new", None)


class TestTheEndpoint:
    def test_a_malformed_crop_is_a_422_that_says_why(self):
        r = client.post(
            "/auth/face-match", json={"id_face": "AAAA", "selfie_face": "AAAA", "align": 2}
        )
        assert r.status_code == 422
        assert "raw RGB" in r.json()["detail"]

    def test_it_needs_no_token(self):
        """Registration runs before the account exists, so there is no session
        to authenticate with. Rate limiting is the control here, not auth."""
        r = client.post(
            "/auth/face-match", json={"id_face": _buf(), "selfie_face": _buf()}
        )
        assert r.status_code == 200

    @needs_model
    def test_the_response_carries_a_message_for_the_screen(self):
        r = client.post(
            "/auth/face-match", json={"id_face": _buf(), "selfie_face": _buf()}
        )
        body = r.json()
        assert body["message"]
        assert body["verdict"] in {
            "match", "uncertain", "no_match", "unavailable",
        }


def test_a_missing_model_is_a_supported_state_not_an_error(monkeypatch):
    """The weights are an optional download. A deployment without them must
    return a verdict, not a 500 — the reviewing admin then does exactly what
    they did before this feature existed.
    """
    monkeypatch.setattr(fm, "_session", None)
    monkeypatch.setattr(fm, "_load_failed", True)

    result = fm.compare(_buf(), _buf())
    assert result["verdict"] == "unavailable"
    assert result["score"] is None
    assert result["available"] is False
    assert "admin" in fm.describe("unavailable", None).lower()


class TestFlipInvariance:
    """A mirrored face is the same face, and the score must say so.

    Whether a front-camera still arrives mirrored is a property of the handset.
    The client corrects for it with a FIXED platform guess — Android yes, iOS
    no — because there is no reliable runtime test for it. On a handset where
    that guess is wrong, the selfie is reversed relative to the ID card, and
    without this the pair would score as a stranger. Per-device, silent, and
    indistinguishable from a genuinely doubtful pair.
    """

    def test_mirroring_twice_returns_the_original(self):
        raw = os.urandom(fm.FACE_SIZE * fm.FACE_SIZE * 3)
        assert fm._mirror(fm._mirror(raw)) == raw

    def test_mirror_reverses_columns_and_leaves_rows_alone(self):
        import numpy as np

        raw = os.urandom(fm.FACE_SIZE * fm.FACE_SIZE * 3)
        a = np.frombuffer(raw, dtype=np.uint8).reshape(112, 112, 3)
        b = np.frombuffer(fm._mirror(raw), dtype=np.uint8).reshape(112, 112, 3)
        # Column 0 of the mirror is the last column of the original.
        assert np.array_equal(b[:, 0, :], a[:, -1, :])
        # A vertical flip would also pass the check above, so pin that rows
        # are untouched: mirroring must not rotate the face.
        assert np.array_equal(b[0, :, :][::-1], a[0, :, :])

    @needs_model
    def test_a_mirrored_selfie_scores_the_same_as_an_unmirrored_one(self):
        """The property the max() exists to provide.

        Same crop, compared against itself and against its own mirror. Both
        must reach the same verdict — otherwise a handset that mirrors and one
        that does not would give two different answers about one face.
        """
        raw = os.urandom(fm.FACE_SIZE * fm.FACE_SIZE * 3)
        b = base64.b64encode(raw).decode()
        flipped = base64.b64encode(fm._mirror(raw)).decode()

        direct = fm.compare(b, b)
        mirrored = fm.compare(b, flipped)
        assert direct["verdict"] == mirrored["verdict"]
        assert mirrored["score"] == pytest.approx(direct["score"], abs=0.02)

    @needs_model
    def test_both_scores_are_reported_not_just_the_winner(self):
        """The gap between them is the only evidence about whether a given
        handset mirrors its stills, and it is what any future change to
        mirrorFrontCamera would have to be argued from."""
        b = _buf()
        result = fm.compare(b, b)
        assert "score_direct" in result
        assert "score_flipped" in result
        assert result["score"] == max(
            result["score_direct"], result["score_flipped"]
        )


class TestOldAppBuilds:
    """App builds before 2026-10-08 sent crops that were the whole photo
    shrunk, not the face (eyes and mouth mirrored onto the template), and this
    model scores any two non-faces as a match. They are not scored."""

    def test_an_old_build_is_answered_unavailable_not_scored(self, monkeypatch):
        called = []
        monkeypatch.setattr(fm, "compare", lambda *a: called.append(a))
        r = client.post("/auth/face-match", json={"id_face": _buf(), "selfie_face": _buf()})
        assert r.status_code == 200
        body = r.json()
        assert body["verdict"] == "unavailable" and body["score"] is None
        assert body["message"]
        assert called == []

    def test_stored_verdicts_from_old_builds_are_shown_as_not_checked(self):
        from app.services.user_service import _discount_stale_face_match

        old = {"face_match_verdict": "match", "face_match_score": 0.83, "face_match_model": fm.MODEL_NAME}
        _discount_stale_face_match(old)
        assert old["face_match_verdict"] == "unavailable" and old["face_match_score"] is None
        assert old["face_match_stale"] is True and old["face_match_stale_verdict"] == "match"

        new = {"face_match_verdict": "no_match", "face_match_score": 0.1, "face_match_model": fm.SCORED_MODEL}
        _discount_stale_face_match(new)
        assert new["face_match_verdict"] == "no_match" and "face_match_stale" not in new

        # Decided on the phone before any score: true whatever the alignment.
        no_face = {"face_match_verdict": "no_face_on_id", "face_match_model": None}
        _discount_stale_face_match(no_face)
        assert no_face["face_match_verdict"] == "no_face_on_id"
