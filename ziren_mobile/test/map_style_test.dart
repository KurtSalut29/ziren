import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/shared/map/ziren_map_style.dart';

/// The map styles every Ziren map screen loads — see ziren_map_style.dart.
void main() {
  Map<String, dynamic> offline() => jsonDecode(buildOfflineStyle(4242)) as Map<String, dynamic>;
  Map<String, dynamic> hybrid() => jsonDecode(buildHybridStyle(4242)) as Map<String, dynamic>;
  List<String> ids(Map<String, dynamic> s) =>
      [for (final l in s['layers'] as List) (l as Map)['id'] as String];

  test('both styles read tiles and fonts from the local server only', () {
    for (final s in [offline(), hybrid()]) {
      expect(s['glyphs'], 'http://127.0.0.1:4242/fonts/{fontstack}/{range}.pbf');
      final biliran = (s['sources'] as Map)['biliran'] as Map;
      expect(biliran['tiles'], ['http://127.0.0.1:4242/tiles/{z}/{x}/{y}.pbf']);
    }
  });

  test('offline map has labels and no satellite dependency', () {
    final s = offline();
    expect((s['sources'] as Map).containsKey('satellite'), isFalse);
    expect(ids(s), containsAll(['place-town', 'place-small', 'road-name', 'poi-emergency', 'poi-civic', 'poi-other']));
  });

  test('hybrid map draws streets UNDER the photo and labels OVER it', () {
    final order = ids(hybrid());
    final photo = order.indexOf('satellite');
    expect(photo, greaterThan(order.indexOf('road-major')), reason: 'street map must sit under the photo');
    expect(photo, lessThan(order.indexOf('place-town')), reason: 'labels must sit over the photo');
    expect(order, contains('photo-road-major'));
  });

  test('every font a label asks for is bundled and registered', () {
    for (final s in [offline(), hybrid()]) {
      for (final l in s['layers'] as List) {
        final fonts = ((l as Map)['layout'] as Map?)?['text-font'] as List?;
        for (final f in fonts ?? const []) {
          final dir = kBundledFontDirs[f];
          expect(dir, isNotNull, reason: '$f is not bundled');
          for (final range in ['0-255', '256-511', '8192-8447']) {
            expect(File('assets/map/fonts/$dir/$range.pbf').existsSync(), isTrue, reason: '$dir/$range');
          }
        }
      }
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in kBundledFontDirs.values) {
      expect(pubspec, contains('assets/map/fonts/$dir/'), reason: 'asset dirs are not recursive');
    }
  });

  test('every landmark icon the style can ask for is in the bundled sprite', () {
    final s = offline();
    expect(s['sprite'], 'http://127.0.0.1:4242/sprite/sprite');
    final sprite = jsonDecode(File('assets/map/sprite/sprite.json').readAsStringSync()) as Map<String, dynamic>;
    final sprite2x = jsonDecode(File('assets/map/sprite/sprite@2x.json').readAsStringSync()) as Map<String, dynamic>;
    final layer = (s['layers'] as List).cast<Map>().firstWhere((l) => l['id'] == 'poi-emergency');
    final match = (layer['layout'] as Map)['icon-image'] as List;
    // ['match', input, label, output, label, output, ..., fallback]
    final outputs = <String>[
      for (var i = 3; i < match.length - 1; i += 2) match[i] as String,
      match.last as String,
    ];
    for (final icon in outputs) {
      expect(sprite.containsKey(icon), isTrue, reason: '$icon missing from sprite.json');
      expect(sprite2x.containsKey(icon), isTrue, reason: '$icon missing from sprite@2x.json');
    }
    expect(File('assets/map/sprite/sprite.png').existsSync(), isTrue);
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/map/sprite/'));
  });

  test('the pin shapes the app draws its own marks with are in the sprite, tintable', () {
    // map_screen (incidents), the responder detail map and navigation screen
    // name these directly; without them those pins draw nothing at all.
    // `sdf` is what lets their per-pin iconColor (severity colours) apply.
    for (final file in ['sprite.json', 'sprite@2x.json']) {
      final sprite = jsonDecode(File('assets/map/sprite/$file').readAsStringSync()) as Map<String, dynamic>;
      for (final icon in ['marker-15', 'circle-15']) {
        expect(sprite[icon], isA<Map>(), reason: '$icon missing from $file');
        expect((sprite[icon] as Map)['sdf'], isTrue, reason: '$icon in $file must be an SDF icon');
      }
    }
  });
}
