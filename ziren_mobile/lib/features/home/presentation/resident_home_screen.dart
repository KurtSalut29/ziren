import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/backend_health.dart';
import '../../../features/announcements/presentation/active_alerts_card.dart';
import '../../../features/auth/domain/auth_provider.dart';
import '../../../features/demo/presentation/demo_anchor.dart';
import '../../../features/hotlines/data/hotlines_store.dart';
import '../../../features/help/presentation/help_sheet.dart';
import '../../../features/hotlines/presentation/hotlines_view.dart';
import '../../../features/incident_report/domain/incident_category_style.dart';
import '../../../features/incident_report/domain/incident_provider.dart';
import '../../../features/notifications/domain/notification_provider.dart';
import '../../../features/settings/domain/profile_provider.dart';
import '../../../features/weather/data/weather_store.dart';
import '../../../features/weather/domain/weather_advice.dart';
import '../../../features/weather/presentation/weather_card.dart';
import '../../../features/weather/presentation/weather_words.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/suspension_banner.dart';
import '../../../shared/widgets/verification_banner.dart';
import '../../../shared/widgets/home_kit.dart';
import '../../../shared/widgets/home_surface.dart';
import '../../../shared/widgets/mascot_home_header.dart';
import '../../demo/presentation/welcome_demo.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Resident Home.
///
/// One screen, top to bottom: an identity banner, a greeting, the one
/// uncategorised emergency action, six one-tap report categories, and
/// recent activity.
///
/// The uncategorised emergency action is never demoted below the fold: it
/// is the path for someone who cannot classify what is happening, and it
/// keeps the same priority the SOS dial gave it before this screen's
/// restyle — see [EmergencyCtaCard].
class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen> {
  _ConnectivityMode _connectivity = _ConnectivityMode.unknown;
  Timer? _connectivityTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Session-scoped, deliberately not persisted. Dismissing means "not right
  /// now", not "never ask again" — the banner is the only route back into
  /// verification for someone who skipped it at signup.
  bool _verificationDismissed = false;

  /// Whether the new-account greeting has been considered on this Home.
  bool _welcomeChecked = false;

  final _alertsKey = GlobalKey<ActiveAlertsCardState>();

  static const _pingInterval = Duration(seconds: 30);

