import '../../../l10n/app_localizations.dart';
import 'responder_ack.dart';
import 'responder_vocabulary.dart';

/// Incident model for Responder view.
/// Extends the basic IncidentModel with Responder-specific fields
/// (reporter identity, station detail, emergency contacts).
class ResponderIncidentModel {
  const ResponderIncidentModel({
    required this.id,
    required this.reportText,
    required this.status,
    required this.createdAt,
    this.severity,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.landmarkNote,
    this.incidentCategory,
    this.sosFlag = false,
    this.dispatchedAt,
    this.resolvedAt,
    // Station
    this.stationName,
    this.agencyType,
    this.municipality,
    this.stationAddress,
    // Reporter
    this.reporterName,
    this.reporterPhone,
    this.reporterVerified = false,
    this.reporterWarningCount = 0,
    this.emergencyContactName,
    this.emergencyContactNumber,
    // Phase 6D / migration 024
    this.ack = const ResponderAck(state: 'not_applicable', deadlineSeconds: 60),
    this.etaMinutes,
    this.hazards = const [],
    this.outcome,
    this.backupOfIncidentId,
  });

  final String id;
  final String reportText;
  final String status;
  final DateTime createdAt;
  final String? severity;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final String? landmarkNote;
  final String? incidentCategory;
  final bool sosFlag;
  final DateTime? dispatchedAt;
  final DateTime? resolvedAt;

  // Station / agency info
  final String? stationName;
  final String? agencyType;
  final String? municipality;
  final String? stationAddress;

  // Reporter info (for dispatcher + responder context)
  final String? reporterName;
  final String? reporterPhone;
  final bool reporterVerified;
  final int reporterWarningCount;
  final String? emergencyContactName;
  final String? emergencyContactNumber;

  // ── Phase 6D — acceptance, ETA, hazards, after-action ──────

  /// Whether this crew has answered for this assignment yet. Computed by
  /// the backend so the phone and the dispatcher board can never disagree
  /// about the clock — see ResponderAck.
  final ResponderAck ack;

  /// Minutes to the scene, recomputed on every location ping while
  /// en_route. Coarse on purpose: promising a precise arrival to someone
  /// whose house is on fire is worse than promising nothing.
  final int? etaMinutes;

  /// Standing local knowledge near the scene. Only populated on the detail
  /// fetch — the queue does not need it and it costs a spatial scan.
  final List<ApproachHazard> hazards;

  /// What the crew found, once closed. Null while the call is live.
  final String? outcome;

  /// Set when THIS incident is a mutual-aid request raised from another.
  /// A backup incident cannot itself request backup.
  final String? backupOfIncidentId;

  /// Coordinates out of whatever the endpoint actually sent.
  ///
  /// THE BUG THIS REPLACES. These two used to read json['latitude'] and
  /// json['longitude'] — keys the responder endpoints have never sent. The
  /// incidents table stores a PostGIS `location`, and PostgREST returns it as
  /// a GeoJSON object, so both values were silently null on every incident.
  ///
  /// What that cost was the Navigate button. With no coordinates it fell
  /// through to a Google Maps text search of the address string, and when the
  /// address was null too — every SOS filed without a reverse geocode — it
  /// built no URI at all and the tap did nothing whatsoever. No error, no
  /// toast, nothing to distinguish it from a dead button.
  ///
  /// GeoJSON orders its pair [LONGITUDE, LATITUDE], which is the opposite of
  /// how every screen here names them. Reading it backwards does not throw; it
  /// puts a Biliran fire in the sea off Somalia.
  ///
  /// The flat keys are still honoured first, so this keeps working if the
  /// backend is ever changed to send them.
  static double? _latOf(Map<String, dynamic> json) {
    final flat = (json['latitude'] as num?)?.toDouble();
    if (flat != null) return flat;
    return _geoPair(json)?.$1;
  }

  static double? _lngOf(Map<String, dynamic> json) {
    final flat = (json['longitude'] as num?)?.toDouble();
    if (flat != null) return flat;
    return _geoPair(json)?.$2;
  }

