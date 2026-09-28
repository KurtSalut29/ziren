"""
Turning a resident's voice note into text, after the report is already safe.

Why this exists
---------------
The recording is the truth. A dispatcher in Naval who speaks Waray understands
it perfectly, which is more than any transcriber of Waray currently manages.
But a recording cannot be ranked: the dispatcher queue is ordered by severity,
severity comes from the triage model, and the model reads text. Thirty voice
notes in a typhoon would have to be played one at a time, in real time, to find
the worst one.

So the audio is what a human listens to, and the transcript is what the machine
sorts by. The transcript only has to be good enough to RANK — a far lower bar
than being good enough to act on, and the dispatcher always has the recording
to check it against.

Why it runs after the insert, never during
------------------------------------------
Transcription takes seconds to tens of seconds. `incident_service` already
settled the principle for the triage model:

    triage() never raises and never blocks the save. A resident in an
    emergency must never lose their report because a classifier is down.

The same holds here, more strongly: this one needs a network round trip to
Storage before it can even start. The report lands first with its audio
attached — the dispatcher can play it within seconds — and the transcript
sharpens the ranking a moment later.

Why there is no engine in here
------------------------------
None is installed, deliberately. Which recogniser reads Waray and Bisaya best
is a question to answer by measurement, on real recordings from real handsets,
and those only started existing today. Until one is chosen, `transcribe()`
returns None and the whole path no-ops: reports still land, still carry their
audio, and are still ranked on what the resident typed.

Registering one is a single call — see `register_engine`.
"""

from __future__ import annotations

from typing import Any, Protocol

import structlog

from app.db.supabase_client import get_supabase
from app.models.incident import IncidentCategory, IncidentStatus
from app.services import triage_service

log = structlog.get_logger()


# ── What counts as transcribable ─────────────────────────────────────────────
#
# Kept here rather than imported from dispatch_service: that module answers
# "how should the dashboard render this attachment", which is a presentation
# question. This one answers "can speech be recovered from it", and the two
# will not always have the same answer — a video has audio a dispatcher can
# hear, but feeding it to a recogniser needs a demux step this does not do.
_AUDIO_EXT = (".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus")

_BUCKET = "incident-media"

# Anything longer is not a voice note. A 60-second clip at the app's 32 kbps is
# roughly 240 KB; this leaves generous headroom for a different encoder while
# still refusing to pull something unbounded into memory.
_MAX_BYTES = 8 * 1024 * 1024


class TranscriptionEngine(Protocol):
    """The whole contract an ASR backend has to satisfy.

    Kept this small on purpose. Swapping faster-whisper for a fine-tuned
    Philippine model, or for a hosted API, should not touch anything outside
    the object registered here.
    """

    name: str
    version: str

    def transcribe(self, audio: bytes, *, filename: str) -> dict[str, Any]:
        """Return at least {"text": str}. May add "language", "confidence"."""
        ...


_engine: TranscriptionEngine | None = None


def register_engine(engine: TranscriptionEngine | None) -> None:
    """Install (or remove) the recogniser. Call once at startup."""
    global _engine
    _engine = engine
    log.info(
        "transcription.engine_registered",
        engine=getattr(engine, "name", None),
        version=getattr(engine, "version", None),
    )


def is_available() -> bool:
    return _engine is not None


def status() -> dict:
    """Mirrors triage_service.status() so /health can report both alike."""
    return {
        "engine": getattr(_engine, "name", None),
        "version": getattr(_engine, "version", None),
        "available": _engine is not None,
        "reason": None if _engine else "No transcription engine registered.",
    }


def is_transcribable(path: str) -> bool:
    return bool(path) and path.lower().endswith(_AUDIO_EXT)


def pick_audio(media_urls: list[str] | None) -> str | None:
    """The first attachment speech could be recovered from, if any."""
    for path in media_urls or []:
        if is_transcribable(path):
            return path
    return None


def transcribe(audio: bytes, *, filename: str) -> dict[str, Any] | None:
    """Text from audio, or None when no engine is installed or it failed.

    Never raises. A recogniser falling over must not be able to damage an
    incident that is already saved and already actionable.
    """
    if _engine is None:
        return None
    try:
        result = _engine.transcribe(audio, filename=filename)
    except Exception as e:  # noqa: BLE001 - see docstring
        log.warning("transcription.failed", filename=filename, error=str(e))
        return None

    text = (result or {}).get("text") or ""
    if not text.strip():
        return None
    return {
        "text": text.strip(),
        "engine": getattr(_engine, "name", "unknown"),
        "engine_version": getattr(_engine, "version", "unknown"),
        "language": (result or {}).get("language"),
        "confidence": (result or {}).get("confidence"),
    }


