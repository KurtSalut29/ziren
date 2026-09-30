import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../announcements/data/announcement_repository.dart';
import '../../announcements/domain/announcement_model.dart';
import '../../auth/domain/auth_provider.dart';
import '../../incident_report/presentation/incident_labels.dart';
import '../../responder/domain/responder_notification_provider.dart';
import '../domain/notification_provider.dart';
import 'notice_view.dart';
import 'open_report.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Full notifications list - opened from the bell icon in the AppBar.
///
/// Merges two real data sources into one chronological feed:
///  - [NotificationProvider] - what happened to this resident's own reports:
///    the agency accepted it, help was sent, the responder is on the way or has
///    arrived, it was resolved or cancelled (with the reason), a question, a
///    message. Dismissible; drives the unread badge.
///  - [AnnouncementRepository] - official broadcasts (spec Section 24). These
///    are not per-user notifications in the backend (no read/dismiss endpoint),
///    so dismissal here is session-local only.
///
/// Every incident entry is worded by `noticeView`, the same function the pop-up
/// uses, so the list and the pop-up can never describe one event two ways.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _announcementRepo = AnnouncementRepository();
  List<AnnouncementModel> _announcements = [];
  final Set<String> _dismissedAnnouncementIds = {};

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    try {
      final items = await _announcementRepo.getAnnouncements();
      if (mounted) setState(() => _announcements = items);
    } on ServerFailure {
      // Silent — announcements are a secondary feed here. The dedicated
      // Announcements screen already surfaces a retry UI for real errors.
    } on NetworkFailure {
      // Same as above.
    } catch (_) {
      // Same as above.
    }
  }

  void _handleClearAll(NotificationProvider provider, ResponderNotificationProvider crew) {
    provider.markAllRead();
    crew.markAllRead();
    setState(() {
      _dismissedAnnouncementIds.addAll(_announcements.map((a) => a.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<NotificationProvider>();
    // The bell on a responder's home screen counts THEIR notifications - an
    // assignment, being stood down - and used to open this list, which only ever
    // read the resident's provider: a badge with an empty page behind it, and a
    // badge that could never be cleared.
    final crew = context.watch<ResponderNotificationProvider>();
    final isResponder = context.watch<AuthProvider>().userRole == 'responder';

    final entries = <_FeedEntry>[
      if (isResponder)
        for (var i = 0; i < crew.unread.length; i++)
          _buildResponderEntry(t, crew, crew.unread[i], i)
      else
        for (var i = 0; i < provider.unread.length; i++)
          _buildIncidentEntry(t, provider, provider.unread[i], i),
      for (final a in _announcements)
        if (!_dismissedAnnouncementIds.contains(a.id))
          _buildAnnouncementEntry(t, a),
    ]..sort((a, b) => b.time.compareTo(a.time));

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.homeBellLabel),
        actions: [
          if (entries.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: t.notifMoreOptions,
              icon: const Icon(LucideIcons.ellipsis_vertical),
              onSelected: (_) => _handleClearAll(provider, crew),
              itemBuilder:
                  (context) => [
                    PopupMenuItem(value: 'clear', child: Text(t.notifClearAll)),
                  ],
            ),
        ],
      ),
      body:
          entries.isEmpty
              ? const _EmptyState()
              : ListView(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                children: [for (final e in entries) e.child],
              ),
    );
  }

  // ── Incident-derived entries ──────────────────────────────
  //
  // One entry per thing that happened to one of the resident's reports, worded
  // by [noticeView] - the same words as the pop-up - so "a responder is on the
  // way", "the agency cancelled your report", "new message from the agency" each
  // read as what they are. This used to squeeze every status into four
  // categories from a mockup ("Emergency Update", "Report Confirmed") and print
  // the raw status word as the body.
  //
  // Amber is the agency's own decision or question; brand orange is the crew
  // moving; green is resolved. Red is not used here: red means critical
  // severity, and none of these is a severity.

  _FeedEntry _buildIncidentEntry(
    AppLocalizations t,
    NotificationProvider provider,
    AppNotification n,
    int index,
  ) {
    final view = noticeView(t, n);
    // What the resident sees first: the agency's own words when it has any, else
    // the plain sentence.
    final body = (view.quote != null && view.quote!.isNotEmpty)
        ? view.quote!
        : view.body;
    return _FeedEntry(
      time: n.receivedAt,
      child: _NotificationTile(
        key: ValueKey('${n.incidentId}:${n.newStatus}:${n.receivedAt}'),
        icon: view.icon,
        color: view.color,
        title: view.title,
        body: body,
        meta: n.reportText.trim().isEmpty
            ? _timeAgo(t, n.receivedAt)
            : '${IncidentLabels.reportText(t, n.reportText.trim())} · ${_timeAgo(t, n.receivedAt)}',
        onDismiss: () => provider.dismiss(index),
        // Anything that has a report to go to opens it - a message opens the
        // chat, where it is answered.
        onTap: () async {
          provider.dismiss(index);
          if (view.primary == NoticeAction.openChat) {
            await openReportChatById(context, n.incidentId);
          } else {
            await openReportById(context, n.incidentId);
          }
        },
      ),
    );
  }

  // ── Responder entries ─────────────────────────────────────
  //
  // What happened TO the responder: a call assigned, dispatch standing them
  // down, a change of priority. Worded by ResponderNotification itself, so this
  // and the phone's own notification say the same thing.

  _FeedEntry _buildResponderEntry(
    AppLocalizations t,
    ResponderNotificationProvider provider,
    ResponderNotification n,
    int index,
  ) {
    final (icon, color) = switch (n.eventType) {
      'assigned' => (LucideIcons.siren, ZirenTokens.brandOrange),
      'cancelled' => (LucideIcons.circle_x, ZirenTokens.systemWarning),
      'severity' => (LucideIcons.triangle_alert, ZirenTokens.systemWarning),
      _ => (LucideIcons.info, ZirenTokens.systemInfo),
    };
    return _FeedEntry(
      time: n.receivedAt,
      child: _NotificationTile(
        key: ValueKey('crew:${n.incidentId}:${n.eventType}:${n.receivedAt}'),
        icon: icon,
        color: color,
        title: n.label,
        body: n.detail,
        meta: '${t.notifReportPrefix}${n.shortId}… · ${_timeAgo(t, n.receivedAt)}',
        onDismiss: () => provider.dismiss(index),
        // A cancelled incident is no longer in the crew's queue; the detail
        // screen says so plainly rather than the tap doing nothing.
        onTap: () {
          provider.dismiss(index);
          context.push('/responder/incident/${n.incidentId}');
        },
      ),
    );
  }

  // ── Announcement-derived entries ──────────────────────────
  //
  // Real mapping from AnnouncementModel.category (Section 24 broadcasts):
  //   emergency / service_interruption -> "Safety Advisory" (blue, a
  //     hazard/service broadcast that is not tied to one incident report)
  //   maintenance / feature / reminder / general -> "System Message"
  //     (indigo — app-authored, not safety-critical)

  _FeedEntry _buildAnnouncementEntry(AppLocalizations t, AnnouncementModel a) {
    final bool isAdvisory =
        a.category == 'emergency' || a.category == 'service_interruption';
    return _FeedEntry(
      time: a.createdAt,
      child: _NotificationTile(
        key: ValueKey('ann_${a.id}'),
        icon: isAdvisory ? LucideIcons.info : LucideIcons.message_circle,
        color:
            isAdvisory
                ? ZirenTokens.systemInfo
                // Indigo, not aiSuggested purple — purple is reserved
                // strictly for actual AI/machine-generated output in this
                // app's color contract, and a Super Admin broadcast is
                // human-authored, not machine output.
                : ZirenTokens.statusProcessing,
        title:
            isAdvisory
                ? t.notifCategorySafetyAdvisory
                : t.notifCategorySystemMessage,
        body: a.title,
        meta: _timeAgo(t, a.createdAt),
        onDismiss:
            () => setState(() => _dismissedAnnouncementIds.add(a.id)),
      ),
    );
  }

  String _timeAgo(AppLocalizations t, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return t.timeAgoJustNow;
    if (diff.inMinutes < 60) return t.timeAgoMinutes(diff.inMinutes);
    if (diff.inHours < 24) return t.timeAgoHours(diff.inHours);
    return t.timeAgoDays(diff.inDays);
  }
}

