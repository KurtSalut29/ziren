import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/settings/domain/profile_provider.dart';
import '../theme/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Tells a resident their account is not verified yet, and what to do.
///
/// Why this exists
/// ---------------
/// Since 2026-10-07 (user request) a resident reports only once an
/// administrator has verified the account - false reports from throwaway
/// accounts sent crews out. Until then, this is what explains why the report
/// buttons ask them to verify first: on Home directly under the SOS button,
/// and on Profile. It cannot be dismissed while it is true.
///
/// The palette stays systemInfo rather than a severity colour: severity tokens
/// mean something specific in this product and must not be spent on a notice.
class VerificationBanner extends StatelessWidget {
  const VerificationBanner({super.key, this.onDismiss});

  /// Supplied by the home screen, which lets a resident hide it for the
  /// session. Profile has no dismiss — that is where you go to act on it.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final profile = context.watch<ProfileProvider>().profile;

    // No profile yet, or already verified: nothing to say. Showing a
    // half-formed banner while the fetch is in flight is worse than waiting.
    if (profile == null || profile.isVerifiedResident) {
      return const SizedBox.shrink();
    }
    if (profile.role != 'resident') return const SizedBox.shrink();

    final submitted = profile.hasSubmittedEvidence;

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemInfoBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(
          color: ZirenTokens.systemInfo.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            submitted
                ? LucideIcons.hourglass
                : LucideIcons.shield_check,
            size: 20,
            color: ZirenTokens.systemInfo,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submitted ? t.bannerInReview : t.bannerFinishVerifying,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  submitted
                      // Deliberately no time estimate. A promise we cannot
                      // keep is worse than no promise, and review depends on
                      // an admin's workload.
                      ? t.bannerInReviewBody
                      : t.bannerFinishBody,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                if (!submitted) ...[
                  const SizedBox(height: ZirenTokens.space8),
                  Row(
                    children: [
                      Flexible(child: TextButton(
                        onPressed: () => context.push('/profile/verify'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(t.bannerVerifyNow),
                      )),
                      if (onDismiss != null) ...[
                        const SizedBox(width: ZirenTokens.space20),
                        TextButton(
                          onPressed: onDismiss,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: ZirenTokens.textMuted,
                          ),
                          child: Text(t.bannerNotNow),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
