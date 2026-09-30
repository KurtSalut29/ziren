import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../notifications/presentation/notice_view.dart' show noticeStage;
import '../incident_labels.dart';

/// Where a report is, as four named steps: Received, Checking, On the way,
/// Resolved. Each step is a segment of a bar with its name under it; the
/// steps already passed and the current one are filled, the current name is
/// in bold and in the stage's colour.
///
/// Used on My Reports' cards and on the report's own screen. It replaced a
/// bare "Step 1 of 4", which a tester could not read: it named no step, so
/// it said neither what had happened nor what came next.
class ReportStageTrack extends StatelessWidget {
  const ReportStageTrack({super.key, required this.status, this.compact = false});

  /// The report's wire status ('received', 'processing', 'dispatched',
  /// 'en_route', 'arrived', 'resolved').
  final String status;

  /// Smaller type, for a list card.
  final bool compact;

  static Color colorFor(int stage) => switch (stage) {
    0 => ZirenTokens.statusReceived,
    1 => ZirenTokens.statusProcessing,
    2 => ZirenTokens.statusDispatched,
    _ => ZirenTokens.statusResolved,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final stage = noticeStage(status);
    final color = colorFor(stage);
    final labels = [
      t.stageShortReceived,
      t.stageShortChecking,
      t.stageShortOnTheWay,
      t.stageShortResolved,
    ];

    return Semantics(
      label: IncidentLabels.status(t, status),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: ZirenTokens.motionQuick,
                    height: compact ? 5 : 6,
                    decoration: BoxDecoration(
                      color:
                          i <= stage
                              ? color
                              : ZirenTokens.surfaceBorder.withValues(
                                alpha: 0.8,
                              ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: i == stage ? FontWeight.w800 : FontWeight.w600,
                      color:
                          i == stage
                              ? color
                              : i < stage
                              ? ZirenTokens.textSecondary
                              : ZirenTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
