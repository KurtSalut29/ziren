import 'dart:math' as math;

/// Distance between two points on the ground, on the WGS-84 ellipsoid.
///
/// A port of `app/core/geo.py` (and `lib/geo/geodesic.ts` on the dashboard), so
/// the phone, the console and the server quote the SAME distance for the same
/// pair of points. See the backend file for the whole argument; the short version:
/// Haversine treats the Earth as a sphere, which at Biliran's latitude makes every
/// north-south leg about half a percent long (~50 m per 10 km). Vincenty's inverse
/// formula on the ellipsoid GPS itself reports in is accurate to half a millimetre.
///
/// Most of the app already asks the platform (`Geolocator.distanceBetween`, which
/// is ellipsoidal on Android and iOS). This exists for the places that need the
/// answer without a plugin - in a pure-Dart domain class, in a test - and to keep
/// the three implementations checkable against one another.
class Geodesic {
  const Geodesic._();

  static const double _a = 6378137.0; // semi-major axis, metres
  static const double _f = 1 / 298.257223563; // flattening
  static const double _b = _a * (1 - _f); // semi-minor axis
  static const double _meanRadiusM = 6371008.7714; // IUGG mean, fallback only

  /// Assumed average road speed. Keep equal to ASSUMED_SPEED_KMH in the backend.
  static const double assumedSpeedKmh = 30.0;

  static double _rad(double deg) => deg * math.pi / 180.0;

  static bool valid(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  /// Spherical great-circle distance in metres. A fallback and a pre-filter.
  static double haversineM(double lat1, double lon1, double lat2, double lon2) {
    final dPhi = _rad(lat2 - lat1);
    final dLmb = _rad(lon2 - lon1);
    final h =
        math.pow(math.sin(dPhi / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLmb / 2), 2);
    return 2 *
        _meanRadiusM *
        math.atan2(math.sqrt(h.toDouble()), math.sqrt(1 - h.toDouble()));
  }

  /// Shortest distance in metres between two points on the WGS-84 ellipsoid
  /// (Vincenty's inverse formula, iterated to 1e-12 rad). NaN for a coordinate
  /// that is not a real latitude/longitude, so a caller that formats it shows a
  /// dash rather than a confident wrong number.
  static double metres(double lat1, double lon1, double lat2, double lon2) {
    if (!valid(lat1, lon1) || !valid(lat2, lon2)) return double.nan;
    if (lat1 == lat2 && lon1 == lon2) return 0.0;

    final l = _rad(lon2 - lon1);
    final u1 = math.atan((1 - _f) * math.tan(_rad(lat1)));
    final u2 = math.atan((1 - _f) * math.tan(_rad(lat2)));
    final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
    final sinU2 = math.sin(u2), cosU2 = math.cos(u2);

    var lam = l;
    var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0;
    var cosSqAlpha = 0.0, cos2SigmaM = 0.0;
    var converged = false;
    for (var i = 0; i < 200; i++) {
      final sinLam = math.sin(lam), cosLam = math.cos(lam);
      sinSigma = math.sqrt(
        math.pow(cosU2 * sinLam, 2) +
            math.pow(cosU1 * sinU2 - sinU1 * cosU2 * cosLam, 2),
      );
      if (sinSigma == 0) return 0.0; // coincident points
      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLam;
      sigma = math.atan2(sinSigma, cosSigma);
      final sinAlpha = cosU1 * cosU2 * sinLam / sinSigma;
      cosSqAlpha = 1 - sinAlpha * sinAlpha;
      // cosSqAlpha is 0 only on the equator; the term is then defined as 0.
      cos2SigmaM =
          cosSqAlpha != 0 ? cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha : 0.0;
      final c = _f / 16 * cosSqAlpha * (4 + _f * (4 - 3 * cosSqAlpha));
      final prev = lam;
      lam =
          l +
          (1 - c) *
              _f *
              sinAlpha *
              (sigma +
                  c *
                      sinSigma *
                      (cos2SigmaM +
                          c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
      if ((lam - prev).abs() < 1e-12) {
        converged = true;
        break;
      }
    }
    if (!converged) return haversineM(lat1, lon1, lat2, lon2); // near-antipodal

    final uSq = cosSqAlpha * (_a * _a - _b * _b) / (_b * _b);
    final bigA =
        1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
    final bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
    final deltaSigma =
        bigB *
        sinSigma *
        (cos2SigmaM +
            bigB /
                4 *
                (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                    bigB /
                        6 *
                        cos2SigmaM *
                        (-3 + 4 * sinSigma * sinSigma) *
                        (-3 + 4 * cos2SigmaM * cos2SigmaM)));
    return _b * bigA * (sigma - deltaSigma);
  }

  /// [metres] in kilometres.
  static double km(double lat1, double lon1, double lat2, double lon2) =>
      metres(lat1, lon1, lat2, lon2) / 1000.0;

  /// Minutes to cover [distanceKm] at the assumed road speed, rounded UP and never
  /// 0 - the same model as the backend and the dashboard, so nobody is quoted two
  /// different ETAs for one trip. A NaN distance gives 1, never NaN.
  static int etaMinutes(double distanceKm) {
    final safe = distanceKm.isFinite ? math.max(0.0, distanceKm) : 0.0;
    return (safe / assumedSpeedKmh * 60).floor().clamp(0, 599) + 1;
  }
}