  Future<void> _checkConnectivity() async {
    // "Online" means OUR backend answered, not that the phone shows bars — see
    // BackendHealth for the two ways those come apart.
    var reachable = await BackendHealth.isReachable();
    // One miss while online is usually the phone handing over between mobile
    // data and wifi, not a lost connection: ask once more before saying so.
    // Without this, Home (and Ziren on it) flipped to "no internet" for a few
    // seconds every time wifi came back.
    if (!reachable && _connectivity == _ConnectivityMode.online) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      reachable = await BackendHealth.isReachable();
    }
    final mode =
        reachable ? _ConnectivityMode.online : _ConnectivityMode.offline;
    if (mounted && mode != _connectivity) {
      setState(() => _connectivity = mode);
    }
  }

  /// The OS said "no network". During a handover it says that for a moment
  /// too, so look again shortly before showing the offline state.
  void _confirmNoNetwork() {
    Future<void>.delayed(const Duration(milliseconds: 1500), () async {
      final now = await Connectivity().checkConnectivity();
      final stillNone =
          !now.any(
            (r) =>
                r == ConnectivityResult.wifi ||
                r == ConnectivityResult.mobile ||
                r == ConnectivityResult.ethernet,
          );
      if (stillNone && mounted && _connectivity != _ConnectivityMode.offline) {
        setState(() => _connectivity = _ConnectivityMode.offline);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WeatherStore.instance.addListener(_onWeather);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final incidents = context.read<IncidentProvider>();
      incidents.loadMyIncidents();
      // Warmed up here rather than only when the report screen opens: a GPS
      // fix can take several seconds to tighten, and a resident often
      // spends a few seconds on Home before tapping a category. Starting
      // the request now means a precise fix is more likely already ready
      // by the time they need one.
      final located =
          incidents.currentPosition == null
              ? incidents.fetchLocation()
              : Future<void>.value();
      // The forecast is for where the resident is, so it waits for the fix
      // (or its failure: no fix means the forecast for Naval).
      _refreshWeather(after: located);
      // Refreshes the saved copy of the station numbers while there is still
      // a connection, so the offline list is as current as it can be.
      HotlinesStore.instance.refresh();
      _checkConnectivity();
      _connectivityTimer = Timer.periodic(_pingInterval, (_) {
        _checkConnectivity();
        // Throttled by the store (every 15 minutes at most).
        _refreshWeather();
      });

      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        final hasNetwork = results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet,
        );
        if (hasNetwork) {
          Future.delayed(const Duration(seconds: 2), () {
            _checkConnectivity();
            if (mounted) {
              final p = context.read<IncidentProvider>();
              if (p.incidentsError != null) p.loadMyIncidents();
              if (WeatherStore.instance.failed) _refreshWeather();
            }
          });
        } else {
          _confirmNoNetwork();
        }
      });
    });
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _connectivitySub?.cancel();
    WeatherStore.instance.removeListener(_onWeather);
    super.dispose();
  }

  /// Ziren's message on top reads the forecast too, so Home redraws with it.
  void _onWeather() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshWeather({
    Future<void>? after,
    bool force = false,
  }) async {
    if (after != null) {
      try {
        await after;
      } catch (_) {}
    }
    if (!mounted) return;
    final pos = context.read<IncidentProvider>().currentPosition;
    await WeatherStore.instance.refresh(
      lat: pos?.latitude,
      lng: pos?.longitude,
      force: force,
    );
  }

  /// One tap on a category tile: set it, then go straight to the quick
  /// report's confirm screen. Deliberately not the full wizard — the
  /// category was the question the wizard opens with, and it has already
  /// been answered.
  Future<void> _report(IncidentCategory category) async {
    // No connection to Ziren: a report cannot go anywhere, so the category
    // opens the numbers of the stations that handle it instead — BFP for a
    // fire, PNP for a crime, MDRRMO for the rest. A call needs only signal.
    if (_connectivity == _ConnectivityMode.offline) {
      showHotlinesSheet(context, category: category, offline: true);
      return;
    }
    // A suspended account's report is refused by the server. Say so here,
    // before the wizard, not after they have described an emergency.
    if (await refuseIfSuspended(context)) return;
    if (!mounted) return;
    context.read<IncidentProvider>()
      ..clearWizard()
      ..setCategory(category);
    context.push('/report/quick');
  }

  String _greeting(AppLocalizations t, String name) {
    final h = DateTime.now().hour;
    if (h < 12) return t.homeGreetingMorning(name);
    if (h < 18) return t.homeGreetingAfternoon(name);
    return t.homeGreetingEvening(name);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<ProfileProvider>().profile;
    // Watched, not read: the hero pill now shows the live GPS fix, which
    // arrives asynchronously (see fetchLocation in initState) and has to
    // rebuild the pill as it resolves.
    final incidents = context.watch<IncidentProvider>();
    final notifications = context.watch<NotificationProvider>();

    final displayName =
        profile?.fullName.isNotEmpty == true
            ? profile!.fullName
            : (auth.user?.email?.split('@').first ??
                t.homeResidentFallbackName);

    // The big greeting uses the first name only - a full name at 30 px
    // wraps onto a third line on a small phone.
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;

    // A new account's first visit: Ziren says hi and offers the demo
    // (WelcomeDemo decides whether this account is new and not yet asked).
    // Waits for the profile, so the greeting has the real first name.
    if (!_welcomeChecked && profile != null) {
      _welcomeChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          WelcomeDemo.maybeGreet(
            context,
            responder: false,
            firstName: firstName,
          );
        }
      });
    }

    final barangay = profile?.barangay;
    // Falls back to the registered profile barangay — never to nothing —
    // but that fallback is exactly the bug this replaces if it is ever the
    // steady state: a resident standing somewhere else was seeing their
    // registered address here, not where they actually were. Live GPS is
    // now the first choice; the registered barangay is only what shows
    // while a fix is still resolving or permission was refused.
    final registeredLabel =
        barangay?.isNotEmpty == true
            ? (barangay!.toLowerCase().startsWith('brgy')
                ? barangay
                : t.homeBarangay(barangay))
            : t.homeLocationUnknown;
    final locationLabel =
        incidents.locationAddress ??
        (incidents.locationDenied ? registeredLabel : t.homeLocating);

    return Scaffold(
      backgroundColor: kHomeCanvas,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: ZirenTokens.brandOrange,
              onRefresh:
                  () => Future.wait([
                    incidents.loadMyIncidents(),
                    _checkConnectivity(),
                    if (_alertsKey.currentState != null)
                      _alertsKey.currentState!.reload(),
                    _refreshWeather(force: true),
                  ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Room under the last card for the help button, so it never
                // covers anything the resident has to read or tap.
                padding: const EdgeInsets.only(
                  bottom: ZirenHelpButton.size + ZirenTokens.space24,
                ),
                children: [
                  // ── Mascot header ─────────────────────────────
                  //
                  // Tagline, date, a large greeting, and Ziren speaking to the
                  // resident. Connectivity still rides at the top (under the
                  // mascot's message): the app working without the network is
                  // the one claim that has to land in the first seconds.
                  MascotHomeHeader(
                    tagline: t.welcomeTagline,
                    hasUnread: notifications.hasUnread,
                    onBellTap: () => context.push('/notifications'),
                    bellLabel: t.homeBellLabel,
                    bellLabelUnread: t.homeBellLabelUnread,
                    displayName: displayName,
                    avatarUrl: profile?.avatarUrl,
                    onProfileTap: () => context.go('/profile'),
                    profileLabel: t.homeProfileButtonLabel,
                    greeting: _greeting(t, firstName),
                    greetingName: firstName,
                    offline: _connectivity == _ConnectivityMode.offline,
                    mascotName: t.mascotName,
                    message: _mascotMessage(t, incidents, firstName),
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
                      // Neutral grey, not red: a plain status the resident
                      // cannot fix from this screen anyway.
                      _ConnectivityMode.offline =>
                        ZirenTokens.connectivityOffline,
                      _ConnectivityMode.online =>
                        ZirenTokens.connectivityOnline,
                      _ConnectivityMode.unknown => ZirenTokens.textMuted,
                    },
                  ),
                  const SizedBox(height: ZirenTokens.space20),

                  // ── A safety alert for where they live ──────────
                  //
                  // Above the report button: an evacuation order for your
                  // barangay is the most important thing on this screen that day,
                  // and "are you safe?" is answered right here. Draws nothing on
                  // an ordinary day. Read again whenever a new alert notice lands.
                  DemoAnchor(
                    id: 'home.alerts',
                    child: ActiveAlertsCard(
                      key: _alertsKey,
                      refreshKey:
                          notifications.unread
                              .where((n) => n.isAnnouncement)
                              .length,
                    ),
                  ),

                  // ── Report an Emergency (uncategorised) ──────────
                  DemoAnchor(
                    id: 'home.sos',
                    child: EmergencyCtaCard(
                      title: t.homeReportCtaTitle,
                      subtitle: t.homeReportCtaSubtitle,
                      badge: t.homeReportCtaBadge,
                      onTap: () async {
                        if (_connectivity == _ConnectivityMode.offline) {
                          showHotlinesSheet(context, offline: true);
                          return;
                        }
                        if (await refuseIfSuspended(context)) return;
                        if (!context.mounted) return;
                        context.push('/sos-confirm');
                      },
                    ),
                  ),

                  // ── Suspended from reporting ───────────────────
                  //
                  // Directly under the button it disables, so the two are read
                  // together. Draws nothing for an account in good standing.
                  if (context.watch<ProfileProvider>().profile?.isSuspended ??
                      false) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: kHomeGutter),
                      child: SuspensionBanner(),
                    ),
                  ],

                  if (_connectivity == _ConnectivityMode.offline) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeGutter,
                      ),
                      child: _OfflineCallHint(text: t.homeOfflineCallHint),
                    ),
                  ],

                  const SizedBox(height: ZirenTokens.space20),

                  // ── Category grid ─────────────────────────────────
                  DemoAnchor(
                    id: 'home.categories',
                    child: QuickActionGrid(
                      actions: [
                        QuickAction(
                          icon: LucideIcons.flame,
                          label: t.categoryFireShort,
                          semanticLabel: t.homeReportAction(
                            t.categoryFireShort,
                          ),
                          color: IncidentCategoryStyle.color(
                            IncidentCategory.fire,
                          ),
                          onTap: () => _report(IncidentCategory.fire),
                        ),
                        QuickAction(
                          icon: LucideIcons.stethoscope,
                          label: t.categoryMedicalShort,
                          semanticLabel: t.homeReportAction(
                            t.categoryMedicalShort,
                          ),
                          color: IncidentCategoryStyle.color(
                            IncidentCategory.medicalTrauma,
                          ),
                          onTap: () => _report(IncidentCategory.medicalTrauma),
                        ),
                        QuickAction(
                          icon: LucideIcons.car,
                          label: t.categoryAccidentShort,
                          semanticLabel: t.homeReportAction(
                            t.categoryAccidentShort,
                          ),
                          color: IncidentCategoryStyle.color(
                            IncidentCategory.vehicular,
                          ),
                          onTap: () => _report(IncidentCategory.vehicular),
                        ),
                        QuickAction(
                          icon: LucideIcons.shield,
                          label: t.categoryCrimeShort,
                          semanticLabel: t.homeReportAction(
                            t.categoryCrimeShort,
                          ),
                          color: IncidentCategoryStyle.color(
                            IncidentCategory.domesticDisputeCrime,
                          ),
                          onTap:
                              () => _report(
                                IncidentCategory.domesticDisputeCrime,
                              ),
                        ),
                        // One category covers flood, landslide and storm damage in
                        // the backend, so it is one tile in the grid.
                        QuickAction(
                          icon: LucideIcons.droplet,
                          label: t.categoryCalamityShort,
                          semanticLabel: t.homeReportAction(
                            t.categoryCalamityShort,
                          ),
                          color: IncidentCategoryStyle.color(
                            IncidentCategory.floodLandslideCalamity,
                          ),
                          onTap:
                              () => _report(
                                IncidentCategory.floodLandslideCalamity,
                              ),
                        ),
                        QuickAction(
                          icon: LucideIcons.ellipsis,
                          label: t.categoryOtherShort,
                          semanticLabel: t.homeReportAction(
                            t.categoryOtherShort,
                          ),
                          color: IncidentCategoryStyle.color(
                            IncidentCategory.other,
                          ),
                          onTap: () => _report(IncidentCategory.other),
                        ),
                      ],
                    ),
                  ),

                  // ── Weather ─────────────────────────────────────
                  //
                  // Below the report actions, never above them: the forecast is
                  // for planning the day, the tiles are for an emergency now.
                  // Ziren's top message already carries the one line that
                  // matters (rain at 3 PM, dangerous heat); this is the detail.
                  const SizedBox(height: ZirenTokens.space16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kHomeGutter,
                    ),
                    child: DemoAnchor(
                      id: 'home.weather',
                      child: WeatherCard(store: WeatherStore.instance),
                    ),
                  ),

                  // ── Station hotlines ─────────────────────────────
                  //
                  // Always here, not only offline: a resident should already know
                  // where the numbers are before the day the network is down.
                  const SizedBox(height: ZirenTokens.space16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kHomeGutter,
                    ),
                    child: DemoAnchor(
                      id: 'home.hotlines',
                      child: _HotlinesCard(
                        title: t.hotlinesHomeCardTitle,
                        body: t.hotlinesHomeCardBody,
                        onTap: () => context.push('/hotlines'),
                      ),
                    ),
                  ),

                  // ── Verification nudge ─────────────────────────
                  //
                  // Below the emergency action, never above it. This is a chore
                  // the app is asking of someone; it does not get to sit between
                  // a person and the report button. Dismissable for the session,
                  // because a nudge that cannot be silenced becomes noise the
                  // user learns to scroll past.
                  if (!_verificationDismissed) ...[
                    const SizedBox(height: ZirenTokens.space20),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kHomeGutter,
                      ),
                      child: VerificationBanner(
                        onDismiss:
                            () => setState(() => _verificationDismissed = true),
                      ),
                    ),
                  ],

                  const SizedBox(height: ZirenTokens.space24),
                ],
              ),
            ),
          ),
          // ── Ziren help ─────────────────────────────────
          //
          // Bottom-right, just above the navigation bar (the shell already
          // lifts this screen clear of it): "How to use Ziren" as a modal.
          Positioned(
            right: kHomeGutter,
            bottom: ZirenTokens.space16,
            child: DemoAnchor(
              id: 'home.help',
              child: ZirenHelpButton(
                label: t.helpButtonLabel,
                onPressed: () => showHelpSheet(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the mascot says: what the resident can do right now, or how their
  /// reports are doing.
  String _mascotMessage(
    AppLocalizations t,
    IncidentProvider incidents,
    String name,
  ) {
    if (_connectivity == _ConnectivityMode.offline) {
      return t.mascotResidentOffline;
    }
    final mine = incidents.myIncidents;
    final open =
        mine
            .where((i) => i.status != 'resolved' && i.status != 'cancelled')
            .length;
    // A report still in progress comes first: it is the resident's own
    // emergency. Then the weather, which is what Ziren knows about today.
    if (open > 0) return t.mascotResidentOpen('$open', name);
    final forecast = WeatherStore.instance.forecast;
    if (forecast != null) {
      final advice = WeatherAdvice.from(forecast, DateTime.now());
      return WeatherWords(
        t,
        Localizations.localeOf(context).toLanguageTag(),
      ).headline(advice.headline, name);
    }
    if (mine.isEmpty) return t.mascotResidentIntro(name);
    return t.mascotResidentThanks('${mine.length}', name);
  }
}

enum _ConnectivityMode { unknown, online, offline }

/// Shown under the report button while offline: says what the tiles do now.
class _OfflineCallHint extends StatelessWidget {
  const _OfflineCallHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.phone_call,
            size: 18,
            color: ZirenTokens.systemWarning,
          ),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotlinesCard extends StatelessWidget {
  const _HotlinesCard({
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZirenTokens.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        side: BorderSide(color: ZirenTokens.surfaceBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ZirenTokens.systemSuccess.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.phone,
                  size: 20,
                  color: ZirenTokens.systemSuccess,
                ),
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: ZirenTokens.textSecondary,
                      ),
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
