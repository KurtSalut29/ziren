"""
Does the selfie belong to the person on the ID?

WHAT THIS IS FOR

Verification is a queue of people waiting for an administrator to look at two
photographs and decide whether they are the same face. On a province-sized
deployment that is hours of work in which almost every decision is "yes", and
the few that are not are exactly the ones fatigue makes it easiest to miss.

So this does not replace the administrator. It sorts the queue for them: an
obvious match arrives already labelled as one, and anything doubtful is pushed
to the top of the list with a reason attached. The requirement it answers was
stated exactly that way -- make the check automatic "so that admins will just
double check the users".

WHAT IT MUST NEVER DO

Decide. `verification_level` is raised by a human, and nothing in this file is
permitted to raise it -- the same rule migration 020 states for liveness, for
the same reason. Concretely:

  - A `no_match` verdict does not reject anybody. It flags a submission for a
    closer look. A resident whose ID photograph is fifteen years old, or who
    has since had chemotherapy, or who wears a hijab in one image and not the
    other, is a person this model will score badly and an administrator will
    approve in four seconds.
  - Verification is not a permission anywhere in Ziren. An unverified resident
    reports an emergency exactly like a verified one (migration 012). Whatever
    this returns, nobody is prevented from calling for help.

WHY THE THRESHOLDS ARE NOT A GUARANTEE

The bands below come from the operating points published for this embedding
family on academic benchmarks -- LFW, CFP-FP, AgeDB -- which are photographs of
faces. They have NOT been validated on the actual distribution here: a
laminated Philippine ID card, often years old and printed at low resolution,
re-photographed under a phone flash at an angle, against a phone selfie. That
domain shift is large and it moves scores DOWN, which means false "no_match"
is the expected failure and false "match" the rarer one. That asymmetry is the
right way round for a pre-screen, and it is still a reason to keep every band
advisory. UNCERTAIN is deliberately wide for the same reason.

THE DETECTION GATE IS LOAD-BEARING

Measured while building this: two buffers of pure random noise, containing no
face at all, score 0.83 against each other -- more than twice the match
threshold. That is not a bug in the model. ArcFace is trained only on faces and
has no concept of "not a face"; out-of-distribution input collapses toward a
common direction in the embedding space, and any two such inputs then look
alike.

The consequence is concrete and worth stating where someone will read it before
changing the wiring: this function CANNOT tell you whether it was given a face.
It can only tell you whether two faces agree. If a caller ever hands it a
photograph of a wall and a photograph of a floor, it will answer "match", with
a high score, and the score will look like evidence.

So the ML Kit detection on the handset is not a convenience that saves a
round trip -- it is the only thing standing between this feature and confident
nonsense. `compare` is called ONLY when a face was found in both images.
Absence of a face is its own verdict (`no_face_on_id`, `no_face_in_selfie`),
decided before this code runs, and any future path into this function has to
carry the same guarantee.

WHERE THE FACES COME FROM

The client sends two already-aligned 112x112 crops, not photographs. Detection
and the five-point alignment run on the handset in ML Kit, which is already
integrated for the liveness challenge and is the part of this pipeline with the
most testing behind it. That choice also keeps a face detector out of this
process entirely -- SCRFD post-processing is several hundred lines of anchor
decoding and NMS that would have to be right, and is not needed when the phone
has already done the job.

Crops arrive as RAW RGB rather than JPEG, which is why nothing here decodes an
image format. 112*112*3 is 37,632 bytes, base64 to about 50 KB, and the server
needs no imaging library at all -- notably not Pillow, which is not a
dependency of this project and would be a heavy one to add for a resize this
code never performs. It also avoids a JPEG round trip softening a crop that has
already been resampled once during alignment.

MODEL

buffalo_s / w600k_mbf, the MobileFaceNet-scale ArcFace recogniser from the
InsightFace model zoo, 13.6 MB, run on CPU through onnxruntime -- which is
already installed as a transitive dependency of faster-whisper, so this adds no
new package.

The weights are NOT committed; they are fetched by scripts/fetch_face_model.py.
A deployment that has not fetched them is a SUPPORTED state, not a broken one:
every call returns verdict "unavailable" and the reviewing administrator does
the comparison by eye exactly as they did before. That mirrors how
transcription_service treats a missing ASR engine, and it is the only honest
way to ship an optional 13 MB binary.

InsightFace publishes these weights for non-commercial research use. This is
academic work; a commercial deployment would need to revisit that.
"""

from __future__ import annotations

import base64
import math
import os
import threading
from pathlib import Path

import structlog

log = structlog.get_logger()

# ── Model location ───────────────────────────────────────────

_MODEL_DIR = Path(__file__).resolve().parent.parent / "ml_models" / "face"
_MODEL_PATH = _MODEL_DIR / "w600k_mbf.onnx"

#: Recorded on every result. A later threshold change or model swap has to be
#: distinguishable in the stored data, or scores from two different models sit
#: in one column looking comparable.
MODEL_NAME = "buffalo_s/w600k_mbf"

# ── Input contract ───────────────────────────────────────────

