import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/incident_model.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// "Is this what you said?" — asked again, later, from somewhere safe.
///
/// Only shown while the question is still open: once the reporter has agreed
/// or corrected it, [IncidentModel.transcriptSettled] is true and this
/// disappears. Nobody should be nagged about a report they already checked.
///
/// Shared between the My Reports list card and the full report detail
/// screen — the reports whose transcripts are worst come from people who
/// were panicking, and they are exactly the people who will skip a prompt
/// they have to go looking for, so it stays visible wherever they land.
class TranscriptPrompt extends StatelessWidget {
  const TranscriptPrompt({super.key, required this.incident});

  final IncidentModel incident;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      onTap: () => context.push('/report/confirm/${incident.id}'),
      child: Container(
        padding: const EdgeInsets.all(ZirenTokens.space12),
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          border: Border.all(
            color: ZirenTokens.brandOrange.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.mic_vocal,
              size: 18,
              color: ZirenTokens.brandOrange,
            ),
            const SizedBox(width: ZirenTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).reportsAskConfirmVoice,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '"${incident.heardText}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevron_right,
              size: 20,
              color: ZirenTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
