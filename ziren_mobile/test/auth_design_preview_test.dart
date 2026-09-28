import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/features/auth/presentation/widgets/auth_legal_note.dart';
import 'package:Ziren/features/auth/presentation/widgets/auth_shell.dart';
import 'package:Ziren/l10n/app_localizations.dart';
import 'package:Ziren/shared/theme/app_tokens.dart';
import 'package:Ziren/shared/widgets/ziren_button.dart';
import 'package:Ziren/shared/widgets/ziren_text_field.dart';

/// Renders the auth card with representative content and writes goldens.
///
/// Same purpose as home_design_preview_test: the real LoginScreen needs an
/// AuthProvider, which needs an initialised Supabase client, so the layout
/// cannot be looked at by pumping the screen itself. This reproduces the
/// composition instead. Run with
/// `flutter test --update-goldens test/auth_design_preview_test.dart` and open
/// the PNGs under test/goldens/.
void main() {
  // Not AppTheme.light: it resolves Nunito through google_fonts, which fetches
  // over the network, and flutter_test stubs HttpClient out — the fetch throws
  // and fails the test before a pixel is written. home_design_preview_test
  // sidesteps it the same way. This mirrors the parts of the real theme the
  // auth card actually reads; the typeface is the only difference.
  Widget wrap(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    // AuthLegalNote reads its copy from AppLocalizations, so the delegates
    // have to be here even though the test font renders every glyph as a box.
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ZirenTokens.surfaceBase,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ZirenTokens.surfaceRaised,
        hintStyle: TextStyle(fontSize: 14, color: ZirenTokens.textMuted),
        prefixIconColor: ZirenTokens.textMuted,
        suffixIconColor: ZirenTokens.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ZirenTokens.brandOrange,
          foregroundColor: ZirenTokens.textInverse,
          elevation: 0,
          minimumSize: const Size.fromHeight(ZirenTokens.minTouchTarget + 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    home: child,
  );

  testWidgets('sign-in card', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        AuthShell(
          title: 'Sign in',
          subtitle: 'Report an emergency, or respond to one.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: 'Email address',
                child: ZirenTextField(
                  label: '',
                  hint: 'you@example.com',
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: ZirenTokens.space16),
              AuthField(
                label: 'Password',
                child: ZirenTextField(
                  label: '',
                  hint: 'Enter your password',
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: Icon(
                    Icons.visibility_outlined,
                    size: 20,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: ZirenTokens.textPrimary,
                    minimumSize: const Size(0, ZirenTokens.minTouchTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZirenTokens.space8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: ZirenTokens.space8),
              ZirenButton(label: 'Sign in', onPressed: () {}),
              const SizedBox(height: ZirenTokens.space16),
              AuthFooterLink(
                question: 'New to Ziren?',
                action: 'Create an account',
                onPressed: () {},
              ),
              const SizedBox(height: ZirenTokens.space8),
              const AuthLegalNote(),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AuthShell),
      matchesGoldenFile('goldens/auth_sign_in.png'),
    );
  });

  testWidgets('registration step card', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        AuthShell(
          compact: true,
          title: 'Create account',
          subtitle: 'Which of these are you?',
          onBack: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              i == 0
                                  ? ZirenTokens.brandOrange
                                  : ZirenTokens.surfaceBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (i < 5) const SizedBox(width: 4),
                  ],
                ],
              ),
              const SizedBox(height: ZirenTokens.space24),
              AuthField(
                label: 'First name',
                child: ZirenTextField(label: '', hint: 'Juan'),
              ),
              const SizedBox(height: ZirenTokens.space16),
              AuthField(
                label: 'Mobile number',
                child: ZirenTextField(
                  label: '',
                  hint: '09XX XXX XXXX',
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: ZirenTokens.space32),
              ZirenButton(label: 'Continue', onPressed: () {}),
              const SizedBox(height: ZirenTokens.space8),
              AuthFooterLink(
                question: 'Already have an account?',
                action: 'Sign in',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AuthShell),
      matchesGoldenFile('goldens/auth_registration_step.png'),
    );
  });
}
