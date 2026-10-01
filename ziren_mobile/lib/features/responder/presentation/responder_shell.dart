import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../demo/presentation/demo_anchor.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../data/incident_alarm.dart';
import '../domain/responder_incident_model.dart';
import '../domain/responder_provider.dart';
import '../domain/responder_vocabulary.dart';
import 'incident_alert_screen.dart';
import 'widgets/incoming_report_sheet.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// Responder shell has a different tab set than the Resident shell:
//  0  Queue      /responder/queue
//  1  Reports    /responder/reports
//  2  Map        /responder/map    (reuses existing map screen)
//  3  Profile    /responder/profile
// No SOS FAB — Responders do not file SOS reports.
//
// Queue stays first, not Dashboard. A responder opening this app during a
// shift is looking for what to do next, and the dashboard answers a slower
// question — how the shift is going. Putting the figures in front of the work
// would cost a tap on every single launch to save one on a few.

const double _navBarHeight = 64.0;
const double _navBarMarginH = 16.0;
const double _navBarMarginB = 20.0;

/// STATEFUL, and for one reason: this is the only widget mounted for the whole
/// of a responder's shift, which makes it the only place that can raise the
/// full-screen assignment alert over whatever they happen to be looking at.
/// Everything else here is still stateless in spirit.
class ResponderShell extends StatefulWidget {
  const ResponderShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<ResponderShell> createState() => _ResponderShellState();
}

