import 'biliran_places.dart';

/// Turns a position into an address a dispatcher can act on.
///
/// The failure this replaces
/// -------------------------
/// A report from a ±32 m fix — a good one — was filed as:
///
///     San Roque, Biliran
///
/// OpenStreetMap knew more than that. For the same point it returned
/// `neighbourhood: San Roque` **and** `village: Larrazabal`. San Roque is a
/// sitio inside barangay Larrazabal, and the app printed the sitio as though
/// it were the whole address, dropping the barangay and the municipality.
/// "San Roque" alone is close to useless: the name repeats across the country
/// and twice within Biliran.
///
/// The address that position deserves is
///
///     San Roque, Larrazabal, Naval, Biliran
///
/// so this composes every level it can establish, and drops none of them.
///
/// Which source to believe
/// -----------------------
/// Neither source is right everywhere, and they fail in different places:
///
///   * Where OpenStreetMap has local detail — a sitio, a road, a named
///     building — its containment is correct and finer than anything Ziren
///     ships. Believe it.
///   * Where it returns a bare `village` and nothing else, it has no data
///     there and has answered with the nearest node it happens to hold. That
///     is exactly how a report from Talustusan came back as Padre Sergio
///     Eamiguel, 1.66 km away. Fall back to Ziren's own table and say how far
///     the nearest known place is, rather than asserting a name.
///
/// The previous attempt inverted this and led with the local table for
/// everything, which is how a point 50 m from OSM's San Roque node lost the
/// barangay that OSM was willing to name.
///
/// The third source
/// ----------------
/// Both of the above ask "what is near this point". [HomeBarangay] answers a
/// different question — "where does this person say they live" — and it is
/// what rescues the case where neither of the other two can establish
/// anything.

/// The barangay the reporter told us they live in, and how far the reported
/// position is from that barangay's node.
///
/// This is a different kind of evidence from everything else here. OSM and the
/// local table both answer "what is near this point"; this answers "where does
/// this person say they live". Neither is reliable alone at Biliran's node
/// density, and together they are much stronger than either.
class HomeBarangay {
  const HomeBarangay({required this.name, this.municipality, this.km});

  final String name;
  final String? municipality;

  /// Null when the barangay is one of the seven with no node in the table.
  final double? km;
}

class PlaceNaming {
  const PlaceNaming._();

  /// How far from their own registered barangay a reporter can be before we
  /// stop assuming they are in it.
  ///
  /// 2.5 km is generous for a barangay, and deliberately so: several nodes in
  /// the table are schools standing in for a centroid, which puts them at the
  /// edge of the area they name rather than the middle. Talustusan is one —
  /// its node is the elementary school, 1.77 km from a position genuinely
  /// inside the barangay.
  static const double _homeRadiusKm = 2.5;

  /// How much closer another place must be before it beats the reporter's own
  /// barangay.
  ///
  /// Without this, a position 1.48 km from San Roque and 1.77 km from the
  /// reporter's own Talustusan is "won" by San Roque on a 290 m difference —
  /// which is well inside the error of a school-node stand-in. A near tie
  /// should go to the barangay the person actually lives in.
  static const double _tieMarginKm = 1.0;

  /// Fields OpenStreetMap uses for a named point of interest, most findable
  /// first. A building beats a road: a responder can be sent to a school.
  static const _landmarkKeys = [
    'amenity',
    'building',
    'shop',
    'place_of_worship',
    'school',
  ];

  /// Sub-barangay: sitio, purok, subdivision.
  static const _sitioKeys = ['neighbourhood', 'suburb', 'city_block'];

  /// Barangay.
  static const _barangayKeys = ['village', 'quarter', 'hamlet'];

  static const _municipalityKeys = ['town', 'municipality', 'city', 'county'];

