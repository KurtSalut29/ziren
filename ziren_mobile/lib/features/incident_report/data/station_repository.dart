import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../domain/station_model.dart';

/// Fetches station list directly from Supabase.
/// Uses the anon key with RLS anon-read grant (migration 002c).
/// No FastAPI call needed — this is read-only public reference data.
class StationRepository {
  StationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetch all active stations with their parent agency info.
  /// Returns stations sorted: BFP first, then PNP, then MDRRMO,
  /// then alphabetically by municipality within each group.
  Future<List<StationModel>> fetchAllStations() async {
    try {
      final result = await _client
          .from('stations')
          .select(
            'id, agency_id, name, address, location, agencies(name, agency_type, municipality)',
          )
          .eq('is_active', true)
          .order('name');

      final stations =
          (result as List<dynamic>)
              .map((row) => StationModel.fromJson(row as Map<String, dynamic>))
              .toList();

      // Sort: BFP → PNP → MDRRMO, then by municipality
      const order = {'BFP': 0, 'PNP': 1, 'MDRRMO': 2};
      stations.sort((a, b) {
        final typeCompare = (order[a.agencyType] ?? 3).compareTo(
          order[b.agencyType] ?? 3,
        );
        if (typeCompare != 0) return typeCompare;
        return a.municipality.compareTo(b.municipality);
      });

      return stations;
    } catch (e) {
      throw const NetworkFailure(
        'Could not load station list. Check your connection.',
      );
    }
  }
}
