/// The response from a successful SOS submission.
/// Mirrors the FastAPI SosResponse schema.
class SosResult {
  const SosResult({
    required this.id,
    required this.reportText,
    required this.status,
    required this.submittedVia,
    required this.createdAt,
    this.stationId,
    this.stationName,
    this.agencyType,
    this.municipality,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String reportText;
  final String status;
  final String submittedVia;
  final String createdAt;
  final String? stationId;
  final String? stationName;
  final String? agencyType;
  final String? municipality;
  final double? latitude;
  final double? longitude;

  factory SosResult.fromJson(Map<String, dynamic> json) {
    return SosResult(
      id: json['id'] as String,
      reportText: json['report_text'] as String,
      status: json['status'] as String,
      submittedVia: json['submitted_via'] as String,
      createdAt: json['created_at'] as String,
      stationId: json['station_id'] as String?,
      stationName: json['station_name'] as String?,
      agencyType: json['agency_type'] as String?,
      municipality: json['municipality'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  /// Short display ID for user-facing confirmation (first 8 chars).
  String get shortId => id.length >= 8 ? id.substring(0, 8) : id;
}
