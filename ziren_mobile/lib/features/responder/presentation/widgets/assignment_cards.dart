import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/responder_incident_model.dart';
import '../../domain/responder_vocabulary.dart';
import 'responder_ui.dart';

/// The one assignment to work on now, as the biggest thing under the duty
/// card: what it is, how bad, where, where the crew is in it, and the button
/// that opens it.
///
/// It replaces the old orange "Awaiting Dispatch" bar. That bar said nothing
/// about the call behind it, and its words were wrong for a responder: the
/// call had already been dispatched - to them.
class NextUpAssignmentCard extends StatelessWidget {
  const NextUpAssignmentCard({
    super.key,
    required this.incident,
    required this.total,
    required this.onOpen,
    this.onNavigate,
    this.highlighted = false,
  });

  final ResponderIncidentModel incident;

  /// How many open assignments there are in all ("1 of 2").
  final int total;
  final VoidCallback onOpen;

  /// Null when the call has no coordinates to go to.
  final VoidCallback? onNavigate;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tint = ResponderVocabulary.color(incident.severity);
    final title =
        incident.reportText.isEmpty
            ? incident.categoryLabel
            : ResponderVocabulary.reportText(incident.reportText);
    final since = incident.dispatchedAt ?? incident.createdAt;

    return ResponderCard(
      stripe: tint,
      highlighted: highlighted,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponderEyebrow(
            total > 1
                ? '${t.respNextUpTitle} · ${t.respNextUpCount('$total')}'
                : t.respNextUpTitle,
            color: tint,
            trailing: _Waiting(
              label: t.respWaitingFor(ResponderVocabulary.elapsed(since)),
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Row(
            children: [
              CategoryTile(
                category: incident.incidentCategory,
                severity: incident.severity,
                size: 46,
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident.categoryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      incident.shortId,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space12),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16.5,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SeverityChip(severity: incident.severity),
              PhaseChip(incident: incident),
              if (incident.sosFlag) const SosChip(),
            ],
          ),
          const SizedBox(height: ZirenTokens.space12),
          _PlaceLine(
            icon: LucideIcons.map_pin,
            text: incident.locationAddress ?? t.respNoLocation,
            strong: true,
          ),
          if (incident.landmarkNote?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            _PlaceLine(
              icon: LucideIcons.landmark,
              text: t.respLandmarkPrefix(incident.landmarkNote!.trim()),
            ),
          ],
          const SizedBox(height: ZirenTokens.space16),
          AssignmentProgress(incident: incident),
          const SizedBox(height: ZirenTokens.space16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onOpen,
                  icon: Icon(
                    incident.needsAnswer
                        ? LucideIcons.bell_ring
                        : LucideIcons.arrow_right,
                    size: 18,
                  ),
                  label: Text(
                    incident.needsAnswer
                        ? t.respAnswerNow
                        : t.respOpenAssignment,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZirenTokens.brandOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: responderButtonText(
                      context,
                      14.5,
                      FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (onNavigate != null) ...[
                const SizedBox(width: ZirenTokens.space10),
                OutlinedButton.icon(
                  onPressed: onNavigate,
                  icon: const Icon(LucideIcons.navigation, size: 17),
                  label: Text(t.respNavigate),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZirenTokens.textPrimary,
                    minimumSize: const Size(0, 50),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: BorderSide(
                      color: ZirenTokens.surfaceBorder,
                      width: 1.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: responderButtonText(
                      context,
                      14,
                      FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One open assignment in the list under the "do this first" card.
class ResponderQueueCard extends StatelessWidget {
  const ResponderQueueCard({
    super.key,
    required this.rank,
    required this.incident,
    required this.onTap,
    this.highlighted = false,
  });

  /// Place in the working order, 1-based.
  final int rank;
  final ResponderIncidentModel incident;
  final VoidCallback onTap;

  /// True for ~2 s right after this call arrived while Home was open.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tint = ResponderVocabulary.color(incident.severity);
    final title =
        incident.reportText.isEmpty
            ? incident.categoryLabel
            : ResponderVocabulary.reportText(incident.reportText);
    final since = incident.dispatchedAt ?? incident.createdAt;

    return ResponderCard(
      stripe: tint,
      highlighted: highlighted,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryTile(
            category: incident.incidentCategory,
            severity: incident.severity,
            size: 40,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                _PlaceLine(
                  icon: LucideIcons.map_pin,
                  text: incident.locationAddress ?? t.respNoLocation,
                  small: true,
                ),
                const SizedBox(height: ZirenTokens.space8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SeverityChip(severity: incident.severity),
                    PhaseChip(incident: incident),
                    if (incident.sosFlag) const SosChip(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '#$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: ZirenTokens.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ResponderVocabulary.elapsed(since),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Icon(
                LucideIcons.chevron_right,
                size: 18,
                color: ZirenTokens.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 12, color: ZirenTokens.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceLine extends StatelessWidget {
  const _PlaceLine({
    required this.icon,
    required this.text,
    this.strong = false,
    this.small = false,
  });

  final IconData icon;
  final String text;
  final bool strong;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: small ? 13 : 15,
            color: ZirenTokens.textMuted,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: small ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: small ? 12 : 13.5,
              height: 1.3,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color:
                  strong ? ZirenTokens.textPrimary : ZirenTokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
