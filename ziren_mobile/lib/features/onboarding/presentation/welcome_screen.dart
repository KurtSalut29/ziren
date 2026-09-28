import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_logo.dart';
import '../../registration/domain/registration_draft.dart';

/// The fork at the end of onboarding: sign in, or create an account.
///
/// It exists as its own screen rather than dropping straight onto the login
/// form because a first-time user has just been told what the app collects and
/// why — landing them on a password field implies they already have an
/// account, and "Create account" as a small link under a form is the shape
/// that gets missed.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// Offer to pick up an abandoned registration before starting a new one.
  ///
  /// Registration is eight screens. Someone who got to the selfie and then took
  /// a phone call should not have to retype their address, and without this
  /// prompt the saved draft would never be reachable — the flow always enters
  /// at step one.
  ///
  /// Asking rather than silently restoring matters: a shared handset may hold
  /// somebody else's half-finished details, and quietly prefilling another
  /// person's name and address would be both confusing and a small privacy
  /// leak.
  Future<void> _startRegistration(BuildContext context) async {
    final draft = context.read<RegistrationDraft>();
    // Back from step one belongs here, not on the sign-in screen. Set on both
    // exits below, so a restored draft cannot carry the other door's answer.
    draft.cameFromSignIn = false;
    if (!await RegistrationDraft.hasSavedDraft()) {
      if (context.mounted) context.go('/register/role');
      return;
    }
    if (!context.mounted) return;

    final t = AppLocalizations.of(context);
    final resume = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.rotate_ccw_clock,
      tone: ZirenTone.info,
      title: t.welcomeResumeTitle,
      message: t.welcomeResumeBody,
      actions: [
        ZirenDialogAction(
          label: t.welcomeResumeContinue,
          value: true,
          kind: ZirenActionKind.primary,
        ),
        ZirenDialogAction(label: t.welcomeResumeStartOver, value: false),
      ],
    );
    if (!context.mounted) return;

    if (resume == true) {
      await draft.restore();
      draft.cameFromSignIn = false;
    } else if (resume == false) {
      draft.reset();
    } else {
      return; // dismissed — leave the draft alone
    }
    if (context.mounted) context.go('/register/role');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space24,
            ZirenTokens.space32,
            ZirenTokens.space24,
            ZirenTokens.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              Center(child: ZirenLogo.mark(size: 88, onDark: ZirenTokens.isDark)),
              const SizedBox(height: ZirenTokens.space24),
              Center(
                child: Text(
                  'ZIREN',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 7,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: ZirenTokens.space8),
              Center(
                child: Text(
                  t.welcomeTagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              ZirenButton(
                label: t.welcomeCreateAccount,
                onPressed: () => _startRegistration(context),
              ),
              const SizedBox(height: ZirenTokens.space12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => context.go('/login'),
                  child: Text(t.welcomeSignIn),
                ),
              ),
              const SizedBox(height: ZirenTokens.space16),
            ],
          ),
        ),
      ),
    );
  }
}
