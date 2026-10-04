import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/core/geo/geodesic.dart';

/// Evaluator finding #24: the responder app's distance and ETA are held to the
/// same reference cases as the backend and the dashboard
/// (shared/geo_reference_cases.json at the repository root).
void main() {
  final cases = jsonDecode(File('../shared/geo_reference_cases.json').readAsStringSync())
      as Map<String, dynamic>;
  final tolerance = (cases['distance_tolerance_m'] as num).toDouble();

  test('the assumed speed is the shared one', () {
    expect(Geodesic.assumedSpeedKmh, (cases['assumed_speed_kmh'] as num).toDouble());
  });

  for (final c in (cases['distances'] as List).cast<Map<String, dynamic>>()) {
    test('distance: ${c['name']}', () {
      final from = (c['from'] as List).cast<num>();
      final to = (c['to'] as List).cast<num>();
      final m = Geodesic.metres(from[0].toDouble(), from[1].toDouble(), to[0].toDouble(), to[1].toDouble());
      expect(m, closeTo((c['metres'] as num).toDouble(), tolerance));
    });
  }

  for (final c in (cases['eta'] as List).cast<Map<String, dynamic>>()) {
    test('eta: ${c['km']} km', () {
      expect(Geodesic.etaMinutes((c['km'] as num).toDouble()), c['minutes']);
    });
  }
}
