import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/locale_provider.dart';
import '../domain/weather_advice.dart';
import '../presentation/weather_words.dart';

/// The phone reminder an hour before heavy rain, a thunderstorm or dangerous
/// heat.
///
/// The BACKEND decides when (ziren_backend app/services/weather_alerts.py)
/// and sends a data-only, high-priority push; this draws it, in the phone's
/// language, unless the resident switched reminders off.
///
/// It used to be an alarm scheduled on the phone from the last forecast. On
/// the user's Infinix that never arrived: Transsion's battery manager freezes
/// a closed app within seconds and swallows its alarms ("proxy alarm" in
/// logcat), and could hand them over hours late once the app was opened
/// again. A high-priority push is what gets through.
class WeatherReminders {
  WeatherReminders._();

  static const channelId = 'ziren_weather_v1';
  static const _enabledKey = 'weather.reminders.enabled';

  /// Fixed, and far from the 31-bit FNV ids the responder alarms hash into.
  static const idRain = 7301;
  static const idHeat = 7302;

  static int idFor(ReminderSlot slot) =>
      slot == ReminderSlot.rain ? idRain : idHeat;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// On by default: a resident who never opens the switch still hears about
  /// heavy rain.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, on);
    } catch (_) {}
    if (!on) await cancelAll();
  }

  static Future<bool> _init() async {
    if (_ready) return true;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      final t = LocaleProvider.strings;
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              channelId,
              t.weatherChannelName,
              description: t.weatherChannelDescription,
              importance: Importance.high,
            ),
          );
      _ready = true;
    } catch (e) {
      debugPrint('[WeatherReminders] init failed: $e');
    }
    return _ready;
  }

  /// Draw the reminder a weather push carries. Returns whether one was shown.
  ///
  /// Runs in the push background isolate when the app is closed, so it reads
  /// the language itself and stays quick (some phones freeze the app again a
  /// few seconds after a push wakes it).
  static Future<bool> showFromPush(
    Map<String, dynamic> data, {
    DateTime? now,
    bool loadLanguage = false,
  }) async {
    final plan = WeatherReminderPlan.fromPush(data);
    if (plan == null) return false;
    // Arrived after the weather started (a phone that was off): say nothing.
    if (!plan.startsAt.isAfter(now ?? DateTime.now())) return false;
    if (!await isEnabled()) return false;
    if (loadLanguage) await LocaleProvider().load();
    if (!await _init()) return false;
    final t = LocaleProvider.strings;
    final words = WeatherWords(t, LocaleProvider.current.toLanguageTag());
    final body = words.reminderBody(plan);
    try {
      await _plugin.show(
        idFor(plan.slot),
        words.reminderTitle(plan),
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            t.weatherChannelName,
            channelDescription: t.weatherChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            styleInformation: BigTextStyleInformation(body),
            // Gone by the time the weather it warns about should be over.
            timeoutAfter: plan.endsAt
                .difference(now ?? DateTime.now())
                .inMilliseconds
                .clamp(60000, 8 * 3600000),
          ),
        ),
        payload: 'weather:${plan.slot.name}',
      );
      return true;
    } catch (e) {
      debugPrint('[WeatherReminders] not shown: $e');
      return false;
    }
  }

  static Future<void> cancelAll() async {
    for (final id in const [idRain, idHeat]) {
      try {
        await _plugin.cancel(id);
      } catch (e) {
        debugPrint('[WeatherReminders] cancel $id failed: $e');
      }
    }
  }
}
