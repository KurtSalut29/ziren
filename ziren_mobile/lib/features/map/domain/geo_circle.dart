import 'dart:math' as math;

/// A circle on the map, in real metres.
///
/// MapLibre's circle layer sizes its radius in *screen pixels*, so a circle
/// drawn that way shrinks and grows as you zoom and never means a distance.
/// A GPS accuracy radius has to keep its size in metres — that is the entire
/// point of drawing it — so it is built as a GeoJSON polygon in real
/// coordinates instead.
///
/// Why it is drawn at all
/// ---------------------
/// Android returns a network-derived position — a cell tower, a wifi lookup —
/// through the same call as a satellite fix, and the two are indistinguishable
/// unless `Position.accuracy` is read. Ziren showed a confident place name for
/// a fix that may have been over a kilometre out, and nobody could see the
/// difference.
///
/// A circle can be seen. If it covers the barangay, the resident knows the app
/// does not really know where they are, and can say so before help is sent to
/// the wrong place.
class GeoCircle {
  const GeoCircle._();

  /// Metres per degree of latitude. Constant enough anywhere on Earth.
  static const double _mPerDegLat = 111320.0;

  /// GeoJSON `Feature` holding a polygon that approximates a circle of
  /// [radiusMetres] around ([lat], [lon]).
  ///
  /// [points] trades smoothness for payload size; 64 is round to the eye at
  /// any zoom a phone will show.
  static Map<String, dynamic> polygon({
    required double lat,
    required double lon,
    required double radiusMetres,
    int points = 64,
  }) {
    // A degree of longitude shortens towards the poles; at Biliran's latitude
    // it is about 98% of a degree of latitude. Ignoring that would draw a
    // visible ellipse.
    final mPerDegLon = _mPerDegLat * math.cos(lat * math.pi / 180.0);
    final dLat = radiusMetres / _mPerDegLat;
    final dLon = radiusMetres / (mPerDegLon.abs() < 1 ? 1 : mPerDegLon);

    final ring = <List<double>>[
      for (var i = 0; i <= points; i++)
        () {
          final theta = 2 * math.pi * i / points;
          return [lon + dLon * math.cos(theta), lat + dLat * math.sin(theta)];
        }(),
    ];

    return {
      'type': 'Feature',
      'properties': const <String, dynamic>{},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
    };
  }

  /// The same, wrapped as a one-feature collection — the shape
  /// `GeojsonSourceProperties.data` expects.
  static Map<String, dynamic> featureCollection({
    required double lat,
    required double lon,
    required double radiusMetres,
    int points = 64,
  }) => {
    'type': 'FeatureCollection',
    'features': [
      polygon(lat: lat, lon: lon, radiusMetres: radiusMetres, points: points),
    ],
  };

  /// An empty collection, for clearing the layer without removing it.
  static Map<String, dynamic> get empty => const {
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };
}
