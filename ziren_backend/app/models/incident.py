"""
Incident Pydantic models.
Keep in sync with public.incidents and public.dispatch_log tables.
"""

from uuid import UUID
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, ConfigDict, computed_field, field_validator, model_validator


class IncidentStatus(str, Enum):
    received = "received"
    processing = "processing"
    dispatched = "dispatched"
    resolved = "resolved"
    cancelled = "cancelled"


class SeverityLevel(str, Enum):
    critical = "critical"
    high = "high"
    medium = "medium"
    low = "low"


class SubmissionChannel(str, Enum):
    internet = "internet"
    offline_sync = "offline_sync"
    sos = "sos"


class IncidentCategory(str, Enum):
    """
    The six categories a resident can choose in Step 1 of the 5W1H wizard.

    `hazmat` and `missing_person` were retired in Phase 4: the triage model
    has no class for either, so a report filed under them could never receive
    a model-derived severity. The remaining five map one-to-one onto the
    model's classes (see triage_service.BACKEND_TO_MODEL) and `other` means
    "the resident did not choose", which the model answers with its own
    reading.

    Both retired concerns survive as OverlapFlag values — a hazmat leak or a
    missing person can still be flagged on a report, it just cannot be the
    report's primary category. Migration 019 rewrote existing rows to `other`
    and preserved the original value in wizard_answers.retired_category.
    """
    fire                      = "fire"
    medical_trauma            = "medical_trauma"
    vehicular                 = "vehicular"
    flood_landslide_calamity  = "flood_landslide_calamity"
    domestic_dispute_crime    = "domestic_dispute_crime"
    other                     = "other"


class VictimRelationship(str, Enum):
    ako_mismo   = "ako_mismo"
    kamag_anak  = "kamag_anak"
    kakilala    = "kakilala"
    estranghero = "estranghero"


class OverlapFlag(str, Enum):
    injuries       = "injuries"
    fire           = "fire"
    flooding       = "flooding"
    missing_person = "missing_person"
    hazmat         = "hazmat"
    none           = "none"


# ── The 15 NLP signals (Phase 4 will populate these) ──────────
class ExtractedSignals(BaseModel):
    # Signal 1: What type of incident
    incident_type: str | None = None
    # Signal 2: Fire-specific sub-type
    fire_type: str | None = None
    # Signal 3: Whether casualties are mentioned
    casualty_mentioned: bool = False
    # Signal 4: Number of injured
    injured_count: int | None = None
    # Signal 5: Number of dead
    dead_count: int | None = None
    # Signal 6: Whether a weapon is mentioned
    weapon_mentioned: bool = False
    # Signal 7: Weapon type if mentioned
    weapon_type: str | None = None
    # Signal 8: Why category (cause/motive)
    why_category: str | None = None
    # Signal 9: How category (method/means)
    how_category: str | None = None
    # Signal 10: Structure involved (house, vehicle, etc.)
    structure_type: str | None = None
    # Signal 11: Whether children are mentioned
    children_involved: bool = False
    # Signal 12: Whether urgency words are used
    urgency_level: str | None = None
    # Signal 13: Whether location is specific
    location_specificity: str | None = None
    # Signal 14: Whether multiple units needed
    multi_agency_needed: bool = False
    # Signal 15: Language detected
    language_detected: str | None = None
    # Confidence score (0–1); below threshold = flagged for dispatcher review
    confidence_score: float = 0.0


