import '../../../core/geo/geodesic.dart';

/// Named places in Biliran, with coordinates, held on the device.
///
/// Why this exists
/// ---------------
/// The app reverse-geocoded through Nominatim (OpenStreetMap) and showed
/// whatever came back. Standing in barangay Talustusan, it reported
/// "Padre Sergio Eamiguel" — a different barangay 1.66 km away.
///
/// That is not a bug in the request. OpenStreetMap has no `place` node for
/// Talustusan at all; searching for it returns only Talustusan Elementary
/// School. Reverse geocoding answers with the nearest *mapped* name, so no
/// amount of GPS accuracy could ever have produced "Talustusan" — the name is
/// not in the data being searched.
///
/// Ziren already knows Biliran's barangays: predict.py carries the list, and
/// the triage model matches location text against it. The gap was only that
/// the app asked a service that knows less about Biliran than Ziren does.
///
/// How the table was built
/// -----------------------
/// One-off geocode of predict.py's BARANGAYS through Nominatim, then filtered
/// to results whose address actually falls in Biliran. 52 of 61 names
/// resolved. Ten of those resolved to a school rather than a settlement node
/// — `source` records which, because a school is a stand-in for a barangay
/// centroid, not the centroid itself, and a reader deserves to know that.
///
/// Not resolved, and therefore not nameable from coordinates alone:
/// Sanggalang, Pinangumhan, Virginia, Marvel, P.I. Garcia, Haguikhikan,
/// Iyusan. [nearest] returns the closest known place with its distance, so a
/// report from one of those still says something true — the distance is what
/// keeps it honest.
///
/// Coordinates remain the authority. This layer names them; it never replaces
/// them.
class BiliranPlace {
  const BiliranPlace(
    this.name,
    this.lat,
    this.lon,
    this.source, [
    this.municipality,
  ]);

  final String name;
  final double lat;
  final double lon;

  /// The municipality this place sits in, where OpenStreetMap states it —
  /// 29 of the 52. Null is left as null rather than guessed from the nearest
  /// town: an address a dispatcher reads is the wrong place to be inventive.
  final String? municipality;

  /// What OpenStreetMap object supplied the point: `village`, `town`,
  /// `school`, `hamlet`, `neighbourhood`, `residential`, `administrative`.
  final String source;

  /// True when the point came from a settlement, rather than from a building
  /// standing in for one.
  bool get isSettlement =>
      source == 'village' ||
      source == 'town' ||
      source == 'hamlet' ||
      source == 'neighbourhood' ||
      source == 'administrative';
}

typedef _P = BiliranPlace;

/// A place and how far the reported position is from it.
class NearestPlace {
  const NearestPlace(this.place, this.km);

  final BiliranPlace place;
  final double km;

  /// Close enough that naming the place is a statement, not a guess.
  ///
  /// The threshold is 1 km, and it was originally set at 2 km — which was too
  /// loose to be honest. A real reported position sat 1.48 km from San Roque,
  /// 1.77 km from Talustusan and 1.88 km from Padre Sergio Eamiguel: three
  /// candidates within 400 m of each other in ranking, none of them
  /// established. At 2 km that position would have been labelled "San Roque"
  /// flatly — trading OpenStreetMap's wrong confident answer for Ziren's own.
  ///
  /// Naval fits roughly 26 barangays into about 10 km, so a node more than a
  /// kilometre away is usually a different barangay. Past that the UI reports
  /// a distance instead of a name, which is less satisfying and true.
  bool get isConfident => km <= 1.0;
}

class BiliranPlaces {
  const BiliranPlaces._();

  /// Nearest known place to a position, or null when the table is empty.
  ///
  /// Straight-line distance. Biliran is roughly 25 km across, so the error
  /// from ignoring terrain is far smaller than the error this replaces.
  static NearestPlace? nearest(double lat, double lon) {
    NearestPlace? best;
    for (final p in all) {
      final km = distanceKm(lat, lon, p.lat, p.lon);
      if (best == null || km < best.km) best = NearestPlace(p, km);
    }
    return best;
  }

  /// How far [lat],[lon] is from the named place, or null when the name is
  /// not in the table.
  ///
  /// Used to weigh the reporter's own registered barangay against whatever
  /// node happens to be nearest. Seven of Biliran's barangays are absent from
  /// this table entirely, so null is a normal answer and means "no opinion",
  /// not "far away".
  static double? distanceToNamed(String name, double lat, double lon) {
    final place = byName(name);
    if (place == null) return null;
    return distanceKm(lat, lon, place.lat, place.lon);
  }

