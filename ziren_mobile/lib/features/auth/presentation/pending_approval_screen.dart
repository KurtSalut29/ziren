import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_card.dart';
import '../domain/auth_provider.dart';
import 'widgets/auth_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Shown to Responders whose account is pending Agency Admin approval.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _AccountStatusScreen(
      icon: LucideIcons.hourglass,
      accent: ZirenTokens.systemWarning,
      accentBg: ZirenTokens.severityHighBg,
      title: t.pendingTitle,
      body: t.pendingBody,
      steps: [t.pendingStep1, t.pendingStep2, t.pendingStep3],
    );
  }
}

/// Shown to Responders whose account was rejected.
class RejectedAccountScreen extends StatelessWidget {
  const RejectedAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _AccountStatusScreen(
      icon: LucideIcons.circle_x,
      accent: ZirenTokens.systemError,
      accentBg: ZirenTokens.severityCriticalBg,
      title: t.rejectedTitle,
      body: t.rejectedBody,
      steps: [t.rejectedStep1, t.rejectedStep2],
    );
  }
}

// ── Shared layout ─────────────────────────────────────────────
//
// The pending and rejected screens differ only in wording and colour. They
// used to be two near-identical 60-line widgets, which is how they drifted
// into slightly different paddings and icon sizes.

class _AccountStatusScreen extends StatelessWidget {
  const _AccountStatusScreen({
    required this.icon,
    required this.accent,
    required this.accentBg,
    required this.title,
    required this.body,
    required this.steps,
  });

  final IconData icon;
  final Color accent;
  final Color accentBg;
  final String title;
  final String body;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();

    return AuthShell(
      compact: true,
      title: title,
      subtitle: body,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZirenCard(
            padding: const EdgeInsets.all(ZirenTokens.space20),
            accent: accent,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: accent),
                ),
                const SizedBox(width: ZirenTokens.space16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: ZirenTokens.space24),

          // Telling someone what happens next is the difference between
          // a dead end and a wait.
          ZirenSectionLabel(t.pendingWhatNext),
          ZirenGroupedRows(
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZirenTokens.space16,
                    vertical: ZirenTokens.space16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ZirenTokens.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space12),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: ZirenTokens.space32),

          OutlinedButton.icon(
            icon: const Icon(LucideIcons.log_out, size: 18),
            label: Text(t.actionLogOut),
            onPressed: () => auth.logout(),
            style: OutlinedButton.styleFrom(
              foregroundColor: ZirenTokens.textSecondary,
              side: BorderSide(color: ZirenTokens.surfaceBorder),
              minimumSize: const Size.fromHeight(
                ZirenTokens.minTouchTarget + 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              ),
            ),
          ),
          const SizedBox(height: ZirenTokens.space16),
        ],
      ),
    );
  }
}
