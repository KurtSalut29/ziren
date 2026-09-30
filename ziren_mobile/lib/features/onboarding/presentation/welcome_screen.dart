import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../shared/widgets/ziren_button.dart';
import 'widgets/onboarding_kit.dart';
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
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // ── Brand hero ─────────────────────────────────
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF7A2F), ZirenTokens.brandOrange],
                    ),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(32),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ZirenTokens.space24,
                        ZirenTokens.space16,
                        ZirenTokens.space24,
                        ZirenTokens.space32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _StepsOnBrand(step: 3),
                          const SizedBox(height: ZirenTokens.space16),
                          // The same Ziren who asked for the language on
                          // step 1, now pointing at the two doors below.
                          OnboardingMascot(
                            text: t.welcomeMascotLine,
                            size: 104,
                            onBrand: true,
                          ),
                          const SizedBox(height: ZirenTokens.space12),
                          Text(
                            t.welcomeHeadline,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: ZirenTokens.space6),
                          Text(
                            t.welcomeTagline,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── What it does, in three lines ───────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZirenTokens.space24,
                    ZirenTokens.space24,
                    ZirenTokens.space24,
                    ZirenTokens.space16,
                  ),
                  child: Column(
                    children: [
                      _Feature(
                        icon: LucideIcons.siren,
                        color: ZirenTokens.severityCritical,
                        text: t.welcomeFeatureReport,
                      ),
                      _Feature(
                        icon: LucideIcons.building,
                        color: ZirenTokens.systemInfo,
                        text: t.welcomeFeatureStation,
                      ),
                      _Feature(
                        icon: LucideIcons.truck,
                        color: ZirenTokens.systemSuccess,
                        text: t.welcomeFeatureTrack,
                        last: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── The two doors ─────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space24,
                ZirenTokens.space8,
                ZirenTokens.space24,
                ZirenTokens.space20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.welcomeNewHere,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  ZirenButton(
                    key: const Key('welcome-create'),
                    label: t.welcomeCreateAccount,
                    icon: LucideIcons.user_plus,
                    onPressed: () => _startRegistration(context),
                  ),
                  const SizedBox(height: ZirenTokens.space16),
                  Text(
                    t.welcomeHasAccount,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('welcome-sign-in'),
                      onPressed: () => context.go('/login'),
                      icon: const Icon(LucideIcons.log_in, size: 18),
                      label: Text(
                        t.welcomeSignIn,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ZirenTokens.textPrimary,
                        side: BorderSide(
                          color: ZirenTokens.surfaceBorder,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The onboarding step dots, drawn white on the brand hero.
class _StepsOnBrand extends StatelessWidget {
  const _StepsOnBrand({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        for (var i = 1; i <= 3; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Container(
            width: i == step ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i <= step ? 1 : 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
        const SizedBox(width: ZirenTokens.space10),
        Text(
          t.onbStep('$step', '3'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.color,
    required this.text,
    this.last = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : ZirenTokens.space16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