# ── What the triage model actually writes (Phase 4) ───────────
class TriageSignals(BaseModel):
    """
    The `incidents.signals` JSONB column, as produced by triage_service.

    This supersedes ExtractedSignals as the *shape of the column*.
    ExtractedSignals is still the vocabulary the rubric engine evaluates
    against, but the trained model emits its own richer payload and that is
    what is stored and returned.

    Every field is optional. A row written before Phase 4 — or by a future
    dataset release that adds a key — must still deserialise; a dispatcher
    losing access to an incident because its signals blob is an unexpected
    shape is a worse failure than a missing field.

    Do not tighten `verification_status` or `severity_level` into enums for
    the same reason: a new rule id or status from a later model release should
    render, not 500.
    """

    # The docstring above promises that a key from a future release still
    # deserialises. Pydantic's default does the opposite on the way OUT: an
    # undeclared key is silently DROPPED when the response is serialised.
    #
    # That is not hypothetical. `transcript` was written to the column, stored
    # correctly, and deleted from every API response — so the confirm screen
    # polled for words the server was throwing away, waited its full forty
    # seconds, and told the resident we could not write down what they said
    # while the transcript sat in the database.
    #
    # extra="allow" makes the docstring true for output as well as input.
    model_config = ConfigDict(extra="allow")

    # Which model produced this, so a severity can be traced to a release
    engine:                   str | None = None   # "ziren-model"
    engine_version:           str | None = None   # matches app/ml/VERSION

    # What the model read the report as
    model_predicted:          str | None = None   # model taxonomy, e.g. "FIRE"
    model_predicted_category: str | None = None   # app taxonomy, e.g. "fire"
    model_confidence:         float | None = None
    runner_up:                dict[str, Any] | None = None

    # What the resident chose, and whether the two agree
    user_selected:            str | None = None
    # AGREE | MISMATCH_FLAGGED | UNCERTAIN | NO_SELECTION | NO_TEXT
    verification_status:      str | None = None
    verification_message:     str | None = None

    # Why this incident got this severity — the audit trail
    severity_level:           str | None = None   # CRITICAL|HIGH|MODERATE|LOW
    severity_rule:            str | None = None   # e.g. "SR002"
    severity_reason:          str | None = None   # e.g. "someone is trapped"

    # What was read from the report, and what stayed unknown
    signals:                  dict[str, Any] = {}
    signals_unknown:          list[str] = []
    signals_from_wizard:      list[str] = []

    # Suggested routing — advisory, never a dispatch
    routing_agencies:         list[str] = []
    routing_based_on:         str | None = None   # user_selected|model_predicted

    # How much the agency suggestion is worth (release 2.1.5). When the
    # resident chose no category and the model is under the flag threshold,
    # the agency rests on a guess — the agencies are still returned so the
    # report reaches someone, but the dispatcher is told to pick.
    # user_selected | model_confident | model_uncertain
    agency_basis:             str | None = None
    needs_manual_agency:      bool = False
    agency_note:              str | None = None

    # A numeral the recogniser welded to the word after it, so any count in
    # this report is suspect. Deliberately not corrected — a wrong count is
    # worse than a missing one, because a dispatcher acts on it.
    count_uncertain:          bool = False
    count_note:               str | None = None

    # Waray/Bisaya spelling corrections applied before signal extraction
    normalisation:            dict[str, Any] | None = None
    disclaimer:               str | None = None

    # What the recogniser made of the resident's voice note, and whether the
    # resident agreed with it. Declared rather than left to extra="allow"
    # because the confirm screen and the dashboard both read it by name: this
    # is part of the contract now, not a passenger.
    #
    #   text                  what the recogniser produced
    #   corrected_to          what the reporter said it should be
    #   confirmed_by_reporter they were asked and agreed
    transcript:               dict[str, Any] | None = None


# ── Request models ──────────────────────────────────────────

