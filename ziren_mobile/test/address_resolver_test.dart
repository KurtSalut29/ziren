import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/features/auth/data/barangay_repository.dart';
import 'package:Ziren/features/registration/domain/address_resolver.dart';

/// "Use my location" on the address step: a municipality AND a barangay.
///
/// The reference below is the real `public.barangays` table (120 rows), and the
/// coordinates are real points from the on-device place table, so these are the
/// answers a resident standing in those barangays would actually get.
const _reference = <String, List<String>>{
  'Almeria': [
    'Caucab',
    'Iyosan',
    'Jamorawon',
    'Lo-ok',
    'Looc',
    'Matanga',
    'Pili',
    'Poblacion Norte',
    'Poblacion Sur',
    'Salangi',
    'Sampao',
    'Tabunan',
    'Talahid',
    'Tamarindo',
  ],
  'Biliran': [
    'Bato',
    'Burabod',
    'Canila',
    'Hugpa',
    'Julita',
    'Pinangumhan',
    'Poblacion',
    'San Isidro',
    'Sanggalang',
    'Uson',
  ],
  'Cabucgayan': [
    'Balaquid',
    'Bunga',
    'Caanibongan',
    'Casiawan',
    'Esperanza',
    'Langgao',
    'Libertad',
    'Looc',
    'Magbangon',
    'Pawikan',
    'Salawaki',
    'Talibong',
  ],
  'Caibiran': [
    'Asug',
    'Binohangan',
    'Cabibihan',
    'Kawayanon',
    'Looc',
    'Mainit',
    'Manlabang',
    'Maurang',
    'Palanay',
    'Poblacion',
    'Tomalistis',
    'Union',
    'Uson',
    'Victory',
  ],
  'Culaba': [
    'Acaban',
    'Bacolod',
    'Binongtoan',
    'Bool Central',
    'Bool East',
    'Bool West',
    'Culaba Central',
    'Guindapunan',
    'Habuhab',
    'Looc',
    'Marvel',
    'Patag',
    'Patag Norte',
    'Salvacion',
    'San Roque',
    'Virginia',
  ],
  'Kawayan': [
    'Baganito',
    'Balacson',
    'Bilwang',
    'Bulalacao',
    'Burabod',
    'Buyo',
    'Inasuyan',
    'Kansanok',
    'Mapuyo',
    'Masagongsong',
    'Poblacion',
    'San Lorenzo',
    'Tabunan',
    'Ungale',
  ],
  'Maripipi': [
    'Agutay',
    'Banlas',
    'Binalayan East',
    'Binalayan West',
    'Binongtoan',
    'Calbani',
    'Canduhao',
    'Casibang',
    'Danao',
    'Ermita',
    'Olingan',
    'Poblacion',
    'Trabugan',
    'Viga',
  ],
  'Naval': [
    'Agpangi',
    'Anislagan',
    'Atipolo',
    'Borac',
    'Calumpang',
    'Capiñahan',
    'Caraycaray',
    'Catmon',
    'Haguikhikan',
    'Imelda',
    'Larrazabal',
    'Libertad',
    'Libtong',
    'Lico',
    'Lucsoon',
    'Mabini',
    'Padre Inocentes Garcia',
    'Padre Sergio Eamiguel',
    'Sabang',
    'San Pablo',
    'Santissimo Rosario',
    'Santo Niño',
    'Talustusan',
    'Villa Caneja',
    'Villa Consuelo',
    'Villa Enage',
  ],
};

final _ref = <Barangay>[
  for (final e in _reference.entries)
    for (final name in e.value)
      Barangay(id: '${e.key}-$name', name: name, municipality: e.key),
];

