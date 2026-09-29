import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/home_kit.dart' show kCardRadius;
import '../../domain/nearby_incident.dart';
import '../../domain/responder_vocabulary.dart';

/// One undispatched incident near this responder — an invitation to help, not
/// a command. See `ResponderProvider.loadNearby` / `app.services.proximity`.
///
/// WHY THIS LOOKS DIFFERENT FROM [ResponderQueueCard]
///
/// A queue card is a call this crew already holds — the rank, the FSM status,
/// the full detail are all theirs to act on. This is something they were only
/// TOLD about: nothing here is assigned to them, so the card carries no rank
/// and no "open" affordance of its own, only the two answers that mean
/// anything — "I can respond" or "not available" — and, once given, shows
/// which one was sent rather than the buttons again.
///
/// A busy responder (a call already in hand) can still see and answer one of
/// these — the backend only shows it to them at all when it judged that worth
/// asking (see NearbyIncident.isAdvisory) — but the card says plainly that
/// answering does not drop what they are already on.
class NearbyIncidentCard extends StatelessWidget {
  const NearbyIncidentCard({
    super.key,
    required this.incident,
    required this.onRespond,
    required this.onUnavailable,
    this.answering = false,
  });

  final NearbyIncident incident;
  final VoidCallback onRespond;
  final VoidCallback onUnavailable;

  /// True while this card's own answer is in flight — disables both buttons
  /// so a slow connection cannot be tapped twice.
  final bool answering;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final i = incident;
    final color = ResponderVocabulary.color(i.severity);
    final where = (i.locationAddress ?? '').trim();
    final title = i.reportText.trim().isEmpty ? i.categoryLabel : i.reportText;

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: ResponderVocabulary.background(i.severity),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                ),
                child: Icon(
                  ResponderVocabulary.icon(i.severity),
                  size: 17,
                  color: color,
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
                              fontSize: 14,
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
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    if (where.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space10),
          Wrap(
            spacing: ZirenTokens.space6,
            runSpacing: ZirenTokens.space6,
            children: [
              if (i.distanceKm != null)
                _Chip(
                  icon: LucideIcons.navigation,
                  text:
                      '${i.distanceKm!.toStringAsFixed(1)} km'
                      '${i.direction != null ? ' ${i.direction}' : ''}'
                      '${i.etaMinutes != null ? ' · ~${i.etaMinutes} min' : ''}',
                )
              else
                _Chip(
                  icon: LucideIcons.map_pin_off,
                  text: t.respNearbyDistanceUnknown,
                ),
              _Chip(
                icon: LucideIcons.clock,
                text: ResponderVocabulary.elapsed(i.createdAt),
              ),
              if (i.sosFlagged)
                _Chip(
                  icon: LucideIcons.megaphone,
                  text: t.respNearbySosChip,
                  tint: ZirenTokens.severityCritical,
                ),
              if (!i.you.isFree)
                _Chip(
                  icon: LucideIcons.info,
                  text: t.respNearbyAlreadyOn(
                    ResponderVocabulary.categoryLabel(i.you.currentCategory),
                  ),
                  tint: ZirenTokens.systemWarning,
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),
          if (i.hasAnswered)
            _AnsweredBanner(answer: i.answered!, t: t)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: answering ? null : onUnavailable,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZirenTokens.textSecondary,
                      minimumSize: const Size.fromHeight(40),
                      side: BorderSide(
                        color: ZirenTokens.surfaceBorder,
                        width: 1.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius12,
                        ),
                      ),
                    ),
                    child: Text(
                      t.respNearbyNotAvailable,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: answering ? null : onRespond,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZirenTokens.brandOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius12,
                        ),
                      ),
                    ),
                    child:
                        answering
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              t.respNearbyCanRespond,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AnsweredBanner extends StatelessWidget {
  const _AnsweredBanner({required this.answer, required this.t});

  /// 'can_respond' | 'unavailable'
  final String answer;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final yes = answer == 'can_respond';
    final color = yes ? ZirenTokens.systemSuccess : ZirenTokens.textMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space10,
        vertical: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            yes ? LucideIcons.circle_check : LucideIcons.circle_x,
            size: 15,
            color: color,
          ),
          const SizedBox(width: ZirenTokens.space6),
          Text(
            yes ? t.respNearbyAnsweredYes : t.respNearbyAnsweredNo,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.tint});

  final IconData icon;
  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? ZirenTokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}