class IncidentSubmitRequest(BaseModel):
    report_text:          str
    # Optional since the "faster reporting" change: when omitted, the server
    # resolves the nearest active station from the reporter's coordinates
    # (same path SOS already used). A reporter in an emergency should not be
    # asked which station covers them — they usually do not know.
    # Still accepted when present so the reporter can override the auto-pick.
    station_id:           UUID | None = None
    latitude:             float | None = None
    longitude:            float | None = None
    location_address:     str   | None = None
    media_urls:           list[str]    = []
    submitted_via:        SubmissionChannel = SubmissionChannel.internet

    # ── 5W1H wizard fields (all optional for backwards compat / SOS path) ──
    incident_category:    IncidentCategory   | None = None
    wizard_answers:       dict[str, Any]     | None = None  # JSONB
    overlap_agencies:     list[OverlapFlag]  | None = None
    landmark_note:        str   | None = None
    victim_relationship:  VictimRelationship | None = None

    # ── Reported from somewhere else (migration 042) ──
    # latitude/longitude above are always WHERE THE INCIDENT IS — that is what
    # routes the report and what a crew drives to. When the reporter is not
    # standing there (a relative called them, they saw it from across the
    # bay), the app lets them place the incident on the map and sends where
    # THEY are here, so the dispatcher knows the two differ and can call back
    # to confirm. All optional: absent means "I am at the incident".
    reported_from_elsewhere: bool = False
    reporter_latitude:    float | None = None
    reporter_longitude:   float | None = None
    reporter_address:     str   | None = None

    @field_validator("report_text")
    @classmethod
    def report_text_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Report text cannot be empty.")
        if len(v) < 10:
            raise ValueError("Report text must be at least 10 characters.")
        if len(v) > 5000:
            raise ValueError("Report text cannot exceed 5000 characters.")
        return v

    @field_validator("reporter_latitude")
    @classmethod
    def validate_reporter_latitude(cls, v: float | None) -> float | None:
        if v is not None and not (-90 <= v <= 90):
            raise ValueError("Invalid reporter latitude.")
        return v

    @field_validator("reporter_longitude")
    @classmethod
    def validate_reporter_longitude(cls, v: float | None) -> float | None:
        if v is not None and not (-180 <= v <= 180):
            raise ValueError("Invalid reporter longitude.")
        return v

    @field_validator("reporter_address")
    @classmethod
    def clamp_reporter_address(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        return v[:300] or None

    @field_validator("landmark_note")
    @classmethod
    def clamp_landmark_note(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        if len(v) > 300:
            raise ValueError("Landmark note cannot exceed 300 characters.")
        return v or None

    @field_validator("wizard_answers")
    @classmethod
    def clamp_wizard_answers(cls, v: dict | None) -> dict | None:
        if v is None:
            return v
        import json
        if len(json.dumps(v)) > 4096:
            raise ValueError("Wizard answers payload too large (max 4 KB).")
        return v

    @field_validator("latitude")
    @classmethod
    def validate_latitude(cls, v: float | None) -> float | None:
        if v is not None and not (-90 <= v <= 90):
            raise ValueError("Invalid latitude.")
        return v

    @field_validator("longitude")
    @classmethod
    def validate_longitude(cls, v: float | None) -> float | None:
        if v is not None and not (-180 <= v <= 180):
            raise ValueError("Invalid longitude.")
        return v

    @model_validator(mode="after")
    def require_station_or_coordinates(self) -> "IncidentSubmitRequest":
        """
        station_id became optional so the server can auto-resolve the nearest
        station. But if the client sends neither a station nor coordinates,
        there is nothing to resolve from — reject at the model boundary rather
        than letting the service layer fail deeper in with a vaguer error.
        """
        has_station = self.station_id is not None
        has_coords  = self.latitude is not None and self.longitude is not None
        if not has_station and not has_coords:
            raise ValueError(
                "Provide either station_id or both latitude and longitude "
                "so the nearest station can be resolved."
            )
        return self


class SosSubmitRequest(BaseModel):
    """
    SOS Quick-Report request model.

    Intentionally different from IncidentSubmitRequest:
    - No station_id   — nearest station is derived server-side via PostGIS
    - No report_text  — defaults to "SOS" if omitted; no min-character rule
    - No media_urls   — SOS path skips attachment upload for speed
    - GPS coordinates are strongly encouraged but still optional
      (user may have denied location permission)

    incident_category is optional and, unlike the rest of this model, not new
    for speed's sake — it exists to fix a real gap: without it, the nearest
    station is picked from EVERY agency with no regard for incident type, so
    a medical SOS can be routed to the nearest fire station purely because it
    is geographically closer than the nearest MDRRMO post. See
    _resolve_nearest_station's agency_type_hint parameter.
    """
    # Optional brief description — no minimum length, max 500 chars
    # If omitted, stored as "SOS" to ensure report_text is never blank
    description:      str | None = None
    latitude:         float | None = None
    longitude:        float | None = None
    location_address: str   | None = None
    incident_category: IncidentCategory | None = None
    # The landmark nearest the reporter, filled in by the app from its bundled
    # map data — never typed, so SOS stays one hold of a button.
    landmark_note:    str   | None = None

    @field_validator("landmark_note")
    @classmethod
    def clamp_sos_landmark(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        return v[:300] or None

    @field_validator("description")
    @classmethod
    def clamp_description(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        if len(v) > 500:
            raise ValueError("SOS description cannot exceed 500 characters.")
        return v or None   # treat whitespace-only as None

    @field_validator("latitude")
    @classmethod
    def validate_latitude(cls, v: float | None) -> float | None:
        if v is not None and not (-90 <= v <= 90):
            raise ValueError("Invalid latitude.")
        return v

    @field_validator("longitude")
    @classmethod
    def validate_longitude(cls, v: float | None) -> float | None:
        if v is not None and not (-180 <= v <= 180):
            raise ValueError("Invalid longitude.")
        return v


class SosResponse(BaseModel):
    """Slimmer response for SOS — includes resolved station details."""
    id:               str
    report_text:      str
    status:           IncidentStatus
    submitted_via:    SubmissionChannel
    created_at:       str
    station_id:       str | None
    station_name:     str | None
    agency_type:      str | None
    municipality:     str | None
    latitude:         float | None
    longitude:        float | None


class DispatchLogRequest(BaseModel):
    incident_id: UUID
    agency_id: UUID
    suggested_severity: SeverityLevel | None = None
    chosen_severity: SeverityLevel
    suggested_agency_id: UUID | None = None
    chosen_agency_id: UUID
    was_override: bool = False
    override_reason: str | None = None
    action: str
    notes: str | None = None


# ── Response models ─────────────────────────────────────────

class IncidentResponse(BaseModel):
    id:                  UUID
    reporter_id:         UUID
    station_id:          UUID | None
    report_text:         str
    location_address:    str | None
    latitude:            float | None
    longitude:           float | None
    status:              IncidentStatus
    severity:            SeverityLevel | None
    suggested_agency_id: UUID | None
    assigned_agency_id:  UUID | None
    signals:             TriageSignals | None
    signals_confidence:  float | None
    submitted_via:       SubmissionChannel
    created_at:          datetime
    updated_at:          datetime
    dispatched_at:       datetime | None
    resolved_at:         datetime | None
    # Set when the reporter withdraws their own report (see
    # incident_service.withdraw_incident). Trash retention is measured from
    # this timestamp — see incident_service.TRASH_RETENTION_DAYS.
    withdrawn_at:        datetime | None = None

    # ── The agency's Verification decision (migration 029) ────────
    #
    # Until these were returned the resident's app could not tell a report an
    # agency REJECTED from one the resident withdrew: both are status
    # 'cancelled', so a rejected report was filed straight into Trash with no
    # word about why, and a clarification request never reached the person it
    # was addressed to. review_status is one of pending / accepted / rejected /
    # clarification_requested.
    review_status:              str | None = None
    reviewed_at:                datetime | None = None
    rejection_reason:           str | None = None
    clarification_note:         str | None = None
    clarification_requested_at: datetime | None = None

    # 5W1H wizard fields
    incident_category:   IncidentCategory   | None = None
    wizard_answers:      dict[str, Any]     | None = None
    overlap_agencies:    list[str]          | None = None
    landmark_note:       str               | None = None
    victim_relationship: VictimRelationship | None = None
    nlp_review_needed:   bool                     = False

    # ── What the reporter is told while they wait ─────────────────
    #
    # A resident who reported an emergency has been shown NOTHING
    # afterwards: not who is coming, not whether anyone is. The
    # position needed to answer that has been arriving at
    # PATCH /responder/location all along and being written to a column
    # only the dispatcher's map read.
    #
    # Coarse on purpose, and always rendered as "about N minutes":
    # promising a precise arrival to somebody whose house is on fire is
    # worse than promising nothing.
    eta_minutes:         int  | None = None
    eta_updated_at:      datetime | None = None

    # Which agency is actually coming. The reporter is told the AGENCY,
    # never the responder's name or number: a resident does not need a
    # crew member's identity to be reassured, and handing it out invites
    # direct contact that bypasses the dispatcher entirely.
    responding_agency:   str  | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def meet_code(self) -> str:
        """The reporter tells the arriving crew this; see app/core/meet_code.py."""
        from app.core.meet_code import meet_code
        return meet_code(self.id)


class DispatchLogResponse(BaseModel):
    id: UUID
    incident_id: UUID
    dispatcher_id: UUID
    agency_id: UUID
    suggested_severity: SeverityLevel | None
    chosen_severity: SeverityLevel
    was_override: bool
    override_reason: str | None
    action: str
    notes: str | None
    created_at: datetime
