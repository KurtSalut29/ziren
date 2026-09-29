import 'package:geolocator/geolocator.dart';

import 'incident_provider.dart';
import 'station_model.dart';

/// A resolved station plus its distance from the resident, in kilometres.
typedef NearestStation = ({StationModel station, double km});

/// Shared by the quick-report confirm and review screens so "which station
/// gets this" cannot drift between the two steps of the same flow.
abstract final class NearestStationResolver {
  /// Which agency owns this kind of incident. Mirrors the rubric's
  /// recommended_agency so the report lands where the dispatcher would have
  /// sent it anyway.
  static String? agencyFor(IncidentCategory? c) => switch (c) {
    IncidentCategory.fire => 'BFP',
    IncidentCategory.domesticDisputeCrime => 'PNP',
    IncidentCategory.medicalTrauma => 'MDRRMO',
    IncidentCategory.vehicular => 'MDRRMO',
    IncidentCategory.floodLandslideCalamity => 'MDRRMO',
    _ => null, // "Iba pa" — nearest station of any agency
  };

  /// Nearest to the INCIDENT — the point the resident placed when they are
  /// reporting from somewhere else, the phone otherwise. Measuring from the
  /// phone would hand a Larrazabal fire to Kawayan because that is where the
  /// caller happened to be.
  static NearestStation? resolve(IncidentProvider p) {
    final lat = p.incidentLat;
    final lng = p.incidentLng;
    final agency = agencyFor(p.incidentCategory);

    var pool = p.stations.where(
      (s) => s.latitude != null && s.longitude != null,
    );
    if (agency != null) {
      final scoped = pool.where((s) => s.agencyType == agency);
      // Fall back to any agency rather than failing: a report that reaches
      // the wrong desk still reaches a dispatcher, who can reassign it.
      if (scoped.isNotEmpty) pool = scoped;
    }
    if (pool.isEmpty || lat == null || lng == null) return null;

    StationModel? best;
    double bestM = double.infinity;
    for (final s in pool) {
      final m = Geolocator.distanceBetween(
        lat,
        lng,
        s.latitude!,
        s.longitude!,
      );
      if (m < bestM) {
        bestM = m;
        best = s;
      }
    }
    return best == null ? null : (station: best, km: bestM / 1000);
  }
}
