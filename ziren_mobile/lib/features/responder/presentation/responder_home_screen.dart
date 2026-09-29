import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/network/backend_health.dart';
import '../../../features/auth/domain/auth_provider.dart';
import '../../../features/help/presentation/help_sheet.dart';
import '../../../features/incident_report/domain/incident_provider.dart';
import '../../../features/settings/domain/profile_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/home_kit.dart';
import '../../../shared/widgets/mascot_home_header.dart';
import '../domain/nearby_incident.dart';
import '../domain/responder_incident_model.dart';
import '../domain/responder_notification_provider.dart';
import '../domain/responder_provider.dart';
import '../domain/responder_vocabulary.dart';
import 'responder_reports_screen.dart' show ReportRow;
import 'widgets/nearby_incident_card.dart';
import 'widgets/responder_kit.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Responder Home — the assignment queue.
///
/// Laid out to match the reference responder mockup: a plain identity bar
/// (no photo — tried, but a decorative photo the responder opens dozens of
/// times a shift costs more scroll than it earns in warmth; the treatment
/// stays on Profile, opened far less often), a duty-status card that also
/// carries who is signed in, three figures, three quick-action tiles, a
/// recent-activity feed, then the queue as ranked cards.
///
/// WHY THE BIG DIAL WENT
///
/// This screen used to open with the resident's SOS dial, recoloured — one
/// dominant circular control, on the argument that the app should read as one
/// product. It read as one product and worked as neither. A resident presses
/// the SOS perhaps twice in their life and it must be unmissable; a responder
/// touches the duty switch twice a shift and then spends the rest of it
/// reading the queue. Spending the top third of the screen on the control they
/// touch least pushed the assignments — the actual work — below the fold.
///
/// The prototype gets the proportions right: duty is a ROW that states its
/// state plainly, and the space it gives back goes to the figures and the
/// queue. The switch is still the first thing on the screen, because an
/// off-duty responder receives no assignments and that remains the single most
/// consequential state in the app for them. It is simply no longer the biggest
/// thing on it.
///
/// Ziren's own tokens throughout — the prototype's structure, not its palette.
/// Severity keeps its colour AND its word, and brand orange stays on actions.
class ResponderHomeScreen extends StatefulWidget {
  const ResponderHomeScreen({super.key});

  @override
  State<ResponderHomeScreen> createState() => _ResponderHomeScreenState();
}

enum _ConnectivityMode { unknown, online, offline }

class _ResponderHomeScreenState extends State<ResponderHomeScreen> {
  /// The one nearby card currently sending an answer, so only its own
  /// buttons show a spinner and disable — a slow reply on one card must not
  /// freeze the others.
  String? _answeringNearbyId;

  // The breathing pulse went with the dial. A switch that throbs is a switch
  // that looks broken, and nothing else on this screen is a live indicator.

  /// Anchors the queue section so the stat cells above it can scroll it
  /// into view on tap — the three figures are entirely derived from this
  /// list, so "show me" is the one honest action all three share.
  final _queueSectionKey = GlobalKey();

  /// The top-ranked queue item's id as of the last frame, so a NEW top item
  /// can be told apart from the screen simply rebuilding with the same one.
  String? _lastTopId;

  /// Distinguishes "the queue was empty and a genuinely new incident just
  /// arrived" from "this is the first frame this screen has ever built" —
  /// both look like _lastTopId being null, but only the first should
  /// highlight.
  bool _seenFirstBuild = false;

  /// The id currently being highlighted, or null. Compared by id rather than
  /// tracking "the top card" by position, so the highlight follows the
  /// specific new incident even if the rest of the queue reorders under it.
  String? _highlightedId;
  Timer? _highlightTimer;

  // Same connectivity + location pills as the resident hero banner, ported
  // rather than shared because ResidentHomeScreen's version is private to
  // that file. A responder's own position and the backend's reachability
  // are exactly as relevant mid-shift as a resident's are before reporting.
  _ConnectivityMode _connectivity = _ConnectivityMode.unknown;
  Timer? _connectivityTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static const _pingInterval = Duration(seconds: 30);

