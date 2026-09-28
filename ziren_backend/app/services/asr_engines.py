"""
Recognisers that can be plugged into `transcription_service`.

Each loader returns an object satisfying `TranscriptionEngine`: `.name`,
`.version`, and `.transcribe(audio: bytes, *, filename: str) -> {"text": ...}`.
Nothing here is imported at module load — a missing package must degrade to
"no engine", which is a supported state, not an outage.

Which one to run is a measurement, not a preference. `tools/measure_asr.py`
scores candidates on the thing that decides whether a recogniser ships: not
word error rate, but whether the dispatcher would have seen the same severity.
"""

from __future__ import annotations

import io
import os
from typing import Any

import structlog

log = structlog.get_logger()

# Where CTranslate2 caches downloaded weights. Kept inside the repo's ml tree
# rather than the user profile so the model sits with the other artefacts the
# project version-controls the provenance of.
_MODEL_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml", "asr_models"
)


class FasterWhisperEngine:
    """OpenAI Whisper via CTranslate2 — the Filipino baseline.

    Read the language caveat before trusting any Waray output from this.
    Whisper's language set includes Tagalog but NOT Cebuano or Waray. Given
    Waray it does not fail loudly: it decodes it as the nearest language it
    knows and returns fluent, confident, wrong Tagalog. That is more dangerous
    than a garbled transcript, because `predict.extract()` will mine signals
    out of it and the severity rules will act on them.

    So it is registered here as a baseline and for Filipino, and the
    `INVENTED` column in tools/measure_asr.py is the one to watch: signals a
    mis-hearing created that were never said.
    """

    def __init__(self, model_size: str = "small", language: str | None = None):
        from faster_whisper import WhisperModel  # noqa: PLC0415

        self.name = f"faster-whisper-{model_size}"
        self.version = "ct2"
        self._language = language

        os.makedirs(_MODEL_DIR, exist_ok=True)
        # int8 on CPU: roughly four times faster than float32 with a WER cost
        # far smaller than the gap between any two candidates here. This runs
        # on a laptop that is also serving the API.
        self._model = WhisperModel(
            model_size,
            device="cpu",
            compute_type="int8",
            download_root=_MODEL_DIR,
        )

    def transcribe(self, audio: bytes, *, filename: str) -> dict[str, Any]:
        segments, info = self._model.transcribe(
            io.BytesIO(audio),
            beam_size=5,
            language=self._language,
            # The recordings are one person reporting an emergency, often with
            # pauses. VAD trims the silence the encoder would otherwise spend
            # time on and that Whisper is prone to hallucinating into.
            vad_filter=True,
        )
        segments = list(segments)
        return {
            "text": " ".join(s.text.strip() for s in segments).strip(),
            "language": getattr(info, "language", None),
            "confidence": getattr(info, "language_probability", None),
        }


def load(name: str) -> Any | None:
    """Build an engine by name, or None if it cannot be built.

    Never raises. A recogniser that fails to load must leave the API serving
    exactly as it does with none installed.
    """
    try:
        if name in ("faster-whisper-small", "faster-whisper"):
            return FasterWhisperEngine("small")
        if name == "faster-whisper-medium":
            return FasterWhisperEngine("medium")
        if name == "faster-whisper-small-fil":
            # Pinning the language stops Whisper guessing, which on Visayan
            # speech it does badly and confidently.
            return FasterWhisperEngine("small", language="tl")
        log.warning("asr.unknown_engine", requested=name)
        return None
    except Exception as e:  # noqa: BLE001 — see docstring
        log.warning("asr.engine_load_failed", requested=name, error=str(e))
        return None
