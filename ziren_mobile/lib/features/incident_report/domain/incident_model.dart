import '../../../l10n/app_localizations.dart';

/// Client-side model for an incident report.
/// Mirrors the FastAPI IncidentResponse schema.
class IncidentModel {
  const IncidentModel({
    required this.id,
    required this.reportText,
    required this.status,
    required this.submittedVia,
    required this.createdAt,
    this.stationId,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.severity,
    this.dispatchedAt,
    this.resolvedAt,
    this.withdrawnAt,
    this.reviewStatus,
    this.reviewedAt,
    this.rejectionReason,
    this.clarificationNote,
    this.clarificationRequestedAt,
    this.signals,
    this.etaMinutes,
    this.respondingAgency,
    this.incidentCategory,
  });

  final String id;
  final String reportText;
  final String status;
  final String submittedVia;
  final DateTime createdAt;
  final String? stationId;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final String? severity;
  final DateTime? dispatchedAt;
  final DateTime? resolvedAt;

  /// Set once the resident withdraws their own report (status becomes
  /// 'cancelled'). Trash retention is measured from this moment — see
  /// [daysUntilPurge] and the backend's matching
  /// incident_service.TRASH_RETENTION_DAYS.
  final DateTime? withdrawnAt;

  /// The agency's Verification decision: `pending`, `accepted`, `rejected` or
  /// `clarification_requested` (backend migration 029).
  ///
  /// Carried because [status] cannot say it. A report the agency REJECTED and a
  /// report the resident WITHDREW are both `cancelled`, so until this was read
  /// a rejected report was filed straight into Trash with no word about why,
  /// and a clarification request - which changes no status at all - never
  /// reached the person it was addressed to.
  final String? reviewStatus;
  final DateTime? reviewedAt;

  /// Why the agency rejected it. Present only when [isRejected].
  final String? rejectionReason;

  /// What the agency asked, and when.
  final String? clarificationNote;
  final DateTime? clarificationRequestedAt;

  /// The agency reviewed this report and did not accept it.
  bool get isRejected => reviewStatus == 'rejected' && status == 'cancelled';

  /// The resident took the report back themselves: status `cancelled`, not a
  /// rejection, and stamped `withdrawn_at` (the backend's withdraw always
  /// stamps it). Only these belong in Trash and are purged after 30 days.
  bool get isWithdrawn =>
      status == 'cancelled' && !isRejected && withdrawnAt != null;

  /// The AGENCY cancelled the report: status `cancelled`, not a rejection, and
  /// never withdrawn by the resident. It used to count as "withdrawn" - so a
  /// report an agency cancelled sat in Trash, next to ones the resident had
  /// binned, with nothing to say who did it or why.
  bool get isCancelledByAgency =>
      status == 'cancelled' && !isRejected && withdrawnAt == null;

  /// The agency is waiting on an answer from the resident.
  bool get needsClarification =>
      reviewStatus == 'clarification_requested' &&
      status != 'resolved' &&
      status != 'cancelled';

  /// The triage blob, kept raw.
  ///
  /// Deliberately not modelled field by field: a later dataset release adds
  /// keys, and a resident must never lose sight of their own report because
  /// its signals payload grew a field this build has not heard of.
  final Map<String, dynamic>? signals;

  /// Minutes until the crew reaches the scene, while one is en route.
  ///
  /// The reporter's half of the loop. Until this existed a resident who
  /// reported an emergency was shown nothing afterwards — not who was coming,
  /// not whether anyone was. The backend already had the position needed to
  /// answer that; it was only ever written to a column the dispatcher's map
  /// read.
  ///
  /// Null unless status is en_route. The backend clears it deliberately: a
  /// stale "about 4 minutes" shown to somebody the fire truck is already
  /// parked in front of is worse than showing nothing.
  final int? etaMinutes;

  /// BFP / PNP / MDRRMO. The AGENCY, never the responder's name or number —
  /// a resident does not need a crew member's identity to be reassured, and
  /// handing it out invites contact that routes around the dispatcher.
  final String? respondingAgency;

  /// The wizard category wire value ('fire', 'medical_trauma', 'vehicular',
  /// 'flood_landslide_calamity', 'domestic_dispute_crime', 'other') — see
  /// `IncidentCategory` in incident_provider.dart for the full enum. Null
  /// for incidents filed through a path that never set one (the plain SOS
  /// path, or a report predating the 5W1H wizard fields).
  final String? incidentCategory;

  /// "mga 7 minuto" — never a precise time. See etaMinutes.
  String? etaLabel(AppLocalizations t) {
    final m = etaMinutes;
    if (m == null) return null;
    if (m <= 1) return t.respNavClose;
    return t.incidentEtaMinutes(m);
  }

  /// What the recogniser made of the voice note, if one was transcribed.
  String? get heardText {
    final t = signals?['transcript'];
    if (t is! Map) return null;
    final text = t['text'];
    return text is String && text.trim().isNotEmpty ? text.trim() : null;
  }

