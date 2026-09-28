import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:Ziren/features/map/domain/geo_circle.dart';

/// The accuracy circle has to mean metres. MapLibre's own circle layer sizes
/// its radius in screen pixels, which would make it grow and shrink with zoom
/// and mean nothing at all — so it is built as a real polygon, and these tests
/// hold it to the distance it claims.
void main() {
  // Biliran, near the position the investigation was about.
  const lat = 11.5928486;
  const lon = 124.4168239;

  /// Haversine, metres — deliberately a second implementation, so the polygon
  /// is checked against something other than the maths that built it.
  double metres(double aLat, double aLon, double bLat, double bLon) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final sLat = math.sin(rad(bLat - aLat) / 2);
    final sLon = math.sin(rad(bLon - aLon) / 2);
    final h =
        sLat * sLat +
        math.cos(rad(aLat)) * math.cos(rad(bLat)) * sLon * sLon;
    return 2 * r * math.asin(math.sqrt(h));
  }

  List<List<double>> ringOf(Map<String, dynamic> feature) =>
      ((feature['geometry'] as Map)['coordinates'] as List).first
          .cast<List<double>>();

  group('the polygon really is the radius it claims', () {
    for (final radius in [15.0, 150.0, 1500.0]) {
      test('every vertex sits ~$radius m from the centre', () {
        final ring = ringOf(
          GeoCircle.polygon(lat: lat, lon: lon, radiusMetres: radius),
        );
        for (final point in ring) {
          final d = metres(lat, lon, point[1], point[0]);
          // 1% covers the flat-earth approximation at these distances.
          expect(d, closeTo(radius, radius * 0.01));
        }
      });
    }

    test('it is a circle, not an ellipse', () {
      // A degree of longitude is shorter than a degree of latitude. Ignoring
      // that draws a visibly squashed circle, which would misstate the
      // east-west accuracy.
      final ring = ringOf(
        GeoCircle.polygon(lat: lat, lon: lon, radiusMetres: 500),
      );
      final distances = ring
          .map((p) => metres(lat, lon, p[1], p[0]))
          .toList();
      final spread =
          distances.reduce(math.max) - distances.reduce(math.min);
      expect(spread, lessThan(10));
    });
  });

  group('the shape it hands to MapLibre', () {
    test('the ring is closed', () {
      final ring = ringOf(
        GeoCircle.polygon(lat: lat, lon: lon, radiusMetres: 100),
      );
      expect(ring.first, ring.last);
    });

    test('coordinates are [lon, lat], the GeoJSON order', () {
      // Reversing these is the classic mapping bug: the pin lands in the
      // ocean off Somalia and everything else still looks fine.
      final ring = ringOf(
        GeoCircle.polygon(lat: lat, lon: lon, radiusMetres: 100),
      );
      expect(ring.first[0], closeTo(lon, 0.01));
      expect(ring.first[1], closeTo(lat, 0.01));
    });

    test('a feature collection wraps exactly one feature', () {
      final fc = GeoCircle.featureCollection(
        lat: lat,
        lon: lon,
        radiusMetres: 50,
      );
      expect(fc['type'], 'FeatureCollection');
      expect((fc['features'] as List).length, 1);
    });

    test('empty is a valid, drawable, featureless collection', () {
      // Used to clear the layer without removing it, so a lost fix cannot
      // leave a stale circle on screen claiming to know where you are.
      expect(GeoCircle.empty['type'], 'FeatureCollection');
      expect((GeoCircle.empty['features'] as List), isEmpty);
    });

    test('vertex count is honoured', () {
      final ring = ringOf(
        GeoCircle.polygon(lat: lat, lon: lon, radiusMetres: 100, points: 8),
      );
      expect(ring.length, 9); // 8 points plus the repeated closing vertex
    });
  });
}
