"""
Which recogniser actually serves Ziren — measured, not assumed.

Run:
    python tools/measure_asr.py tools/asr_clips.csv

What it answers
---------------
Not "which model has the lowest word error rate". Ziren does not act on
transcripts; it acts on the SIGNALS pulled out of them and the SEVERITY those
produce. A transcript can be badly wrong and perfectly useful, and it can be
nearly perfect and useless. Both happen, and only the second is dangerous.

So every clip is scored four ways, cheapest to truest:

  WER              comparability with published work, and nothing else
  critical words   did the emergency vocabulary survive (transcript_eval)
  signal recall    did predict.extract() recover the same signals
  severity match   would the dispatcher have seen the same ranking

The last one is the one to put in a Results chapter. It is the only score that
says whether the recogniser changed what happens to the resident.

Input
-----
A CSV with a header. `clip` is a Supabase Storage path (as stored in
incidents.media_urls) or a local file. `said` is ground truth — what you know
you actually said. `heard` is optional: paste the on-device transcript from
Settings -> Speech diagnostic to score it here alongside the server engines.

    clip,said,heard
    05d9749f-.../1788118244670.m4a,"may sunog sa balay duha kabook ang na trap",
    local:clips/waray_02.m4a,"mayda sunog didi ha Caibiran","mayda sunog didiha kaibigan"

Engines
-------
Discovered, never required. Nothing here installs a model, and a missing one
is skipped with a line saying so — the script is useful the day before any
engine exists, because the `heard` column alone produces the on-device table.

To add one, write a function returning an object with .name, .version and
.transcribe(audio: bytes, filename: str) -> {"text": ...}, and register it in
ENGINE_LOADERS. That is the same contract transcription_service takes, so
whatever wins here can be registered in production unchanged.
"""
from __future__ import annotations

import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ziren_backend"))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
for _k in ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY", "SUPABASE_KEY"):
    os.environ.setdefault(_k, "dummy")

from app.ml.tools import predict                      # noqa: E402
from app.services import transcript_eval              # noqa: E402
from app.services import triage_service               # noqa: E402


# ── Engines ─────────────────────────────────────────────────────────────────

def _load_faster_whisper(model_size: str = "small"):
    """OpenAI Whisper via CTranslate2. Baseline, with a caveat that matters.

    Whisper's language set includes Tagalog but NOT Cebuano or Waray. Fed
    Waray it does not fail loudly: it decodes it as Tagalog and returns fluent,
    confident, wrong text. That is worse than a garbled transcript, because
    extract() will happily pull signals out of it. Included so that claim is
    measured rather than repeated.
    """
    from faster_whisper import WhisperModel  # noqa: PLC0415

    model = WhisperModel(model_size, device="cpu", compute_type="int8")

    class Engine:
        name = f"faster-whisper-{model_size}"
        version = "ct2"

        def transcribe(self, audio: bytes, *, filename: str) -> dict:
            segments, info = model.transcribe(io.BytesIO(audio), beam_size=5)
            return {
                "text": " ".join(s.text for s in segments).strip(),
                "language": info.language,
            }

    return Engine()


def _load_mms():
    """Meta MMS — the only mainstream model with an explicit Waray adapter.

    Same domain caveat as every candidate here: MMS was trained on read
    religious recordings, and a panicking caller in wind noise is nowhere near
    that distribution. Its published numbers will not survive contact with
    these clips, which is exactly why the clips exist.
    """
    import torch  # noqa: PLC0415
    from transformers import AutoProcessor, Wav2Vec2ForCTC  # noqa: PLC0415

    model_id = "facebook/mms-1b-all"
    processor = AutoProcessor.from_pretrained(model_id)
    model = Wav2Vec2ForCTC.from_pretrained(model_id)

    class Engine:
        name = "mms-1b-all"
        version = "war"

        def __init__(self):
            processor.tokenizer.set_target_lang("war")
            model.load_adapter("war")

        def transcribe(self, audio: bytes, *, filename: str) -> dict:
            import soundfile as sf  # noqa: PLC0415

            wav, sr = sf.read(io.BytesIO(audio))
            inputs = processor(wav, sampling_rate=sr, return_tensors="pt")
            with torch.no_grad():
                logits = model(**inputs).logits
            ids = torch.argmax(logits, dim=-1)[0]
            return {"text": processor.decode(ids), "language": "war"}

    return Engine()


ENGINE_LOADERS = {
    "faster-whisper-small": lambda: _load_faster_whisper("small"),
    "faster-whisper-medium": lambda: _load_faster_whisper("medium"),
    "mms-war": _load_mms,
}


# Where asr_engines caches CTranslate2 weights. Checked before loading so the
# script never triggers a download.
_MODEL_DIR = os.path.join(ROOT, "ziren_backend", "app", "ml", "asr_models")

_CACHE_DIR_FOR = {
    "faster-whisper-small": "models--Systran--faster-whisper-small",
    "faster-whisper-medium": "models--Systran--faster-whisper-medium",
    # MMS comes from the HuggingFace cache, not this directory, so it is only
    # ever loaded when named explicitly on the command line.
    "mms-war": None,
}


def _is_cached(label: str) -> bool:
    sub = _CACHE_DIR_FOR.get(label)
    if sub is None:
        return False
    return os.path.isdir(os.path.join(_MODEL_DIR, sub))


def available_engines(requested: list[str] | None = None) -> list:
    """Engines to score with.

    Without `requested`, only engines whose weights are ALREADY on disk are
    loaded. A measurement script that quietly downloads one-and-a-half
    gigabytes because a name appears in a dict is not one anybody should run
    twice — the first version of this did exactly that and died allocating
    67 MB mid-download. Naming an engine explicitly is consent to fetch it.
    """
    engines = []
    for label, loader in ENGINE_LOADERS.items():
        if requested is not None:
            if label not in requested:
                continue
        elif not _is_cached(label):
            print("  not cached %-22s (name it explicitly to download)" % label)
            continue
        try:
            engines.append(loader())
        except Exception as e:
            print("  skipped %-24s (%s: %s)" % (label, type(e).__name__, e))
    return engines