  /// Look a place up by name, case- and punctuation-insensitively.
  ///
  /// Used to attach a municipality to a name OpenStreetMap supplied, so the
  /// two sources can be combined instead of one replacing the other.
  static BiliranPlace? byName(String name) {
    final wanted = _key(name);
    for (final p in all) {
      if (_key(p.name) == wanted) return p;
    }
    return null;
  }

  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Ellipsoidal (WGS-84, Vincenty) distance, in kilometres - the same one
  /// the backend and the dashboard use, not a separate Haversine copy.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) =>
      Geodesic.km(lat1, lon1, lat2, lon2);

  static const List<BiliranPlace> all = [
    _P('Agpangi', 11.588672, 124.396245, 'village', 'Naval'),
    _P('Agutay', 11.81284, 124.332812, 'village', 'Maripipi'),
    _P('Almeria', 11.620278, 124.381667, 'town', 'Almeria'),
    _P('Anislagan', 11.529053, 124.441778, 'village', 'Naval'),
    _P('Atipolo', 11.572509, 124.391139, 'village', 'Naval'),
    _P('Balaquid', 11.477635, 124.531787, 'village', null),
    _P('Bari-is', 11.555324, 124.597087, 'school', null),
    _P('Baso', 11.487206, 124.594776, 'village', null),
    _P('Bato', 11.504476, 124.435423, 'village', 'Biliran'),
    _P('Biliran', 11.466574, 124.474097, 'town', 'Biliran'),
    _P('Borac', 11.531036, 124.426721, 'school', 'Naval'),
    _P('Bunga', 11.484439, 124.592691, 'school', 'Cabucgayan'),
    _P('Burabod', 11.478487, 124.453812, 'village', null),
    _P('Busali', 11.491778, 124.447575, 'village', 'Naval'),
    _P('Cabibihan', 11.580411, 124.549754, 'village', null),
    _P('Cabucgayan', 11.472953, 124.574997, 'town', 'Cabucgayan'),
    _P('Caibiran', 11.57232, 124.581336, 'town', 'Caibiran'),
    _P('Calumpang', 11.568141, 124.411299, 'village', 'Naval'),
    _P('Canila', 11.498742, 124.482506, 'village', null),
    _P('Caraycaray', 11.553319, 124.414829, 'school', null),
    _P('Catmon', 11.524795, 124.422506, 'village', 'Naval'),
    _P('Culaba', 11.655596, 124.540621, 'town', 'Culaba'),
    _P('Danao', 11.8093, 124.341209, 'village', 'Maripipi'),
    _P('Hugpa', 11.493702, 124.489796, 'village', null),
    _P('Imelda', 11.594661, 124.45427, 'village', 'Naval'),
    _P('Jamorawon', 11.603267, 124.386462, 'village', null),
    _P('Julita', 11.476563, 124.515613, 'village', null),
    _P('Kawayan', 11.679951, 124.357023, 'town', 'Kawayan'),
    _P('Larrazabal', 11.577174, 124.404589, 'village', null),
    _P('Libertad', 11.570784, 124.27116, 'administrative', null),
    _P('Looc', 11.65102, 124.546837, 'village', null),
    _P('Manlabang', 11.566856, 124.579425, 'school', 'Caibiran'),
    _P('Maripipi', 11.776523, 124.348595, 'administrative', 'Maripipi'),
    _P('Matanggo', 11.645627, 124.36672, 'school', 'Almeria'),
    _P('Maurang', 11.566014, 124.565568, 'school', 'Caibiran'),
    _P('Naval', 11.56179, 124.396527, 'town', 'Naval'),
    _P('Padre Sergio Eamiguel', 11.589268, 124.433645, 'village', 'Naval'),
    _P('Pili', 11.635599, 124.378112, 'village', null),
    _P('Sampao', 11.618552, 124.430176, 'village', null),
    _P('San Isidro', 11.61934, 124.381138, 'residential', 'Almeria'),
    _P('San Roque', 11.5821, 124.408771, 'neighbourhood', 'Naval'),
    _P('Santo Rosario', 11.56035, 124.392994, 'residential', null),
    _P('Tabunan', 11.651994, 124.361925, 'hamlet', null),
    _P('Talahid', 11.637196, 124.364652, 'village', null),
    _P('Talustusan', 11.603488, 124.42891, 'school', 'Naval'),
    _P('Tamarindo', 11.606561, 124.405053, 'school', 'Almeria'),
    _P('Tucdao', 11.700801, 124.469982, 'village', null),
    _P('Ungale', 11.701887, 124.449261, 'village', null),
    _P('Union', 11.563756, 124.551607, 'village', null),
    _P('Uson', 11.54412, 124.615742, 'village', null),
    _P('Viga', 11.806168, 124.308219, 'village', 'Maripipi'),
    _P('Villa Enage', 11.475656, 124.4935, 'school', null),
  ];
}
