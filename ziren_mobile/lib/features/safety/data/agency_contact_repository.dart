import 'package:supabase_flutter/supabase_flutter.dart';

/// One agency's official contact number, for the Emergency Contacts screen
/// (spec Section 21). Read straight from Supabase with the same anon-read
/// grant `StationRepository` already relies on — this is public reference
/// data, not something behind the FastAPI backend.
class AgencyContact {
  const AgencyContact({
    required this.agencyType,
    required this.name,
    required this.municipality,
    this.contactNumber,
  });

  final String agencyType;
  final String name;
  final String municipality;
  final String? contactNumber;

  factory AgencyContact.fromJson(Map<String, dynamic> json) => AgencyContact(
    agencyType: json['agency_type'] as String,
    name: json['name'] as String,
    municipality: json['municipality'] as String? ?? '',
    contactNumber: json['contact_number'] as String?,
  );
}

class AgencyContactRepository {
  AgencyContactRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Only agencies with a real number on file are worth showing — a "Call"
  /// button that dials nothing is worse than not offering it.
  Future<List<AgencyContact>> fetchContacts() async {
    try {
      final result = await _client
          .from('agencies')
          .select('agency_type, name, municipality, contact_number')
          .not('contact_number', 'is', null)
          .order('agency_type');

      const order = {'BFP': 0, 'PNP': 1, 'MDRRMO': 2};
      final contacts =
          (result as List<dynamic>)
              .map((row) => AgencyContact.fromJson(row as Map<String, dynamic>))
              .where((c) => c.contactNumber?.trim().isNotEmpty == true)
              .toList();
      contacts.sort((a, b) {
        final t = (order[a.agencyType] ?? 3).compareTo(order[b.agencyType] ?? 3);
        return t != 0 ? t : a.municipality.compareTo(b.municipality);
      });
      return contacts;
    } catch (_) {
      return const [];
    }
  }
}
