import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ziren/core/config/locale_provider.dart';
import 'package:ziren/features/onboarding/presentation/consent_screen.dart';
import 'package:ziren/features/onboarding/domain/legal_documents.dart';
import 'package:ziren/features/onboarding/presentation/language_screen.dart';
import 'package:ziren/features/onboarding/presentation/legal_reader_screen.dart';
import 'package:ziren/features/onboarding/presentation/welcome_screen.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// The three first-run screens (language → privacy → get started), redesigned
/// 2026-09-30, and the bug a tester found on the first one: tapping English
/// left the screen in Filipino, so the choice looked broken.
///
/// Refresh the pictures with:
///   flutter test --update-goldens test/onboarding_design_test.dart

/// The app wires its locale the same way: MaterialApp.locale follows
/// LocaleProvider, so a tap that changes the provider re-renders every string.
Widget _app(LocaleProvider locale, Widget home) =>
    ChangeNotifierProvider<LocaleProvider>.value(
      value: locale,
      child: Consumer<LocaleProvider>(
        builder:
            (_, l, __) => MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: l.locale,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            ),
      ),
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
    await _loadRealFonts();
  });

  void phone(WidgetTester tester, {double height = 2400}) {
    tester.view.physicalSize = Size(1100, height);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  group('Language', () {
    testWidgets('tapping English turns the screen into English at once', (
      tester,
    ) async {
      phone(tester);
      final locale = LocaleProvider();
      await tester.pumpWidget(_app(locale, const LanguageScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      // Filipino by default.
      expect(find.text('Piliin ang inyong wika'), findsOneWidget);
      expect(find.text('Magpatuloy'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lang-en')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(locale.locale.languageCode, 'en');
      expect(find.text('Choose your language'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(
        find.text('Hi, I\'m Ziren! Which language would you like me to use?'),
        findsOneWidget,
      );
      // The other language's heading stays, small, for the other reader.
      expect(find.text('Piliin ang inyong wika'), findsOneWidget);

      // And back.
      await tester.tap(find.byKey(const Key('lang-fil')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(locale.locale.languageCode, 'fil');
      expect(find.text('Magpatuloy'), findsOneWidget);
    });

    for (final english in [false, true]) {
      testWidgets('golden ${english ? 'en' : 'fil'}', (tester) async {
        phone(tester);
        final locale = LocaleProvider();
        if (english) await locale.setLanguageName('English');
        await tester.pumpWidget(_app(locale, const LanguageScreen()));
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(
          find.byType(LanguageScreen),
          matchesGoldenFile(
            'goldens/onboarding_language_${english ? 'en' : 'fil'}.png',
          ),
        );
      });
    }
  });

  group('Consent', () {
    testWidgets('continue waits for both agreements', (tester) async {
      phone(tester, height: 3000);
      final locale = LocaleProvider();
      await locale.setLanguageName('English');
      await tester.pumpWidget(_app(locale, const ConsentScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Open to read'), findsNWidgets(2));
      expect(find.text('0 of 2 agreed'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('consent-continue')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('golden', (tester) async {
      phone(tester, height: 3000);
      final locale = LocaleProvider();
      await tester.pumpWidget(_app(locale, const ConsentScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(ConsentScreen),
        matchesGoldenFile('goldens/onboarding_consent.png'),
      );
    });
  });

  group('Legal reader', () {
    test('every bundled document splits into header, sections and note', () {
      for (final name in [
        'privacy_en',
        'privacy_fil',
        'terms_en',
        'terms_fil',
      ]) {
        final doc = LegalDocumentView.parse(
          File('assets/legal/$name.md').readAsStringSync(),
        );
        expect(doc.title, isNotNull, reason: name);
        expect(doc.version, isNotNull, reason: name);
        expect(doc.sections.length, greaterThanOrEqualTo(10), reason: name);
        // Numbered 1..N in order, so the badges read 1, 2, 3 ...
        for (var i = 0; i < doc.sections.length; i++) {
          expect(doc.sections[i].number, '${i + 1}', reason: name);
          expect(doc.sections[i].body, isNotEmpty, reason: name);
        }
        expect(doc.footer, isNotEmpty, reason: name);
      }
    });

    testWidgets('accept stays off until the end, then says so', (
      tester,
    ) async {
      phone(tester, height: 2400);
      final locale = LocaleProvider();
      await locale.setLanguageName('English');
      await tester.pumpWidget(
        _app(
          locale,
          const LegalReaderScreen(
            doc: LegalDoc.privacy,
            languageCode: 'en',
            title: 'Data Privacy Notice',
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      ElevatedButton accept() => tester.widget<ElevatedButton>(
        find.byKey(const Key('legal-accept')),
      );
      expect(accept().onPressed, isNull);
      expect(find.textContaining('0% read'), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -20000),
      );
      await tester.pumpAndSettle();
      expect(accept().onPressed, isNotNull);
      expect(find.text('You\'ve reached the end'), findsOneWidget);
    });

    testWidgets('golden', (tester) async {
      phone(tester, height: 2400);
      final locale = LocaleProvider();
      await tester.pumpWidget(
        _app(
          locale,
          const LegalReaderScreen(
            doc: LegalDoc.privacy,
            languageCode: 'fil',
            title: 'Paunawa sa Pagkapribado ng Datos',
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(LegalReaderScreen),
        matchesGoldenFile('goldens/onboarding_legal_reader.png'),
      );
    });
  });

  testWidgets('Welcome golden', (tester) async {
    phone(tester);
    final locale = LocaleProvider();
    await tester.pumpWidget(_app(locale, const WelcomeScreen()));
    // Asset images decode off the test's fake clock; without this the logo
    // tile is drawn empty.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/mascot_help.png'),
        tester.element(find.byType(WelcomeScreen)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('welcome-create')), findsOneWidget);
    expect(find.byKey(const Key('welcome-sign-in')), findsOneWidget);
    await expectLater(
      find.byType(WelcomeScreen),
      matchesGoldenFile('goldens/onboarding_welcome.png'),
    );
  });
}

Future<void> _loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null) '$flutterRoot/bin/cache/artifacts/material_fonts',
    'C:/src/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final dir in candidates) {
    final regular = File('$dir/roboto-regular.ttf');
    final bold = File('$dir/roboto-bold.ttf');
    if (!regular.existsSync()) continue;
    final loader = FontLoader('Roboto');
    loader.addFont(regular.readAsBytes().then((b) => ByteData.view(b.buffer)));
    if (bold.existsSync()) {
      loader.addFont(bold.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
    break;
  }

  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['LOCALAPPDATA']}/Pub/Cache';
  final hosted = Directory('$pubCache/hosted/pub.dev');
  if (!hosted.existsSync()) return;
  final lucide =
      hosted
          .listSync()
          .whereType<Directory>()
          .where(
            (d) => d.path
                .split(RegExp(r'[\\/]'))
                .last
                .startsWith('flutter_lucide-'),
          )
          .map((d) => File('${d.path}/lib/fonts/lucide.ttf'))
          .where((f) => f.existsSync())
          .toList();
  if (lucide.isEmpty) return;
  final iconLoader = FontLoader('packages/flutter_lucide/lucide');
  iconLoader.addFont(
    lucide.last.readAsBytes().then((b) => ByteData.view(b.buffer)),
  );
  await iconLoader.load();
}