def _compose_report_text(existing: str | None, transcript: str) -> str:
    """What the incident should read as once the words are recovered.

    The category label the app prefixes ("Sunog / Fire") is not a report, and
    replacing the resident's own typed words with a machine's guess at their
    speech would be worse than either. So the transcript is appended, and the
    typed text always stays first and intact.
    """
    base = (existing or "").strip()
    if not base:
        return transcript
    if transcript.lower() in base.lower():
        return base
    return f"{base} — {transcript}"


def transcribe_incident(incident_id: str, audio_path: str) -> None:
    """Background task: recover the words, then re-rank the incident.

    Runs after the row exists. Everything here is best-effort by design; the
    report is already saved, already carries its audio, and is already visible
    to a dispatcher before this starts.
    """
    if _engine is None:
        # Not a warning. This is the configured state until a recogniser is
        # chosen by measurement, and logging it as a problem every report would
        # bury the ones that are.
        log.info("transcription.skipped_no_engine", incident_id=incident_id)
        return

    db = get_supabase()

    try:
        row = (
            db.table("incidents")
            .select("id, report_text, status, severity, signals, "
                    "incident_category, wizard_answers, overlap_agencies, "
                    "landmark_note")
            .eq("id", incident_id)
            .single()
            .execute()
        ).data
    except Exception as e:  # noqa: BLE001
        log.warning("transcription.row_unreadable", incident_id=incident_id, error=str(e))
        return

    if not row:
        return

    # A dispatcher has already acted on this. Rewriting the text under them,
    # or re-scoring a severity they set by hand, would be worse than having no
    # transcript at all.
    if row.get("status") not in (IncidentStatus.received.value,):
        log.info("transcription.skipped_already_handled",
                 incident_id=incident_id, status=row.get("status"))
        return

    try:
        audio = db.storage.from_(_BUCKET).download(audio_path)
    except Exception as e:  # noqa: BLE001
        log.warning("transcription.download_failed",
                    incident_id=incident_id, path=audio_path, error=str(e))
        return

    if not audio or len(audio) > _MAX_BYTES:
        log.warning("transcription.rejected_size",
                    incident_id=incident_id, bytes=len(audio or b""))
        return

    result = transcribe(audio, filename=audio_path)
    if result is None:
        return

    text = _compose_report_text(row.get("report_text"), result["text"])

    # Re-run triage on the words we now have. This is the point of the whole
    # exercise: until this moment the incident was ranked on its category
    # alone, because a resident who speaks contributes no text.
    update: dict[str, Any] = {"report_text": text}
    signals = dict(row.get("signals") or {})

    # The resident's own category has to be passed back in. Dropping it would
    # make triage read this as an unasserted model guess, and SR005B and the
    # SR010/SR011 fail-safes treat those differently on purpose: someone who
    # taps MEDICAL is asserting a person is in distress, and that assertion
    # survives however the transcript reads. Re-scoring without it can lower a
    # severity the resident already justified.
    category = None
    raw_category = row.get("incident_category")
    if raw_category:
        try:
            category = IncidentCategory(raw_category)
        except ValueError:
            # A category retired by a later migration must not stop the
            # transcript from being saved.
            log.warning("transcription.unknown_category",
                        incident_id=incident_id, category=raw_category)

    triaged = triage_service.triage(
        report_text=text,
        incident_category=category,
        wizard_answers=row.get("wizard_answers"),
        overlap_agencies=row.get("overlap_agencies"),
        landmark_note=row.get("landmark_note"),
    )
    if triaged is not None:
        signals = dict(triaged["signals"])
        if triaged["severity"] is not None:
            update["severity"] = triaged["severity"].value

    # Provenance, always. A dispatcher reading this text is entitled to know a
    # machine heard it rather than a person typing it, and which machine.
    signals["transcript"] = {
        "text": result["text"],
        "engine": result["engine"],
        "engine_version": result["engine_version"],
        "language": result.get("language"),
        "confidence": result.get("confidence"),
        "audio_path": audio_path,
        "note": "Machine transcription of the resident's recording. "
                "The audio is authoritative.",
    }
    update["signals"] = signals

    try:
        db.table("incidents").update(update).eq("id", incident_id).execute()
        log.info(
            "transcription.applied",
            incident_id=incident_id,
            engine=result["engine"],
            chars=len(result["text"]),
            severity=update.get("severity"),
        )
    except Exception as e:  # noqa: BLE001
        log.warning("transcription.update_failed", incident_id=incident_id, error=str(e))


def schedule(background, incident_id: Any, media_urls: list[str] | None) -> None:
    """Queue transcription for a freshly created incident, if it has audio.

    `background` is a FastAPI BackgroundTasks, which runs the task AFTER the
    response has been sent. That ordering is the whole point: nothing here can
    delay or fail the 201 the resident is waiting on.

    media_urls comes from the submitted request rather than the response, which
    does not carry attachments.
    """
    audio_path = pick_audio(media_urls)
    if not audio_path or not incident_id:
        return
    background.add_task(transcribe_incident, str(incident_id), audio_path)