  /// (lat, lng) from a GeoJSON Point, or null.
  static (double, double)? _geoPair(Map<String, dynamic> json) {
    final loc = json['location'];
    if (loc is! Map) return null;
    final coords = loc['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lng = (coords[0] as num?)?.toDouble();
    final lat = (coords[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  factory ResponderIncidentModel.fromJson(Map<String, dynamic> json) {
    // Nested station + agency
    final station = json['stations'] as Map<String, dynamic>?;
    final agency = station?['agencies'] as Map<String, dynamic>?;

    // Nested reporter
    final reporter =
        (json['users'] is Map<String, dynamic>
            ? json['users'] as Map<String, dynamic>?
            : null);

    return ResponderIncidentModel(
      id: json['id'] as String,
      reportText: json['report_text'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      severity: json['severity'] as String?,
      locationAddress: json['location_address'] as String?,
      latitude: _latOf(json),
      longitude: _lngOf(json),
      landmarkNote: json['landmark_note'] as String?,
      incidentCategory: json['incident_category'] as String?,
      sosFlag: json['sos_flagged'] as bool? ?? false,
      dispatchedAt:
          json['dispatched_at'] != null
              ? DateTime.parse(json['dispatched_at'] as String)
              : null,
      resolvedAt:
          json['resolved_at'] != null
              ? DateTime.parse(json['resolved_at'] as String)
              : null,
      stationName: station?['name'] as String?,
      agencyType: agency?['agency_type'] as String?,
      municipality: agency?['municipality'] as String?,
      stationAddress: station?['address'] as String?,
      reporterName: reporter?['full_name'] as String?,
      reporterPhone: reporter?['phone_number'] as String?,
      reporterVerified: reporter?['is_verified'] as bool? ?? false,
      reporterWarningCount: reporter?['sos_warning_count'] as int? ?? 0,
      emergencyContactName: reporter?['emergency_contact_name'] as String?,
      emergencyContactNumber: reporter?['emergency_contact_number'] as String?,
      ack: ResponderAck.fromJson(json['ack'] as Map<String, dynamic>?),
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      hazards:
          (json['hazards'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ApproachHazard.fromJson)
              .toList(),
      outcome: json['outcome'] as String?,
      backupOfIncidentId: json['backup_of_incident_id'] as String?,
    );
  }

  /// Human-readable category label in Filipino/English — see
  /// ResponderVocabulary.categoryLabel, the one copy every responder screen
  /// (including a nearby-incident alert) reads.
  String get categoryLabel => ResponderVocabulary.categoryLabel(incidentCategory);

  /// Human-readable status label.
  String get statusLabel {
    switch (status) {
      case 'dispatched':
        return 'Dispatched — Respond Now';
      case 'en_route':
        return 'En Route';
      case 'arrived':
        return 'On Scene';
      case 'resolved':
        return 'Resolved';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// Whether this assignment is still waiting for this crew to answer.
  ///
  /// While true the detail screen shows ACCEPT / CAN'T RESPOND instead of
  /// the status button. Letting a crew tap "En Route" without accepting
  /// would leave the board showing an unanswered assignment for someone
  /// who is already driving, which is the exact confusion this feature
  /// exists to remove.
  bool get needsAnswer => status == 'dispatched' && ack.needsAnswer;

  /// True once this crew has committed but not yet moved.
  bool get isAcceptedNotMoving => status == 'dispatched' && ack.isAccepted;

  /// "about 7 min" — never a precise time. See etaMinutes.
  String? etaLabel(AppLocalizations t) {
    final m = etaMinutes;
    if (m == null) return null;
    if (m <= 1) return t.respNavClose;
    return t.respEtaMinutes(m);
  }

  /// Next allowed status in the FSM (null if terminal).
  String? get nextStatus {
    switch (status) {
      case 'dispatched':
        return 'en_route';
      case 'en_route':
        return 'arrived';
      case 'arrived':
        return 'resolved';
      default:
        return null;
    }
  }

  /// Human-readable label for the next action button.
  String? get nextActionLabel {
    switch (status) {
      case 'dispatched':
        return 'Papunta Na (En Route)';
      case 'en_route':
        return 'Nakarating Na (On Scene)';
      case 'arrived':
        return 'Natapos Na (Resolved)';
      default:
        return null;
    }
  }

  String get shortId {
    final s = id.replaceAll('-', '').toUpperCase();
    return 'INC-${s.substring(s.length > 6 ? s.length - 6 : 0)}';
  }
}
