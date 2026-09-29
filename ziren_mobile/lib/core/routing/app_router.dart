import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/domain/auth_provider.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/pending_approval_screen.dart';
import '../../features/assistant/presentation/ziren_ai_screen.dart';
import '../../features/announcements/presentation/announcements_screen.dart';
import '../../features/help/presentation/help_screen.dart';
import '../../features/hotlines/presentation/hotlines_view.dart';
import '../../features/safety/presentation/safety_guide_screen.dart';
import '../../features/onboarding/presentation/consent_screen.dart';
import '../../features/onboarding/presentation/language_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/registration/presentation/step_address_screen.dart';
import '../../features/registration/presentation/step_contact_screen.dart';
import '../../features/registration/presentation/step_id_capture_screen.dart';
import '../../features/registration/presentation/step_id_type_screen.dart';
import '../../features/registration/presentation/step_personal_screen.dart';
import '../../features/registration/presentation/step_responder_screen.dart';
import '../../features/registration/presentation/step_review_screen.dart';
import '../../features/registration/presentation/step_role_screen.dart';
import '../../features/registration/presentation/step_selfie_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/home/presentation/resident_home_screen.dart';
import '../../features/incident_report/presentation/my_reports_screen.dart';
import '../../features/incident_report/presentation/pick_incident_location_screen.dart';
import '../../features/incident_report/presentation/quick_report_confirm_screen.dart';
import '../../features/incident_report/presentation/quick_report_review_screen.dart';
import '../../features/incident_report/presentation/speech_diagnostic_screen.dart';
import '../../features/incident_report/presentation/station_selector_screen.dart';
import '../../features/incident_report/presentation/wizard_review_screen.dart';
import '../../features/incident_report/presentation/wizard_report_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/responder/presentation/responder_reports_screen.dart';
import '../../features/responder/presentation/responder_home_screen.dart';
import '../../features/responder/presentation/responder_incident_detail_screen.dart';
import '../../features/responder/presentation/responder_profile_screen.dart';
import '../../features/responder/presentation/responder_shell.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/verify_account_screen.dart';
import '../../features/sos/presentation/sos_confirm_screen.dart';
import '../../features/sos/presentation/sos_success_screen.dart';
import '../../shared/theme/app_tokens.dart';
import '../../shared/widgets/main_shell.dart';
import '../../features/incident_report/presentation/report_confirm_screen.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// Root navigator key so StatefulShellRoute pushes outside the shell correctly.
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellHomeKey = GlobalKey<NavigatorState>();
final _shellReportsKey = GlobalKey<NavigatorState>();
final _shellMapKey = GlobalKey<NavigatorState>();
final _shellProfileKey = GlobalKey<NavigatorState>();

// Responder shell navigator keys
final _responderQueueKey = GlobalKey<NavigatorState>();
final _responderReportsKey = GlobalKey<NavigatorState>();
final _responderMapKey = GlobalKey<NavigatorState>();
final _responderProfileKey = GlobalKey<NavigatorState>();

