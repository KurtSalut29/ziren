import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ziren/features/registration/domain/registration_draft.dart';
import 'package:ziren/features/registration/presentation/registration_shell.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Where the back arrow on step one of registration goes.
///
/// It used to go to /onboarding/welcome unconditionally, which meant someone
/// who tapped "Create an account" on the sign-in screen and immediately
/// changed their mind was shown a screen asking them to choose between
/// creating an account and signing in — the question they had just answered.
/// Worse, `go` replaced the stack, so the sign-in screen they came from was
/// gone along with anything typed on it.
void main() {
  Widget harness(RegistrationDraft draft, GoRouter router) {
    return ChangeNotifierProvider<RegistrationDraft>.value(
      value: draft,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        routerConfig: router,
      ),
    );
  }

  GoRouter buildRouter({required String initial}) {
    return GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/login',
          builder:
              (context, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      context.read<RegistrationDraft>().cameFromSignIn = true;
                      context.push('/register/role');
                    },
                    child: const Text('Create an account'),
                  ),
                ),
              ),
        ),
        GoRoute(
          path: '/onboarding/welcome',
          builder: (_, _) => const Scaffold(body: Text('WELCOME SCREEN')),
        ),
        GoRoute(
          path: '/register/role',
          builder:
              (_, _) => RegistrationScaffold(
                step: RegStep.role,
                title: 'Create account',
                onContinue: () {},
                child: const SizedBox.shrink(),
              ),
        ),
        GoRoute(
          path: '/register/personal',
          builder:
              (_, _) => RegistrationScaffold(
                step: RegStep.personal,
                title: 'Your name',
                onContinue: () {},
                child: const SizedBox.shrink(),
              ),
        ),
      ],
    );
  }

  // Evaluator finding #19 (2026-10-05): the phone's own Back button left
  // registration altogether, because steps move forward with `go` and leave
  // nothing beneath them. It now takes one step back, like the arrow, and
  // what was typed is still in the draft.
  testWidgets("the phone's Back button goes one step back, keeping what was typed", (
    tester,
  ) async {
    final draft = RegistrationDraft()..firstName = 'Maria';
    final router = buildRouter(initial: '/register/personal');
    await tester.pumpWidget(harness(draft, router));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsOneWidget, reason: 'one step back, not out');
    expect(draft.firstName, 'Maria');
  });

  testWidgets('back from step one returns to sign-in when it came from there', (
    tester,
  ) async {
    final draft = RegistrationDraft();
    await tester.pumpWidget(harness(draft, buildRouter(initial: '/login')));

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('WELCOME SCREEN'), findsNothing);
  });

  testWidgets('back from step one goes to welcome when onboarding sent them', (
    tester,
  ) async {
    final draft = RegistrationDraft();
    // What welcome_screen sets on its way into the flow.
    draft.cameFromSignIn = false;

    await tester.pumpWidget(
      harness(draft, buildRouter(initial: '/register/role')),
    );
    expect(find.text('Create account'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('WELCOME SCREEN'), findsOneWidget);
  });

  testWidgets('back lands on sign-in even with no page left to pop', (
    tester,
  ) async {
    // The state after walking forward through the steps and back again: every
    // step navigated with `go`, so the pushed sign-in page is long gone. The
    // remembered door is the only thing left to go on.
    final draft = RegistrationDraft();
    draft.cameFromSignIn = true;

    await tester.pumpWidget(
      harness(draft, buildRouter(initial: '/register/role')),
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('WELCOME SCREEN'), findsNothing);
  });
}
