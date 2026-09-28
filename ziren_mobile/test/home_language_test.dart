import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/l10n/app_localizations.dart';
import 'package:Ziren/l10n/app_localizations_en.dart';
import 'package:Ziren/shared/theme/app_tokens.dart';
import 'package:Ziren/shared/widgets/home_kit.dart';

/// Guards against mixed-language output on Home.
///
/// The bug this exists for was not a missing translation — it was a screen
/// that had been half-converted. `resident_home_screen.dart` read 34 strings
/// out of AppLocalizations and then hardcoded eight more beside them, so an
/// English build rendered "Routing: Awtomatiko" and a Filipino build rendered
/// an English legal warning under a translated heading. Both locales looked
/// finished in isolation; only switching languages showed it.
///
/// Asserting on rendered text rather than on the .arb files is the point: a
/// key can exist and still not be the one the widget uses.
Widget _strip(Locale locale, {required bool offline}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final t = AppLocalizations.of(context);
        return Scaffold(
          backgroundColor: kHomeCanvas,
          body: SafeArea(
            child: HeroActionCard(
              title: 'SOS',
              subtitle: t.homeEmergency,
              caption: t.homeSosHint,
              onTap: () {},
              facts: [
                HeroFact(
                  icon: Icons.location_on_rounded,
                  label: t.homeLocation,
                  value: t.homeBarangay('Caraycaray'),
                  color: ZirenTokens.textSecondary,
                ),
                HeroFact(
                  icon: Icons.shield_rounded,
                  label: t.homeRouting,
                  value: offline ? t.homeDeliveryOfflineTitle : t.homeRoutingAuto,
                  color: offline
                      ? ZirenTokens.connectivityOffline
                      : ZirenTokens.connectivityOnline,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  testWidgets('the hero strip speaks one language at a time', (tester) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_strip(const Locale('fil'), offline: false));
    await tester.pumpAndSettle();
    expect(find.text('Awtomatiko'), findsOneWidget);
    expect(find.text('Brgy. Caraycaray'), findsOneWidget);
    expect(find.text('Hindi tiyak? Pindutin ito'), findsOneWidget);
    expect(find.text('Automatic'), findsNothing);

    // Before the fix, "Awtomatiko" rendered here under an English "Routing".
    await tester.pumpWidget(_strip(const Locale('en'), offline: false));
    await tester.pumpAndSettle();
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Not sure? Press this'), findsOneWidget);
    expect(find.text('Awtomatiko'), findsNothing);
    expect(find.text('Hindi tiyak? Pindutin ito'), findsNothing);

    await tester.pumpWidget(_strip(const Locale('en'), offline: true));
    await tester.pumpAndSettle();
    expect(find.text('No internet'), findsOneWidget);
    expect(find.text('Walang internet'), findsNothing);
  });

  test('the English catalogue carries no Tagalog copy', () {
    final en = AppLocalizationsEn();
    const leaked = [
      'Awtomatiko',
      'Walang internet',
      'Hindi pa alam',
      'Hindi tiyak? Pindutin ito',
      'Ipadala ang ulat',
      'may naipit sa loob',
      'Naipadala ang ulat',
      'Malabo ang GPS',
    ];
    final values = <String>[
      en.homeRoutingAuto,
      en.homeDeliveryOfflineTitle,
      en.homeLocationUnknown,
      en.homeSosHint,
      en.homeMapAction,
      en.homeResidentFallbackName,
      en.quickSendReport,
      en.quickNoteHint,
      en.quickSendWarning,
      en.quickSentTo('Naval BFP'),
      en.quickGpsVague(40),
      en.sosSendNow,
      en.sosTruthConfirm,
      en.sosLegalBody,
      en.sosCooldownWarning(3),
    ];
    for (final v in values) {
      for (final bad in leaked) {
        expect(
          v.contains(bad),
          isFalse,
          reason: '"$v" still carries Tagalog copy "$bad"',
        );
      }
    }
  });
}