class ZirenRouter {
  ZirenRouter()
    : router = GoRouter(
        navigatorKey: _rootNavigatorKey,
        initialLocation: '/splash',
        // No refreshListenable — all navigation is imperative via AuthProvider.
        // This eliminates the !_debugLocked race condition that occurred when
        // notifyListeners() fired during a mid-frame navigation (e.g. dialog pop).
        routes: [
          // ── Splash ──────────────────────────────────────────
          GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),

          // ── Onboarding (first launch only) ──────────────────
          //
          // Language leads, because consent to a notice you cannot read is
          // not consent. The splash decides whether to enter this branch at
          // all — see OnboardingRepository for what "only once" means and
          // where it is remembered.
          GoRoute(
            path: '/onboarding/language',
            builder: (_, __) => const LanguageScreen(),
          ),
          GoRoute(
            path: '/onboarding/consent',
            builder: (_, __) => const ConsentScreen(),
          ),
          GoRoute(
            path: '/onboarding/welcome',
            builder: (_, __) => const WelcomeScreen(),
          ),

          // ── Auth routes (outside shell) ─────────────────────
          GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
          // ── Registration ────────────────────────────────────
          //
          // One screen per question, with RegistrationDraft holding state
          // across them and mirroring it to disk.
          //
          // Each step is a top-level route rather than a nested one so that
          // context.go() between them replaces rather than stacks: the flow
          // has its own back handling through RegistrationScaffold, and a
          // growing Navigator stack behind it would let the system back
          // gesture walk backwards through steps the person has already
          // corrected.
          GoRoute(
            path: '/register',
            redirect: (_, __) => '/register/role',
          ),
          GoRoute(
            path: '/register/role',
            builder: (_, __) => const StepRoleScreen(),
          ),
          GoRoute(
            path: '/register/personal',
            builder: (_, __) => const StepPersonalScreen(),
          ),
          GoRoute(
            path: '/register/address',
            builder: (_, __) => const StepAddressScreen(),
          ),
          GoRoute(
            path: '/register/contact',
            builder: (_, __) => const StepContactScreen(),
          ),
          GoRoute(
            path: '/register/responder',
            builder: (_, __) => const StepResponderScreen(),
          ),
          GoRoute(
            path: '/register/id-type',
            builder: (_, __) => const StepIdTypeScreen(),
          ),
          GoRoute(
            path: '/register/id-capture',
            builder: (_, __) => const StepIdCaptureScreen(),
          ),
          GoRoute(
            path: '/register/selfie',
            builder: (_, __) => const StepSelfieScreen(),
          ),
          GoRoute(
            path: '/register/review',
            builder: (_, __) => const StepReviewScreen(),
          ),
          GoRoute(
            path: '/forgot-password',
            builder: (_, __) => const ForgotPasswordScreen(),
          ),
          GoRoute(
            path: '/pending-approval',
            builder: (_, __) => const PendingApprovalScreen(),
          ),
          GoRoute(
            path: '/account-rejected',
            builder: (_, __) => const RejectedAccountScreen(),
          ),
          GoRoute(
            path: '/dashboard-only',
            builder: (_, __) => const _DashboardOnlyNotice(),
          ),

          // ── Main shell — 4 bottom-nav branches ──────────────
          StatefulShellRoute.indexedStack(
            parentNavigatorKey: _rootNavigatorKey,
            builder:
                (context, state, shell) => MainShell(navigationShell: shell),
            branches: [
              // Branch 0 — Home
              StatefulShellBranch(
                navigatorKey: _shellHomeKey,
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (_, __) => const ResidentHomeScreen(),
                    routes: [
                      GoRoute(
                        path: 'select-station',
                        builder: (_, __) => const StationSelectorScreen(),
                      ),
                      // /home/report → new combined report screen
                      GoRoute(
                        path: 'report',
                        builder: (_, __) => const WizardReportScreen(),
                      ),
                      GoRoute(
                        path: 'sos-confirm',
                        builder: (_, __) => const SosConfirmScreen(),
                      ),
                      GoRoute(
                        path: 'sos-success',
                        builder: (_, __) => const SosSuccessScreen(),
                      ),
                    ],
                  ),
                ],
              ),

              // Branch 1 — Reports
              StatefulShellBranch(
                navigatorKey: _shellReportsKey,
                routes: [
                  GoRoute(
                    path: '/my-reports',
                    builder: (_, __) => const MyReportsScreen(),
                  ),
                ],
              ),

              // Branch 2 — Map
              StatefulShellBranch(
                navigatorKey: _shellMapKey,
                routes: [
                  GoRoute(
                    path: '/map',
                    // Set when a report is opened here from My Reports — see
                    // ReportDetailScreen's "View on Map" action — so the map
                    // lands centred on that one report instead of the
                    // resident's default nearby-stations view.
                    builder:
                        (_, state) => MapScreen(
                          focusIncidentId:
                              state.uri.queryParameters['incidentId'],
                        ),
                  ),
                ],
              ),

              // Branch 3 — Profile
              StatefulShellBranch(
                navigatorKey: _shellProfileKey,
                routes: [
                  GoRoute(
                    path: '/profile',
                    builder: (_, __) => const ProfileScreen(),
                    routes: [
                      GoRoute(
                        path: 'settings',
                        builder: (_, __) => const SettingsScreen(),
                      ),
                      GoRoute(
                        path: 'verify',
                        builder: (_, __) => const VerifyAccountScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // ── Full-screen overlays (pushed over shell) ─────────
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          // One report on the map, opened from its detail screen.
          //
          // This used to be `context.push('/map?incidentId=...')`. /map is a
          // branch of the tab shell, and pushing a shell branch builds a SECOND
          // copy of the whole shell - with the same navigator keys as the one
          // already on screen. Two widgets claiming one GlobalKey is an error
          // Flutter cannot render through: the pushed screen came up blank, and
          // the real Map tab underneath was left unable to take a tap until the
          // app was restarted. A route outside the shell has none of that.
          GoRoute(
            path: '/report-map/:incidentId',
            builder:
                (_, state) => MapScreen(
                  focusIncidentId: state.pathParameters['incidentId'],
                ),
          ),
          // Unlinked from the nav bar in the resident redesign (which
          // specifies four tabs on every screen), but kept as a reachable
          // route rather than deleted — see main_shell.dart.
          GoRoute(
            path: '/ziren-ai',
            builder: (_, __) => const ZirenAiScreen(),
          ),
          GoRoute(
            path: '/announcements',
            builder: (_, __) => const AnnouncementsScreen(),
          ),
          // Station hotlines — every official BFP/PNP/MDRRMO number, usable
          // with no internet (the list ships inside the app). The old
          // /emergency-contacts screen read them live from the database only,
          // so it showed nothing exactly when a call was the only way left.
          GoRoute(
            path: '/hotlines',
            builder: (_, __) => const HotlinesScreen(),
          ),
          GoRoute(
            path: '/emergency-contacts',
            builder: (_, __) => const HotlinesScreen(),
          ),
          // "How to use Ziren". ?role=responder shows the responder's topics.
          GoRoute(
            path: '/help',
            builder: (_, state) => HelpScreen(
              forResponder: state.uri.queryParameters['role'] == 'responder',
            ),
          ),
          GoRoute(
            path: '/safety-guide',
            builder: (_, __) => const SafetyGuideScreen(),
          ),

          // ── Responder shell — separate nav from Resident ──────
          StatefulShellRoute.indexedStack(
            parentNavigatorKey: _rootNavigatorKey,
            restorationScopeId: 'responder_shell',
            builder:
                (context, state, shell) =>
                    ResponderShell(navigationShell: shell),
            branches: [
              // Branch 0 — Queue
              StatefulShellBranch(
                navigatorKey: _responderQueueKey,
                routes: [
                  GoRoute(
                    path: '/responder/queue',
                    builder: (_, __) => const ResponderHomeScreen(),
                  ),
                ],
              ),
              // Branch 1 — Reports (everything assigned to this responder)
              //
              // This was the Dashboard branch. Those figures moved onto Home,
              // where they sit beside the work they describe, and the slot
              // went to the record a responder previously had no way to reach:
              // /responder/history existed and was linked from one place on a
              // screen most of them never opened.
              StatefulShellBranch(
                navigatorKey: _responderReportsKey,
                routes: [
                  GoRoute(
                    path: '/responder/reports',
                    builder: (_, __) => const ResponderReportsScreen(),
                  ),
                ],
              ),
              // Branch 2 — Map (reuses resident map screen)
              StatefulShellBranch(
                navigatorKey: _responderMapKey,
                routes: [
                  GoRoute(
                    path: '/responder/map',
                    // forResponder, or the crew is shown the incidents they
                    // filed as civilians — none — instead of the ones assigned
                    // to them. See MapScreen.forResponder.
                    builder: (_, __) => const MapScreen(forResponder: true),
                  ),
                ],
              ),
              // Branch 3 — Profile (Responder-specific screen — Phase 6B.2)
              StatefulShellBranch(
                navigatorKey: _responderProfileKey,
                routes: [
                  GoRoute(
                    path: '/responder/profile',
                    builder: (_, __) => const ResponderProfileScreen(),
                  ),
                ],
              ),
            ],
          ),

          // The pushed /responder/history route is gone. The Reports tab shows
          // closed incidents alongside open ones behind a filter, so a
          // separate screen for half the record would be a second answer to
          // the same question — and it was reachable from exactly one link on
          // the Stats tab, which no longer exists.

          // ── Responder incident detail — full screen ───────────
          GoRoute(
            path: '/responder/incident/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder:
                (_, state) => ResponderIncidentDetailScreen(
                  incidentId: state.pathParameters['id']!,
                ),
          ),

          // ── Flat routes kept for context.push() compatibility ─
          GoRoute(
            path: '/select-station',
            builder: (_, __) => const StationSelectorScreen(),
          ),
          // /report → new combined report screen (Step 1 of 2)
          GoRoute(
            path: '/report',
            builder: (_, __) => const WizardReportScreen(),
          ),
          // /report/category kept for back-compat deep-links → same screen
          GoRoute(
            path: '/report/category',
            builder: (_, __) => const WizardReportScreen(),
          ),
          // Step 2 of 2 — review + submit
          GoRoute(
            path: '/report/review',
            builder: (_, __) => const WizardReviewScreen(),
          ),
          // One-tap category report. Category is already set on
          // IncidentProvider by the caller; this screen settles location and
          // station and sends.
          GoRoute(
            path: '/report/quick',
            builder: (_, __) => const QuickReportConfirmScreen(),
          ),
          // Step 2 of the quick flow — review + submit.
          GoRoute(
            path: '/report/quick/review',
            builder: (_, __) => const QuickReportReviewScreen(),
          ),
          // Shown after a VOICE report only, and only once the report is
          // already saved. Asks the resident whether the recogniser heard
          // them correctly — the one source of certainty in a pipeline that
          // cannot read Waray reliably.
          GoRoute(
            path: '/report/confirm/:id',
            builder: (_, state) => ReportConfirmScreen(
              incidentId: state.pathParameters['id']!,
              stationName: state.uri.queryParameters['station'],
            ),
          ),
          // "The incident is somewhere else" — pops with the chosen LatLng.
          GoRoute(
            path: '/report/pick-location',
            builder: (_, __) => const PickIncidentLocationScreen(),
          ),
          GoRoute(
            path: '/sos-confirm',
            builder: (_, __) => const SosConfirmScreen(),
          ),
          GoRoute(
            path: '/sos-success',
            builder: (_, __) => const SosSuccessScreen(),
          ),
          // Diagnostic, not a resident feature: measures which recogniser
          // actually reads Waray and Bisaya on this handset.
          GoRoute(
            path: '/speech-diagnostic',
            builder: (_, __) => const SpeechDiagnosticScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      );

  final GoRouter router;
}

// ── Dashboard-only notice (admin accounts) ────────────────────

class _DashboardOnlyNotice extends StatelessWidget {
  const _DashboardOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                LucideIcons.monitor,
                size: 72,
                color: Color(0xFFD32F2F),
              ),
              const SizedBox(height: 24),
              Text(
                'Use the Web Dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: ZirenTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Agency Admin and Super Admin accounts are managed '
                'through the Ziren web dashboard, not the mobile app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ZirenTokens.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                icon: const Icon(LucideIcons.log_out),
                label: const Text('Log out'),
                onPressed: () => auth.logout(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