void main() {
  group('from the position alone (no network)', () {
    test('Larrazabal is Naval, and the barangay is found too', () {
      // The reported case: standing in Larrazabal, Naval, the app filled in
      // nothing useful. The on-device table has no municipality for Larrazabal,
      // which used to read as "you are not in Biliran".
      final r = AddressResolver.resolve(
        lat: 11.577174,
        lon: 124.404589,
        reference: _ref,
      );
      expect(r.municipality, 'Naval');
      expect(r.barangay?.name, 'Larrazabal');
      expect(r.barangayIsConfident, isTrue);
    });

    test('Talustusan, at the school that stands in for its centre', () {
      final r = AddressResolver.resolve(
        lat: 11.603488,
        lon: 124.42891,
        reference: _ref,
      );
      expect(r.municipality, 'Naval');
      expect(r.barangay?.name, 'Talustusan');
      expect(r.barangayIsConfident, isTrue);
    });

    test('a sitio takes its barangay, not a barangay of another town', () {
      // San Roque is a sitio inside Larrazabal, Naval. "San Roque" is also a
      // barangay of Culaba, and must not be offered for a point in Naval.
      final r = AddressResolver.resolve(
        lat: 11.5821,
        lon: 124.408771,
        reference: _ref,
      );
      expect(r.municipality, 'Naval');
      expect(r.barangay?.name, 'Larrazabal');
      expect(r.barangay?.municipality, 'Naval');
    });

    test(
      'a barangay in another municipality is found in THAT municipality',
      () {
        final r = AddressResolver.resolve(
          lat: 11.566856,
          lon: 124.579425,
          reference: _ref,
        );
        expect(r.municipality, 'Caibiran');
        expect(r.barangay?.name, 'Manlabang');
      },
    );

    test('a name shared by several towns resolves inside the right one', () {
      // "Looc" is a barangay of four municipalities. Near Culaba's Looc node
      // (11.65102, 124.546837) it is Culaba's.
      final r = AddressResolver.resolve(
        lat: 11.65102,
        lon: 124.546837,
        reference: _ref,
      );
      expect(r.municipality, 'Culaba');
      expect(r.barangay?.name, 'Looc');
      expect(r.barangay?.municipality, 'Culaba');
    });

    test('the table spells Santo Rosario differently from the reference', () {
      final r = AddressResolver.resolve(
        lat: 11.56035,
        lon: 124.392994,
        reference: _ref,
      );
      expect(r.barangay?.name, 'Santissimo Rosario');
    });

    test(
      'too far from any barangay point: the municipality, and no barangay',
      () {
        // Kawayan town centre - no barangay node within reach - so the person is
        // asked to choose, not handed a wrong guess.
        final r = AddressResolver.resolve(
          lat: 11.679951,
          lon: 124.357023,
          reference: _ref,
        );
        expect(r.municipality, 'Kawayan');
        expect(r.barangay, isNull);
      },
    );

    test('a position that is not in Biliran resolves to nothing', () {
      final r = AddressResolver.resolve(
        lat: 10.3157,
        lon: 123.8854,
        reference: _ref,
      ); // Cebu
      expect(r.municipality, isNull);
      expect(r.barangay, isNull);
    });

    test('an empty reference resolves to nothing rather than crashing', () {
      final r = AddressResolver.resolve(
        lat: 11.577174,
        lon: 124.404589,
        reference: const [],
      );
      expect(r.municipality, isNull);
    });
  });

  group('with what OpenStreetMap says', () {
    test('a named village in the reference is confident', () {
      final r = AddressResolver.resolve(
        lat: 11.58,
        lon: 124.41,
        reference: _ref,
        osmAddress: {
          'village': 'Larrazabal',
          'town': 'Naval',
          'road': 'National Highway',
        },
      );
      expect(r.municipality, 'Naval');
      expect(r.barangay?.name, 'Larrazabal');
      expect(r.barangayIsConfident, isTrue);
    });

    test('"Municipality of Naval" and "Brgy." prefixes are understood', () {
      final r = AddressResolver.resolve(
        lat: 11.58,
        lon: 124.41,
        reference: _ref,
        osmAddress: {
          'municipality': 'Municipality of Naval',
          'village': 'Brgy. Larrazabal',
        },
      );
      expect(r.municipality, 'Naval');
      expect(r.barangay?.name, 'Larrazabal');
    });

    test('the Spanish tilde does not stop a match', () {
      final r = AddressResolver.resolve(
        lat: 11.55,
        lon: 124.4,
        reference: _ref,
        osmAddress: {'village': 'Capinahan', 'town': 'Naval'},
      );
      expect(r.barangay?.name, 'Capiñahan');
    });

    test('a name OpenStreetMap gives that is not a barangay is ignored', () {
      // "San Roque" as a sitio: not in Naval's list, so it cannot be chosen; the
      // nearest known barangay point decides instead.
      final r = AddressResolver.resolve(
        lat: 11.5821,
        lon: 124.408771,
        reference: _ref,
        osmAddress: {'neighbourhood': 'San Roque', 'town': 'Naval'},
      );
      expect(r.barangay?.municipality, 'Naval');
      expect(r.barangay?.name, 'Larrazabal');
    });

    test('OpenStreetMap wins over the nearest node for the municipality', () {
      // A point OpenStreetMap places in Caibiran, wherever the nearest node is.
      final r = AddressResolver.resolve(
        lat: 11.5679,
        lon: 124.5652,
        reference: _ref,
        osmAddress: {'town': 'Caibiran'},
      );
      expect(r.municipality, 'Caibiran');
    });
  });
}
