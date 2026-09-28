"""/system-status — Provincial Admin's service health page (spec Section 13)."""

from fastapi import APIRouter, Depends

from app.core.config import settings
from app.core.dependencies import require_provincial_admin
from app.services import dispatch_service, responder_ack, system_status_service, transcription_service
from app.ml.tools.predict import FLAG_THRESHOLD

router = APIRouter()


@router.get("/")
def get_system_status(current_user: dict = Depends(require_provincial_admin)):
    checks = system_status_service.check_all()
    return {
        "checks": checks,
        "all_operational": all(c["status"] == "operational" for c in checks),
    }


@router.get("/config")
def get_system_config(current_user: dict = Depends(require_provincial_admin)):
    """
    The limits and thresholds this deployment actually runs on, read from the
    code and environment that enforce them — never a copy typed into a form.

    Read-only on purpose. These are set in code or in the server's environment
    (rate limits, the classifier's confidence bar, upload caps) and changing one
    is a deployment decision with a restart, not a switch in a browser. Showing
    them lets an administrator answer "why was I blocked" or "how long a
    recording is accepted" without reading the source.
    """
    severities = ("critical", "high", "medium", "low")
    return {
        "environment": settings.environment,
        "limits": {
            "live_queue_max": dispatch_service.QUEUE_MAX,
            "records_page_max": dispatch_service.HISTORY_PAGE_MAX,
            "voice_recording_max_mb": transcription_service._MAX_BYTES // (1024 * 1024),
        },
        "rate_limits": {
            "login": settings.rate_limit_login,
            "incident_submit": settings.rate_limit_incident_submit,
            "sos_submit": settings.rate_limit_sos_submit,
        },
        "triage": {"confidence_flag_threshold": FLAG_THRESHOLD},
        "ack_deadline_seconds": {
            **{sev: responder_ack.deadline_seconds(sev) for sev in severities},
            "unscored": responder_ack.deadline_seconds(None),
        },
        "password_policy": {"min_length": 8, "requires_uppercase": True, "requires_digit": True},
    }
