import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/announcement_repository.dart';
import '../domain/announcement_model.dart';
import 'alert_response_panel.dart';
import 'announcement_style.dart';

/// The safety alert for where the resident lives, on Home - above the report
/// button, because an evacuation order for your barangay is the most important
/// thing the app can show you that day. It carries the "are you safe?" answer
/// itself, so answering is one tap from opening the app.
///
/// Draws nothing when there is no live safety alert for this resident (the
/// usual case), or while it is loading, or when it could not be loaded - the
/// report button must never move down for a spinner.
class ActiveAlertsCard extends StatefulWidget {
  const ActiveAlertsCard({super.key, this.refreshKey = 0, this.repository});

  /// Changes whenever a new alert notice arrives; the card reads the list again.
  final int refreshKey;
  final AnnouncementRepository? repository;

  @override
  State<ActiveAlertsCard> createState() => ActiveAlertsCardState();
}

class ActiveAlertsCardState extends State<ActiveAlertsCard> {
  late final AnnouncementRepository _repo = widget.repository ?? AnnouncementRepository();
  List<AnnouncementModel> _alerts = const [];

  // Most dangerous kind first; an unanswered question before an answered one.
  static const _rank = {'evacuation': 0, 'emergency': 1, 'hazard': 2, 'weather': 3, 'missing_person': 4, 'road_closure': 5};

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(ActiveAlertsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) reload();
  }

  Future<void> reload() async {
    try {
      final all = await _repo.getAnnouncements();
      final urgent = all.where((a) => a.isUrgent).toList()
        ..sort((a, b) {
          final ask = (a.canAnswer && a.myResponse == null ? 0 : 1) - (b.canAnswer && b.myResponse == null ? 0 : 1);
          if (ask != 0) return ask;
          final r = (_rank[a.category] ?? 9) - (_rank[b.category] ?? 9);
          return r != 0 ? r : b.createdAt.compareTo(a.createdAt);
        });
      if (mounted) setState(() => _alerts = urgent);
    } catch (_) {
      // Keep what was shown. Home must not break because this list did not load.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_alerts.isEmpty) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final a = _alerts.first;
    final (icon, color) = announcementStyle(a.category);
    final chips = announcementChips(t, a);

    return Padding(
      padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, 0, ZirenTokens.space16, ZirenTokens.space16),
      child: Container(
        key: const Key('home-active-alert'),
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () async {
                await context.push('/announcements/${a.id}');
                reload();
              },
              child: Container(
                color: color.withValues(alpha: 0.10),
                padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, ZirenTokens.space12, ZirenTokens.space12, ZirenTokens.space12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: Icon(icon, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.categoryLabel(t).toUpperCase(),
                            style: TextStyle(fontSize: 11.5, letterSpacing: 0.5, fontWeight: FontWeight.w800, color: color),
                          ),
                          Text(
                            a.placeLine(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: ZirenTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevron_right, size: 20, color: color),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(ZirenTokens.space16, ZirenTokens.space12, ZirenTokens.space16, ZirenTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    a.title,
                    style: TextStyle(fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w800, color: ZirenTokens.textPrimary),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: ZirenTokens.space8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                              border: Border.all(color: (c.color ?? ZirenTokens.surfaceBorder).withValues(alpha: c.color == null ? 1 : 0.45)),
                            ),
                            child: Text(c.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.color ?? ZirenTokens.textSecondary)),
                          ),
                      ],
                    ),
                  ],
                  // Where to go matters more than the message on this card.
                  if (a.category == 'evacuation' && a.centers.isNotEmpty) ...[
                    const SizedBox(height: ZirenTokens.space10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.door_open, size: 17, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${t.annGoTo}: ${a.centers.map((c) => c['name']).join(' · ')}',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ZirenTokens.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: ZirenTokens.space6),
                    Text(
                      a.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 1.45, color: ZirenTokens.textSecondary),
                    ),
                  ],
                  if (a.canAnswer || a.myResponse != null) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    AlertResponsePanel(
                      key: ValueKey('home-panel-${a.id}'),
                      announcement: a,
                      repository: _repo,
                      dense: true,
                      onAnswered: (r) => setState(() {
                        _alerts = [a.withResponse(r), ..._alerts.skip(1)];
                      }),
                    ),
                  ],
                  if (_alerts.length > 1) ...[
                    const SizedBox(height: ZirenTokens.space8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('home-more-alerts'),
                        onPressed: () => context.push('/announcements'),
                        icon: const Icon(LucideIcons.megaphone, size: 16),
                        label: Text(t.annHomeMore(_alerts.length - 1)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