FACE_SIZE = 112
_EXPECTED_BYTES = FACE_SIZE * FACE_SIZE * 3

# ── Decision bands ───────────────────────────────────────────

#: At or above: the faces agree well enough that an administrator confirming is
#: a formality. Derived from the published ~1e-4 FAR operating point for this
#: embedding family.
MATCH_AT = 0.36

#: Below: the faces disagree enough to be worth a human's attention FIRST.
#: Not "these are different people" -- see the module docstring on domain shift.
NO_MATCH_BELOW = 0.18

# ── Lazy singleton ───────────────────────────────────────────

_session = None
_load_lock = threading.Lock()
_load_failed = False


def _get_session():
    """Load the ONNX session once, on first use.

    Not at import time. This module is imported by the users router, which is
    imported by app.main -- loading 13 MB of weights there would put a hard
    dependency on an optional file into application startup, and a deployment
    that has not fetched the model would fail to boot rather than degrade.
    """
    global _session, _load_failed

    if _session is not None or _load_failed:
        return _session

    with _load_lock:
        # Re-checked inside the lock: two requests arriving together would
        # otherwise both pass the check above and load the model twice.
        if _session is not None or _load_failed:
            return _session

        if not _MODEL_PATH.exists():
            log.info(
                "face_match.model_absent",
                path=str(_MODEL_PATH),
                hint="run scripts/fetch_face_model.py to enable automatic face matching",
            )
            _load_failed = True
            return None

        try:
            import onnxruntime as ort

            _session = ort.InferenceSession(
                str(_MODEL_PATH),
                providers=["CPUExecutionProvider"],
                sess_options=_session_options(ort),
            )
            log.info("face_match.model_loaded", model=MODEL_NAME)
        except Exception:
            log.warning("face_match.model_load_failed", exc_info=True)
            _load_failed = True
            return None

    return _session


def _session_options(ort):
    opts = ort.SessionOptions()
    # One thread. This runs on the same box as the API and the triage model,
    # once per registration, on a 13 MB network — letting onnxruntime claim
    # every core for a 20 ms inference would cost more in contention with
    # request handling than it saves in latency.
    opts.intra_op_num_threads = 1
    opts.inter_op_num_threads = 1
    return opts


def is_available() -> bool:
    """Whether automatic matching can run at all in this deployment."""
    return _get_session() is not None


# ── Embedding ────────────────────────────────────────────────

def _embed(rgb: bytes) -> list[float]:
    """One 112x112 RGB crop to a unit-length 512-d embedding."""
    import numpy as np

    session = _get_session()
    if session is None:
        raise RuntimeError("face model not loaded")

    arr = np.frombuffer(rgb, dtype=np.uint8).astype(np.float32)
    arr = arr.reshape(FACE_SIZE, FACE_SIZE, 3)
    # ArcFace's preprocessing: scale to [-1, 1] and transpose HWC -> CHW.
    arr = (arr - 127.5) / 127.5
    arr = arr.transpose(2, 0, 1)[None, ...]

    out = session.run(None, {session.get_inputs()[0].name: arr})[0][0]

    # L2-normalise so the comparison below is a plain dot product. ArcFace is
    # trained with an angular margin, so ONLY the direction of the embedding
    # carries identity — its magnitude tracks image quality and would otherwise
    # let a sharp photograph of a stranger outscore a blurry one of the right
    # person.
    norm = math.sqrt(sum(float(v) * float(v) for v in out)) or 1.0
    return [float(v) / norm for v in out]


def _mirror(rgb: bytes) -> bytes:
    """Flip a 112x112 RGB crop horizontally.

    Cheap: a reversed view along the width axis, copied out. No imaging
    library, no decode -- the buffer is already raw pixels.
    """
    import numpy as np

    arr = np.frombuffer(rgb, dtype=np.uint8).reshape(FACE_SIZE, FACE_SIZE, 3)
    return arr[:, ::-1, :].tobytes()


def _decode(payload: str, field: str) -> bytes:
    """Base64 to raw RGB, with the length checked rather than assumed.

    A wrong length here would reshape into garbage and produce a confident
    score for noise, which is the worst possible failure for this feature: a
    number that looks like evidence and is not.
    """
    try:
        raw = base64.b64decode(payload, validate=True)
    except Exception:
        raise ValueError(f"{field} is not valid base64")

    if len(raw) != _EXPECTED_BYTES:
        raise ValueError(
            f"{field} must be {_EXPECTED_BYTES} bytes of raw RGB "
            f"({FACE_SIZE}x{FACE_SIZE}x3), got {len(raw)}"
        )
    return raw


# ── Public API ───────────────────────────────────────────────