  static String? _first(Map<String, dynamic> addr, List<String> keys) {
    for (final k in keys) {
      final v = addr[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// Reads one Nominatim `address` object into levels.
  static ResolvedPlace fromOsm(Map<String, dynamic>? addr) {
    if (addr == null || addr.isEmpty) return const ResolvedPlace();
    final road = addr['road'];
    return ResolvedPlace(
      landmark: _first(addr, _landmarkKeys),
      road: road is String && road.trim().isNotEmpty ? road.trim() : null,
      sitio: _first(addr, _sitioKeys),
      barangay: _first(addr, _barangayKeys),
      municipality: _first(addr, _municipalityKeys),
    );
  }

  /// The address string stored on the incident and shown to the dispatcher.
  ///
  /// [nearest] is Ziren's own answer, used to fill a missing municipality and
  /// to take over entirely when OpenStreetMap has nothing local to say.
  /// [accuracyM] is annotated only when the fix is poor enough to change what
  /// a dispatcher should do with the name.
  static String compose({
    required ResolvedPlace osm,
    NearestPlace? nearest,
    double? accuracyM,
    HomeBarangay? home,
  }) {
    final parts = <String>[];

    if (osm.hasLocalDetail) {
      // Trusted, and assembled whole: landmark, sitio, barangay, municipality.
      if (osm.landmark != null) {
        parts.add(osm.landmark!);
      } else if (osm.road != null) {
        parts.add(osm.road!);
      }
      if (osm.sitio != null) parts.add(osm.sitio!);
      if (osm.barangay != null) parts.add(osm.barangay!);

      final muni = osm.municipality ?? _municipalityFor(osm, nearest);
      if (muni != null) parts.add(muni);
    } else if (osm.barangay != null && nearest != null && nearest.isConfident) {
      // OpenStreetMap named a barangay with no supporting detail, and Ziren's
      // own table agrees something is close. Take the name, add what Ziren
      // knows about where it sits.
      parts.add(osm.barangay!);
      final muni = osm.municipality ?? nearest.place.municipality;
      if (muni != null) parts.add(muni);
    } else if (_homeWins(home, nearest)) {
      // Neither source can establish a barangay from the position alone, but
      // the reporter has told us which barangay they live in and the position
      // is consistent with it. That combination is worth more than a distance
      // to a node nobody asked about.
      //
      // "Near" rather than a bare name, because this is inferred from a
      // declared address rather than established from the fix. A dispatcher
      // reading "Near Talustusan, Naval" knows both where to send a crew and
      // how much to trust it — where "1.5 km from San Roque" gave them a
      // barangay the reporter is not even in.
      parts.add('Near ${home!.name}');
      final muni = home.municipality;
      if (muni != null) parts.add(muni);
    } else if (nearest != null) {
      // Nothing reliable from any side. Say where the nearest known place is
      // instead of naming one.
      parts.add(
        nearest.isConfident
            ? nearest.place.name
            : '${nearest.km.toStringAsFixed(1)} km from ${nearest.place.name}',
      );
      final muni = nearest.place.municipality;
      if (muni != null && nearest.isConfident) parts.add(muni);
    } else if (osm.barangay != null) {
      parts.add(osm.barangay!);
    }

    parts.add('Biliran');

    // A name never twice in a row: when the nearest known place IS the town
    // ("Naval") its municipality is the same word, and "Naval, Naval,
    // Biliran" reads like a mistake to the dispatcher.
    final deduped = <String>[];
    for (final part in parts) {
      if (deduped.isEmpty || deduped.last.toLowerCase() != part.toLowerCase()) {
        deduped.add(part);
      }
    }

    final buffer = StringBuffer(deduped.join(', '));
    if (accuracyM != null && accuracyM > 100) {
      buffer.write(' (GPS ±${accuracyM.round()} m)');
    }
    return buffer.toString();
  }

  /// Should the reporter's own barangay be named, rather than a distance to
  /// whatever node happens to be closest?
  ///
  /// Yes when they are plausibly within it, and no other place is decisively
  /// closer. Both conditions matter: the first stops a report from Kawayan
  /// being labelled with a home barangay in Naval, and the second stops a
  /// genuinely better local answer being discarded.
  ///
  /// A barangay with no node in the table cannot be range-checked, so it is
  /// not asserted. Saying nothing is better than guessing.
  static bool _homeWins(HomeBarangay? home, NearestPlace? nearest) {
    if (home == null) return false;
    final homeKm = home.km;
    if (homeKm == null || homeKm > _homeRadiusKm) return false;
    if (nearest == null) return true;
    // The nearest node already names the home barangay: the ordinary path
    // handles that better than this branch would.
    if (nearest.isConfident) return false;
    return homeKm <= nearest.km + _tieMarginKm;
  }

  /// Ziren's municipality for whichever name OpenStreetMap gave, then the
  /// nearest place's, then nothing.
  static String? _municipalityFor(ResolvedPlace osm, NearestPlace? nearest) {
    for (final name in [osm.barangay, osm.sitio]) {
      if (name == null) continue;
      final match = BiliranPlaces.byName(name);
      if (match?.municipality != null) return match!.municipality;
    }
    return nearest?.place.municipality;
  }
}

/// The levels of an address, each one either established or absent.
class ResolvedPlace {
  const ResolvedPlace({
    this.landmark,
    this.road,
    this.sitio,
    this.barangay,
    this.municipality,
  });

  /// A named building — the most findable thing on this list.
  final String? landmark;
  final String? road;

  /// Sitio or purok, inside a barangay.
  final String? sitio;
  final String? barangay;
  final String? municipality;

  /// Whether OpenStreetMap holds real data for this spot, rather than having
  /// answered with the nearest village node it happens to have.
  ///
  /// A sitio, a road or a building only exist in the reply when someone has
  /// actually mapped the area. A lone `village` is a nearest-neighbour guess,
  /// and treating the two the same is what put a Talustusan report 1.66 km
  /// away in Padre Sergio Eamiguel.
  bool get hasLocalDetail => landmark != null || road != null || sitio != null;

  bool get isEmpty =>
      landmark == null &&
      road == null &&
      sitio == null &&
      barangay == null &&
      municipality == null;
}
