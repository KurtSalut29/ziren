import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/core/config/locale_provider.dart';
import 'package:ziren/features/incident_report/domain/incident_provider.dart';
import 'package:ziren/features/incident_report/presentation/incident_labels.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// The language picker was a dead control for the whole of this project's
/// life: it offered four languages, wrote the choice to the backend, and no
/// line of UI code ever read it back. These tests exist so that cannot
/// silently return — each one fails if a string stops responding to the
/// active locale.
void main() {
  /// Pumps a widget under a given locale and hands back its AppLocalizations.
  Future<AppLocalizations> l10nFor(WidgetTester tester, Locale locale) async {
    late AppLocalizations captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: LocaleProvider.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            captured = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  group('locale resolution', () {
    test('display names map to locales', () {
      expect(
        LocaleProvider.localeForLanguageName('English'),
        const Locale('en'),
      );
      expect(
        LocaleProvider.localeForLanguageName('Filipino'),
        const Locale('fil'),
      );
    });

    test('untranslated languages fall back to Filipino, not English', () {
      // A profile saved before the picker was narrowed can still hold these.
      // Falling through to English would be the worse of the two answers for
      // a Biliran resident.
      for (final name in ['Waray', 'Bisaya']) {
        expect(
          LocaleProvider.localeForLanguageName(name),
          const Locale('fil'),
          reason: '$name should fall back to Filipino',
        );
      }
    });

    test('an unknown value does not throw', () {
      expect(
        LocaleProvider.localeForLanguageName('Klingon'),
        const Locale('fil'),
      );
    });

    test('the picker only offers what the app can render', () {
      expect(
        LocaleProvider.supportedLanguageNames.length,
        LocaleProvider.supportedLocales.length,
        reason:
            'Every option in the Settings picker needs a locale behind it. '
            'This is the assertion the old four-language picker would have '
            'failed.',
      );
    });
  });

  group('resident-facing strings change with the locale', () {
    testWidgets('report acknowledgement', (tester) async {
      final en = await l10nFor(tester, const Locale('en'));
      expect(en.reportReceivedTitle, 'Report Received');
      expect(en.recordedAs, 'Recorded as');

      final fil = await l10nFor(tester, const Locale('fil'));
      expect(fil.reportReceivedTitle, 'Natanggap ang Ulat');
      expect(fil.recordedAs, 'Naitala bilang');
    });

    testWidgets('status labels', (tester) async {
      final en = await l10nFor(tester, const Locale('en'));
      final fil = await l10nFor(tester, const Locale('fil'));

      // The specific defect this replaces: My Reports showed a Tagalog
      // progress stepper ("Natanggap · Sinusuri") directly beneath an English
      // badge ("Received"), because the label lived on the data model.
      expect(IncidentLabels.status(en, 'received'), 'Received');
      expect(IncidentLabels.status(fil, 'received'), 'Natanggap');
      expect(IncidentLabels.status(fil, 'dispatched'), isNot('Dispatched'));
    });

    testWidgets('an unknown status degrades to the wire value', (tester) async {
      final fil = await l10nFor(tester, const Locale('fil'));
      // Better a resident sees the raw word than an empty badge if the backend
      // adds a state before the app knows about it. (`en_route` and `arrived`
      // used to be the example; they now have words of their own.)
      expect(IncidentLabels.status(fil, 'teleporting'), 'teleporting');
    });

    testWidgets('dialog copy that was once hard-coded English is translated', (
      tester,
    ) async {
      final en = await l10nFor(tester, const Locale('en'));
      final fil = await l10nFor(tester, const Locale('fil'));
      // Log out (profile), "continue where you left off?" (welcome) and the
      // responder's sign-out-with-a-call-in-hand warning.
      final pairs = <(String, String)>[
        (en.settingsLogOutConfirmTitle, fil.settingsLogOutConfirmTitle),
        (en.settingsLogOutConfirmBody, fil.settingsLogOutConfirmBody),
        (en.welcomeResumeTitle, fil.welcomeResumeTitle),
        (en.welcomeResumeBody, fil.welcomeResumeBody),
        (en.welcomeResumeContinue, fil.welcomeResumeContinue),
        (en.welcomeResumeStartOver, fil.welcomeResumeStartOver),
        (en.respActiveAssignmentTitle, fil.respActiveAssignmentTitle),
        (en.respActiveAssignmentBody, fil.respActiveAssignmentBody),
        (en.respStaySignedIn, fil.respStaySignedIn),
      ];
      for (final (e, f) in pairs) {
        expect(f.trim(), isNotEmpty);
        expect(f, isNot(e), reason: '"$e" was left in English');
      }
    });

    testWidgets('category names', (tester) async {
      final en = await l10nFor(tester, const Locale('en'));
      final fil = await l10nFor(tester, const Locale('fil'));

      expect(IncidentLabels.category(en, IncidentCategory.fire), 'Fire');
      expect(IncidentLabels.category(fil, IncidentCategory.fire), 'Sunog');
      expect(
        IncidentLabels.category(en, IncidentCategory.vehicular),
        'Road Accident',
      );
    });

    testWidgets('every category resolves — no enum name leaks to a resident', (
      tester,
    ) async {
      final fil = await l10nFor(tester, const Locale('fil'));
      for (final c in IncidentCategory.values) {
        final label = IncidentLabels.category(fil, c);
        expect(label, isNotEmpty);
        expect(
          label,
          isNot(contains('IncidentCategory')),
          reason: 'Raw enum name reached the UI for $c',
        );
      }
    });

    testWidgets('categoryFromValue handles the retired categories', (
      tester,
    ) async {
      final fil = await l10nFor(tester, const Locale('fil'));
      expect(IncidentLabels.categoryFromValue(fil, 'fire'), 'Sunog');
      // hazmat and missing_person were merged out in taxonomy v2.0. A legacy
      // row must return null so the caller omits the line, rather than
      // printing something meaningless.
      expect(IncidentLabels.categoryFromValue(fil, 'hazmat'), isNull);
      expect(IncidentLabels.categoryFromValue(fil, null), isNull);
    });

    testWidgets('English pluralises', (tester) async {
      final en = await l10nFor(tester, const Locale('en'));
      expect(en.mediaAttached(1), '1 photo or video');
      expect(en.mediaAttached(3), '3 photos or videos');
    });

    testWidgets('Filipino reports the real count at every value', (
      tester,
    ) async {
      // Regression guard. This string used to be an ICU plural with an
      // `=1{...}` case. The generator compiles `=1` into CLDR's `one`
      // category, and Filipino's `one` includes 2 and 3 — so three attached
      // photos rendered as "1 larawan o video". On a screen whose only job is
      // to confirm what was recorded, under-reporting the attachments is the
      // worst way for it to be wrong.
      final fil = await l10nFor(tester, const Locale('fil'));
      for (final n in [1, 2, 3, 5, 11, 21]) {
        expect(
          fil.mediaAttached(n),
          '$n larawan o video',
          reason: 'count=$n must render as itself',
        );
      }
    });
  });
}
