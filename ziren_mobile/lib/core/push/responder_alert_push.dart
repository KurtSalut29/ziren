import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import '../../features/weather/data/weather_reminders.dart';

/// The responder's full-screen alarms, shared by the app and by the push
/// handler that runs while the app is CLOSED.
///
/// Tester request 2026-10-05: a responder near a new incident, or newly
/// assigned one, must be told even with the phone locked or Ziren closed —
/// "like MDRRMC": the screen wakes and the alert comes up over the lock screen.
///
/// An ordinary FCM push cannot do that: Android draws it as a banner. So the
/// backend sends responder alerts as DATA-ONLY, high-priority messages
/// (push_service.send_alert_to_users) and [zirenFirebaseBackgroundHandler]
/// raises the notification itself, with a full-screen intent. When the phone
/// is in use it shows as a heads-up; when it is locked or asleep it takes the
/// screen the way an incoming call does, and opening it lands in the app,
/// where the shell raises the matching modal.
///
/// What it still cannot reach, said plainly: an app the user FORCE-STOPPED
/// (Android delivers nothing to a stopped app), and some handsets whose battery
/// savers hold back background work until Ziren is allowed to run unrestricted.

/// Notification ids that are the same in every isolate and every launch.
///
/// `String.hashCode` is not promised to be stable between runs, and the push
/// handler runs in its own isolate; an alarm raised there under one id could
/// then never be cancelled from the app, and an insistent alarm that cannot be
/// cancelled is the worst thing this feature could do.
abstract final class ResponderAlertIds {
  static int assignment(String incidentId) => _fnv('assign:$incidentId');
  static int nearby(String incidentId) => _fnv('nearby:$incidentId');
  static int standDown(String incidentId) => _fnv('standdown:$incidentId');

  static int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}

/// Channels and notification details for the two alarms.
abstract final class ResponderAlertChannels {
  // The dispatch channel's id is versioned: Android caches a channel's sound
  // and importance at creation and ignores later edits (see
  // ResponderAlertService for the history).
  // v3: the sound became the dashboard's alert (res/raw/ziren_alert). A
  // channel's sound cannot be changed once created, so the id changes with it.
  static const dispatchId = 'ziren_responder_dispatch_v3';
  static const dispatchName = 'Dispatch alerts';
  static const dispatchDescription =
      'Full-screen alarm when a dispatcher assigns you an incident. '
      'Sounds even when the phone is on silent.';

  /// New in 1.0.0+15. Nearby alerts used to share the quiet "Incident updates"
  /// channel; they now wake the phone, so they need a channel whose sound is
  /// an alarm - and, being new, it is created with those settings.
  static const nearbyId = 'ziren_responder_nearby_v2';

  /// Channels this file used to create, deleted so a responder's notification
  /// settings do not collect a dead entry per sound change.
  static const retiredIds = [
    'ziren_responder_dispatch_v2',
    'ziren_responder_nearby_v1',
  ];

  /// The dashboard's alert sound, as an Android raw resource (kept from
  /// resource shrinking by res/raw/keep.xml).
  static const sound = RawResourceAndroidNotificationSound('ziren_alert');
  static const nearbyName = 'Nearby incident alerts';
  static const nearbyDescription =
      'Full-screen alert when a new incident near you has no responder yet.';

  /// Wait, buzz, wait, buzz: felt through a jacket while driving.
  static final Int64List dispatchVibration = Int64List.fromList(<int>[
    0,
    700,
    400,
    700,
    400,
    700,
  ]);
  static final Int64List nearbyVibration = Int64List.fromList(<int>[
    0,
    500,
    300,
    500,
  ]);

  /// FLAG_INSISTENT (0x4): repeat the sound until the alert is dealt with.
  static const int flagInsistent = 4;

  static AndroidNotificationChannel get dispatchChannel =>
      AndroidNotificationChannel(
        dispatchId,
        dispatchName,
        description: dispatchDescription,
        importance: Importance.max,
        playSound: true,
        sound: sound,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        vibrationPattern: dispatchVibration,
      );

