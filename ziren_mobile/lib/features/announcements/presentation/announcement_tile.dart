import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/announcement_model.dart';
import 'alert_response_panel.dart' show canAnswerAlerts;
import 'announcement_style.dart';

/// One announcement in the list: its kind (colour + icon + word, never colour
/// alone), what it says, where it applies, and - on an alert that asked -
/// whether the resident has answered.
class AnnouncementTile extends StatelessWidget {
  const AnnouncementTile({super.key, required this.item, required this.onTap});

  final AnnouncementModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (icon, color) = announcementStyle(item.category);
    final chips = announcementChips(t, item);
    final answer = item.myResponse;

    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child: InkWell(
        key: Key('announcement-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
            border: Border.all(
              color: item.isUrgent ? color.withValues(alpha: 0.45) : ZirenTokens.surfaceBorder,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The kind's colour down the edge: a list that reads by kind.
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: 16, color: color),
                            ),
                            const SizedBox(width: ZirenTokens.space8),
                            Expanded(
                              child: Text(
                                item.categoryLabel(t).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  letterSpacing: 0.4,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                            Text(
                              timeAgoShort(t, item.createdAt),
                              style: TextStyle(fontSize: 11, color: ZirenTokens.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: ZirenTokens.space8),
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: ZirenTokens.space8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final c in chips) AnnouncementChip(label: c.label, color: c.color)],
                          ),
                        ],
                        const SizedBox(height: ZirenTokens.space6),
                        Text(
                          item.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, height: 1.45, color: ZirenTokens.textSecondary),
                        ),
                        const SizedBox(height: ZirenTokens.space8),
                        Row(
                          children: [
                            Icon(LucideIcons.map_pin, size: 13, color: ZirenTokens.textMuted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.placeLine(t),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
                              ),
                            ),
                          ],
                        ),
                        if (canAnswerAlerts(context) && (item.canAnswer || answer != null)) ...[
                          const SizedBox(height: ZirenTokens.space10),
                          _AnswerLine(answer: answer),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Answer: are you safe?" until answered, then what was said.
class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.answer});

  final AlertResponse? answer;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a = answer;
    final (icon, color, text) = a == null
        ? (LucideIcons.circle_alert, ZirenTokens.severityCritical, t.annRespondNow)
        : a.needsHelp && a.handledAt == null
        ? (LucideIcons.life_buoy, ZirenTokens.severityCritical, t.annYouAskedHelp)
        : a.needsHelp
        ? (LucideIcons.shield_check, ZirenTokens.systemSuccess, t.annHelpReached)
        : (LucideIcons.shield_check, ZirenTokens.systemSuccess, t.annYouSaidSafe);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Icon(LucideIcons.chevron_right, size: 15, color: color),
        ],
      ),
    );
  }
}

class AnnouncementChip extends StatelessWidget {
  const AnnouncementChip({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZirenTokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color == null ? Colors.transparent : c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        border: Border.all(color: color == null ? ZirenTokens.surfaceBorder : c.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

/// "5m ago", in the app's language.
String timeAgoShort(AppLocalizations t, DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return t.timeAgoJustNow;
  if (diff.inMinutes < 60) return t.timeAgoMinutes(diff.inMinutes);
  if (diff.inHours < 24) return t.timeAgoHours(diff.inHours);
  return t.timeAgoDays(diff.inDays);
}
