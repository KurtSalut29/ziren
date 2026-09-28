import 'package:flutter/material.dart';

import '../../../../features/incident_report/domain/incident_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Compact status strip for an open report.
///
/// This replaces a full-height panel that rendered all four response stages
/// as rows — three of which were greyed-out descriptions of things that had
/// not happened yet. It filled more than half the screen to communicate one
/// word, and it pushed the SOS button below it.
///
/// Both of those were mistakes. On an emergency app the SOS is the reason the
/// product exists and must stay the largest thing on the screen; and a
/// progress readout does not need four paragraphs when a bar and the current
/// stage say the same thing in one line. Future stages are conveyed by the
/// unfilled part of the bar, which is what a bar is for.
class ActiveReportStrip extends StatelessWidget {
  const ActiveReportStrip({
    super.key,
    required this.incident,
    required this.onOpen,
  });

  final IncidentModel incident;
  final VoidCallback onOpen;

  static const _stages = ['received', 'processing', 'dispatched', 'resolved'];

  int get _stageIndex {
    final i = _stages.indexOf(incident.status);
    return i < 0 ? 0 : i;
  }

  String _age() {
    final d = DateTime.now().difference(incident.createdAt);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  /// A report that has sat unacknowledged for over a day is not "live" in any
  /// useful sense. Saying so is better than implying a crew is on the way.
  bool get _isStale =>
      DateTime.now().difference(incident.createdAt).inHours > 24 &&
      _stageIndex == 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cancelled = incident.status == 'cancelled';
    final accent =
        cancelled || _isStale ? ZirenTokens.textMuted : ZirenTokens.brandOrange;

    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(ZirenTokens.radius20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        child: Container(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZirenTokens.radius20),
            border: Border.all(
              color:
                  cancelled || _isStale
                      ? ZirenTokens.surfaceBorder
                      : ZirenTokens.brandOrange.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space8),
                  Expanded(
                    child: Text(
                      incident.statusLabel(t),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color:
                            cancelled || _isStale
                                ? ZirenTokens.textSecondary
                                : ZirenTokens.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    _age(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevron_right,
                    size: 18,
                    color: ZirenTokens.textMuted,
                  ),
                ],
              ),

              const SizedBox(height: ZirenTokens.space12),

              // Segmented progress. The unfilled segments carry "what is still
              // to come" without spelling it out in prose.
              if (!cancelled)
                Row(
                  children: [
                    for (var i = 0; i < _stages.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color:
                                i <= _stageIndex && !_isStale
                                    ? accent
                                    : ZirenTokens.surfaceBorder,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

              const SizedBox(height: ZirenTokens.space8),

              // ── WHO IS COMING, AND ROUGHLY WHEN ──────────────────
              //
              // The thing a person waiting actually wants to know, and the
              // thing this app has never told them. Every screen the reporter
              // saw after submitting described the SYSTEM's progress —
              // received, processing, dispatched — and none of it answered
              // "is somebody coming to my house".
              //
              // Deliberately vague, and rendered as "about N minutes". A
              // precise arrival time promised to someone whose house is on
              // fire becomes a broken promise at the first traffic light.
              if (incident.etaLabel(t) != null) ...[
                Row(
                  children: [
                    Icon(LucideIcons.truck, size: 15, color: accent),
                    const SizedBox(width: ZirenTokens.space6),
                    Expanded(
                      child: Text(
                        incident.respondingAgency != null
                            ? t.activeReportAgencyEnRoute(
                              incident.respondingAgency!,
                              incident.etaLabel(t)!,
                            )
                            : t.activeReportResponderEnRoute(
                              incident.etaLabel(t)!,
                            ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space4),
              ],

              Text(
                cancelled
                    ? t.activeReportNotFollowedUp
                    : _isStale
                    ? t.activeReportStale
                    : t.activeReportStep(_stageIndex + 1, _stages.length),
                style: TextStyle(
                  fontSize: 12,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
