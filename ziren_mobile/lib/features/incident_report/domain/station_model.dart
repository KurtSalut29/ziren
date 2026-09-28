/// Client-side model for a station.
/// Fetched directly from Supabase (public reference data).
class StationModel {
  const StationModel({
    required this.id,
    required this.agencyId,
    required this.agencyType,
    required this.agencyName,
    required this.name,
    required this.municipality,
    this.address,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String agencyId;
  final String agencyType; // BFP | PNP | MDRRMO
  final String agencyName;
  final String name;
  final String municipality;
  final String? address;
  final double? latitude;
  final double? longitude;

  factory StationModel.fromJson(Map<String, dynamic> json) {
    final agency = json['agencies'] as Map<String, dynamic>? ?? {};

    // Parse PostGIS POINT returned as WKT "POINT(lon lat)" or GeoJSON dict
    double? lat;
    double? lng;
    final loc = json['location'];
    if (loc is String && loc.toUpperCase().startsWith('POINT')) {
      // WKT: POINT(124.4063 11.5836)
      final inner = loc.trim().substring(6, loc.length - 1);
      final parts = inner.trim().split(' ');
      if (parts.length == 2) {
        lng = double.tryParse(parts[0]);
        lat = double.tryParse(parts[1]);
      }
    } else if (loc is Map) {
      // GeoJSON: {"type":"Point","coordinates":[lon, lat]}
      final coords = loc['coordinates'];
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num?)?.toDouble();
        lat = (coords[1] as num?)?.toDouble();
      }
    }

    return StationModel(
      id: json['id'] as String,
      agencyId: json['agency_id'] as String,
      agencyType: agency['agency_type'] as String? ?? '',
      agencyName: agency['name'] as String? ?? '',
      name: json['name'] as String,
      municipality: agency['municipality'] as String? ?? '',
      address: json['address'] as String?,
      latitude: lat,
      longitude: lng,
    );
  }

  @override
  String toString() => '$agencyType — $name ($municipality)';
}
