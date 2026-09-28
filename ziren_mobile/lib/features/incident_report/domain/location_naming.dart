import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'biliran_places.dart';
import 'place_naming.dart';

/// Turns a GPS fix into the same kind of place name IncidentProvider shows
/// on a normal report — "San Roque, Larrazabal, Naval, Biliran" instead of
/// bare coordinates — for any screen that only has a position and needs a
/// name for it.
///
/// The naming intelligence itself (which source to trust, when a barangay
/// name is a real match versus a nearest-neighbour guess) lives entirely in
/// [PlaceNaming] and [BiliranPlaces] and is not reimplemented here — this is
/// only the HTTP/orchestration glue, shared so a second caller (SosProvider)
/// gets the same fixes IncidentProvider already earned rather than an
/// independent, driftable copy. Deliberately without IncidentProvider's
/// home-barangay personalisation: that needs its own Supabase round trip,
/// and a caller that only has a position and wants a fast answer is better
/// served without waiting on it.
abstract final class LocationNaming {
  /// Instant, local-only guess — no network. Always returns something
  /// usable the moment a position is known, refined by [resolve] shortly
  /// after.
  static String guess(Position pos) {
    final nearest = BiliranPlaces.nearest(pos.latitude, pos.longitude);
    return PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: nearest,
      accuracyM: pos.accuracy,
    );
  }

  /// Network-enriched address. Falls back to [guess] on any failure —
  /// offline, rate-limited, or slow — so a lost connection downgrades the
  /// detail rather than removing the address.
  static Future<String> resolve(Position pos) async {
    final nearest = BiliranPlaces.nearest(pos.latitude, pos.longitude);
    Map<String, dynamic>? osmAddress;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': pos.latitude.toString(),
        'lon': pos.longitude.toString(),
        'format': 'json',
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: {'User-Agent': 'ZirenEmergencyApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        osmAddress = data['address'] as Map<String, dynamic>?;
      }
    } catch (_) {
      osmAddress = null;
    }
    return PlaceNaming.compose(
      osm: PlaceNaming.fromOsm(osmAddress),
      nearest: nearest,
      accuracyM: pos.accuracy,
    );
  }
}
