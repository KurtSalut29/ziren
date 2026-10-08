import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../features/settings/domain/profile_provider.dart';
import '../theme/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Tells a resident their account is not verified yet, and what to do.
///
/// Why this exists
/// ---------------
/// A new resident may report for their first 7 days unverified; after that
/// only an administrator's approval lets them report (user request
/// 2026-10-08, softening 2026-10-07's verified-only rule; backend
/// app/core/resident_trust.py). This counts those days down, and once they
/// are over says why the report buttons stop: on Home directly under the SOS
/// button, and on Profile.
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
    // In the first week the reports still go through; after it, they do not.
    // A profile without a deadline (a server older than the first-week rule)
    // is the old verified-only rule, so it reads as locked.
    final grace = profile.inReportingGrace;
    final until = grace ? deadline(t, profile.reportingGraceEndsAt!) : '';
    final days = profile.graceDaysLeft;
    final title =
        submitted
            ? t.bannerInReview
            : grace
            ? (days <= 1 ? t.bannerGraceLastDay : t.bannerGraceTitle(days))
            : t.bannerLockedTitle;
    final body =
        grace
            ? (submitted ? t.bannerGraceReviewBody(until) : t.bannerGraceBody(until))
            // Deliberately no time estimate for a review. A promise we cannot
            // keep is worse than no promise, and it depends on an admin's
            // workload.
            : (submitted ? t.bannerInReviewBody : t.bannerFinishBody);

    // Amber once reporting has stopped and nothing is waiting for an admin:
    // that is the one state the resident has to act on. A system colour,
    // never a severity one - those mean something specific in this product.
    final urgent = !grace && !submitted;
    final tint = urgent ? ZirenTokens.systemWarning : ZirenTokens.systemInfo;
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: urgent ? ZirenTokens.systemWarningBg : ZirenTokens.systemInfoBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            submitted
                ? LucideIcons.hourglass
                : grace
                ? LucideIcons.calendar_clock
                : LucideIcons.shield_alert,
            size: 20,
            color: tint,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey('verification-banner-title'),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  body,
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

  /// When the first week ends, as the resident reads it: "Oct 15, 3:20 PM".
  static String deadline(AppLocalizations t, DateTime when) {
    final local = when.toLocal();
    try {
      return DateFormat.MMMd(t.localeName).add_jm().format(local);
    } catch (_) {
      return DateFormat.MMMd().add_jm().format(local);
    }
  }
}
