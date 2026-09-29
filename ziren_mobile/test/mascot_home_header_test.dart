import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:ziren/features/help/presentation/help_sheet.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/widgets/mascot_home_header.dart';

Widget _app(Widget child, {String lang = 'en'}) => MaterialApp(
  locale: Locale(lang),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

MascotHomeHeader _header({String message = 'Hello there'}) => MascotHomeHeader(
  tagline: 'Emergency response for Biliran.',
  hasUnread: true,
  onBellTap: () {},
  bellLabel: 'Notifications',
  bellLabelUnread: 'Notifications, unread',
  displayName: 'Kurt Salut',
  onProfileTap: () {},
  profileLabel: 'Open your profile',
  greeting: 'Good morning, Kurt!',
  greetingName: 'Kurt',
  mascot: MascotArt.resident,
  mascotName: 'Ziren',
  message: message,
  locationLabel: 'Caraycaray, Naval',
  connectivityLabel: 'Connected',
  connectivityIcon: LucideIcons.radio_tower,
  connectivityColor: Colors.green,
);

void main() {
  testWidgets('header shows the greeting with the name in the brand colour', (tester) async {
    await tester.pumpWidget(_app(SingleChildScrollView(child: _header())));
    await tester.pump();

    final rich = tester.widget<Text>(find.byWidgetPredicate(
      (w) => w is Text && w.textSpan?.toPlainText() == 'Good morning, Kurt!',
    ));
    final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.text), ['Good morning, ', 'Kurt', '!']);
    expect(spans[1].style?.color, const Color(0xFFFC5A05));

    expect(find.text('Hello there'), findsOneWidget);
    expect(find.text('Caraycaray, Naval'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('KS'), findsOneWidget); // initials on the profile button
    expect(find.bySemanticsLabel('Notifications, unread'), findsOneWidget);
  });

  testWidgets('the help button opens "How to use Ziren" as a modal', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(Builder(
      builder: (context) => Stack(
        children: [
          Positioned(
            right: 16,
            bottom: 16,
            child: ZirenHelpButton(
              label: 'Ask Ziren for help',
              onPressed: () => showHelpSheet(context),
            ),
          ),
        ],
      ),
    )));
    // The label loops forever, so pump real time instead of pumpAndSettle.
    // One second in, it has popped out of the head and can be tapped.
    await tester.pump(const Duration(seconds: 1));
    // The label is part of the button: tapping the words opens the guide too.
    await tester.tap(find.text('Ask Ziren for help'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('How to use Ziren'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BottomSheet), findsNothing);
  });

  group('loops every 5 seconds', () {
    String typed(WidgetTester tester) {
      final text = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.textSpan?.toPlainText().startsWith('H') ?? false) &&
            w.textSpan!.toPlainText() != 'Hello there',
      ));
      // Drop the cursor, which is always laid out (only its colour blinks).
      final plain = text.textSpan!.toPlainText();
      return plain.substring(0, plain.length - 1);
    }

    double labelOpacity(WidgetTester tester) => tester
        .widget<Opacity>(find.ancestor(of: find.text('Ask Ziren for help'), matching: find.byType(Opacity)))
        .opacity;

    testWidgets('"Hi! I\'m Ziren" is typed out, held, erased, and typed again', (tester) async {
      await tester.pumpWidget(_app(SingleChildScrollView(child: MascotHomeHeader(
        tagline: '', hasUnread: false, onBellTap: () {}, bellLabel: 'b',
        bellLabelUnread: 'b', displayName: 'Kurt', onProfileTap: () {}, profileLabel: 'p',
        greeting: 'Good morning, Kurt!', greetingName: 'Kurt',
        mascot: MascotArt.resident, mascotName: "Hi! I'm Ziren",
        message: 'Hello there', locationLabel: 'x', connectivityLabel: 'y',
        connectivityIcon: LucideIcons.radio_tower, connectivityColor: Colors.green,
      ))));

      await tester.pump(const Duration(milliseconds: 500)); // typing
      final partial = typed(tester);
      expect(partial.length, inExclusiveRange(1, "Hi! I'm Ziren".length));
      expect("Hi! I'm Ziren".startsWith(partial), isTrue);

      await tester.pump(const Duration(seconds: 2)); // 2.5 s: held in full
      expect(typed(tester), "Hi! I'm Ziren");

      await tester.pump(const Duration(milliseconds: 2400)); // 4.9 s: nearly erased
      expect(typed(tester).length, lessThan(3));

      await tester.pump(const Duration(seconds: 3)); // 7.9 s: the next loop, written again
      expect(typed(tester), "Hi! I'm Ziren");
      // The screen reader hears the whole line, never a half-typed one.
      expect(find.bySemanticsLabel("Hi! I'm Ziren"), findsOneWidget);
    });

    testWidgets('"Ask Ziren for help" pops out, pops back in, and repeats', (tester) async {
      await tester.pumpWidget(_app(Stack(children: [
        Positioned(right: 16, bottom: 16, child: ZirenHelpButton(label: 'Ask Ziren for help', onPressed: () {})),
      ])));

      expect(labelOpacity(tester), 0); // starts inside the head
      await tester.pump(const Duration(seconds: 1));
      expect(labelOpacity(tester), 1); // popped out
      await tester.pump(const Duration(milliseconds: 3600)); // 4.6 s: popped back in
      expect(labelOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 600)); // 5.2 s: growing again, not yet full
      expect(labelOpacity(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 800)); // 6.0 s: out again
      expect(labelOpacity(tester), 1);
    });

    testWidgets('with "Remove animations" on, both simply stand still', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(_app(Stack(children: [
        Positioned(right: 16, bottom: 16, child: ZirenHelpButton(label: 'Ask Ziren for help', onPressed: () {})),
      ])));
      await tester.pump();
      expect(labelOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 4, milliseconds: 600));
      expect(labelOpacity(tester), 1);
    });
  });

  testWidgets('the mascot waves at the start of every loop, then holds still', (tester) async {
    await tester.pumpWidget(_app(SingleChildScrollView(child: _header())));

    double handAngle() {
      final rotate = tester.widget<Transform>(find.ancestor(
        of: find.image(const AssetImage('assets/images/mascot_resident_hand.png')),
        matching: find.byType(Transform),
      ).first);
      // Rotation about z: atan2 of the matrix's first column.
      return math.atan2(rotate.transform.entry(1, 0), rotate.transform.entry(0, 0));
    }

    final seen = <double>[];
    for (var ms = 100; ms <= 1900; ms += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      seen.add(handAngle());
    }
    // Swings both ways, never past 16°.
    expect(seen.any((a) => a > 0.05), isTrue);
    expect(seen.any((a) => a < -0.05), isTrue);
    expect(seen.every((a) => a.abs() <= 16 * math.pi / 180 + 1e-9), isTrue);

    await tester.pump(const Duration(seconds: 1)); // 2.9 s: resting
    expect(handAngle(), 0);
    await tester.pump(const Duration(milliseconds: 2600)); // 5.5 s: waving again
    expect(handAngle().abs(), greaterThan(0.01));
  });

  test('each mascot is split into a body and a hand layer of the same size', () {
    (int, int) size(String path) {
      final b = File(path).readAsBytesSync();
      int u32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      return (u32(16), u32(20)); // IHDR width, height
    }

    for (final art in [MascotArt.resident, MascotArt.responder]) {
      expect(size(art.body), (art.size.width.toInt(), art.size.height.toInt()), reason: art.body);
      expect(size(art.hand), size(art.body), reason: art.hand);
    }
  });

  test('the mascot images are bundled with transparent backgrounds', () {
    for (final name in [
      'mascot_resident', 'mascot_responder', 'mascot_help',
      'mascot_resident_body', 'mascot_resident_hand',
      'mascot_responder_body', 'mascot_responder_hand',
    ]) {
      final bytes = File('assets/images/$name.png').readAsBytesSync();
      // PNG colour type 6 = RGBA: the white studio backdrop was cut out.
      expect(bytes[25], 6, reason: name);
    }
  });
}
