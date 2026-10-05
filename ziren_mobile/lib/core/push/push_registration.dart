import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'responder_alert_push.dart';
import '../../features/weather/data/weather_reminders.dart';

/// Push notifications that reach the phone with Ziren closed.
///
/// Evaluator findings #11 and #12 (2026-10-05): a resident heard nothing about
/// an admin's message or a change to their report unless the app was open,
/// and a responder heard nothing about a new assignment. The backend now also
/// sends every notice through Firebase Cloud Messaging; this registers the
/// phone for it after sign-in and unregisters it at sign-out.
///
/// Off unless the four FIREBASE_* values are in dart_defines.json
/// ([AppConfig.pushConfigured]); with them missing every call here is a no-op.
///
/// With the app OPEN, the in-app notices (Supabase Realtime) already show the
/// same event, so a push arriving in the foreground is not shown again.
class PushRegistration {
  PushRegistration._();

  static bool _firebaseReady = false;
  static String? _token;
  static StreamSubscription<String>? _refreshSub;
  static StreamSubscription<RemoteMessage>? _foregroundSub;

  /// A responder alert (assignment / nearby) that arrived while the app is
  /// OPEN. The full-screen notification is the closed-app path; open, the app
  /// just has to look now instead of on its next two-minute poll. Wired in
  /// main.dart to reload the queue or the nearby list.
  static void Function(String kind, Map<String, dynamic> data)? onAlert;

  /// Before runApp: register the handler that raises a responder's alarm while
  /// the app is closed, and listen for alerts while it is open.
  ///
  /// The background handler has to be registered on every launch, signed in or
  /// not, or a push that arrives after the next cold start finds nobody to
  /// handle it. Never throws; with Firebase not configured it does nothing.
  static Future<void> initEarly() async {
    if (!await _ensureFirebase()) return;
    try {
      FirebaseMessaging.onBackgroundMessage(zirenFirebaseBackgroundHandler);
      await _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen((m) {
        final kind = m.data['ziren_alert'];
        if (kind is String) onAlert?.call(kind, m.data);
        // Weather reminder with the app open: still a notification, so it
        // is there after the resident leaves Home.
        if (m.data['ziren_weather'] != null) {
          WeatherReminders.showFromPush(m.data);
        }
      });
    } catch (e) {
      debugPrint('[PushRegistration] alert handlers not registered: $e');
    }
  }

  /// Residents' channels. A responder's assignment uses the responder alert
  /// service's own dispatch channel, created by that service.
  static const _alerts = AndroidNotificationChannel(
    'ziren_alerts',
    'Urgent updates',
    description: 'A responder is on the way, a message from the station, safety alerts.',
    importance: Importance.high,
  );
  static const _updates = AndroidNotificationChannel(
    'ziren_updates',
    'Report updates',
    description: 'Changes to reports you sent and announcements.',
    importance: Importance.defaultImportance,
  );

  static Future<bool> _ensureFirebase() async {
    if (!AppConfig.pushConfigured) return false;
    if (_firebaseReady) return true;
    try {
      if (Firebase.apps.isNotEmpty) {
        _firebaseReady = true;
        return true;
      }
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_alerts);
      await android?.createNotificationChannel(_updates);
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[PushRegistration] Firebase unavailable: $e');
    }
    return _firebaseReady;
  }

  /// After sign-in: ask permission, get this phone's token, tell the backend.
  static Future<void> start() async {
    if (!await _ensureFirebase()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) await _send(token);
      await _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen(_send);
    } catch (e) {
      debugPrint('[PushRegistration] could not register: $e');
    }
  }

  /// At sign-out: stop pushing to this phone. Called before the session ends,
  /// while the request can still be authorised.
  static Future<void> stop() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    final token = _token;
    _token = null;
    if (!_firebaseReady || token == null) return;
    try {
      final access = Supabase.instance.client.auth.currentSession?.accessToken;
      if (access != null) {
        // In the body, not the query: a query parameter is written into the
        // server's access log on every sign-out.
        await http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/users/me/push-token/forget'),
              headers: {'Authorization': 'Bearer $access', 'Content-Type': 'application/json'},
              body: jsonEncode({'token': token}),
            )
            .timeout(const Duration(seconds: 8));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[PushRegistration] could not unregister: $e');
    }
  }

  static Future<void> _send(String token) async {
    _token = token;
    final access = Supabase.instance.client.auth.currentSession?.accessToken;
    if (access == null) return;
    try {
      await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/users/me/push-token'),
            headers: {'Authorization': 'Bearer $access', 'Content-Type': 'application/json'},
            body: jsonEncode({'token': token, 'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[PushRegistration] token not sent: $e');
    }
  }
}
