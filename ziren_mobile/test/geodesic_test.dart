import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/core/geo/geodesic.dart';

/// The phone, the console and the server must quote the same distance for the same
/// two points. The reference values are Karney's algorithm (geographiclib) - the
/// same table as backend `tests/test_geo.py` and the dashboard's check - so a drift
/// in any one implementation shows up here.
///
/// The first pair is Vincenty's own published test line (Flinders Peak to
/// Buninyong, Geoscience Australia).
void main() {
  // lat1, lon1, lat2, lon2, metres
  final golden = <String, List<double>>{
    'flinders_buninyong': [
      -(37 + 57 / 60 + 3.72030 / 3600),
      144 + 25 / 60 + 29.52440 / 3600,
      -(37 + 39 / 60 + 10.15610 / 3600),
      143 + 55 / 60 + 35.38390 / 3600,
      54972.271,
    ],
    'naval_north_0_09deg': [11.56, 124.4, 11.65, 124.4, 9955.7301],
    'naval_east_0_09deg': [11.56, 124.4, 11.56, 124.4915, 9980.4614],
    'naval_diagonal': [11.56, 124.4, 11.61, 124.45, 7767.2481],
    'cabucgayan_to_naval': [11.45, 124.56, 11.56, 124.4, 21278.1054],
    'short_200m': [11.56, 124.4, 11.5617, 124.401, 217.3962],
  };

  group('matches the reference to a millimetre', () {
    golden.forEach((name, v) {
      test(name, () {
        expect(
          Geodesic.metres(v[0], v[1], v[2], v[3]),
          closeTo(v[4], 0.001),
        );
      });
    });
  });

  test('is symmetric', () {
    final v = golden['cabucgayan_to_naval']!;
    expect(
      Geodesic.metres(v[0], v[1], v[2], v[3]),
      closeTo(Geodesic.metres(v[2], v[3], v[0], v[1]), 1e-6),
    );
  });

  test('the same point is zero metres away', () {
    expect(Geodesic.metres(11.56, 124.4, 11.56, 124.4), 0);
  });

  test('the equator and the poles do not break the iteration', () {
    expect(Geodesic.metres(0, 0, 0, 1), closeTo(111319.4908, 0.01));
    expect(Geodesic.metres(-90, 0, 90, 0), closeTo(20003931.4586, 0.01));
    expect(Geodesic.metres(89.9, 0, 89.9, 180), greaterThan(0));
  });

  test('nearly antipodal points fall back instead of throwing', () {
    final d = Geodesic.metres(0, 0, 0.5, 179.7);
    expect(d, inInclusiveRange(19900000, 20100000));
  });

  test('a sphere is about 52 m long on a 10 km north-south leg here', () {
    final v = golden['naval_north_0_09deg']!;
    final sphere = Geodesic.haversineM(v[0], v[1], v[2], v[3]);
    expect(sphere - v[4], closeTo(51.8, 0.5));
  });

  test('junk is NaN, not a confident number', () {
    expect(Geodesic.metres(95, 0, 0, 0).isNaN, isTrue);
    expect(Geodesic.metres(double.nan, 0, 0, 0).isNaN, isTrue);
    expect(Geodesic.metres(0, 181, 0, 0).isNaN, isTrue);
    expect(Geodesic.valid(11.5, 124.4), isTrue);
    expect(Geodesic.valid(91, 0), isFalse);
  });

  test('km is metres over a thousand', () {
    final v = golden['naval_north_0_09deg']!;
    expect(Geodesic.km(v[0], v[1], v[2], v[3]), closeTo(9.9557301, 1e-6));
  });

  group('ETA is the shared model: 30 km/h, rounded up, never 0', () {
    test('values', () {
      expect(Geodesic.etaMinutes(0), 1);
      expect(Geodesic.etaMinutes(0.2), 1);
      expect(Geodesic.etaMinutes(1.0), 3);
      expect(Geodesic.etaMinutes(15.0), 31);
    });
    test('ceiling and junk', () {
      expect(Geodesic.etaMinutes(10000), 600);
      expect(Geodesic.etaMinutes(-5), 1);
      expect(Geodesic.etaMinutes(double.nan), 1);
    });
  });
}