  /// True once the reporter has said whether we heard them right.
  bool get transcriptSettled {
    final t = signals?['transcript'];
    if (t is! Map) return false;
    return t['confirmed_by_reporter'] == true || t['corrected_to'] != null;
  }

  /// Facts the pipeline pulled out of the report, machine-named.
  Map<String, dynamic> get extractedSignals {
    final inner = signals?['signals'];
    return inner is Map ? Map<String, dynamic>.from(inner) : const {};
  }

  /// Days left in Trash before this report is permanently deleted — null
  /// unless it was withdrawn. 30 must match the backend's
  /// incident_service.TRASH_RETENTION_DAYS; the backend is what actually
  /// enforces the deletion; this is only the countdown shown while waiting.
  int? get daysUntilPurge {
    final w = withdrawnAt;
    if (w == null) return null;
    final remaining = w.add(const Duration(days: 30)).difference(DateTime.now());
    return remaining.isNegative ? 0 : remaining.inDays;
  }

  factory IncidentModel.fromJson(Map<String, dynamic> json) {
    return IncidentModel(
      id: json['id'] as String,
      reportText: json['report_text'] as String,
      status: json['status'] as String,
      submittedVia: json['submitted_via'] as String? ?? 'internet',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      stationId: json['station_id'] as String?,
      locationAddress: json['location_address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      severity: json['severity'] as String?,
      dispatchedAt:
          json['dispatched_at'] != null
              ? DateTime.parse(json['dispatched_at'] as String).toLocal()
              : null,
      resolvedAt:
          json['resolved_at'] != null
              ? DateTime.parse(json['resolved_at'] as String).toLocal()
              : null,
      withdrawnAt:
          json['withdrawn_at'] != null
              ? DateTime.parse(json['withdrawn_at'] as String).toLocal()
              : null,
      reviewStatus: json['review_status'] as String?,
      reviewedAt:
          json['reviewed_at'] != null
              ? DateTime.parse(json['reviewed_at'] as String).toLocal()
              : null,
      rejectionReason: json['rejection_reason'] as String?,
      clarificationNote: json['clarification_note'] as String?,
      clarificationRequestedAt:
          json['clarification_requested_at'] != null
              ? DateTime.parse(json['clarification_requested_at'] as String).toLocal()
              : null,
      signals: json['signals'] as Map<String, dynamic>?,
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      respondingAgency: json['responding_agency'] as String?,
      incidentCategory: json['incident_category'] as String?,
    );
  }

  /// Human-readable status label.
  String statusLabel(AppLocalizations t) {
    switch (status) {
      case 'received':
        return t.incidentStatusReceived;
      case 'processing':
        return t.incidentStatusProcessing;
      case 'dispatched':
        return t.incidentStatusDispatched;
      case 'resolved':
        return t.incidentStatusResolved;
      case 'cancelled':
        return t.incidentStatusCancelled;
      default:
        return status;
    }
  }

  /// Status badge color key (used by UI).
  String get statusColorKey {
    switch (status) {
      case 'received':
        return 'warning';
      case 'processing':
        return 'info';
      case 'dispatched':
        return 'primary';
      case 'resolved':
        return 'success';
      case 'cancelled':
        return 'secondary';
      default:
        return 'secondary';
    }
  }
}

/// One message on an incident's thread — Sections 14 ("Add Information to
/// an Existing Report") and 16 ("Incident-Specific Communication") are the
/// same act from the reporter's side: a line on this thread, not a second
/// report. Shared with the agency/responder/provincial_admin side of the
/// same thread (see backend migration 031, extended by migration 034).
class IncidentNote {
  const IncidentNote({
    required this.id,
    required this.authorId,
    required this.authorRole,
    required this.body,
    required this.createdAt,
    this.authorName,
  });

  final String id;
  final String authorId;
  final String authorRole;
  final String body;
  final DateTime createdAt;
  final String? authorName;

  factory IncidentNote.fromJson(Map<String, dynamic> json) {
    final userRel = json['users'];
    return IncidentNote(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      authorRole: json['author_role'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      authorName:
          userRel is Map ? userRel['full_name'] as String? : null,
    );
  }

  String authorLabel(AppLocalizations t) {
    if (authorName?.isNotEmpty == true) return authorName!;
    switch (authorRole) {
      case 'resident':
        return t.threadAuthorYou;
      case 'agency_admin':
        return 'Agency';
      case 'responder':
        return 'Responder';
      case 'provincial_admin':
        return 'Provincial Admin';
      default:
        return authorRole;
    }
  }
}

/// The resident's own rating of a resolved incident (Section 26). Null
/// fields (via [IncidentFeedback.none]) mean "not yet rated".
class IncidentFeedback {
  const IncidentFeedback({
    required this.rating,
    this.comment,
  });

  final int rating;
  final String? comment;

  factory IncidentFeedback.fromJson(Map<String, dynamic> json) =>
      IncidentFeedback(
        rating: json['rating'] as int,
        comment: json['comment'] as String?,
      );
}