/// A sortable (time, widget) pair — lets incident and announcement entries
/// merge into one chronological feed without either source knowing about
/// the other.
class _FeedEntry {
  const _FeedEntry({required this.time, required this.child});
  final DateTime time;
  final Widget child;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.meta,
    required this.onDismiss,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String meta;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: ZirenTokens.space10),
        padding: const EdgeInsets.only(right: ZirenTokens.space16),
        decoration: BoxDecoration(
          color: ZirenTokens.systemErrorBg,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        ),
        child: Icon(
          LucideIcons.trash,
          color: ZirenTokens.systemError,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
        margin: const EdgeInsets.only(bottom: ZirenTokens.space10),
        padding: const EdgeInsets.all(ZirenTokens.space16),
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          border: Border.all(color: ZirenTokens.surfaceBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: ZirenTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: 11,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.bell,
                size: 40,
                color: ZirenTokens.textMuted,
              ),
            ),
            const SizedBox(height: ZirenTokens.space20),
            Text(
              t.notifEmptyTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space8),
            Text(
              t.notifEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: ZirenTokens.textMuted,
              ),
            ),
            const SizedBox(height: ZirenTokens.space24),
            OutlinedButton(
              onPressed: () => context.go('/home'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space24,
                  vertical: ZirenTokens.space12,
                ),
                side: BorderSide(color: ZirenTokens.surfaceBorder),
                foregroundColor: ZirenTokens.textPrimary,
              ),
              child: Text(t.actionBackToHome),
            ),
          ],
        ),
      ),
    );
  }
}
