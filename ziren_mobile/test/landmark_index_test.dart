import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/incident_report/domain/landmark_index.dart';

MapPlace _p(String name, String kind, double lat, double lng, {bool landmark = true}) =>
    MapPlace(name: name, kind: kind, isLandmark: landmark, lat: lat, lng: lng);

void main() {
  group('nearestLandmark', () {
    // ~0.0009° latitude ≈ 100 m.
    final index = LandmarkIndex.fromPlaces([
      _p('Sari-sari Store', 'shop', 11.5600, 124.4000),
      _p('Naval Central School', 'school', 11.5603, 124.4000),
      _p('Far Chapel', 'place_of_worship', 11.5700, 124.4000),
      _p('Larrazabal', 'village', 11.5600, 124.4001, landmark: false),
    ]);

    test('the closest landmark wins, whatever its kind', () {
      // Store 0 m, school ~33 m.
      expect(index.nearestLandmark(11.5600, 124.4000)?.name, 'Sari-sari Store');
      expect(index.nearestLandmark(11.5603, 124.4000)?.name, 'Naval Central School');
    });

    test('an unnamed court closer than a named hall is the one picked', () {
      // The stations' case in Naval: the hall ~125 m away, the court ~15 m.
      final withCourt = LandmarkIndex.fromPlaces(
        [_p('NSAHA and KYC Center', 'town_hall', 11.580927, 124.409233)],
        unnamed: [_p('Basketball Court', 'pitch', 11.581878, 124.409040)],
      );
      expect(withCourt.nearestLandmark(11.5820, 124.4091)?.name, 'Basketball Court');
      expect(withCourt.nearestLandmark(11.5809, 124.4092)?.name, 'NSAHA and KYC Center');
    });

    test('unnamed landmarks are not search results', () {
      final withCourt = LandmarkIndex.fromPlaces(const [],
          unnamed: [_p('Basketball Court', 'pitch', 11.58, 124.40)]);
      expect(withCourt.search('basketball'), isEmpty);
    });

    test('never names a barangay as a landmark', () {
      expect(index.nearestLandmark(11.5600, 124.4001)?.isLandmark, isTrue);
    });

    test('nothing past 250 m', () {
      expect(index.nearestLandmark(11.5650, 124.4000), isNull);
    });
  });

  group('search', () {
    final index = LandmarkIndex.fromPlaces([
      _p('Larrazabal Elementary School', 'school', 1, 1),
      _p('Larrazabal', 'village', 1, 1, landmark: false),
      _p('Mañgas Chapel', 'place_of_worship', 1, 1),
      _p('Union, Caibiran', 'village', 1, 1, landmark: false),
      _p('Caibiran', 'town', 1, 1, landmark: false),
    ]);

    test('exact name first, and the barangay before a landmark named after it', () {
      expect(index.search('larrazabal').map((p) => p.name), ['Larrazabal', 'Larrazabal Elementary School']);
    });

    test('starts-with beats a later word', () {
      expect(index.search('caibiran').first.name, 'Caibiran');
    });

    test('ignores accents and case', () {
      expect(index.search('MANGAS').single.name, 'Mañgas Chapel');
    });

    test('empty query finds nothing', () {
      expect(index.search('  '), isEmpty);
    });
  });

  test('the app bundles the same place list the dashboard map searches', () {
    final app = File('assets/map/places.json').readAsStringSync();
    final dashboard = File('../ziren_dashboard/public/map/places.json').readAsStringSync();
    expect(app, dashboard);
    final list = jsonDecode(app) as List;
    expect(list.length, greaterThan(500));
    expect(list.where((e) => e['k'] == 'poi'), isNotEmpty);
    expect(File('pubspec.yaml').readAsStringSync(), matches(RegExp(r'- assets/map/\r?\n')));
  });

  test('unnamed landmarks are bundled, each labelled by what it is', () {
    final list = jsonDecode(File('assets/map/unnamed_landmarks.json').readAsStringSync()) as List;
    expect(list.length, greaterThan(50));
    final places = list.map((e) => MapPlace.fromJson(e as Map<String, dynamic>)).toList();
    expect(places.every((p) => p.isLandmark && p.name.isNotEmpty && p.name != 'Landmark'), isTrue);
    // The court beside NSAHA and KYC Center in Naval, which the stations pointed out.
    final index = LandmarkIndex.fromPlaces(const [], unnamed: places);
    expect(index.nearestLandmark(11.581878, 124.409040)?.name, 'Basketball Court');
  });
}
