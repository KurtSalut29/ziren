import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:ziren/features/help/presentation/help_sheet.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/widgets/mascot_home_header.dart';
import 'package:ziren/shared/widgets/ziren_mascot.dart';

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
        mascotName: "Hi! I'm Ziren",
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

  group('Ziren on Home (wave / no-internet clips)', () {
    String shownClip(WidgetTester tester) => tester
        .widgetList<Image>(find.descendant(of: find.byType(ZirenMascotClip), matching: find.byType(Image)))
        .map((i) => (i.image as AssetImage).assetName)
        .single;

    testWidgets('plays the clip for its mood', (tester) async {
      for (final mood in ZirenMascotMood.values) {
        await tester.pumpWidget(MaterialApp(home: ZirenMascotClip(key: ValueKey(mood), mood: mood)));
        expect(shownClip(tester), 'assets/images/mascot/${mood.name}.webp');
      }
    });

    testWidgets('a clip fading in holds its first frame, then plays from it', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: ZirenMascotClip(mood: ZirenMascotMood.offline, startDelay: Duration(milliseconds: 520)),
      ));
      expect(shownClip(tester), 'assets/images/mascot/offline_still.webp');
      await tester.pump(const Duration(milliseconds: 500));
      expect(shownClip(tester), 'assets/images/mascot/offline_still.webp');
      await tester.pump(const Duration(milliseconds: 40));
      expect(shownClip(tester), 'assets/images/mascot/offline.webp');
    });

    testWidgets('with "Remove animations" on, Ziren stands still on a single frame', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(const MaterialApp(home: ZirenMascotClip(mood: ZirenMascotMood.offline)));
      expect(shownClip(tester), 'assets/images/mascot/offline_still.webp');
    });

    testWidgets('losing the internet swaps the wave for the no-internet clip with a fade-through, and back',
        (tester) async {
      var offline = false;
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          set = setState;
          return Center(child: SizedBox(width: 136, height: 158, child: ZirenMascot(offline: offline)));
        }),
      ));
      // Both clips have their first frame decoded before Ziren appears.
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<ZirenMascotClip>(find.byType(ZirenMascotClip)).mood, ZirenMascotMood.wave);

      set(() => offline = true);
      await tester.pump();
      // A fade-through: never both showing at once (two figures drawn over
      // each other showed two pins).
      double opacityOf(ZirenMascotMood mood) => tester
          .widget<FadeTransition>(find.ancestor(
            of: find.byWidgetPredicate((w) => w is ZirenMascotClip && w.mood == mood),
            matching: find.byType(FadeTransition),
          ).first)
          .opacity
          .value;
      for (var ms = 0; ms <= 520; ms += 40) {
        final clips = tester.widgetList<ZirenMascotClip>(find.byType(ZirenMascotClip)).map((w) => w.mood).toList();
        if (clips.length == 2) {
          final both = opacityOf(ZirenMascotMood.wave) > 0 && opacityOf(ZirenMascotMood.offline) > 0;
          expect(both, isFalse, reason: 'at $ms ms both clips were showing');
        }
        if (ms == 120) expect(clips.length, 2, reason: 'the wave is still fading out');
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<ZirenMascotClip>(find.byType(ZirenMascotClip)).mood, ZirenMascotMood.offline);

      set(() => offline = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<ZirenMascotClip>(find.byType(ZirenMascotClip)).mood, ZirenMascotMood.wave);
    });
  });

  test('both clips are looping animated WebP with transparency, on one canvas', () {
    (int, int) canvasOf(String path) {
      final b = File(path).readAsBytesSync();
      return switch (String.fromCharCodes(b.sublist(12, 16))) {
              'VP8X' => ((b[24] | b[25] << 8 | b[26] << 16) + 1, (b[27] | b[28] << 8 | b[29] << 16) + 1),
              // Lossless still: 14-bit width-1, 14-bit height-1 after the 0x2f signature.
              'VP8L' => (
                  ((b[21] | b[22] << 8) & 0x3fff) + 1,
                  (((b[22] >> 6) | b[23] << 2 | b[24] << 10) & 0x3fff) + 1,
                ),
              final kind => throw StateError('$path: $kind'),
            };
    }

    for (final mood in ZirenMascotMood.values) {
      final clip = File(mood.clip).readAsBytesSync();
      expect(String.fromCharCodes(clip.sublist(8, 16)), 'WEBPVP8X', reason: mood.clip);
      expect(clip[20] & 0x10, 0x10, reason: '${mood.clip} has an alpha channel');
      expect(clip[20] & 0x02, 0x02, reason: '${mood.clip} is animated');
      // ANIM chunk: loop count 0 = forever.
      final anim = String.fromCharCodes(clip).indexOf('ANIM');
      expect(clip[anim + 12] | clip[anim + 13] << 8, 0, reason: '${mood.clip} loops forever');

      final still = File(mood.still).readAsBytesSync();
      expect(String.fromCharCodes(still.sublist(8, 16)), 'WEBPVP8L', reason: '${mood.still} is one lossless frame');
      expect(still[24] & 0x10, 0x10, reason: '${mood.still} has transparency');

      final size = (ZirenMascot.canvas.width.toInt(), ZirenMascot.canvas.height.toInt());
      expect(canvasOf(mood.clip), size, reason: mood.clip);
      expect(canvasOf(mood.still), size, reason: mood.still);
    }
  });

  test('the help head is bundled with a transparent background', () {
    final bytes = File('assets/images/mascot_help.png').readAsBytesSync();
    // PNG colour type 6 = RGBA: the white studio backdrop was cut out.
    expect(bytes[25], 6);
  });
}
