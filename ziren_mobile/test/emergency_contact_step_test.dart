import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:Ziren/features/registration/domain/registration_draft.dart';
import 'package:Ziren/features/registration/presentation/step_contact_screen.dart';
import 'package:Ziren/l10n/app_localizations.dart';

/// The emergency-contact block on registration step 4.
///
/// Testers could not tell whether it asked for THEIR contact details or for
/// someone else's, so it now says outright that it is ONE other person, and it
/// refuses the commonest mix-up: typing the account's own number.
void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const StepContactScreen()),
        GoRoute(path: '/register/role', builder: (_, _) => const SizedBox()),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RegistrationDraft(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // email, mobile, password, confirm, then the emergency name and number.
  Finder field(int i) => find.byType(TextFormField).at(i);

  Future<void> fill(
    WidgetTester tester, {
    String phone = '09171234567',
    String ecName = '',
    String ecNumber = '',
  }) async {
    await tester.enterText(field(0), 'me@example.com');
    await tester.enterText(field(1), phone);
    await tester.enterText(field(2), 'Passw0rdX');
    await tester.enterText(field(3), 'Passw0rdX');
    await tester.enterText(field(4), ecName);
    await tester.enterText(field(5), ecNumber);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('says whose contact this is, in English', (tester) async {
    await pump(tester, const Locale('en'));
    expect(find.text('Emergency contact person'), findsOneWidget);
    expect(find.textContaining('ONE other person'), findsOneWidget);
    expect(find.textContaining('not your own'), findsOneWidget);
    expect(find.text('Their full name (not yours)'), findsOneWidget);
    expect(find.text('Their mobile number (not yours)'), findsOneWidget);
  });

  testWidgets('and in Filipino', (tester) async {
    await pump(tester, const Locale('fil'));
    expect(find.text('Taong tatawagan sa oras ng emergency'), findsOneWidget);
    expect(find.textContaining('ISANG ibang tao'), findsOneWidget);
    expect(find.text('Buong pangalan nila (hindi sa inyo)'), findsOneWidget);
  });

  testWidgets('their own number, written another way, is refused', (
    tester,
  ) async {
    await pump(tester, const Locale('en'));
    await fill(
      tester,
      phone: '09171234567',
      ecName: 'Maria Santos',
      ecNumber: '+63 917 123 4567',
    );
    expect(find.textContaining('That is your own number'), findsOneWidget);
  });

  testWidgets('a different person\'s number is accepted', (tester) async {
    await pump(tester, const Locale('en'));
    await fill(
      tester,
      phone: '09171234567',
      ecName: 'Maria Santos',
      ecNumber: '09281112222',
    );
    expect(find.textContaining('That is your own number'), findsNothing);
    expect(find.textContaining('Add their'), findsNothing);
  });

  testWidgets('a name with no number asks for the number', (tester) async {
    await pump(tester, const Locale('en'));
    await fill(tester, ecName: 'Maria Santos');
    expect(find.textContaining('Add their mobile number too'), findsOneWidget);
  });

  testWidgets('a number with no name asks for the name', (tester) async {
    await pump(tester, const Locale('en'));
    await fill(tester, ecNumber: '09281112222');
    expect(find.textContaining('Add their name too'), findsOneWidget);
  });

  testWidgets('leaving both empty is fine - it is optional', (tester) async {
    await pump(tester, const Locale('en'));
    await fill(tester);
    expect(find.textContaining('Add their'), findsNothing);
    expect(find.textContaining('That is your own number'), findsNothing);
  });
}