  Future<void> _checkConnectivity() async {
    // "Online" means OUR backend answered, not that the phone shows bars — see
    // BackendHealth for the two ways those come apart.
    final mode =
        await BackendHealth.isReachable()
            ? _ConnectivityMode.online
            : _ConnectivityMode.offline;
    if (mounted && mode != _connectivity) {
      setState(() => _connectivity = mode);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ResponderProvider>();
      p.loadQueue();
      // The figure band reads these. There is no Dashboard tab any more — its
      // figures live here now — so this screen is the only thing that loads
      // them, and a responder who never scrolls past the queue still needs
      // them correct at the top.
      p.loadDashboard();
      // The charts are derived from closed incidents. Without this the record
      // section draws an empty week on a responder who has closed plenty.
      p.loadHistory();
      // A responder who was already on duty when the app was killed comes back
      // to duty on restart, so the position reporting has to resume with them
      // rather than waiting for them to toggle the switch off and on again.
      if (p.isOnDuty) p.startLocationReporting();

      // Same warm-up the resident Home does: a fix can take several seconds
      // to tighten, and the hero pill should already have one by the time a
      // responder glances up from the queue.
      final incidents = context.read<IncidentProvider>();
      if (incidents.currentPosition == null) incidents.fetchLocation();
      // Whatever position is already known — refined further once the location
      // ping (started above, if on duty) gets its own fresher fix.
      p.loadNearby(
        lat: incidents.currentPosition?.latitude,
        lng: incidents.currentPosition?.longitude,
      );
      _checkConnectivity();
      _connectivityTimer = Timer.periodic(
        _pingInterval,
        (_) => _checkConnectivity(),
      );
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        final hasNetwork = results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet,
        );
        if (hasNetwork) {
          Future.delayed(const Duration(seconds: 2), _checkConnectivity);
        } else if (mounted && _connectivity != _ConnectivityMode.offline) {
          setState(() => _connectivity = _ConnectivityMode.offline);
        }
      });
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _connectivityTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Turn duty on or off, and start or stop reporting position with it.
  ///
  /// The two are tied together deliberately. An off-duty responder receives no
  /// assignments, so their whereabouts are nobody's business — reporting them
  /// anyway would be tracking a person rather than dispatching a crew, and the
  /// dashboard map filters to on-duty regardless, so the rows would never even
  /// be read.
  ///
  /// The location permission is requested HERE, at the moment someone
  /// deliberately goes on duty, and nowhere else. The periodic ping only ever
  /// checks permission; a system dialog appearing on a two-minute timer, over
  /// whatever the responder happens to be reading, would be an interruption at
  /// the worst possible moment.
  Future<void> _toggleDuty(ResponderProvider provider) async {
    final goingOnDuty = !provider.isOnDuty;

    final ok = await provider.toggleAvailability();
    if (!ok) return;

    if (goingOnDuty) {
      // Not awaited before starting: a responder who declines the prompt is
      // still on duty and still gets assignments. Position reporting is a
      // convenience for the dispatcher's map, never a condition of working.
      await Permission.location.request();
      provider.startLocationReporting();
    } else {
      provider.stopLocationReporting();
    }
  }

  /// Refresh everything this screen now draws.
  ///
  /// It used to reload the queue alone, which was right when the queue was all
  /// that was here. A responder pulling down on a screen showing four figures
  /// and two charts is asking for those to be current too, and leaving them
  /// stale behind a refreshed list is the kind of half-update that makes a
  /// number look wrong rather than old.
  Future<void> _refresh(ResponderProvider p) {
    final pos = context.read<IncidentProvider>().currentPosition;
    return Future.wait([
      p.loadQueue(),
      p.loadDashboard(),
      p.loadHistory(),
      p.loadNearby(lat: pos?.latitude, lng: pos?.longitude),
    ]);
  }

  /// Send an answer for one nearby card, and say what happened.
  ///
  /// Never assigns anything — the dispatcher decides. A failure here means the
  /// alert had already gone stale (dispatched to someone else, or duty/agency
  /// changed underneath it), which ResponderProvider.answerNearby already
  /// drops from the list; the toast is the only thing left to say.
  Future<void> _answerNearby(
    ResponderProvider provider,
    NearbyIncident incident,
    String answer,
  ) async {
    setState(() => _answeringNearbyId = incident.incidentId);
    final pos = context.read<IncidentProvider>().currentPosition;
    final ok = await provider.answerNearby(
      incident.incidentId,
      answer,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    if (!mounted) return;
    setState(() => _answeringNearbyId = null);
    if (!ok) {
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.respAnswerSendFailed)));
    }
  }

  /// Same time-of-day greeting the resident side uses (`homeGreetingMorning`
  /// etc.) — the wording isn't resident-specific, just parameterised by
  /// name, so reusing it keeps the two sides feeling like one product.
  String _greeting(AppLocalizations t, String name) {
    final h = DateTime.now().hour;
    if (h < 12) return t.homeGreetingMorning(name);
    if (h < 18) return t.homeGreetingAfternoon(name);
    return t.homeGreetingEvening(name);
  }

  /// Brings the queue into view — what tapping "Assigned", "Critical", or
  /// "Longest waiting" does. All three figures are counts or facts about
  /// this exact list, so revealing it is the one action that is true for
  /// all three rather than three invented, unrelated destinations.
  void _scrollToQueue() {
    final ctx = _queueSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: ZirenTokens.motionBase,
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  /// Briefly highlights a newly-arrived top-of-queue item.
  ///
  /// Runs from a post-frame callback in build(), never from inside build()
  /// itself — comparing and possibly calling setState synchronously during
  /// build is the standard way to trigger "setState called during build".
  /// A responder looking at Home when a dispatch lands should see something
  /// move, not just a silently incremented number.
  void _maybeHighlightNewTop(String? topId) {
    final isNewArrival =
        _seenFirstBuild && topId != null && _lastTopId != topId;
    if (isNewArrival && mounted) {
      _highlightTimer?.cancel();
      setState(() => _highlightedId = topId);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedId = null);
      });
    }
    _lastTopId = topId;
    _seenFirstBuild = true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<ProfileProvider>().profile;
    final provider = context.watch<ResponderProvider>();
    final notifications = context.watch<ResponderNotificationProvider>();
    // Watched, not read: the hero pill shows the live GPS fix, which
    // arrives asynchronously (see fetchLocation in initState) and has to
    // rebuild the pill as it resolves — same reasoning as the resident Home.
    final incidents = context.watch<IncidentProvider>();
    final locationLabel =
        incidents.locationAddress ??
        (incidents.locationDenied ? t.homeLocationUnknown : t.homeLocating);

    final displayName =
        profile?.fullName.isNotEmpty == true
            ? profile!.fullName
            : (auth.user?.email?.split('@').first ?? 'Responder');

    final onDuty = provider.isOnDuty;
    final queue = provider.queue;

    // Severity first, then oldest first — the same ordering rule the
    // dispatcher console uses, so a responder and a dispatcher looking at
    // the same incident see it in the same position in their list. The
    // comparator lives in ResponderVocabulary now, shared with the alert
    // sheet and the Reports tab, so the three cannot disagree about which
    // call comes next.
    final sorted = ResponderVocabulary.sorted(queue);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHighlightNewTop(sorted.isEmpty ? null : sorted.first.id);
    });

    final criticalCount = queue.where((i) => i.severity == 'critical').length;
    // The big greeting uses the first name only - a full name at 30 px
    // wraps onto a third line on a small phone.
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;

    // Newest-first, closed by when it closed. Capped at four rows — this is
    // a glance at the dashboard, not the record; the full list with filters
    // is what the Reports tab is for.
    final recentActivity = [...provider.history]..sort((a, b) {
      final at = a.resolvedAt ?? a.createdAt;
      final bt = b.resolvedAt ?? b.createdAt;
      return bt.compareTo(at);
    });
    final recentActivityTop = recentActivity.take(4).toList();

    return Scaffold(
      backgroundColor: kHomeCanvas,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: ZirenTokens.brandOrange,
              onRefresh: () => _refresh(provider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Room under the last card for the help button.
                padding: const EdgeInsets.only(
                  bottom: ZirenHelpButton.size + ZirenTokens.space24,
                ),
                children: [
                  // ── Mascot header ─────────────────────────────
                  //
                  // Same layout as the resident Home, with the responder mascot:
                  // tagline, date, greeting, and a message about the queue.
                  MascotHomeHeader(
                    tagline:
                        profile?.agencyName?.isNotEmpty == true
                            ? 'Responder · ${profile!.agencyName}'
                            : 'Responder',
                    hasUnread: notifications.hasUnread,
                    onBellTap: () => context.push('/notifications'),
                    bellLabel: t.homeBellLabel,
                    bellLabelUnread: t.homeBellLabelUnread,
                    displayName: displayName,
                    avatarUrl: profile?.avatarUrl,
                    onProfileTap: () => context.go('/responder/profile'),
                    profileLabel: t.homeProfileButtonLabel,
                    greeting: _greeting(t, firstName),
                    greetingName: firstName,
                    mascot: MascotArt.responder,
                    mascotName: t.mascotName,
                    message:
                        !onDuty
                            ? t.mascotResponderOffDuty(firstName)
                            : queue.isEmpty
                            ? t.mascotResponderReady(firstName)
                            : t.mascotResponderQueue(
                              '${queue.length}',
                              '$criticalCount',
                              firstName,
                            ),
                    locationLabel: locationLabel,
                    connectivityLabel: switch (_connectivity) {
                      _ConnectivityMode.offline => t.homeDeliveryOfflineTitle,
                      _ConnectivityMode.online => t.homeDeliveryOnlineTitle,
                      _ConnectivityMode.unknown => t.homeDeliveryCheckingTitle,
                    },
                    connectivityIcon: switch (_connectivity) {
                      _ConnectivityMode.offline => LucideIcons.wifi_off,
                      _ConnectivityMode.online => LucideIcons.radio_tower,
                      _ConnectivityMode.unknown => LucideIcons.refresh_cw,
                    },
                    connectivityColor: switch (_connectivity) {
                      _ConnectivityMode.offline =>
                        ZirenTokens.connectivityOffline,
                      _ConnectivityMode.online =>
                        ZirenTokens.connectivityOnline,
                      _ConnectivityMode.unknown => ZirenTokens.textMuted,
                    },
                  ),
                  const SizedBox(height: ZirenTokens.space20),

                  // ── Duty status ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kHomeGutter,
                    ),
                    child: Text(
                      'Duty Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  DutyStatusCard(
                    onDuty: onDuty,
                    busy: provider.togglingAvailability,
                    onChanged: (_) => _toggleDuty(provider),
                    displayName: displayName,
                    rank:
                        profile?.badgeId != null
                            ? '#${profile!.badgeId}'
                            : null,
                    agencyLabel: profile?.agencyName,
                    avatarUrl: profile?.avatarUrl,
                    onTap: () => context.go('/responder/profile'),
                  ),

                  // ── The figures ────────────────────────────────
                  //
                  // Every number is one the backend actually reports for THIS
                  // responder — see get_dashboard in responder_service.py, which
                  // scopes every query to assigned_responder_id. None of them is
                  // an agency total: a figure a responder can neither act on nor
                  // affect is a figure that measures them without telling them
                  // anything. Three cells, not the prototype's four — "Duty
                  // Schedule" in the reference design has no backing data (shift
                  // scheduling is not a feature of this product yet), and a
                  // placeholder that never reads anything but "—" is a worse use
                  // of the slot than a number that is real every time. Oldest
                  // waiting replaces the median-response-time cell that used to
                  // sit here: that number answers "how am I doing generally",
                  // which belongs on Reports/Profile, not on the one screen built
                  // for "what needs me right now" — see
                  // docs/specs/2026-09-11-responder-redesign-design.md §4.
                  ResponderStatBand(
                    cells: [
                      ResponderStat(
                        icon: LucideIcons.clipboard_list,
                        value: '${queue.length}',
                        label: t.respStatAssigned,
                        color: ZirenTokens.brandOrange,
                        onTap: queue.isEmpty ? null : _scrollToQueue,
                      ),
                      ResponderStat(
                        icon: LucideIcons.triangle_alert,
                        value: '$criticalCount',
                        label: t.respStatCritical,
                        color: ZirenTokens.severityCritical,
                        onTap: criticalCount == 0 ? null : _scrollToQueue,
                      ),
                      ResponderStat(
                        icon: LucideIcons.hourglass,
                        // Oldest waiting, not median response time — this row is
                        // about what needs attention right now, and a
                        // retrospective "how am I doing" number belongs on
                        // Reports/Profile instead. Null (nothing open) reads as
                        // "—" via ResponderVocabulary.waiting, same as every
                        // other empty figure in this app.
                        value: ResponderVocabulary.waiting(
                          provider.oldestWaitingMinutes,
                        ),
                        label: t.respStatOldest,
                        onTap: queue.isEmpty ? null : _scrollToQueue,
                        color: ZirenTokens.severityHigh,
                      ),
                    ],
                  ),

                  // ── Quick action ───────────────────────────────
                  //
                  // One shortcut, not three. "View My Tasks" used to open the
                  // Reports tab — a bottom-nav icon directly below this — and
                  // "Report Unit Status" used to toggle duty, which is the card
                  // directly above this. Both were shortcuts to something already
                  // one tap away or already on screen; under an alert-glance
                  // read, three saturated colour tiles that mostly duplicate
                  // visible controls cost scan time for no real gain. Only
                  // "Awaiting Dispatch" survives: it is a genuine shortcut,
                  // jumping straight into the worst-ranked open assignment
                  // without a scroll — the same job the deleted
                  // PendingResponseCard used to do. See
                  // docs/specs/2026-09-11-responder-redesign-design.md §4.
                  if (sorted.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kHomeGutter,
                        ZirenTokens.space16,
                        kHomeGutter,
                        0,
                      ),
                      child: ResponderQuickActionTile(
                        icon: LucideIcons.bell_ring,
                        label: t.respHomeAwaitingDispatch,
                        color: ZirenTokens.brandOrange,
                        badgeCount: queue.length,
                        onTap:
                            () => context.push(
                              '/responder/incident/${sorted.first.id}',
                            ),
                      ),
                    ),

                  if (provider.availabilityError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kHomeGutter,
                        ZirenTokens.space12,
                        kHomeGutter,
                        0,
                      ),
                      child: _InlineError(message: provider.availabilityError!),
                    ),

                  // ── Incidents near you ──────────────────────────
                  //
                  // An invitation to help, not a command — nothing here is assigned
                  // to this responder, and answering never bypasses the dispatcher.
                  // See ResponderProvider.loadNearby / app.services.proximity for
                  // the ranking this mirrors. Hidden entirely once empty: an
                  // "all clear" card here would compete with the queue below for a
                  // state that is already the normal one.
                  if (provider.nearby.isNotEmpty) ...[
                    ResponderSectionHeading(t.respNearbyTitle),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kHomeGutter,
                        0,
                        kHomeGutter,
                        ZirenTokens.space10,
                      ),
                      child: Text(
                        t.respNearbySubtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeGutter,
                      ),
                      child: Column(
                        children: [
                          for (final n in provider.nearby) ...[
                            NearbyIncidentCard(
                              incident: n,
                              answering: _answeringNearbyId == n.incidentId,
                              onRespond:
                                  () =>
                                      _answerNearby(provider, n, 'can_respond'),
                              onUnavailable:
                                  () =>
                                      _answerNearby(provider, n, 'unavailable'),
                            ),
                            const SizedBox(height: ZirenTokens.space10),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // ── Recent activity ────────────────────────────
                  //
                  // The reference design's dashboard feed — what has actually
                  // happened lately, closed and current mixed together, newest
                  // first. Reuses ReportRow verbatim from the Reports tab rather
                  // than a second implementation of the same card, so a report
                  // looks identical whichever screen it is seen from.
                  if (recentActivityTop.isNotEmpty) ...[
                    ResponderSectionHeading(
                      t.respHomeRecentActivity,
                      action: t.respHomeViewAll,
                      onAction: () => context.go('/responder/reports'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeGutter,
                      ),
                      child: Column(
                        children: [
                          for (final incident in recentActivityTop) ...[
                            ReportRow(
                              incident: incident,
                              onTap:
                                  () => context.push(
                                    '/responder/incident/${incident.id}',
                                  ),
                            ),
                            const SizedBox(height: ZirenTokens.space10),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // ── Queue ──────────────────────────────────────
                  KeyedSubtree(
                    key: _queueSectionKey,
                    child: ResponderSectionHeading(
                      t.respHomeQueueTitle,
                      action: queue.isEmpty ? null : t.respTabMap,
                      onAction: () => context.go('/responder/map'),
                    ),
                  ),

                  if (provider.loadingQueue && queue.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ZirenTokens.space32,
                      ),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (provider.queueError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeGutter,
                      ),
                      child: _InlineError(message: provider.queueError!),
                    )
                  else if (queue.isEmpty)
                    HomeActivityCard(
                      title:
                          onDuty
                              ? t.respHomeNoAssignmentsTitle
                              : t.respHomeOffDutyTitle,
                      emptyIcon:
                          onDuty ? LucideIcons.circle_check : LucideIcons.moon,
                      emptyTitle:
                          onDuty
                              ? t.respHomeQueueClear
                              : t.respHomeNotAccepting,
                      emptyBody:
                          onDuty
                              ? t.respHomeQueueClearBody
                              : t.respHomeOffDutyBody,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeGutter,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < sorted.length; i++) ...[
                            ResponderQueueCard(
                              // 1-based, and assigned over the SORTED list, so the
                              // number means place in the working order rather
                              // than position in whatever order the API returned.
                              rank: i + 1,
                              incident: sorted[i],
                              color: ResponderVocabulary.color(
                                sorted[i].severity,
                              ),
                              icon: ResponderVocabulary.icon(
                                sorted[i].severity,
                              ),
                              elapsed: ResponderVocabulary.elapsed(
                                sorted[i].createdAt,
                              ),
                              highlighted: sorted[i].id == _highlightedId,
                              onTap:
                                  () => context.push(
                                    '/responder/incident/${sorted[i].id}',
                                  ),
                            ),
                            const SizedBox(height: ZirenTokens.space10),
                          ],
                        ],
                      ),
                    ),

                  // The shift figures (en route/on scene counts, the closed-per-
                  // day chart, severity mix) that used to live here moved out —
                  // see the reference design: Home is the dashboard a responder
                  // checks mid-shift, not the full record of it. That record is
                  // still reachable, just not stacked onto this screen — the
                  // Reports tab ("My Mission Logs") is where it belongs.
                ],
              ),
            ),
          ),
          // ── Ziren help ─────────────────────────────────
          //
          // Bottom-right above the navigation bar; lifted over the shell's
          // "waiting to sync" strip while that is showing.
          Positioned(
            right: kHomeGutter,
            bottom: provider.hasPendingSync ? 64 : ZirenTokens.space16,
            child: ZirenHelpButton(
              label: t.helpButtonLabel,
              onPressed: () => showHelpSheet(context, forResponder: true),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Queue card ──────────────────────────────────────────────────

class ResponderQueueCard extends StatelessWidget {
  const ResponderQueueCard({
    super.key,
    required this.rank,
    required this.incident,
    required this.color,
    required this.icon,
    required this.elapsed,
    required this.onTap,
    this.highlighted = false,
  });

  /// Place in the working order, 1-based. The prototype puts it first on the
  /// card and so does this: it is the only thing on the row that answers
  /// "which of these do I take", and every other field answers "what is it".
  final int rank;
  final ResponderIncidentModel incident;
  final Color color;
  final IconData icon;
  final String elapsed;
  final VoidCallback onTap;

  /// True for ~2s right after this incident became the new top of the queue
  /// while Home was open. Purely visual — never affects ordering or data.
  final bool highlighted;

  /// How full the severity bar runs.
  ///
  /// NOT a score. The prototype draws a percentage here — "AI 97%" — and this
  /// deliberately does not, because no such number exists in Ziren: the rubric
  /// returns a TIER, not a confidence, and printing a made-up percentage beside
  /// a real severity would be the one kind of lie a triage screen cannot
  /// afford. The bar keeps the prototype's shape and reads the tier; the word
  /// beside it says which tier, so the bar never carries the meaning alone.
  double get _fill => switch (incident.severity) {
    'critical' => 1.0,
    'high' => 0.75,
    'medium' => 0.5,
    'low' => 0.28,
    _ => 0.15,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final title =
        incident.reportText.isEmpty
            ? incident.categoryLabel
            : incident.reportText;

    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: AnimatedContainer(
          duration: ZirenTokens.motionBase,
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(ZirenTokens.space10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kCardRadius),
            color:
                highlighted
                    ? color.withValues(alpha: 0.08)
                    : Colors.transparent,
            border: Border.all(
              color:
                  highlighted
                      ? color
                      : ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Rank ────────────────────────────────────────
              SizedBox(
                width: 26,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '#$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: rank == 1 ? color : ZirenTokens.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ZirenTokens.space6),

              // ── Type tile ───────────────────────────────────
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: ZirenTokens.space10),

              // ── The report ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space6),
                        // Severity as a WORD as well as a colour. The console
                        // works to the same rule and for the same reason: a
                        // responder who cannot separate the hues must still be
                        // able to read the tier.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            incident.severity?.toUpperCase() ?? t.respUntriaged,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (incident.sosFlag) ...[
                          const Icon(
                            LucideIcons.megaphone,
                            size: 12,
                            color: ZirenTokens.severityCritical,
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: ZirenTokens.severityCritical,
                            ),
                          ),
                          const SizedBox(width: ZirenTokens.space6),
                        ],
                        Expanded(
                          child: Text(
                            '${incident.locationAddress ?? incident.stationName ?? 'Walang lokasyon'} · $elapsed',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: _fill,
                              minHeight: 4,
                              backgroundColor: ZirenTokens.surfaceRaised,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space8),
                        // The status WORD only. statusLabel carries a call to
                        // action on it — "Dispatched — Respond Now" — which is
                        // right on the detail screen and wrong here: it is
                        // twenty-four characters on a row shared with the
                        // severity bar, and it squeezed the bar down to a stub
                        // on every card. The tail is dropped rather than a
                        // second set of status words being invented, so this
                        // card and the detail screen can never disagree.
                        Text(
                          incident.statusLabel.split(' — ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: ZirenTokens.statusDispatched,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevron_right,
                size: 18,
                color: ZirenTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inline error ────────────────────────────────────────────────

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.severityCriticalBorder),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circle_alert,
            size: 17,
            color: ZirenTokens.systemError,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: ZirenTokens.systemError,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