# ── Clips ───────────────────────────────────────────────────────────────────

def load_audio(clip: str) -> bytes | None:
    if clip.startswith("local:"):
        path = os.path.join(ROOT, clip[len("local:"):])
        if not os.path.exists(path):
            return None
        return open(path, "rb").read()

    from app.db.supabase_client import get_supabase  # noqa: PLC0415

    try:
        return get_supabase().storage.from_("incident-media").download(clip)
    except Exception as e:
        print("  could not download %s: %s" % (clip, e))
        return None


# ── Scoring ─────────────────────────────────────────────────────────────────

def signals_of(text: str) -> dict:
    sig, _hedged = predict.extract(text)
    return {k: v for k, v in sig.items() if v is not None}


def severity_of(text: str) -> str | None:
    result = triage_service.triage(report_text=text, incident_category=None)
    if result is None or result["severity"] is None:
        return None
    return result["severity"].value


def score(said: str, heard: str) -> dict:
    ev = transcript_eval.evaluate(said, heard)
    raw = ev["raw"]

    want = signals_of(said)
    got = signals_of(heard)
    # Recall, not accuracy: a signal invented from a mis-hearing is a different
    # failure from one that was lost, and they are counted separately below.
    kept = sum(1 for k, v in want.items() if got.get(k) == v)
    invented = sum(1 for k, v in got.items() if want.get(k) != v)

    sev_said, sev_heard = severity_of(said), severity_of(heard)

    return {
        "wer": raw["word_error_rate"].get("wer"),
        "critical": raw["critical_words"],
        "signals_want": len(want),
        "signals_kept": kept,
        "signals_invented": invented,
        "sev_said": sev_said,
        "sev_heard": sev_heard,
        "sev_match": sev_said == sev_heard,
        "heard": heard,
    }


def pct(part, whole):
    if not whole:
        return "  n/a"
    return "%5.0f%%" % (100.0 * part / whole)


def main(csv_path: str, requested: list[str] | None = None) -> None:
    rows = list(csv.DictReader(open(csv_path, encoding="utf-8-sig")))
    rows = [r for r in rows if (r.get("said") or "").strip()]
    if not rows:
        print("No clips with ground truth in %s" % csv_path)
        return

    triage_service.load()

    print("clips with ground truth: %d\n" % len(rows))
    print("loading engines:")
    engines = available_engines(requested)
    if not engines:
        print("  none installed — scoring the `heard` column only\n")
    else:
        print()

    results: dict[str, list[dict]] = {}

    for row in rows:
        said = row["said"].strip()
        clip = (row.get("clip") or "").strip()

        # The on-device transcript, if one was pasted in.
        pre = (row.get("heard") or "").strip()
        if pre:
            results.setdefault("on-device", []).append(score(said, pre))

        if not engines or not clip:
            continue
        audio = load_audio(clip)
        if audio is None:
            continue
        for eng in engines:
            try:
                out = eng.transcribe(audio, filename=clip)
            except Exception as e:
                print("  %s failed on %s: %s" % (eng.name, clip, e))
                continue
            results.setdefault(eng.name, []).append(
                score(said, (out or {}).get("text", ""))
            )

    if not results:
        print("Nothing scored. Add a `heard` column, or install an engine.")
        return

    # ── the table ───────────────────────────────────────────────────────────
    print("%-22s %6s %8s %9s %9s %9s" % (
        "ENGINE", "WER", "CRITICAL", "SIGNALS", "INVENTED", "SEVERITY"))
    print("-" * 70)
    for name, scored in results.items():
        wers = [s["wer"] for s in scored if s["wer"] is not None]
        crit_total = sum(s["critical"].get("total", 0) for s in scored)
        crit_ok = sum(s["critical"].get("recognised", 0) for s in scored)
        want = sum(s["signals_want"] for s in scored)
        kept = sum(s["signals_kept"] for s in scored)
        invented = sum(s["signals_invented"] for s in scored)
        sev_ok = sum(1 for s in scored if s["sev_match"])
        print("%-22s %5.0f%% %8s %9s %9d %9s" % (
            name,
            100.0 * sum(wers) / len(wers) if wers else 0.0,
            pct(crit_ok, crit_total),
            pct(kept, want),
            invented,
            pct(sev_ok, len(scored)),
        ))

    print("\nWER            lower is better; least meaningful column here")
    print("CRITICAL       emergency vocabulary that survived (transcript_eval)")
    print("SIGNALS        signals predict.extract() still recovered")
    print("INVENTED       signals the transcript created that were never said")
    print("               — the dangerous column: a confident mis-hearing")
    print("SEVERITY       clips where the dispatcher would see the same ranking")
    print("               — the one that decides which engine ships")

    # Per-clip detail, so a bad aggregate can be traced to the clip that caused it.
    for name, scored in results.items():
        print("\n%s" % name)
        for s in scored:
            flag = "" if s["sev_match"] else "   <-- ranking changed"
            print("  %-4s %s -> %s%s" % (
                "%.0f%%" % (100 * s["wer"]) if s["wer"] is not None else "?",
                s["sev_said"], s["sev_heard"], flag))
            print("      heard: %s" % s["heard"][:96])


if __name__ == "__main__":
    # measure_asr.py [clips.csv] [engine ...]
    args = sys.argv[1:]
    path = args[0] if args else os.path.join(ROOT, "tools", "asr_clips.csv")
    main(path, args[1:] or None)
