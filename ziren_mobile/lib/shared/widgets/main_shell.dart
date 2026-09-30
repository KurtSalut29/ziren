import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/notifications/domain/notification_provider.dart';
import '../../features/settings/domain/profile_provider.dart';
import '../../features/notifications/presentation/open_report.dart';
import '../../features/notifications/presentation/notice_view.dart';
import '../../features/notifications/presentation/widgets/status_update_sheet.dart';
import '../theme/app_tokens.dart';
import 'home_kit.dart';
import 'ziren_toast.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// ============================================================
// MainShell — four-slot floating nav bar.
//
//   0  Home       /home
//   1  Reports    /my-reports
//   2  Map        /map
//   3  Profile    /profile
//
// Ziren AI used to occupy a fifth, accented slot here. It was dropped to
// match the resident redesign, which specifies a four-tab bar on every
// screen. The screen and its route (/ziren-ai) still exist as a flat,
// pushed route outside the shell — see app_router.dart — so the feature
// is not deleted, only currently unlinked from any nav entry point.
//
// The SOS FAB that used to overlap this bar is gone: the SOS now lives
// as the hero of the Home screen. That is a real trade-off — SOS is no
// longer one tap from Reports, Map or Profile — and it is the design's
// call, not an oversight. If it should come back, it belongs here rather
// than duplicated per screen.
// ============================================================

const double _navHeight = 68.0;
const double _navMarginH = 12.0;
const double _navMarginB = 12.0;

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  /// Notifications already put on screen as a sheet, keyed by incident id +
  /// status + arrival time. A resident does not need to be reminded the way
  /// an unanswered responder assignment does — one sheet per status change
  /// is the whole point — so this is a permanent record for the life of the
  /// shell, unlike the responder side's per-state tracking.
  final Set<String> _shown = {};

  /// One sheet at a time, same reasoning as the responder shell: a second
  /// status change arriving while the first sheet is still up would bury
  /// the first one's button under the second one's.
  bool _sheetOnScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app is when a resident finds out what an agency
  /// decided while the phone was in a pocket or out of signal - the stored
  /// notifications are read again, and anything unread is announced.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final notifications = context.read<NotificationProvider>();
      unawaited(notifications.ensureSubscribed());
      unawaited(notifications.syncFromServer());
    }
  }

  static String _key(AppNotification n) =>
      '${n.incidentId}:${n.newStatus}:${n.receivedAt.microsecondsSinceEpoch}';

  /// Show the oldest status change nobody has seen a sheet for yet.
  ///
  /// Deferred to after the frame, same as the responder shell's
  /// `_maybeAlert` — opening a sheet from inside build() throws.
  void _maybeAnnounce(NotificationProvider notifications) {
    if (_sheetOnScreen) return;

    AppNotification? found;
    // Oldest first: _unread is newest-first (see NotificationProvider),
    // so a resident who missed two updates reads them in the order they
    // actually happened rather than most-recent-first.
    for (final n in notifications.unread.reversed) {
      if (!_shown.contains(_key(n))) {
        found = n;
        break;
      }
    }
    if (found == null) return;

    final target = found;
    _shown.add(_key(target));
    _sheetOnScreen = true;
    // A warning or a suspension changes what Home says and what the report
    // buttons do. Read the profile again now, not at the next launch.
    if (target.isAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(context.read<ProfileProvider>().loadProfile(force: true));
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final action = await StatusUpdateSheet.show(context, target);
      _sheetOnScreen = false;
      // Seen, so not announced again on the next launch. Every kind that came
      // from the backend has a row to mark (markServerRead does nothing for one
      // that arrived only over realtime and has not been matched to its row).
      if (mounted) {
        unawaited(context.read<NotificationProvider>().markServerRead(target));
      }
      if (mounted) {
        switch (action) {
          case NoticeAction.viewReport:
            await openReportById(context, target.incidentId);
          case NoticeAction.openChat:
            await openReportChatById(context, target.incidentId);
          case NoticeAction.hotlines:
            await context.push('/hotlines');
          case NoticeAction.openAnnouncement:
            if (target.announcementId != null) {
              await context.push('/announcements/${target.announcementId}');
            }
          case NoticeAction.dismiss:
            break;
        }
      }
      // Two notices can be waiting (a rejection and a question, say). Nothing
      // rebuilds this widget when the first one closes, so the next would sit
      // unseen until something else happened to change - look for it now.
      if (mounted) _maybeAnnounce(context.read<NotificationProvider>());
    });
  }

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  /// Built per frame rather than held as a `static const`, because the labels
  /// change with the active locale and a const list is fixed at compile time.
  /// The icons and order are still fixed here — only the words vary.
  static List<_TabItem> _tabsFor(AppLocalizations t) => [
    _TabItem(
      label: t.navHome,
      icon: LucideIcons.house,
      activeIcon: LucideIcons.house,
    ),
    _TabItem(
      label: t.navReports,
      icon: LucideIcons.receipt_text,
      activeIcon: LucideIcons.receipt_text,
    ),
    _TabItem(
      label: t.navMap,
      icon: LucideIcons.map,
      activeIcon: LucideIcons.map,
    ),
    _TabItem(
      label: t.navProfile,
      icon: LucideIcons.user,
      activeIcon: LucideIcons.user,
    ),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tabs = _tabsFor(t);
    final notifications = context.watch<NotificationProvider>();
    _maybeAnnounce(notifications);
    final currentIndex = navigationShell.currentIndex;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final reserved = _navHeight + _navMarginB + bottomInset;
    // Toasts raised from a tab sit above the floating navigation, not under it.
    ZirenToast.shellInset = reserved;

    return Scaffold(
      backgroundColor: kHomeCanvas,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: reserved),
            child: navigationShell,
          ),
          Positioned(
            left: _navMarginH,
            right: _navMarginH,
            bottom: _navMarginB + bottomInset,
            height: _navHeight,
            child: Container(
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                borderRadius: BorderRadius.circular(ZirenTokens.radius20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _NavItem(
                        tab: tabs[i],
                        isActive: i == currentIndex,
                        // Reports carries the unread dot: a status change on
                        // your own report is what you would go there to read.
                        // A safety alert is not about a report: it does not light
                        // the dot on a tab that would not show it.
                        showBadge: i == 1 && notifications.unread.any((n) => !n.isAnnouncement),
                        onTap: () => _onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isActive,
    required this.showBadge,
    required this.onTap,
  });

  final _TabItem tab;
  final bool isActive;
  final bool showBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? ZirenTokens.brandOrange : const Color(0xFF9E9E9E);

    return Semantics(
      button: true,
      selected: isActive,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? tab.activeIcon : tab.icon,
                  size: 23,
                  color: color,
                ),
                if (showBadge)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: ZirenTokens.severityCritical,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ZirenTokens.surfaceCard,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: ZirenTokens.motionBase,
              curve: Curves.easeOut,
              width: isActive ? 20 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: ZirenTokens.brandOrange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
