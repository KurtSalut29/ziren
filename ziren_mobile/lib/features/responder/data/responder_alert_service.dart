import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/nearby_incident.dart';
import '../domain/responder_notification_provider.dart';

/// Raises an OS notification when a responder is assigned an incident.
///
/// WHY THIS EXISTS SEPARATELY FROM THE REALTIME SUBSCRIPTION
///
/// ResponderNotificationProvider already knows, within a second, that an
/// assignment has arrived. What it can do about it is redraw a badge — and a
/// badge is only useful to someone already looking at the screen. A responder
/// waiting for a call is, by definition, not looking at the screen. Until this
/// existed, the app could know a fire had been assigned and had no way to say
/// so out loud.
///
/// WHAT IT CANNOT DO, STATED PLAINLY
///
/// This is a LOCAL notification, raised by code running inside this app. It
/// reaches a responder whose phone is in their pocket with the app in the
/// background; it does NOT reach one who has force-stopped the app or whose
/// system has evicted it to reclaim memory, because the Realtime socket that
/// feeds it is gone too.
///
/// Closing that gap means Firebase Cloud Messaging: a push delivered by the
/// OS, from a server, whether or not the app is alive. That needs a Firebase
/// project, a service key held by the backend, and a per-build
/// google-services.json — infrastructure this deployment does not have. The
/// honest position is that this covers the common case and not the worst one,
/// and that "responder was notified" must not be read as a guarantee anywhere
/// else in the system. A dispatcher still confirms by radio.
class ResponderAlertService {
  ResponderAlertService();

  /// One channel, at max importance.
  ///
  /// Android caches a channel's importance at creation and IGNORES later
  /// changes to it — the only way to raise an existing channel's importance is
  /// to create a new one with a different id, or for the user to change it in
  /// system settings. So the id carries a version suffix: if this ever needs
  /// to change, the id changes with it rather than the change silently having
  /// no effect on every device that has already run the app.
  // ── v2, AND THE VERSION BUMP IS THE WHOLE POINT ────────────
  //
  // This channel changed from a heads-up notification to a full-screen
  // alarm: audioAttributesUsage moves to alarm, so it sounds through
  // silent, and fullScreenIntent turns it into something that takes the
  // screen the way an incoming call does.
  //
  // Android caches those properties at channel creation and IGNORES every
  // later change to them. Editing v1 in place would have shipped code that
  // looks like a full-screen alarm, passes review, and behaves exactly like
  // the old quiet banner on every handset that had already run the app —
  // that is, on every responder's phone, and on none of the fresh installs
  // it would be tested on. The id changes with the behaviour.
  static const _channelId = 'ziren_responder_dispatch_v2';
  static const _channelName = 'Dispatch alerts';
  static const _channelDescription =
      'Full-screen alarm when a dispatcher assigns you an incident. '
      'Sounds even when the phone is on silent.';

  /// The retired channel. Deleted on init so a responder's notification
  /// settings do not accumulate a dead entry per release.
  static const _legacyChannelId = 'ziren_responder_assignments_v1';

