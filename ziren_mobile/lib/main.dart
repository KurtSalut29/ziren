import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_localizations.dart';
import 'core/config/accessibility_provider.dart';
import 'core/config/app_config.dart';
import 'core/config/locale_provider.dart';
import 'core/routing/app_router.dart';
import 'features/auth/domain/auth_provider.dart';
import 'features/incident_report/domain/incident_provider.dart';
import 'features/notifications/domain/notification_provider.dart';
import 'features/registration/domain/registration_draft.dart';
import 'features/settings/domain/profile_provider.dart';
import 'features/sos/domain/sos_provider.dart';
import 'features/responder/data/responder_alert_service.dart';
import 'features/responder/domain/responder_notification_provider.dart';
import 'features/responder/domain/responder_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/app_tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // Read the stored language before the first frame. A resident opening this
  // app is often about to report an emergency; they should not watch the UI
  // change language underneath them while the profile request lands.
  final localeProvider = LocaleProvider();
  await localeProvider.load();

  // Same reasoning for appearance: read theme/text-size/motion preferences
  // before the first frame so nobody watches the app flash light and then
  // settle into the dark mode they actually chose.
  final accessibilityProvider = AccessibilityProvider();
  await accessibilityProvider.load();

  runApp(
    ZirenApp(
      localeProvider: localeProvider,
      accessibilityProvider: accessibilityProvider,
    ),
  );
}

class ZirenApp extends StatefulWidget {
  const ZirenApp({
    super.key,
    required this.localeProvider,
    required this.accessibilityProvider,
  });

  final LocaleProvider localeProvider;
  final AccessibilityProvider accessibilityProvider;

  @override
  State<ZirenApp> createState() => _ZirenAppState();
}

class _ZirenAppState extends State<ZirenApp> {
  late final AuthProvider _authProvider;
  late final IncidentProvider _incidentProvider;
  late final SosProvider _sosProvider;
  late final NotificationProvider _notificationProvider;
  late final ProfileProvider _profileProvider;
  late final RegistrationDraft _registrationDraft;
  late final ResponderProvider _responderProvider;
  late final ResponderNotificationProvider _responderNotificationProvider;
  late final ResponderAlertService _responderAlerts;
  late final ZirenRouter _zirenRouter;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _incidentProvider = IncidentProvider();
    _sosProvider = SosProvider();
    _notificationProvider = NotificationProvider();
    _profileProvider = ProfileProvider();
    _registrationDraft = RegistrationDraft();
    _responderProvider = ResponderProvider();
    _responderAlerts = ResponderAlertService();
    _responderNotificationProvider = ResponderNotificationProvider(
      onNewAssignment: () {
        _responderProvider.loadQueue();
        // The dashboard figures are derived from the queue, so an assignment
        // that does not refresh them leaves a responder looking at an
        // "active: 2" headline over a list of three.
        _responderProvider.loadDashboard();
      },
      // A new assignment sounds the alarm; dispatch standing the crew down tells
      // them and silences it. Two different things, two different alerts.
      onAlert:
          (n) =>
              n.isStandDown
                  ? _responderAlerts.notifyStandDown(n)
                  : _responderAlerts.notifyAssignment(n),
    );

    // Everything already in the queue is known, so it is not announced. This
    // is the wiring that keeps a cold start from firing three notifications
    // for three incidents the responder has been holding since yesterday.
    _responderProvider.onQueueLoaded = _responderNotificationProvider.seedKnown;

    // A nearby, undispatched incident is an invitation, not a summons - a quiet
    // heads-up on the same channel a stand-down uses, never the full-screen
    // dispatch alarm. Withdrawn again once it is answered, dispatched to
    // someone, or ages out of the list.
    _responderProvider.onNearbyArrived = (items) {
      for (final i in items) {
        _responderAlerts.notifyNearby(i);
      }
    };
    _responderProvider.onNearbyResolved = (ids) {
      for (final id in ids) {
        _responderAlerts.cancelNearby(id);
      }
    };

    // Silence the dispatch alarm once the crew has answered it. The
    // notification is `ongoing` with FLAG_INSISTENT and repeats until
    // cancelled, and an alarm still sounding after the assignment has been
    // accepted teaches responders to silence the phone entirely.
    _responderProvider.onAlertAnswered = _responderAlerts.dismiss;
    _zirenRouter = ZirenRouter();

    // Give AuthProvider a reference to the router so it can navigate
    // imperatively (login → /home, logout → /login) without refreshListenable.
    _authProvider.setRouter(_zirenRouter.router);

