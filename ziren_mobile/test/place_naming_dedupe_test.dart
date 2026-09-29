import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/incident_report/domain/biliran_places.dart';
import 'package:ziren/features/incident_report/domain/place_naming.dart';

void main() {
  test('a town is not named twice when it is its own municipality', () {
    // The poblacion of Naval: the nearest known place is the town itself.
    final nearest = BiliranPlaces.nearest(11.5618, 124.3965);
    final address = PlaceNaming.compose(osm: const ResolvedPlace(), nearest: nearest);
    expect(address, isNot(contains('Naval, Naval')));
    expect(address, endsWith('Biliran'));
  });

  test('a barangay and its municipality are both kept', () {
    final address = PlaceNaming.compose(
      osm: const ResolvedPlace(barangay: 'Larrazabal', municipality: 'Naval', landmark: 'Larrazabal Elementary School'),
    );
    expect(address, 'Larrazabal Elementary School, Larrazabal, Naval, Biliran');
  });
}
