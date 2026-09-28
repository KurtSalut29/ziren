import '../../auth/data/barangay_repository.dart';
import '../../incident_report/domain/biliran_places.dart';

/// What "Use my location" could establish about where someone lives.
class ResolvedResidence {
  const ResolvedResidence({
    this.municipality,
    this.barangay,
    this.barangayIsConfident = false,
  });

  /// One of the province's municipalities, as spelled in the reference table.
  final String? municipality;

  /// A row of the reference table, or null when the barangay could not be told.
  final Barangay? barangay;

  /// True when the barangay is established (OpenStreetMap named it, or a known
  /// barangay point is within a kilometre). False means "the nearest one" - a
  /// good guess that the person is asked to confirm, not a fact.
  final bool barangayIsConfident;
}

/// Turns a GPS fix into a municipality AND a barangay from the reference table.
///
/// The registration step used to fill in the municipality only, on the reasoning
/// that a coordinate near a barangay boundary can land on the wrong side and a
/// plausible wrong barangay already filled in is one nobody re-reads. That was
/// a fair worry and it left every resident choosing their barangay by hand from
/// a list of up to twenty-six - and the residents testing it said the app
/// should find it, as it finds the municipality.
///
/// So it does, with the worry answered rather than ignored:
///
///   * The barangay is only ever a row of the reference table, in the municipality
///     that was found - never free text - so it is always a real, routable one.
///   * The result says how sure it is. A barangay OpenStreetMap names, or one
///     whose known point is within a kilometre, is [ResolvedResidence.barangayIsConfident].
///     Anything further away is offered as "closest" and the screen asks the
///     person to confirm it.
///   * The dropdowns stay editable and the person still presses Continue.
///
/// Pure Dart on purpose - no plugin, no network - so every rule here is tested on
/// a laptop against real Biliran coordinates. The one network call (reverse
/// geocoding) is made by the screen and handed in as [osmAddress].
abstract final class AddressResolver {
  /// Beyond this from every known place, the position is not in Biliran.
  static const double _provinceRadiusKm = 30;

  /// A known barangay point this close (km) is treated as being in that barangay.
  static const double _confidentKm = 1.0;

  /// Beyond this a "closest barangay" is too far to be a useful suggestion.
  static const double _suggestKm = 3.0;

  /// Fields OpenStreetMap uses for a barangay-sized or smaller area.
  static const _barangayKeys = [
    'village',
    'quarter',
    'hamlet',
    'suburb',
    'neighbourhood',
    'city_block',
  ];

  static const _municipalityKeys = ['town', 'municipality', 'city', 'county'];

  /// Places where the on-device table and the barangay reference table spell
  /// the same barangay differently.
  static const _aliases = {'santorosario': 'santissimorosario'};

  static ResolvedResidence resolve({
    required double lat,
    required double lon,
    required List<Barangay> reference,
    Map<String, dynamic>? osmAddress,
  }) {
    if (reference.isEmpty) return const ResolvedResidence();

    final municipalities = {
      for (final b in reference) _key(b.municipality): b.municipality,
    };

    // ── Municipality ──────────────────────────────────────────────────────
    String? municipality = _osmMunicipality(osmAddress, municipalities);
    municipality ??= _nearestKnownMunicipality(
      lat,
      lon,
      reference,
      municipalities,
    );
    if (municipality == null) return const ResolvedResidence();

    final inMunicipality =
        reference.where((b) => b.municipality == municipality).toList();

    // ── Barangay ──────────────────────────────────────────────────────────
    // 1. OpenStreetMap named one, and it is in this municipality's list.
    final fromOsm = _osmBarangay(osmAddress, inMunicipality);
    if (fromOsm != null) {
      return ResolvedResidence(
        municipality: municipality,
        barangay: fromOsm,
        barangayIsConfident: true,
      );
    }

    // 2. The nearest known barangay point WITHIN this municipality. Restricting
    //    to the municipality is what stops a point across a boundary from being
    //    "the nearest barangay" of the wrong town.
    Barangay? best;
    var bestKm = double.infinity;
    for (final place in BiliranPlaces.all) {
      final match = _barangayNamed(place.name, inMunicipality);
      if (match == null) continue;
      final km = BiliranPlaces.distanceKm(lat, lon, place.lat, place.lon);
      if (km < bestKm) {
        bestKm = km;
        best = match;
      }
    }
    if (best != null && bestKm <= _suggestKm) {
      return ResolvedResidence(
        municipality: municipality,
        barangay: best,
        barangayIsConfident: bestKm <= _confidentKm,
      );
    }
    return ResolvedResidence(municipality: municipality);
  }

