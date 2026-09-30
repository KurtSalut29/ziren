import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/geo/geodesic.dart';

/// A path along the roads between two points, from OSRM.
///
/// The route comes from OSRM's public demo routing server: free, keyless, no
/// account for this project to hold. It is also exactly that, a shared
/// community demo with no uptime guarantee and no rate-limit protection, not
/// infrastructure to depend on in an emergency. So it is never the only path.
/// Any failure (down, slow, rate-limited, malformed reply) comes back as null,
/// and every caller falls back to the direct line, which needs nothing
/// external and cannot itself fail.
///
/// Shared by the resident map ("Get directions", the focused report's line)
/// and the responder's navigation screen, which used to draw only a straight
/// line.
@immutable
class RoadRoute {
  const RoadRoute({
    required this.coordinates,
    required this.metres,
    required this.seconds,
  });

  /// `[lon, lat]` pairs, ready to drop into a GeoJSON LineString.
  final List<List<double>> coordinates;

  /// Length along the road, as OSRM measured it.
  final double metres;

  /// OSRM's own driving estimate. Not shown: it assumes free-flowing traffic
  /// on a city car profile, not a fire truck on a barangay road.
  final double seconds;

  static const _host = 'https://router.project-osrm.org';

  /// A road path from ([fromLat], [fromLng]) to ([toLat], [toLng]), or null
  /// if OSRM did not answer with one for any reason.
  ///
  /// Every failure collapses to null on purpose: a caller that only has to
  /// handle "got a route" and "did not" cannot forget to fall back.
  static Future<RoadRoute?> fetch(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final uri = Uri.parse(
        '$_host/route/v1/driving/'
        '$fromLng,$fromLat;$toLng,$toLat'
        '?geometries=geojson&overview=full',
      );
      final response = await (client?.get(uri) ?? http.get(uri)).timeout(
        timeout,
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) return null;

      return RoadRoute(
        coordinates: [
          for (final c in coords)
            [(c[0] as num).toDouble(), (c[1] as num).toDouble()],
        ],
        metres: (route['distance'] as num?)?.toDouble() ?? 0,
        seconds: (route['duration'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      debugPrint('[route] OSRM route fetch failed, falling back to line: $e');
      return null;
    }
  }

  /// What is left of this route for someone standing at ([lat], [lng]).
  ///
  /// The route was fetched from where the crew WAS. Rather than asking OSRM
  /// again every ten metres, the part already driven is cut off: the path
  /// continues from the vertex nearest the crew. [offRouteMetres] is how far
  /// the crew is from that vertex, which is how the caller tells "still on
  /// the route" from "took another road, fetch a new one".
  RemainingRoute remainingFrom(double lat, double lng) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < coordinates.length; i++) {
      final d = metresBetween(lat, lng, coordinates[i][1], coordinates[i][0]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    final rest = coordinates.sublist(best);
    var along = bestDistance;
    for (var i = 1; i < rest.length; i++) {
      along += metresBetween(
        rest[i - 1][1],
        rest[i - 1][0],
        rest[i][1],
        rest[i][0],
      );
    }
    return RemainingRoute(
      coordinates: rest,
      metres: along,
      offRouteMetres: bestDistance,
    );
  }

  /// The app's one distance (WGS-84, see [Geodesic]), so this screen and
  /// every other one quote the same metres for the same two points.
  static double metresBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final d = Geodesic.metres(lat1, lng1, lat2, lng2);
    return d.isNaN ? double.infinity : d;
  }
}

/// The part of a [RoadRoute] still ahead of the crew.
@immutable
class RemainingRoute {
  const RemainingRoute({
    required this.coordinates,
    required this.metres,
    required this.offRouteMetres,
  });

  /// `[lon, lat]` pairs from the vertex nearest the crew to the route's end.
  final List<List<double>> coordinates;

  /// From the crew to the route's end: the gap to the route, plus the road.
  final double metres;

  /// How far the crew is from the route.
  final double offRouteMetres;
}
