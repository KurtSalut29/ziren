import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/nearby_incident.dart';
import '../../domain/responder_vocabulary.dart';

/// What the responder did with a nearby alert.
enum NearbyAlertChoice {
  /// "I can respond" - tells the dispatcher a fact. Assigns nothing.
  canRespond,

  /// "Not available" - also only tells the dispatcher.
  unavailable,

  /// Closed without answering. The card stays on Home; the alert comes back
  /// the next time the app is opened, until it is answered or handled.
  later,
}

/// The modal that announces an undispatched incident near this responder.
///
/// Tester report 2026-10-05: the phone said "incident near you" in the
/// notification shade, but opening the app showed no alert - only a card
/// further down Home. The assignment has a doorbell ([IncomingReportSheet]);
/// a nearby incident now has one too, raised by the shell whenever the app is
/// opened with an unanswered one waiting.
///
/// The answers are the same two the Home card offers and mean the same: they
/// tell the dispatcher, who still decides who goes. The copy says so, because
/// "I can respond" read as "I took the call" would leave a call uncovered.
class NearbyAlertSheet extends StatelessWidget {
  const NearbyAlertSheet({super.key, required this.incident});

  final NearbyIncident incident;

  static Future<NearbyAlertChoice> show(
    BuildContext context,
    NearbyIncident incident,
  ) async {
    final choice = await showDialog<NearbyAlertChoice>(
      context: context,
      barrierDismissible: true,
      builder: (_) => NearbyAlertSheet(incident: incident),
    );
    return choice ?? NearbyAlertChoice.later;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final i = incident;
    final tint = ResponderVocabulary.color(i.severity);
    final where = (i.locationAddress ?? '').trim();
    final distance =
        i.distanceKm == null
            ? t.respNearbyDistanceUnknown
            : '${i.distanceKm!.toStringAsFixed(1)} km'
                '${i.direction != null ? ' ${i.direction}' : ''}'
                '${i.etaMinutes != null ? ' · ~${i.etaMinutes} min' : ''}';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space20,
        vertical: ZirenTokens.space24,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(ZirenTokens.radius24),
        ),
        padding: const EdgeInsets.all(ZirenTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space8),
                Expanded(
                  child: Text(
                    t.respNearbyAlertEyebrow,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
                InkWell(
                  key: const ValueKey('nearby-alert-close'),
                  onTap:
                      () => Navigator.of(context).pop(NearbyAlertChoice.later),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: ZirenTokens.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZirenTokens.space12),

            // ── The incident ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(ZirenTokens.space12),
              decoration: BoxDecoration(
                color: ResponderVocabulary.background(i.severity),
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                border: Border.all(color: tint.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: ZirenTokens.surfaceCard,
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius12,
                          ),
                        ),
                        child: Icon(
                          ResponderVocabulary.icon(i.severity),
                          size: 19,
                          color: tint,
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    i.categoryLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: ZirenTokens.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: ZirenTokens.space6),
                                Text(
                                  ResponderVocabulary.label(i.severity),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                    color: tint,
                                  ),
                                ),
                              ],
                            ),
                            if (where.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                where,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.3,
                                  color: ZirenTokens.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space10),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.navigation,
                        size: 14,
                        color: ZirenTokens.textSecondary,
                      ),
                      const SizedBox(width: ZirenTokens.space6),
                      Expanded(
                        child: Text(
                          distance,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        ResponderVocabulary.elapsed(i.createdAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (i.sosFlagged) ...[
                    const SizedBox(height: ZirenTokens.space8),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.megaphone,
                          size: 13,
                          color: ZirenTokens.severityCritical,
                        ),
                        const SizedBox(width: ZirenTokens.space6),
                        Text(
                          t.respNearbySosChip,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: ZirenTokens.severityCritical,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: ZirenTokens.space12),

            Text(
              t.respNearbySubtitle,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space16),

            Row(
              children: [
                Expanded(
                  child: _Button(
                    key: const ValueKey('nearby-alert-unavailable'),
                    label: t.respNearbyNotAvailable,
                    filled: false,
                    onTap:
                        () => Navigator.of(
                          context,
                        ).pop(NearbyAlertChoice.unavailable),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  flex: 2,
                  child: _Button(
                    key: const ValueKey('nearby-alert-respond'),
                    label: t.respNearbyCanRespond,
                    filled: true,
                    onTap:
                        () => Navigator.of(
                          context,
                        ).pop(NearbyAlertChoice.canRespond),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Orange: this product's action colour. Red stays the severity's.
    return Material(
      color: filled ? ZirenTokens.brandOrange : ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            border:
                filled
                    ? null
                    : Border.all(color: ZirenTokens.surfaceBorder, width: 1.4),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color:
                  filled ? ZirenTokens.textInverse : ZirenTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
