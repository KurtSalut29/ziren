import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/core/utils/validators.dart';
import 'package:ziren/features/registration/presentation/password_requirements.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Testers were not told what a password needed until Continue refused it. The
/// requirements are now a panel that is always on screen and ticks each rule
/// off as it is met - and it has to agree, exactly, with what the form accepts.
void main() {
  Future<TextEditingController> pump(WidgetTester tester, Locale locale) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PasswordRequirements(controller: controller)),
      ),
    );
    return controller;
  }

  int ticks() => find.byIcon(LucideIcons.circle_check).evaluate().length;

  testWidgets('always tells the person what is needed, in English', (
    tester,
  ) async {
    await pump(tester, const Locale('en'));
    expect(find.text('Your password must have:'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('1 uppercase letter (A-Z)'), findsOneWidget);
    expect(find.text('1 number (0-9)'), findsOneWidget);
    expect(ticks(), 0, reason: 'nothing typed yet, nothing met');
  });

  testWidgets('and in Filipino', (tester) async {
    await pump(tester, const Locale('fil'));
    expect(find.text('Ang password ay dapat may:'), findsOneWidget);
    expect(find.text('Hindi bababa sa 8 character'), findsOneWidget);
    expect(find.text('1 malaking titik (A-Z)'), findsOneWidget);
    expect(find.text('1 numero (0-9)'), findsOneWidget);
  });

  testWidgets('each rule ticks as it is met', (tester) async {
    final c = await pump(tester, const Locale('en'));

    c.text = 'abc';
    await tester.pump();
    expect(ticks(), 0);

    c.text = 'abcdefgh'; // long enough
    await tester.pump();
    expect(ticks(), 1);

    c.text = 'Abcdefgh'; // + an uppercase letter
    await tester.pump();
    expect(ticks(), 2);

    c.text = 'Abcdefg1'; // + a number
    await tester.pump();
    expect(ticks(), 3);

    c.text = 'A1'; // short, but has the other two
    await tester.pump();
    expect(ticks(), 2);
  });

  test('the panel and the form agree on every password', () {
    const samples = [
      '',
      'abc',
      'abcdefgh',
      'ABCDEFGH',
      '12345678',
      'Abcdefgh',
      'abcdefg1',
      'ABCDEFG1',
      'Abcdefg1',
      'Abc1',
      'A1bcdefghijk',
    ];
    for (final s in samples) {
      final allMet =
          Validators.passwordHasMinLength(s) &&
          Validators.passwordHasUppercase(s) &&
          Validators.passwordHasNumber(s);
      expect(
        Validators.password(s) == null,
        allMet,
        reason: '"$s": every tick on <=> the form accepts it',
      );
    }
  });
}