  /// Things that happen to a call a crew already holds - dispatch standing them
  /// down. Loud enough to be heard, but an ordinary notification: it is news, not
  /// a summons, so it neither insists nor takes the screen the way an assignment
  /// does.
  static const _updatesChannelId = 'ziren_responder_updates_v1';
  static const _updatesChannelName = 'Incident updates';
  static const _updatesChannelDescription =
      'Dispatch cancelled an incident you were assigned to, or changed its priority.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Set up the plugin and, on Android 13+, ask for notification permission.
  ///
  /// Safe to call more than once — sign-in can fire the auth listener again on
  /// a token refresh, and re-initialising the plugin on every one of those
  /// would re-prompt for permission.
  Future<void> init() async {
    if (_ready) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    try {
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );

      final androidImpl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      // Created explicitly rather than left to the first notification. A
      // channel created implicitly picks up defaults, and on some OEM builds
      // that means no sound — which for this channel is the entire point.
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          // ALARM, not notification. A notification-usage sound obeys the
          // ringer switch, and a responder whose phone is on silent —
          // because they were in a meeting, in church, asleep — would get
          // a dispatch alert they cannot hear. An alarm is the category
          // the OS lets through anyway, and this genuinely is one.
          audioAttributesUsage: AudioAttributesUsage.alarm,
          // Long, uneven, and deliberately not the default double-buzz:
          // felt through a jacket pocket while driving.
          vibrationPattern: _dispatchVibration,
        ),
      );

      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _updatesChannelId,
          _updatesChannelName,
          description: _updatesChannelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Retire v1 so the responder's settings screen does not accumulate a
      // dead channel per release. Harmless on a fresh install.
      await androidImpl?.deleteNotificationChannel(_legacyChannelId);

      await androidImpl?.requestNotificationsPermission();

      // Android 14 gates USE_FULL_SCREEN_INTENT behind a per-app grant
      // that only calling and alarm apps get by default. Asking costs
      // nothing when it is already held, and without it the alert quietly
      // degrades to a heads-up banner — still delivered, no longer loud,
      // and with no error to say so.
      try {
        await androidImpl?.requestFullScreenIntentPermission();
      } catch (e) {
        debugPrint('[ResponderAlertService] no full-screen intent: $e');
      }

      _ready = true;
    } catch (e) {
      // A handset that refuses notifications must not take the responder app
      // down with it. The in-app badge still works; the phone just will not
      // interrupt them.
      debugPrint('[ResponderAlertService.init] $e');
    }
  }

  /// Raise a notification for one assignment.
  Future<void> notifyAssignment(ResponderNotification n) async {
    if (!_ready) return;

    // The words for this event - severity and where - live with the event itself
    // (ResponderNotification.detail), so this and the in-app list say the same.
    final body = n.detail;

    try {
      await _plugin.show(
        // The incident id, not an incrementing counter. Android replaces a
        // notification that reuses an id, so two events on the same incident
        // collapse into one line instead of stacking; two different incidents
        // stay two notifications, which is what a responder needs to see.
        n.incidentId.hashCode,
        n.label,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            // Takes the screen and wakes the device, the way an incoming
            // call does. A heads-up banner reaches a responder who is
            // already looking at their phone, which is the one responder
            // who does not need to be told.
            fullScreenIntent: true,
            // CALL is the honest classification and it is also what earns
            // the full-screen grant on Android 14. A dispatch assignment
            // is a summons that expects an answer.
            category: AndroidNotificationCategory.call,
            // Repeats until it is answered rather than chiming once into an
            // empty room. Cleared by the accept/decline handling.
            audioAttributesUsage: AudioAttributesUsage.alarm,
            additionalFlags: Int32List.fromList(<int>[_flagInsistent]),
            ongoing: true,
            autoCancel: false,
            vibrationPattern: _dispatchVibration,
            ticker: 'New incident assigned',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ResponderAlertService.notifyAssignment] $e');
    }
  }

  /// Tell a crew that dispatch cancelled the incident they were on - and stop the
  /// assignment alarm for it.
  ///
  /// Both halves matter. The assignment notification is `ongoing` and insistent,
  /// so it keeps sounding until something cancels it; a crew that has been stood
  /// down and is still being shouted at by the phone learns to silence it, and a
  /// crew that is not told drives to a call that no longer exists.
  Future<void> notifyStandDown(ResponderNotification n) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(n.incidentId.hashCode);
      await _plugin.show(
        // A different id from the assignment's, so this is its own line and not
        // a replacement that could itself be cancelled by the accept/decline path.
        n.incidentId.hashCode ^ 0x57A9D,
        n.label,
        n.detail,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _updatesChannelId,
            _updatesChannelName,
            channelDescription: _updatesChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
            ticker: 'Incident cancelled',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ResponderAlertService.notifyStandDown] $e');
    }
  }

  /// Tell a crew that an incident nobody has been sent to yet is near them.
  ///
  /// Deliberately NOT the full-screen dispatch alarm - a dispatcher has not
  /// sent anyone, so this is an invitation to help, not a summons. It uses the
  /// same quiet "Incident updates" channel as a stand-down: heads-up, one
  /// notification per incident, no insistent loop.
  Future<void> notifyNearby(NearbyIncident n) async {
    if (!_ready) return;
    final where = (n.locationAddress ?? '').trim();
    final body =
        n.distanceKm != null
            ? '${n.categoryLabel} · ${n.distanceKm!.toStringAsFixed(1)} km away'
                '${where.isEmpty ? '' : ' · $where'}'
            : '${n.categoryLabel}${where.isEmpty ? '' : ' · $where'}';
    try {
      await _plugin.show(
        _nearbyNotificationId(n.incidentId),
        'Nearby incident needs a responder',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _updatesChannelId,
            _updatesChannelName,
            channelDescription: _updatesChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
            ticker: 'Nearby incident',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ResponderAlertService.notifyNearby] $e');
    }
  }

  /// Withdraw a nearby alert - answered, dispatched to someone, or aged out.
  Future<void> cancelNearby(String incidentId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_nearbyNotificationId(incidentId));
    } catch (e) {
      debugPrint('[ResponderAlertService.cancelNearby] $e');
    }
  }

  /// Distinct from the assignment id (`incidentId.hashCode`) and the stand-down
  /// id (`^ 0x57A9D`) so the three can never collide or cancel one another.
  int _nearbyNotificationId(String incidentId) =>
      incidentId.hashCode ^ 0x4E4259;

  /// FLAG_INSISTENT. Repeats the sound until the notification is dealt with.
  /// FLAG_INSISTENT. Repeats the sound until the notification is dealt with.
  ///
  /// Not exposed by the plugin, so it goes in as a raw flag. The constant is
  /// 0x00000004 and has been stable in the Android framework since API 1.
  static const int _flagInsistent = 4;

  /// Wait, buzz, wait, buzz — long enough to be felt through a jacket while
  /// driving, and distinct from every default pattern on the handset.
  /// Int64List, NOT Int32List. `additionalFlags` immediately below takes an
  /// Int32List, so the two adjacent arguments want different widths — which
  /// reads fine and does not compile.
  static final Int64List _dispatchVibration = Int64List.fromList(<int>[
    0,
    700,
    400,
    700,
    400,
    700,
  ]);

  /// Stop an alert that has been answered.
  ///
  /// Load-bearing, because the notification is `ongoing` with FLAG_INSISTENT:
  /// it repeats until something cancels it. Called the moment a responder
  /// accepts or declines, from either the full-screen alert or the incident
  /// screen — an alarm that keeps sounding after the crew has already answered
  /// teaches them to silence the phone, which is the one habit this whole
  /// feature cannot survive.
  Future<void> dismiss(String incidentId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(incidentId.hashCode);
    } catch (e) {
      debugPrint('[ResponderAlertService.dismiss] $e');
    }
  }
}