    // Subscribe to Realtime notifications if already authenticated (warm restart)
    if (_authProvider.isAuthenticated) {
      _notificationProvider.subscribe();
      _responderNotificationProvider.subscribe();
      _responderAlerts.init();
    }
    _authProvider.addListener(_onAuthChange);
  }

  /// Tracks which account the per-user providers currently hold data for, so
  /// a change of account can be told apart from a token refresh.
  String? _providersLoadedForUserId;

  void _onAuthChange() {
    if (_authProvider.isAuthenticated) {
      _notificationProvider.subscribe();
      _responderNotificationProvider.subscribe();
      // init() is idempotent; a token refresh re-enters this branch and must
      // not re-prompt for notification permission.
      _responderAlerts.init();

      // A different person has signed in on this handset. Anything cached for
      // the previous account has to go, and the new profile has to be fetched
      // — ProfileScreen lives in an IndexedStack branch, so its initState will
      // not run again to do it.
      final userId = _authProvider.user?.id;
      if (userId != _providersLoadedForUserId) {
        _providersLoadedForUserId = userId;
        _profileProvider.clear();
        _profileProvider.loadProfile();
      }
    } else {
      _notificationProvider.unsubscribe();
      _responderNotificationProvider.unsubscribe();
      // Stop reporting position. The ping already checks duty status and would
      // fail on a missing token anyway, but leaving the timer alive means a
      // signed-out handset keeps waking every two minutes for the life of the
      // process — and, worse, a responder who signs out has withdrawn from
      // duty, which is exactly when their whereabouts stop being anyone's
      // business.
      _responderProvider.stopLocationReporting();
      _providersLoadedForUserId = null;
      _profileProvider.clear();
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChange);
    _authProvider.dispose();
    _sosProvider.dispose();
    _notificationProvider.dispose();
    _responderNotificationProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _incidentProvider),
        ChangeNotifierProvider.value(value: _sosProvider),
        ChangeNotifierProvider.value(value: _notificationProvider),
        ChangeNotifierProvider.value(value: _profileProvider),
        ChangeNotifierProvider.value(value: _registrationDraft),
        ChangeNotifierProvider.value(value: _responderProvider),
        ChangeNotifierProvider.value(value: _responderNotificationProvider),
        ChangeNotifierProvider.value(value: widget.localeProvider),
        ChangeNotifierProvider.value(value: widget.accessibilityProvider),
      ],
      // Rebuilds the whole app when language or appearance changes, so a
      // switch in Settings takes effect immediately instead of on next
      // launch.
      child: Consumer2<LocaleProvider, AccessibilityProvider>(
        builder: (_, localeProvider, a11y, __) {
          final brightness = a11y.resolvedBrightness;
          // Single point of truth for "which mode is active" — pushed into
          // ZirenTokens here (not only inside AccessibilityProvider's own
          // setters) so a live OS theme change while in ThemeMode.system is
          // also caught on the very next build, not just on an explicit
          // Settings toggle.
          ZirenTokens.setMode(
            brightness: brightness,
            highContrast: a11y.highContrast,
          );
          final theme = AppTheme.themeFor(brightness);

          return KeyedSubtree(
            // ZirenTokens' colours are plain static getters, not an
            // InheritedWidget — most of the widget tree has no Flutter
            // -recognised dependency on them, so nothing below would
            // otherwise know to repaint when brightness flips. Changing this
            // key forces Flutter to discard and rebuild the whole subtree
            // from scratch instead, which is the blunt but reliable way to
            // make ~150 files of bare `ZirenTokens.textPrimary` calls
            // theme-reactive without rewriting every one of them.
            //
            // This does NOT reset navigation: GoRouter lives in
            // `_zirenRouter`, a State field untouched by this rebuild, and
            // it re-attaches to the same current location either way.
            key: ValueKey('${brightness.name}-${a11y.highContrast}'),
            child: MaterialApp.router(
              title: 'Ziren',
              debugShowCheckedModeBanner: false,
              theme: theme,
              darkTheme: theme,
              // Always resolves through `theme` above rather than letting
              // MaterialApp independently re-derive light/dark from the
              // platform — two brightness resolvers running side by side is
              // how the AppBar and a hand-painted ZirenTokens.surfaceCard
              // card end up disagreeing about which mode is active.
              themeMode: ThemeMode.light,
              locale: localeProvider.locale,
              supportedLocales: LocaleProvider.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              routerConfig: _zirenRouter.router,
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(
                    // Replaces rather than multiplies the OS text scale —
                    // this is the resident's own explicit in-app choice, and
                    // stacking it on top of a phone already set to a large
                    // system font would compound into layouts nobody chose.
                    textScaler: TextScaler.linear(a11y.textScale),
                    disableAnimations:
                        mq.disableAnimations || a11y.reduceMotion,
                  ),
                  child: child!,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
