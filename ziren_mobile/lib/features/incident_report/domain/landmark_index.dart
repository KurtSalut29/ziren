import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// A named place from the map extract: a landmark (school, church, hall,
/// store …) or a settlement (town, barangay, sitio).
class MapPlace {
  const MapPlace({
    required this.name,
    required this.kind,
    required this.isLandmark,
    required this.lat,
    required this.lng,
  });

  final String name;

  /// OpenMapTiles class: school, place_of_worship, town_hall, village, town …
  final String kind;

  /// True for a landmark, false for a town / barangay / sitio.
  final bool isLandmark;
  final double lat;
  final double lng;

  factory MapPlace.fromJson(Map<String, dynamic> j) => MapPlace(
        name: j['n'] as String,
        kind: j['c'] as String,
        // unnamed_landmarks.json carries no 'k': every entry is a landmark.
        isLandmark: (j['k'] ?? 'poi') == 'poi',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  double metresTo(double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat) * math.pi / 180;
    final dLng = (lng2 - lng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

/// Every named landmark and place in the Biliran map extract, bundled with the
/// app (assets/map/places.json — the same file the dashboard's map search
/// reads, made by ziren_dashboard/scripts/make-map-assets.mjs).
///
/// Two jobs: naming the landmark nearest an incident without any network
/// (so the landmark field can be filled for the resident), and finding a
/// place by name when a resident places an incident on the map.
///
/// Landmarks nobody named on the map (a basketball court, a chapel) come from
/// assets/map/unnamed_landmarks.json, labelled by what they are — the same
/// words the map prints beside them. They count for the nearest landmark but
/// not for search, where dozens of "Basketball Court" would only get in the way.
class LandmarkIndex {
  LandmarkIndex._(this.places, this.unnamed);

  final List<MapPlace> places;
  final List<MapPlace> unnamed;

  static LandmarkIndex? _instance;
  static Future<LandmarkIndex>? _loading;

  /// Loaded once, on first use.
  static Future<LandmarkIndex> load() {
    final ready = _instance;
    if (ready != null) return Future.value(ready);
    return _loading ??= Future.wait([
      _readList('assets/map/places.json'),
      _readList('assets/map/unnamed_landmarks.json'),
    ]).then((lists) => _instance = LandmarkIndex._(lists[0], lists[1]));
  }

  /// One bundled list; empty (and retried on the next load) if unreadable.
  static Future<List<MapPlace>> _readList(String asset) => rootBundle
          .loadString(asset)
          .then((raw) => (jsonDecode(raw) as List)
              .map((e) => MapPlace.fromJson(e as Map<String, dynamic>))
              .toList())
          .catchError((Object _) {
        _loading = null;
        return <MapPlace>[];
      });

  /// For tests.
  static LandmarkIndex fromPlaces(List<MapPlace> places, {List<MapPlace> unnamed = const []}) =>
      LandmarkIndex._(places, unnamed);

  /// How far a landmark may be and still describe the spot. 250 m is about
  /// two blocks in a poblacion: "near the school" is still useful there, and
  /// past it the name would mislead more than it helps.
  static const double maxLandmarkMetres = 250;

  /// The landmark closest to [lat],[lng], named or not, within
  /// [maxLandmarkMetres]. Plain distance, no preference by kind: stations
  /// asked for the nearest thing a responder can see — the court beside the
  /// incident, not a hall 100 m further on.
  MapPlace? nearestLandmark(double lat, double lng) {
    MapPlace? best;
    double bestMetres = double.infinity;
    for (final list in [places, unnamed]) {
      for (final p in list) {
        if (!p.isLandmark) continue;
        final d = p.metresTo(lat, lng);
        if (d > maxLandmarkMetres || d >= bestMetres) continue;
        bestMetres = d;
        best = p;
      }
    }
    return best;
  }

  /// Places whose name contains every word of [query], best matches first:
  /// exact, then starts-with, then a word that starts with it; settlements
  /// before landmarks on a tie, since "Larrazabal" means the barangay.
  List<MapPlace> search(String query, {int limit = 8}) {
    final q = _fold(query.trim());
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    int rank(String name) {
      if (name == q) return 0;
      if (name.startsWith(q)) return 1;
      if (name.split(RegExp(r'[\s,.-]+')).any((w) => w.startsWith(q))) return 2;
      return 3;
    }

    final hits = [
      for (final p in places)
        if (words.every(_fold(p.name).contains)) p,
    ];
    hits.sort((a, b) {
      final r = rank(_fold(a.name)).compareTo(rank(_fold(b.name)));
      if (r != 0) return r;
      if (a.isLandmark != b.isLandmark) return a.isLandmark ? 1 : -1;
      return a.name.compareTo(b.name);
    });
    return hits.take(limit).toList();
  }

  static String _fold(String s) {
    const from = 'áàâäãéèêëíìîïóòôöõúùûüñ';
    const to = 'aaaaaeeeeiiiiooooouuuun';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString();
  }
}
