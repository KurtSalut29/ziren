import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/help/domain/help_content.dart';

void main() {
  for (final (who, topicsOf) in [
    ('resident', HelpContent.resident),
    ('responder', HelpContent.responder),
  ]) {
    test('$who help says the same thing in Filipino and English', () {
      final fil = topicsOf('fil');
      final en = topicsOf('en');
      expect(fil, isNotEmpty);
      expect(fil.length, en.length);
      for (var i = 0; i < fil.length; i++) {
        expect(fil[i].steps.length, en[i].steps.length, reason: '${en[i].title}: step count differs');
        expect(fil[i].icon, en[i].icon);
        expect(fil[i].route, en[i].route);
        expect(fil[i].tip == null, en[i].tip == null, reason: en[i].title);
        for (final step in [...fil[i].steps, ...en[i].steps]) {
          expect(step.trim(), isNotEmpty);
        }
      }
    });
  }

  test('any language but English falls back to Filipino', () {
    expect(HelpContent.resident('fil').first.title, HelpContent.resident('war').first.title);
  });

  test('every "Try it" route is a real route', () {
    final router = File('lib/core/routing/app_router.dart').readAsStringSync();
    final routes = {
      for (final t in [...HelpContent.resident('en'), ...HelpContent.responder('en')])
        if (t.route != null) t.route!,
    };
    expect(routes, isNotEmpty);
    for (final r in routes) {
      expect(router, contains("path: '$r'"), reason: r);
    }
  });

  test('the resident guide covers the three things stations asked for', () {
    final text = HelpContent.resident('en').map((t) => '${t.title} ${t.steps.join(' ')}').join(' ');
    expect(text, contains('Somewhere else'));
    expect(text, contains('Landmark (required)'));
    expect(text, contains('Call now'));
  });
}
