"""
/triage — inspection and evaluation of the speech-to-text pipeline.

Not part of the report path. `POST /incidents` runs triage inline and needs
nothing here; these endpoints exist so the recognition stage can be measured
and debugged from a real handset, which is the only place its behaviour is
worth measuring.

Authenticated because the vocabulary reveals how severity is decided, and
because an unauthenticated text endpoint is free compute for anyone who finds
it.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.core.dependencies import get_current_user
from app.services import transcript_eval, triage_service

router = APIRouter()


class TranscriptEvalRequest(BaseModel):
    said: str = Field(
        ...,
        max_length=2000,
        description="Ground truth — what the speaker actually said.",
    )
    heard: str = Field(
        "",
        max_length=2000,
        description="What the recogniser produced. May be empty when it heard nothing.",
    )
    locale: str | None = Field(
        None,
        max_length=32,
        description="Recogniser locale used, e.g. ceb_PH. Recorded, not acted on.",
    )


@router.post("/evaluate-transcript")
def evaluate_transcript(
    body: TranscriptEvalRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Score one spoken-vs-transcribed pair.

    Returns Word Error Rate and, separately, critical word accuracy — how many
    of the words that change a dispatch decision survived. WER alone misleads
    here: the first live Waray sample scored 60% while getting `sunog` right
    and losing only a place name the app takes from GPS anyway.

    Both are reported twice, before and after the pipeline's normalisation and
    Ziren's speech corrections, so the correction layer is measured rather than
    asserted.

    The critical vocabulary is read from the loaded model — the same
    emergency_terms.csv and BARANGAYS list the triage pass uses. It is not
    duplicated here and not returned wholesale, so a client cannot drift out of
    step with it.
    """
    result = transcript_eval.evaluate(said=body.said, heard=body.heard)
    if body.locale:
        result["locale"] = body.locale
    return result


@router.get("/status")
def triage_status(current_user: dict = Depends(get_current_user)):
    """
    What the triage model is, and how many speech corrections are loaded.

    The same payload `/health` carries, plus the correction count — useful from
    a handset when a transcript came back uncorrected and the question is
    whether the override file was picked up at all.
    """
    status = triage_service.status()
    status["stt_corrections"] = len(triage_service._load_stt_corrections())
    return status
