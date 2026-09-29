import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/hotlines/domain/station_hotlines.dart';
import 'package:ziren/features/incident_report/domain/incident_provider.dart';

/// agencies.contact_number per agency id, as migration 042 writes it.
Map<String, String> _migrationNumbers() {
  final sql = File(
    '../ziren_backend/supabase/migrations/042_station_hotlines_and_reporter_location.sql',
  ).readAsStringSync();
  final out = <String, String>{};
  final row = RegExp(r"WHEN '([0-9a-f-]{36})' THEN '([^']*)'");
  for (final m in row.allMatches(sql)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

void main() {
  group('parse', () {
    test('reads labelled numbers separated by semicolons', () {
      final n = StationHotlines.parse('Globe: 0955-723-6300; Smart: 0948-024-3466; Landline: (053) 500-9546');
      expect(n.map((e) => e.display), ['0955-723-6300', '0948-024-3466', '(053) 500-9546']);
      expect(n.map((e) => e.label), ['Globe', 'Smart', 'Landline']);
      expect(n.last.dial, '0535009546');
    });

    test('splits on a slash between two numbers, never inside a label', () {
      final a = StationHotlines.parse('09125878288/09173206105');
      expect(a.map((e) => e.dial), ['09125878288', '09173206105']);
      final b = StationHotlines.parse('MDRRMO/EMS: 0969-189-2388');
      expect(b, hasLength(1));
      expect(b.single.label, 'MDRRMO/EMS');
      expect(b.single.dial, '09691892388');
    });

    test('drops anything that is not a dialable number', () {
      expect(StationHotlines.parse(null), isEmpty);
      expect(StationHotlines.parse('N/A'), isEmpty);
      expect(StationHotlines.parse('  ;  ; 123 '), isEmpty);
    });

    test('ignores a duplicate number', () {
      expect(StationHotlines.parse('0905-480-1417; 0905 480 1417'), hasLength(1));
    });

    test('tel uri dials digits only', () {
      expect(const HotlineNumber('0921-555-3961').telUri.toString(), 'tel:09215553961');
      expect(const HotlineNumber('+63 921 555 3961').dial, '+639215553961');
    });
  });

  group('bundled directory', () {
    test('covers the 21 stations, BFP / PNP / MDRRMO in each of 7 towns', () {
      final agencies = StationHotlines.bundled.where((h) => h.agencyId != null).toList();
      expect(agencies, hasLength(21));
      expect(agencies.map((h) => h.agencyId).toSet(), hasLength(21));
      for (final town in StationHotlines.townCentres.keys) {
        final types = agencies.where((h) => h.municipality == town).map((h) => h.agencyType).toSet();
        expect(types, {'BFP', 'PNP', 'MDRRMO'}, reason: town);
      }
      for (final h in StationHotlines.bundled) {
        expect(h.numbers, isNotEmpty, reason: h.name);
        for (final n in h.numbers) {
          expect(n.dial.length, anyOf(10, 11), reason: '${h.name} ${n.display}');
        }
      }
    });

    test('is exactly what migration 042 writes to the database', () {
      final db = _migrationNumbers();
      expect(db, hasLength(21));
      for (final h in StationHotlines.bundled.where((h) => h.agencyId != null)) {
        final fromDb = StationHotlines.parse(db[h.agencyId]);
        expect(
          fromDb.map((n) => n.dial).toList(),
          h.numbers.map((n) => n.dial).toList(),
          reason: '${h.name}: app and migration 042 disagree',
        );
      }
    });

    test('a database number replaces the bundled one; an unusable one does not', () {
      const naval = 'a0000001-0000-0000-0000-000000000003';
      final changed = StationHotlines.directory(live: {naval: '0917-000-0000'});
      expect(changed.firstWhere((h) => h.agencyId == naval).numbers.single.dial, '09170000000');
      final junk = StationHotlines.directory(live: {naval: 'none'});
      expect(junk.firstWhere((h) => h.agencyId == naval).numbers.single.dial, '09054801417');
    });
  });

  group('by category', () {
    final all = StationHotlines.bundled;

    test('fire lists BFP only, crime PNP only', () {
      expect(StationHotlines.forCategory(all, IncidentCategory.fire).map((h) => h.agencyType).toSet(), {'BFP'});
      expect(
        StationHotlines.forCategory(all, IncidentCategory.domesticDisputeCrime).map((h) => h.agencyType).toSet(),
        {'PNP'},
      );
    });

    test('medical adds the Rural Health Units; other lists everyone', () {
      expect(
        StationHotlines.forCategory(all, IncidentCategory.medicalTrauma).map((h) => h.agencyType).toSet(),
        {'MDRRMO', 'RHU'},
      );
      expect(StationHotlines.forCategory(all, IncidentCategory.other), hasLength(all.length));
    });

    test('nearest town first', () {
      // Just outside Kawayan's poblacion.
      final list = StationHotlines.forCategory(all, IncidentCategory.fire, lat: 11.675, lng: 124.36);
      expect(list.first.municipality, 'Kawayan');
      // Caibiran side of the island.
      final east = StationHotlines.forCategory(all, IncidentCategory.fire, lat: 11.57, lng: 124.58);
      expect(east.first.municipality, 'Caibiran');
    });

    test('alphabetical towns when the position is unknown', () {
      expect(StationHotlines.nearestTowns().first, 'Almeria');
    });
  });
}