  static AndroidNotificationChannel get nearbyChannel =>
      AndroidNotificationChannel(
        nearbyId,
        nearbyName,
        description: nearbyDescription,
        importance: Importance.max,
        playSound: true,
        sound: sound,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        vibrationPattern: nearbyVibration,
      );

  /// An assignment: takes the screen, repeats until answered.
  static NotificationDetails assignment({
    String ticker = 'New incident assigned',
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      dispatchId,
      dispatchName,
      channelDescription: dispatchDescription,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      sound: sound,
      category: AndroidNotificationCategory.call,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      additionalFlags: Int32List.fromList(<int>[flagInsistent]),
      ongoing: true,
      autoCancel: false,
      vibrationPattern: dispatchVibration,
      ticker: ticker,
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  /// A nearby incident: takes the screen and sounds once. Not insistent - a
  /// dispatcher has not sent anyone, so it asks; it does not summon.
  static NotificationDetails nearby() => NotificationDetails(
    android: AndroidNotificationDetails(
      nearbyId,
      nearbyName,
      channelDescription: nearbyDescription,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      sound: sound,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      autoCancel: true,
      vibrationPattern: nearbyVibration,
      ticker: 'Incident near you',
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  static Future<void> createAll(FlutterLocalNotificationsPlugin plugin) async {
    final android =
        plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await android?.createNotificationChannel(dispatchChannel);
    await android?.createNotificationChannel(nearbyChannel);
    for (final id in retiredIds) {
      try {
        await android?.deleteNotificationChannel(id);
      } catch (_) {
        // Not there on a fresh install.
      }
    }
  }
}

/// The kinds of data-only push the backend sends for responders.
const kAlertAssignment = 'assignment';
const kAlertNearby = 'nearby';

/// Raise the alarm for one data-only alert push. Returns whether it did.
///
/// Pure enough to test: [plugin] is injectable.
Future<bool> showResponderAlertFromPush(
  Map<String, dynamic> data, {
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  final kind = data['ziren_alert'] as String?;
  final incidentId = data['incident_id'] as String?;
  if (incidentId == null || (kind != kAlertAssignment && kind != kAlertNearby)) {
    return false;
  }

  final p = plugin ?? FlutterLocalNotificationsPlugin();
  await p.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await ResponderAlertChannels.createAll(p);

  final title = (data['title'] as String?)?.trim();
  final body = (data['body'] as String?)?.trim();
  // Cancelled first, then shown. Android launches a full-screen intent only
  // for a notification that is ADDED; re-posting an id still in the shade is
  // an update, which rings but leaves the screen asleep (on-device check
  // 2026-10-06: the second alert for one incident only made a sound).
  // Best effort: a failure to clear the old one must never stop the new one.
  try {
    await p.cancel(
      kind == kAlertAssignment
          ? ResponderAlertIds.assignment(incidentId)
          : ResponderAlertIds.nearby(incidentId),
    );
  } catch (e) {
    debugPrint('[ResponderAlertPush] could not clear the previous alert: $e');
  }
  if (kind == kAlertAssignment) {
    await p.show(
      ResponderAlertIds.assignment(incidentId),
      title?.isNotEmpty == true ? title : 'New assignment',
      body,
      ResponderAlertChannels.assignment(),
      payload: 'assignment:$incidentId',
    );
  } else {
    await p.show(
      ResponderAlertIds.nearby(incidentId),
      title?.isNotEmpty == true ? title : 'Incident near you',
      body,
      ResponderAlertChannels.nearby(),
      payload: 'nearby:$incidentId',
    );
  }
  return true;
}

/// Runs in its own isolate when a push arrives and Ziren is not in the
/// foreground - including when it is closed. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> zirenFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
    }
    if (message.data['ziren_weather'] != null) {
      // A resident's weather reminder rides the same handler: the app is
      // closed, so read the language before wording it.
      await WeatherReminders.showFromPush(message.data, loadLanguage: true);
      return;
    }
    await showResponderAlertFromPush(message.data);
  } catch (e) {
    debugPrint('[ResponderAlertPush] background alert not shown: $e');
  }
}
