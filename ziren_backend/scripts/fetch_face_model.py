"""
Fetch the face-recognition weights that automatic ID/selfie matching needs.

    .venv\\Scripts\\python.exe scripts\\fetch_face_model.py

Downloads one 13.6 MB ONNX file to app/ml_models/face/. Safe to re-run: an
existing file with the right size is left alone.

WHY THIS IS A SCRIPT AND NOT A COMMITTED FILE

13.6 MB of binary in git is 13.6 MB in every clone, every branch, and every
future rewrite of the history. It is also not ours to redistribute: InsightFace
publishes buffalo_s for NON-COMMERCIAL research use. This is academic work, so
that fits — but it fits as "the deployment fetches it", not as "we vendored
it".

WHAT HAPPENS IF YOU NEVER RUN THIS

Nothing breaks. face_match_service treats a missing model as a supported state:
every comparison returns verdict "unavailable", the registration flow says so
plainly, and the reviewing administrator compares the two photographs by eye
exactly as they did before this feature existed. That is the same contract
transcription_service has with a missing ASR engine, and it is deliberate —
an optional 13 MB download must never be load-bearing for registration.
"""

import hashlib
import sys
import urllib.request
from pathlib import Path

# recognition/model.onnx from the InsightFace buffalo_s pack, mirrored by the
# Immich project. w600k_mbf: MobileFaceNet-scale ArcFace, 512-d embeddings.
URL = "https://huggingface.co/immich-app/buffalo_s/resolve/main/recognition/model.onnx"

DEST = Path(__file__).resolve().parent.parent / "app" / "ml_models" / "face" / "w600k_mbf.onnx"

#: Approximate expected size. Used only to notice a truncated or
#: error-page-instead-of-binary download, which is the realistic failure on a
#: rural connection or behind a captive portal — both of which write a small
#: file and exit 0.
MIN_BYTES = 12_000_000
MAX_BYTES = 16_000_000


def main() -> int:
    if DEST.exists() and MIN_BYTES <= DEST.stat().st_size <= MAX_BYTES:
        print(f"already present: {DEST} ({DEST.stat().st_size / 1e6:.1f} MB)")
        return 0

    DEST.parent.mkdir(parents=True, exist_ok=True)
    # Written to a temporary name and renamed, so an interrupted download
    # cannot leave a half-file that looks present to face_match_service.
    tmp = DEST.with_suffix(".onnx.part")

    print(f"downloading {URL}")
    try:
        urllib.request.urlretrieve(URL, tmp)
    except Exception as exc:
        print(f"download failed: {exc}", file=sys.stderr)
        tmp.unlink(missing_ok=True)
        return 1

    size = tmp.stat().st_size
    if not (MIN_BYTES <= size <= MAX_BYTES):
        print(
            f"unexpected size {size} bytes — this is usually an error page "
            f"saved as a file. Not installing it.",
            file=sys.stderr,
        )
        tmp.unlink(missing_ok=True)
        return 1

    tmp.replace(DEST)
    digest = hashlib.sha256(DEST.read_bytes()).hexdigest()
    print(f"installed {DEST} ({size / 1e6:.1f} MB)")
    print(f"sha256 {digest}")
    print()
    print("Automatic ID/selfie face matching is now on. Restart the backend.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
