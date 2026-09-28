import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/backend_health.dart';
import '../../../features/auth/domain/auth_provider.dart';
import '../../../features/incident_report/domain/incident_category_style.dart';
import '../../../features/incident_report/domain/incident_provider.dart';
import '../../../features/notifications/domain/notification_provider.dart';
import '../../../features/settings/domain/profile_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/verification_banner.dart';
import '../../../shared/widgets/home_kit.dart';
import '../../../shared/widgets/home_surface.dart';
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
      final incidents = context.read<IncidentProvider>();
      incidents.loadMyIncidents();
      // Warmed up here rather than only when the report screen opens: a GPS
      // fix can take several seconds to tighten, and a resident often
      // spends a few seconds on Home before tapping a category. Starting
      // the request now means a precise fix is more likely already ready
      // by the time they need one.
      if (incidents.currentPosition == null) incidents.fetchLocation();
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
          Future.delayed(const Duration(seconds: 2), () {
            _checkConnectivity();
            if (mounted) {
              final p = context.read<IncidentProvider>();
              if (p.incidentsError != null) p.loadMyIncidents();
            }
          });
        } else {
          if (mounted && _connectivity != _ConnectivityMode.offline) {
            setState(() => _connectivity = _ConnectivityMode.offline);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// One tap on a category tile: set it, then go straight to the quick
  /// report's confirm screen. Deliberately not the full wizard — the
  /// category was the question the wizard opens with, and it has already
  /// been answered.
  void _report(IncidentCategory category) {
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
        (incidents.locationDenied
            ? registeredLabel
            : t.homeLocating);

    return Scaffold(
      backgroundColor: kHomeCanvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ZirenTokens.brandOrange,
          onRefresh:
              () => Future.wait([
                incidents.loadMyIncidents(),
                _checkConnectivity(),
              ]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: ZirenTokens.space24),
            children: [
              // ── Identity banner ──────────────────────────────
              //
              // Connectivity rides beside the location pill here rather
              // than as its own band — this is the one claim the product
              // has to land in the first seconds (it still works when the
              // network does not), so it stays visible up top, just
              // smaller than the old full-width strip.
              HomeHeroBanner(
                hasUnread: notifications.hasUnread,
                onBellTap: () => context.push('/notifications'),
                bellLabel: t.homeBellLabel,
                bellLabelUnread: t.homeBellLabelUnread,
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
                  // Neutral grey, not red: this is a plain status, and a
                  // steady grey reads calmer under time pressure than an
                  // alarm colour for something the resident cannot fix from
                  // this screen anyway.
                  _ConnectivityMode.offline => ZirenTokens.connectivityOffline,
                  _ConnectivityMode.online => ZirenTokens.connectivityOnline,
                  _ConnectivityMode.unknown => Colors.white,
                },
              ),

              // ── Greeting ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space20,
                  kHomeGutter,
                  ZirenTokens.space16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(t, displayName),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.homeStayAlertBody,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Report an Emergency (uncategorised) ──────────
              EmergencyCtaCard(
                title: t.homeReportCtaTitle,
                subtitle: t.homeReportCtaSubtitle,
                badge: t.homeReportCtaBadge,
                onTap: () => context.push('/sos-confirm'),
              ),

              const SizedBox(height: ZirenTokens.space20),

              // ── Category grid ─────────────────────────────────
              QuickActionGrid(
                actions: [
                  QuickAction(
                    icon: LucideIcons.flame,
                    label: t.categoryFireShort,
                    semanticLabel: t.homeReportAction(t.categoryFireShort),
                    color: IncidentCategoryStyle.color(IncidentCategory.fire),
                    onTap: () => _report(IncidentCategory.fire),
                  ),
                  QuickAction(
                    icon: LucideIcons.stethoscope,
                    label: t.categoryMedicalShort,
                    semanticLabel: t.homeReportAction(t.categoryMedicalShort),
                    color: IncidentCategoryStyle.color(
                      IncidentCategory.medicalTrauma,
                    ),
                    onTap: () => _report(IncidentCategory.medicalTrauma),
                  ),
                  QuickAction(
                    icon: LucideIcons.car,
                    label: t.categoryAccidentShort,
                    semanticLabel: t.homeReportAction(t.categoryAccidentShort),
                    color: IncidentCategoryStyle.color(
                      IncidentCategory.vehicular,
                    ),
                    onTap: () => _report(IncidentCategory.vehicular),
                  ),
                  QuickAction(
                    icon: LucideIcons.shield,
                    label: t.categoryCrimeShort,
                    semanticLabel: t.homeReportAction(t.categoryCrimeShort),
                    color: IncidentCategoryStyle.color(
                      IncidentCategory.domesticDisputeCrime,
                    ),
                    onTap: () => _report(IncidentCategory.domesticDisputeCrime),
                  ),
                  // One category covers flood, landslide and storm damage in
                  // the backend, so it is one tile in the grid.
                  QuickAction(
                    icon: LucideIcons.droplet,
                    label: t.categoryCalamityShort,
                    semanticLabel: t.homeReportAction(t.categoryCalamityShort),
                    color: IncidentCategoryStyle.color(
                      IncidentCategory.floodLandslideCalamity,
                    ),
                    onTap:
                        () => _report(IncidentCategory.floodLandslideCalamity),
                  ),
                  QuickAction(
                    icon: LucideIcons.ellipsis,
                    label: t.categoryOtherShort,
                    semanticLabel: t.homeReportAction(t.categoryOtherShort),
                    color: IncidentCategoryStyle.color(IncidentCategory.other),
                    onTap: () => _report(IncidentCategory.other),
                  ),
                ],
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
                  padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
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
    );
  }
}

enum _ConnectivityMode { unknown, online, offline }
