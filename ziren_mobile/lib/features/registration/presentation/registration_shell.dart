import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../auth/presentation/widgets/auth_shell.dart';
import '../domain/registration_draft.dart';
import '../../../l10n/app_localizations.dart';

/// Shared frame for every registration step.
///
/// Each step screen supplies only its own fields and its own validation. The
/// progress bar, the back behaviour, the continue button and the "I need help
/// right now" escape all live here, so nine screens cannot drift into nine
/// slightly different versions of the same chrome.
class RegistrationScaffold extends StatelessWidget {
  const RegistrationScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    required this.onContinue,
    this.subtitle,
    this.continueLabel = 'Continue',
    this.isLoading = false,
    this.footer,
  });

  final RegStep step;
  final String title;
  final String? subtitle;
  final Widget child;

  /// One step back, however this screen was reached. Shared with the selfie
  /// step, which draws its own full-screen camera layout instead of this frame.
  static void goBackFrom(BuildContext context, RegStep step) {
    final draft = context.read<RegistrationDraft>();
    final prev = draft.previous(step);
    if (prev != null) {
      context.go(prev.path);
    } else if (context.canPop()) {
      // Straight back to the screen that pushed this one, with whatever
      // was typed on it still there.
      context.pop();
    } else {
      // Nothing to pop: either they came from onboarding, or a step
      // navigated with `go` and flattened the stack on the way here.
      context.go(draft.cameFromSignIn ? '/login' : '/onboarding/welcome');
    }
  }

  /// Null disables the continue button — steps use this for validation.
  final VoidCallback? onContinue;

  final String continueLabel;
  final bool isLoading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<RegistrationDraft>();
    final steps = draft.steps;
    final index = draft.indexOf(step);
    final t = AppLocalizations.of(context);

    // The phone's own Back button takes the same single step back as the arrow
    // (evaluator finding #19). Steps move forward with `go`, which leaves
    // nothing beneath them, so the system pop used to close registration
    // entirely; the draft (held above the router) keeps what was typed.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goBackFrom(context, step);
      },
      child: _shell(context, steps, index, t),
    );
  }

  Widget _shell(BuildContext context, List<RegStep> steps, int index, AppLocalizations t) {
    return AuthShell(
      compact: true,
      title: title,
      subtitle: subtitle,
      onBack: () => goBackFrom(context, step),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressBar(current: index, total: steps.length),
          const SizedBox(height: ZirenTokens.space24),

          child,

          const SizedBox(height: ZirenTokens.space32),
          ZirenButton(
            label: continueLabel,
            isLoading: isLoading,
            onPressed: onContinue,
          ),

          if (footer != null) ...[
            const SizedBox(height: ZirenTokens.space16),
            footer!,
          ],

          if (SkipVerificationLink.offeredOn(context, step)) ...[
            const SizedBox(height: ZirenTokens.space8),
            const SkipVerificationLink(),
          ],

          // Only on the first step. Someone who already has an account and
          // tapped the wrong button needs one tap back to sign in; by step two
          // they have entered data, and offering an exit that silently drops it
          // would be worse than making them use Back.
          if (index == 0) ...[
            const SizedBox(height: ZirenTokens.space8),
            AuthFooterLink(
              question: t.regHaveAccount,
              action: t.loginButton,
              onPressed: () => context.go('/login'),
            ),
          ],
          const SizedBox(height: ZirenTokens.space16),
        ],
      ),
    );
  }
}

/// Segmented progress. Deliberately not labelled per step — with up to eight
/// steps the labels are unreadable at phone width, and a count is what people
/// actually want to know ("how much more of this is there").
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            i <= current
                                ? ZirenTokens.brandOrange
                                : ZirenTokens.surfaceBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < total - 1) const SizedBox(width: 4),
                ],
              ],
            ),
            const SizedBox(height: ZirenTokens.space8),
            Text(
              'Step ${current + 1} of $total',
              style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled block, matching the spacing the auth screens already use.
class RegField extends StatelessWidget {
  const RegField({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Flexible, so a long label (the Filipino ones run long) or a large
        // system font shrinks/wraps the label instead of pushing "Optional"
        // off the edge of the screen.
        Row(
          children: [
            Flexible(child: AuthFieldLabel(label)),
            if (optional) ...[
              const SizedBox(width: ZirenTokens.space8),
              Text(
                'Optional',
                style: TextStyle(fontSize: 11, color: ZirenTokens.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: ZirenTokens.space8),
        child,
      ],
    );
  }
}

/// "Verify later": a resident may finish registering without the ID, selfie
/// and 2x2 ID photo, and report for their first 7 days (user request
/// 2026-10-08; backend app/core/resident_trust.py). After that only an
/// administrator's approval lets them report, so the dialog says so before
/// they choose it, and the Home banner counts the days down.
///
/// Offered on the identity steps only, and only to residents - a responder's
/// agency ID is how their station approves them at all.
class SkipVerificationLink extends StatelessWidget {
  const SkipVerificationLink({super.key});

  static bool offeredOn(BuildContext context, RegStep step) {
    final draft = context.read<RegistrationDraft>();
    return !draft.isResponder && RegistrationDraft.identitySteps.contains(step);
  }

  Future<void> _confirm(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final draft = context.read<RegistrationDraft>();
    final proceed = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.calendar_clock,
      tone: ZirenTone.warning,
      title: t.regSkipDialogTitle,
      message: t.regSkipDialogBody,
      // Verifying now is the one we want, so it is the filled button;
      // leaving it for later is a deliberate second act.
      actions: [
        ZirenDialogAction(
          label: t.regVerifyNowInstead,
          value: false,
          kind: ZirenActionKind.primary,
        ),
        ZirenDialogAction(label: t.actionSkipForNow, value: true),
      ],
    );
    if (proceed != true || !context.mounted) return;

    // All of it or none of it: a half-finished submission in the admin's
    // queue is one they can only reject.
    draft.skippedVerification = true;
    draft.commit();
    context.go(draft.afterSkip.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: TextButton(
        key: const ValueKey('reg-verify-later'),
        onPressed: () => _confirm(context),
        child: Text(
          t.regSkipLink,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: ZirenTokens.textSecondary,
            decoration: TextDecoration.underline,
            decorationColor: ZirenTokens.textMuted,
          ),
        ),
      ),
    );
  }
}
