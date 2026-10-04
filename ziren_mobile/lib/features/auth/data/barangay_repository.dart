import 'package:supabase_flutter/supabase_flutter.dart';

/// One barangay from the `public.barangays` reference table.
class Barangay {
  const Barangay({
    required this.id,
    required this.name,
    required this.municipality,
  });

  final String id;
  final String name;
  final String municipality;

  factory Barangay.fromMap(Map<String, dynamic> map) => Barangay(
    id: map['id'] as String,
    name: map['name'] as String,
    municipality: map['municipality'] as String,
  );
}

/// Reads Biliran's municipality/barangay reference list.
///
/// This replaces the free-text `barangay` field used previously. Structured
/// selection means an account is tied to a real place, which both establishes
/// residency without demanding a document and makes dispatch routing reliable.
///
/// The table is readable by `anon`, so the list loads on the registration
/// screen before the user has a session (see migration 012).
class BarangayRepository {
  BarangayRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  List<Barangay>? _cache;

  /// All barangays in the province, ordered by municipality then name.
  ///
  /// Cached for the lifetime of the repository — this is static reference
  /// data and the registration form reads it on every keystroke-free rebuild.
  Future<List<Barangay>> fetchAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final rows = await _client
        .from('barangays')
        .select('id, name, municipality')
        // ascending: true is not optional. postgrest-dart's order() defaults
        // to DESCENDING, so these dropdowns read Z to A (evaluator #32).
        .order('municipality', ascending: true)
        .order('name', ascending: true);

    final list =
        (rows as List)
            .map((r) => Barangay.fromMap(r as Map<String, dynamic>))
            .toList()
          // Also sorted here, case-insensitively, so the order never depends
          // on a query option being remembered.
          ..sort((a, b) {
            final m = a.municipality.toLowerCase().compareTo(b.municipality.toLowerCase());
            return m != 0 ? m : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    _cache = list;
    return list;
  }

  /// Distinct municipalities, in display order.
  Future<List<String>> fetchMunicipalities() async {
    final all = await fetchAll();
    // LinkedHashSet preserves the municipality ordering from the query.
    return all.map((b) => b.municipality).toSet().toList();
  }

  /// Barangays within [municipality].
  Future<List<Barangay>> fetchFor(String municipality) async {
    final all = await fetchAll();
    return all.where((b) => b.municipality == municipality).toList();
  }
}