class _ResponderShellState extends State<ResponderShell>
    with WidgetsBindingObserver {
  /// The ack state ('pending' | 'overdue') this shell last alerted for, per
  /// incident id — not just whether it has ever been alerted.
  ///
  /// A plain "already shown" set (the original design) meant a crew that
  /// dismissed the doorbell without answering was never told again: the
  /// assignment sat unanswered in the queue, silently, for the rest of the
  /// shift. Keying on state instead means a second alert fires exactly once
  /// more, the moment the backend's own deadline flips 'pending' to
  /// 'overdue' — the same clock the dispatcher's board watches (see
  /// [ResponderAck]) — rather than nagging on an arbitrary timer.
  final Map<String, String> _alertedForState = {};

  /// One alert at a time. Two incidents arriving together is rare, and
  /// stacking their alerts would bury the first one's buttons under the
  /// second one's.
  bool _alertOnScreen = false;

  /// The in-app half of the dispatch alarm. See [IncidentAlarm] for why the
  /// app makes a sound of its own when the OS notification already does.
  final IncidentAlarm _alarm = IncidentAlarm();

  /// Rechecks the queue while at least one assignment is still 'pending' —
  /// see [_syncRecheckTimer]. 'overdue' itself is computed by the backend
  /// fresh on every request (see responder_ack.py), not pushed by realtime,
  /// so nothing tells this screen the deadline passed unless it asks again.
  Timer? _recheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ResponderProvider>().startActionQueue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recheckTimer?.cancel();
    _alarm.dispose();
    super.dispose();
  }

  /// Hand the alarm over to the OS when the app leaves the foreground, and
  /// recheck the queue on the way back — the most common way a crew
  /// actually rediscovers an assignment is opening the app again, and
  /// without this the stale queue already in memory would say nothing
  /// changed until the next scheduled recheck.
  ///
  /// [ResponderAlertService] has already raised a full-screen, alarm-usage
  /// notification for this same assignment. If the in-app loop kept running
  /// underneath it, a responder who put the phone down would hear two alarms
  /// at once and be able to silence only one of them — and the one they could
  /// not reach would be this one, playing from a screen they are no longer
  /// looking at. Foreground: this. Background: the notification.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _alarm.stop();
      return;
    }
    context.read<ResponderProvider>().loadQueue();
  }

  /// Starts or stops the periodic recheck to match whether one is needed.
  ///
  /// Anchored to "is anything still pending" rather than running forever:
  /// an off-duty responder, or one with a clear queue, has nothing this
  /// timer could ever discover.
  void _syncRecheckTimer(ResponderProvider provider) {
    final anyPending = provider.queue.any(
      (i) => i.needsAnswer && i.ack.state == 'pending',
    );
    if (anyPending && _recheckTimer == null) {
      _recheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        context.read<ResponderProvider>().loadQueue();
      });
    } else if (!anyPending && _recheckTimer != null) {
      _recheckTimer?.cancel();
      _recheckTimer = null;
    }
  }

  /// Announce an assignment nobody has answered.
  ///
  /// The sheet is the doorbell and [IncidentAlertScreen] is the answer — see
  /// [IncomingReportSheet] for why those are two different things. Both are
  /// deferred to after the frame because navigating from inside build()
  /// throws.
  void _maybeAlert(ResponderProvider provider) {
    _syncRecheckTimer(provider);
    if (_alertOnScreen) return;

    // Worst first, then oldest — the same order the queue is worked in. When
    // two assignments are waiting, announcing whichever the server happened to
    // return first would be arbitrary at precisely the moment it matters.
    ResponderIncidentModel? found;
    for (final candidate in ResponderVocabulary.sorted(provider.queue)) {
      if (candidate.needsAnswer &&
          _alertedForState[candidate.id] != candidate.ack.state) {
        found = candidate;
        break;
      }
    }
    if (found == null) return;

    final target = found;
    _alertedForState[target.id] = target.ack.state;
    _alertOnScreen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      _alarm.start();
      final choice = await IncomingReportSheet.show(context, target);
      // Silenced either way. Whether they open it or not, they have now been
      // told; a loop that outlived the telling would only train them to mute
      // the phone before a shift.
      await _alarm.stop();

      if (choice == IncomingReportChoice.view && mounted) {
        final accepted = await Navigator.of(
          context,
          rootNavigator: true,
        ).push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder:
                (_) => IncidentAlertScreen(
                  incident: target,
                  // The OS notification is `ongoing` with FLAG_INSISTENT, so
                  // it keeps sounding until something cancels it. An alarm
                  // still going after the crew has answered teaches them to
                  // silence the phone, which is the one habit this feature
                  // cannot survive.
                  onDismissed: () => provider.onAlertAnswered?.call(target.id),
                ),
          ),
        );
        // The alert closes itself on either answer. Without a word here the
        // crew is left on the home tab with no sign the answer went through.
        if (accepted != null && mounted) {
          final t = AppLocalizations.of(context);
          final messenger = ScaffoldMessenger.of(context);
          if (accepted) {
            ZirenToast.success(messenger, t.respAccepted);
          } else {
            ZirenToast.notice(
              messenger,
              t.respDeclineSent,
              icon: LucideIcons.undo_2,
            );
          }
        }
      }

      if (mounted) _alertOnScreen = false;
    });
  }

  static List<_TabItem> _tabsFor(AppLocalizations t) => [
    // "Home", not "Queue". The tab is the first thing a responder lands on
    // and it now carries more than a list — duty state, their figures, and
    // any assignment still waiting to be answered. "Queue" described only the
    // list that used to be all it held.
    //
    // The ROUTE stays /responder/queue. Renaming it would ripple through the
    // shell branch keys, the router and every context.go() that targets it,
    // for no gain a responder can see.
    _TabItem(
      label: t.respTabHome,
      icon: LucideIcons.house,
      activeIcon: LucideIcons.house,
    ),
    // Reports, not Stats. The figures this tab used to hold are on Home
    // now; what lives here is the record — every report a dispatcher has
    // sent this responder, open and closed. A clipboard rather than a
    // rising-graph icon, because the tab is a list of work and not a
    // performance readout.
    _TabItem(
      label: t.respTabReports,
      icon: LucideIcons.clipboard_list,
      activeIcon: LucideIcons.clipboard_list,
    ),
    _TabItem(
      label: t.respTabMap,
      icon: LucideIcons.map,
      activeIcon: LucideIcons.map,
    ),
    _TabItem(
      label: t.respTabProfile,
      icon: LucideIcons.user,
      activeIcon: LucideIcons.user,
    ),
  ];

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tabs = _tabsFor(t);
    final provider = context.watch<ResponderProvider>();
    _maybeAlert(provider);
    final currentIndex = widget.navigationShell.currentIndex;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final navBarTotalH = _navBarHeight + _navBarMarginB + bottomPadding;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: navBarTotalH),
            child: widget.navigationShell,
          ),

          // ── Waiting to sync ────────────────────────────────
          //
          // A crew that accepted a call in a dead zone needs to see that the
          // tap was KEPT. Without this the app looks identical whether the
          // acceptance reached the dispatcher or vanished into a failed
          // request — and the rational response to that ambiguity is to press
          // it again, which is how one acceptance becomes four.
          if (provider.hasPendingSync)
            Positioned(
              left: _navBarMarginH,
              right: _navBarMarginH,
              bottom: navBarTotalH + ZirenTokens.space8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space12,
                  vertical: ZirenTokens.space8,
                ),
                decoration: BoxDecoration(
                  color: ZirenTokens.systemWarningBg,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  border: Border.all(
                    color: ZirenTokens.systemWarning.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.cloud_off,
                      size: 16,
                      color: ZirenTokens.systemWarning,
                    ),
                    const SizedBox(width: ZirenTokens.space8),
                    Expanded(
                      child: Text(
                        t.respSyncPending(provider.pendingSyncCount),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ZirenTokens.systemWarning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Floating pill nav bar ──────────────────────────
          Positioned(
            left: _navBarMarginH,
            right: _navBarMarginH,
            bottom: _navBarMarginB + bottomPadding,
            height: _navBarHeight,
            child: Container(
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                borderRadius: BorderRadius.circular(ZirenTokens.radius24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(tabs.length, (i) {
                  final isActive = i == currentIndex;
                  // Show badge on Queue tab when there are active incidents
                  final showBadge = i == 0 && provider.activeCount > 0;
                  // Expanded, not a fixed width. _NavItem used to size itself
                  // to 80px, which was fine for three tabs and overflows the
                  // moment there are four: 4 x 80 is 320px, and the pill has
                  // 312px of usable width on a 360dp handset. The failure is a
                  // yellow-and-black overflow stripe across the nav bar on the
                  // most common phone size in the field, and it would not have
                  // shown up on a tablet or a wide emulator.
                  return Expanded(
                    child: DemoAnchor(
                      id:
                          const [
                            'rnav.home',
                            'rnav.reports',
                            'rnav.map',
                            'rnav.profile',
                          ][i],
                      child: _NavItem(
                        tab: tabs[i],
                        isActive: isActive,
                        badgeCount: showBadge ? provider.activeCount : null,
                        onTap: () => _onTap(i),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single nav item ───────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
    this.badgeCount,
  });

  final _TabItem tab;
  final bool isActive;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? ZirenTokens.brandOrange : const Color(0xFFB0AFAC);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        // Fills whatever slot the Row gives it — see the Expanded above.
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: isActive ? 24 : 0,
              height: 3,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: ZirenTokens.brandOrange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    isActive ? tab.activeIcon : tab.icon,
                    key: ValueKey(isActive),
                    size: 22,
                    color: color,
                  ),
                ),
                if (badgeCount != null && badgeCount! > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: ZirenTokens.severityCritical,
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius32,
                        ),
                        border: Border.all(
                          color: ZirenTokens.surfaceCard,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: color,
                letterSpacing: 0.1,
              ),
              // maxLines + ellipsis rather than letting the label wrap. At
              // four tabs on a narrow phone a slot is about 68px; a wrapped
              // second line pushes the Column past the 64px bar and overflows
              // vertically instead of horizontally, which is not an
              // improvement.
              child: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────

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