def compare(id_face_rgb_b64: str, selfie_face_rgb_b64: str) -> dict:
    """Compare an ID portrait against a selfie.

    Both arguments are base64 of a raw 112x112x3 RGB buffer, aligned on the
    handset. Returns a dict shaped for storage and for display:

        {score, verdict, model, threshold_match, threshold_no_match, available}

    `score` is cosine similarity in [-1, 1]; in practice face embeddings are
    non-negative against each other, so the useful range is roughly [0, 1].
    It is None when no comparison was possible.

    Never raises for a missing model — that is a supported deployment state.
    """
    base = {
        "model": MODEL_NAME,
        "threshold_match": MATCH_AT,
        "threshold_no_match": NO_MATCH_BELOW,
    }

    if not is_available():
        return {
            **base,
            "score": None,
            "score_direct": None,
            "score_flipped": None,
            "verdict": "unavailable",
            "available": False,
        }

    id_rgb = _decode(id_face_rgb_b64, "id_face")
    selfie_rgb = _decode(selfie_face_rgb_b64, "selfie_face")

    a = _embed(id_rgb)

    # MATCHED BOTH WAYS ROUND, AND THE BETTER SCORE WINS.
    #
    # Whether a front-camera still arrives mirrored is a property of the
    # handset, not of the platform: Android's Camera2 spec says it should not
    # be, and a large share of OEM builds mirror it anyway. The client corrects
    # for that with SelfieOrientation.mirrorFrontCamera -- which is a FIXED
    # GUESS, true for Android and false for iOS, because there is no reliable
    # runtime test for "was this image mirrored".
    #
    # On a handset where that guess is wrong, the selfie ends up reversed
    # RELATIVE TO THE ID CARD, and a face scored against its own mirror image
    # lands well below where the same pair belongs -- plausibly straight into
    # the "uncertain" band. That failure would be per-device, silent, and
    # indistinguishable from a genuinely doubtful pair.
    #
    # Taking the max over the flip removes the whole class of error. It is also
    # ordinary practice: test-time horizontal-flip augmentation is standard for
    # face recognition, because a mirrored face is the same face. The cost is
    # one extra 13 MB inference, about 20 ms.
    #
    # It does NOT make the client-side flag pointless. That flag decides what
    # an administrator SEES when they hold the selfie against the ID, and a
    # reversed photograph is harder for a person to compare even when the
    # machine no longer cares.
    b_direct = _embed(selfie_rgb)
    b_flipped = _embed(_mirror(selfie_rgb))

    score_direct = sum(x * y for x, y in zip(a, b_direct))
    score_flipped = sum(x * y for x, y in zip(a, b_flipped))
    score = max(score_direct, score_flipped)

    if score >= MATCH_AT:
        verdict = "match"
    elif score < NO_MATCH_BELOW:
        verdict = "no_match"
    else:
        verdict = "uncertain"

    # Both scores are logged, not just the winner. The GAP between them is the
    # only evidence available about whether a given handset mirrors its stills,
    # and it is what a future change to mirrorFrontCamera would have to be
    # argued from. A large positive gap for `flipped` on one device model means
    # that model does not mirror and the client is flipping it needlessly.
    #
    # The scores are logged; the crops are not, and never should be. They are
    # biometric data, and a log line is the one place in this system nobody
    # thinks to apply a retention policy to.
    log.info(
        "face_match.compared",
        score=round(score, 4),
        score_direct=round(score_direct, 4),
        score_flipped=round(score_flipped, 4),
        verdict=verdict,
    )

    # Both scores are returned, not only the winner. `score` is what the row
    # stores and what an admin reads; the pair beside it is what a later
    # investigation into a particular handset's mirroring would need, and it
    # costs nothing to carry. Callers that only read `score` are unaffected.
    return {
        **base,
        "score": round(score, 4),
        "score_direct": round(score_direct, 4),
        "score_flipped": round(score_flipped, 4),
        "verdict": verdict,
        "available": True,
    }


def describe(verdict: str, score: float | None) -> str:
    """A sentence for the person, or the administrator, reading the result.

    Written to be read by someone who is not being asked to trust it. Every
    line says who decides, because a screen that says "no match" and nothing
    else reads as a rejection to the person standing in front of it.
    """
    if verdict == "match":
        return "The photo on your ID and your selfie look like the same person."
    if verdict == "uncertain":
        return (
            "We could not tell for sure whether the ID photo and your selfie "
            "match. That is common with older or worn ID cards. An admin will "
            "check."
        )
    if verdict == "no_match":
        return (
            "The photo on your ID does not look like your selfie. If you used "
            "someone else's ID by mistake, retake it. Otherwise continue — an "
            "admin will review both photos."
        )
    if verdict == "no_face_on_id":
        return (
            "We could not find a face on the ID photo. Make sure the whole "
            "card is in frame, right side up, and not covered by glare."
        )
    if verdict == "no_face_in_selfie":
        return "We could not find your face in the selfie. Please retake it."
    return "Automatic checking is off. An admin will compare the photos."


def env_summary() -> dict:
    """Health-check shape: is matching on, and where would the weights live."""
    return {
        "available": is_available(),
        "model": MODEL_NAME,
        "model_path": str(_MODEL_PATH),
        "model_present": _MODEL_PATH.exists(),
        "size_mb": (
            round(os.path.getsize(_MODEL_PATH) / 1e6, 1)
            if _MODEL_PATH.exists()
            else None
        ),
    }
