import 'responder_vocabulary.dart';

/// What THIS responder is already doing, as it applies to a nearby alert —
/// free, or already on a call (and which one).
class NearbyYou {
  const NearbyYou({
    required this.state,
    this.currentIncidentId,
    this.currentCategory,
  });

  /// 'free' | 'committed' | 'en_route' | 'on_scene'
  final String state;
  final String? currentIncidentId;
  final String? currentCategory;

  bool get isFree => state == 'free';

  factory NearbyYou.fromJson(Map<String, dynamic> json) {
    final calls = json['current_calls'] as List<dynamic>? ?? const [];
    final first = calls.isNotEmpty ? calls.first as Map<String, dynamic> : null;
    return NearbyYou(
      state: json['state'] as String? ?? 'free',
      currentIncidentId: first?['incident_id'] as String?,
      currentCategory: first?['category'] as String?,
    );
  }
}

/// An incident near this responder that has not been dispatched to anyone yet.
///
/// GET /responder/nearby — see app.services.proximity for the whole policy this
/// mirrors. A responder on duty near a new report is told about it the moment it
/// arrives, without waiting for a dispatcher to assign it; this is the shape that
/// answers "what is near ME, right now".
class NearbyIncident {
  const NearbyIncident({
    required this.incidentId,
    required this.reportText,
    required this.createdAt,
    required this.you,
    this.recordNumber,
    this.severity,
    this.category,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.sosFlagged = false,
    this.distanceKm,
    this.etaMinutes,
    this.direction,
    this.level = 'alarm',
    this.reason = 'nearest',
    this.rank,
    this.unitsFreeInRange = 0,
    this.answered,
  });

  final String incidentId;
  final String? recordNumber;
  final String? severity;
  final String? category;
  final String reportText;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final bool sosFlagged;

  /// Null when this responder's position could not be measured.
  final double? distanceKm;
  final int? etaMinutes;

  /// Compass point (N/NE/E/...) FROM this responder TO the incident.
  final String? direction;

  /// 'alarm' (told at full volume) | 'advisory' (told quietly).
  final String level;
  final String reason;
  final int? rank;
  final int unitsFreeInRange;

  final NearbyYou you;

  /// This responder's own latest reply, if they have answered — 'can_respond' |
  /// 'unavailable' | null.
  final String? answered;

  /// Words for the category, the same ones a queue card already uses.
  String get categoryLabel => ResponderVocabulary.categoryLabel(category);

  bool get isAdvisory => level == 'advisory';
  bool get hasAnswered => answered != null;

  factory NearbyIncident.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) => v == null ? null : (v as num).toDouble();
    return NearbyIncident(
      incidentId: json['incident_id'] as String,
      recordNumber: json['record_number'] as String?,
      severity: json['severity'] as String?,
      category: json['category'] as String?,
      reportText: json['report_text'] as String? ?? '',
      locationAddress: json['location_address'] as String?,
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      sosFlagged: json['sos_flagged'] as bool? ?? false,
      distanceKm: asDouble(json['distance_km']),
      etaMinutes: (json['eta_min'] as num?)?.toInt(),
      direction: json['direction'] as String?,
      level: json['level'] as String? ?? 'alarm',
      reason: json['reason'] as String? ?? 'nearest',
      rank: (json['rank'] as num?)?.toInt(),
      unitsFreeInRange: (json['units_free_in_range'] as num?)?.toInt() ?? 0,
      you: NearbyYou.fromJson(json['you'] as Map<String, dynamic>? ?? const {}),
      answered: json['answered'] as String?,
    );
  }
}

/// GET /responder/nearby's whole response: whether this responder is even on
/// duty (they get nothing if not), how their position was measured, and the list.
class NearbyResult {
  const NearbyResult({
    required this.onDuty,
    required this.position,
    required this.items,
  });

  final bool onDuty;

  /// 'device' (the phone's own live fix was used) | 'last_reported' | 'none'.
  final String position;
  final List<NearbyIncident> items;

  factory NearbyResult.fromJson(Map<String, dynamic> json) {
    final rows = json['items'] as List<dynamic>? ?? const [];
    return NearbyResult(
      onDuty: json['on_duty'] as bool? ?? false,
      position: json['position'] as String? ?? 'none',
      items:
          rows
              .map((e) => NearbyIncident.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }
}
