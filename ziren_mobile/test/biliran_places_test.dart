import 'package:flutter_test/flutter_test.dart';
import 'package:Ziren/features/incident_report/domain/biliran_places.dart';

/// The failure this table was built for: standing in barangay Talustusan, the
/// app reported "Padre Sergio Eamiguel" — a different barangay 1.66 km away —
/// because OpenStreetMap has no place node for Talustusan and reverse
/// geocoding answers with the nearest name it does have.
void main() {
  // Talustusan Elementary School, the only Talustusan object OSM holds.
  const talustusan = (lat: 11.603488, lon: 124.428910);
  // The village node the app used to report instead.
  const eamiguel = (lat: 11.589268, lon: 124.433645);

  group('the reported failure', () {
    test('a position in Talustusan now names Talustusan', () {
      final n = BiliranPlaces.nearest(talustusan.lat, talustusan.lon)!;
      expect(n.place.name, 'Talustusan');
      expect(n.isConfident, isTrue);
    });

    test('the two barangays really are far enough apart to matter', () {
      final km = BiliranPlaces.distanceKm(
        talustusan.lat,
        talustusan.lon,
        eamiguel.lat,
        eamiguel.lon,
      );
      expect(km, greaterThan(1.5));
      expect(km, lessThan(2.0));
    });

    test('standing at Padre Sergio Eamiguel still names it', () {
      // The old answer was not wrong about that place — only about which
      // place the reporter was standing in.
      final n = BiliranPlaces.nearest(eamiguel.lat, eamiguel.lon)!;
      expect(n.place.name, 'Padre Sergio Eamiguel');
    });
  });

  group('the position actually reported from the handset', () {
    // Read back from the incident row: POINT(124.4168239 11.5928486), stored
    // twice fourteen minutes apart and one metre apart.
    const reported = (lat: 11.5928486, lon: 124.4168239);

    test('no known place is close enough to name outright', () {
      final n = BiliranPlaces.nearest(reported.lat, reported.lon)!;
      expect(n.km, greaterThan(1.0));
      expect(
        n.isConfident,
        isFalse,
        reason:
            'San Roque is nearest at 1.48 km, Talustusan 1.77 km and Padre '
            'Sergio Eamiguel 1.88 km. Picking any of them as a fact would '
            'repeat the original error with a different name.',
      );
    });

    test('the three candidates are too close together to separate', () {
      double to(String name) {
        final p = BiliranPlaces.all.firstWhere((p) => p.name == name);
        return BiliranPlaces.distanceKm(
          reported.lat,
          reported.lon,
          p.lat,
          p.lon,
        );
      }

      final spread = to('Padre Sergio Eamiguel') - to('San Roque');
      expect(spread.abs(), lessThan(0.5));
    });
  });

  group('the table', () {
    test('holds every place with usable coordinates', () {
      expect(BiliranPlaces.all.length, greaterThanOrEqualTo(52));
      for (final p in BiliranPlaces.all) {
        expect(p.name, isNotEmpty);
        // Biliran province, generously bounded — Maripipi island to the north,
        // Libertad to the west.
        expect(p.lat, inInclusiveRange(11.40, 11.90));
        expect(p.lon, inInclusiveRange(124.25, 124.70));
      }
    });

    test('names are unique', () {
      final names = BiliranPlaces.all.map((p) => p.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('records which points are buildings standing in for a barangay', () {
      // Ten resolved to a school. That is usable as a centroid and worth
      // knowing about, so it must stay visible rather than being flattened.
      final schools =
          BiliranPlaces.all.where((p) => !p.isSettlement).toList();
      expect(schools, isNotEmpty);
      expect(
        BiliranPlaces.all.firstWhere((p) => p.name == 'Talustusan').source,
        'school',
      );
    });

    test('the municipalities are present', () {
      for (final m in [
        'Naval',
        'Almeria',
        'Caibiran',
        'Culaba',
        'Kawayan',
        'Maripipi',
        'Cabucgayan',
        'Biliran',
      ]) {
        expect(
          BiliranPlaces.all.any((p) => p.name == m),
          isTrue,
          reason: '$m missing from the table',
        );
      }
    });
  });

  group('distance', () {
    test('is zero at the point itself', () {
      final p = BiliranPlaces.all.first;
      expect(BiliranPlaces.distanceKm(p.lat, p.lon, p.lat, p.lon), 0);
    });

    test('a position far out to sea is not confidently named', () {
      // Naming a place 40 km away as though it were an address would be worse
      // than saying nothing.
      final n = BiliranPlaces.nearest(11.20, 124.10)!;
      expect(n.isConfident, isFalse);
    });
  });
}
