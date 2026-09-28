import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/features/incident_report/domain/biliran_places.dart';
import 'package:ziren/features/incident_report/domain/place_naming.dart';

/// Regression tests for the address a dispatcher reads.
///
/// The position below is the one that produced the report this fixes: standing
/// inside barangay Talustusan, the app filed "1.5 km from San Roque, Biliran".
/// San Roque is a different barangay and the reporter was not in it.
void main() {
  // Roughly on the line between the San Roque and Talustusan nodes, which is
  // where the real report came from: closer to San Roque's node than to the
  // school standing in for Talustusan's centre, while actually being in
  // Talustusan.
  const lat = 11.5920;
  const lon = 124.4181;

  HomeBarangay home(String name) => HomeBarangay(
    name: name,
    municipality: BiliranPlaces.byName(name)?.municipality,
    km: BiliranPlaces.distanceToNamed(name, lat, lon),
  );

  test('the position really is the awkward one described', () {
    final nearest = BiliranPlaces.nearest(lat, lon)!;
    final toTalustusan = BiliranPlaces.distanceToNamed('Talustusan', lat, lon)!;

    // Nearest node is NOT the barangay the reporter is standing in.
    expect(nearest.place.name, isNot('Talustusan'));
    // ...and it is not close enough to assert on its own.
    expect(nearest.isConfident, isFalse);
    // ...while the reporter's own barangay is a near tie, not a distant one.
    expect(toTalustusan - nearest.km, lessThan(1.0));
  });

  test('without a home barangay it still refuses to guess (unchanged)', () {
    final address = PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: BiliranPlaces.nearest(lat, lon),
    );
    expect(address, contains('km from'));
    expect(address, isNot(contains('Talustusan')));
  });

  test('the reporter\'s own barangay wins a near tie', () {
    final address = PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: BiliranPlaces.nearest(lat, lon),
      home: home('Talustusan'),
    );
    expect(address, 'Near Talustusan, Naval, Biliran');
    expect(address, isNot(contains('San Roque')));
  });

  test('a home barangay far away is not asserted', () {
    // Reporting from Naval while registered in Maripipi, an island 20 km off.
    final address = PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: BiliranPlaces.nearest(lat, lon),
      home: home('Agutay'),
    );
    expect(address, isNot(contains('Agutay')));
    expect(address, contains('km from'));
  });

  test('OpenStreetMap local detail still wins over the home barangay', () {
    // When OSM has actually mapped the area its containment is finer than
    // anything inferred from a declared address, and must not be overridden.
    final address = PlaceNaming.compose(
      osm: PlaceNaming.fromOsm(const {
        'amenity': 'Talustusan Elementary School',
        'neighbourhood': 'Purok 3',
        'village': 'Talustusan',
        'town': 'Naval',
      }),
      nearest: BiliranPlaces.nearest(lat, lon),
      home: home('Talustusan'),
    );
    expect(address,
        'Talustusan Elementary School, Purok 3, Talustusan, Naval, Biliran');
    expect(address, isNot(contains('Near ')));
  });

  test('a barangay with no node in the table is never asserted', () {
    // Sanggalang is one of the seven that did not geocode. No node means no
    // range check, and an unverifiable claim is worse than a distance.
    expect(BiliranPlaces.distanceToNamed('Sanggalang', lat, lon), isNull);
    final address = PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: BiliranPlaces.nearest(lat, lon),
      home: home('Sanggalang'),
    );
    expect(address, isNot(contains('Sanggalang')));
  });

  test('a poor fix is still annotated', () {
    final address = PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: BiliranPlaces.nearest(lat, lon),
      home: home('Talustusan'),
      accuracyM: 250,
    );
    expect(address, endsWith('(GPS ±250 m)'));
  });
}