  // ── Municipality helpers ──────────────────────────────────────────────

  static String? _osmMunicipality(
    Map<String, dynamic>? addr,
    Map<String, String> municipalities,
  ) {
    if (addr == null) return null;
    for (final k in _municipalityKeys) {
      final v = addr[k];
      if (v is! String) continue;
      final hit = municipalities[_key(_stripPlacePrefix(v))];
      if (hit != null) return hit;
    }
    return null;
  }

  /// The municipality of the nearest place we can attach one to.
  ///
  /// A place can be attached to a municipality two ways: the table states it, or
  /// its name is a barangay that exists in exactly ONE municipality (Larrazabal
  /// is Naval's alone; "Looc" is in four, so it decides nothing). The old code
  /// read the municipality straight off the single nearest place, and for the 23
  /// of 52 whose municipality the table leaves blank - Larrazabal among them -
  /// that was null, reported to the person as "you are not in Biliran".
  static String? _nearestKnownMunicipality(
    double lat,
    double lon,
    List<Barangay> reference,
    Map<String, String> municipalities,
  ) {
    String? best;
    var bestKm = double.infinity;
    for (final place in BiliranPlaces.all) {
      final m = _municipalityOf(place, reference, municipalities);
      if (m == null) continue;
      final km = BiliranPlaces.distanceKm(lat, lon, place.lat, place.lon);
      if (km < bestKm) {
        bestKm = km;
        best = m;
      }
    }
    return bestKm <= _provinceRadiusKm ? best : null;
  }

  static String? _municipalityOf(
    BiliranPlace place,
    List<Barangay> reference,
    Map<String, String> municipalities,
  ) {
    final stated = place.municipality;
    if (stated != null) return municipalities[_key(stated)] ?? stated;
    final owners = <String>{
      for (final b in reference)
        if (_sameName(b.name, place.name)) b.municipality,
    };
    return owners.length == 1 ? owners.first : null;
  }

  // ── Barangay helpers ──────────────────────────────────────────────────

  static Barangay? _osmBarangay(
    Map<String, dynamic>? addr,
    List<Barangay> inMunicipality,
  ) {
    if (addr == null) return null;
    for (final k in _barangayKeys) {
      final v = addr[k];
      if (v is! String) continue;
      final hit = _barangayNamed(v, inMunicipality);
      if (hit != null) return hit;
    }
    return null;
  }

  static Barangay? _barangayNamed(String name, List<Barangay> inMunicipality) {
    for (final b in inMunicipality) {
      if (_sameName(b.name, name)) return b;
    }
    return null;
  }

  static bool _sameName(String a, String b) =>
      _canonical(_key(a)) == _canonical(_key(b));

  static String _canonical(String key) => _aliases[key] ?? key;

  // ── Names ─────────────────────────────────────────────────────────────

  /// "Municipality of Naval", "Town of Almeria" -> "Naval", "Almeria".
  static String _stripPlacePrefix(String s) => s.replaceFirst(
    RegExp(r'^(municipality|town|city)\s+of\s+', caseSensitive: false),
    '',
  );

  /// Lower-case letters and digits only, with the Spanish tilde dropped and the
  /// "Barangay"/"Brgy." prefix removed, so "Brgy. Capiñahan" and "Capinahan"
  /// are the same name.
  static String _key(String s) {
    var out = s.toLowerCase();
    out = out
        .replaceAll('ñ', 'n')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    out = out.replaceFirst(RegExp(r'^(barangay|brgy\.?|bgy\.?)\s+'), '');
    return out.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
