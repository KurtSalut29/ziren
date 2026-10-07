// Weather on resident Home: what Ziren says, which reminders he gives, and
// when the phone buzzes. Built from forecasts shaped like GET /weather/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ziren/features/weather/data/weather_reminders.dart';
import 'package:ziren/features/weather/data/weather_repository.dart';
import 'package:ziren/features/weather/data/weather_store.dart';
import 'package:ziren/features/weather/domain/weather_advice.dart';
import 'package:ziren/features/weather/domain/weather_forecast.dart';
import 'package:ziren/features/weather/presentation/weather_card.dart';
import 'package:ziren/features/weather/presentation/weather_words.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// 10:20 AM on 6 October 2026, Manila (UTC+8).
final now = DateTime.parse('2026-10-06T10:20:00+08:00');

String iso(int hour, {int day = 6}) =>
    '2026-10-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:00:00+08:00';

Map<String, dynamic> hourJson(
  int hour, {
  double temp = 28,
  double hi = 30,
  String heat = 'caution',
  double mm = 0,
  String rain = 'none',
  String cond = 'cloudy',
  double chance = 90,
  double uv = 3,
}) => {
  'time': iso(hour % 24, day: 6 + hour ~/ 24),
  'temperature_c': temp,
  'heat_index_c': hi,
  'humidity': 75,
  'rain_chance': chance,
  'precip_mm': mm,
  'condition': cond,
  'uv_index': uv,
  'wind_kmh': 10,
  'is_day': hour % 24 >= 6 && hour % 24 < 18,
  'rain_level': rain,
  'heat_level': heat,
};

Map<String, dynamic> forecastJson({
  Map<String, dynamic>? current,
  List<Map<String, dynamic>>? hours,
  Map<String, dynamic>? outlook,
  List<Map<String, dynamic>> watch = const [],
  String fetchedAt = '2026-10-06T02:15:00+00:00',
}) => {
  'current':
      current ??
      {
        'time': iso(10),
        'temperature_c': 28.4,
        'heat_index_c': 31.0,
        'humidity': 75,
        'precip_mm': 0,
        'condition': 'partly_cloudy',
        'wind_kmh': 10,
        'is_day': true,
        'rain_level': 'none',
        'heat_level': 'caution',
      },
  'hours': hours ?? [for (var h = 10; h < 34; h++) hourJson(h)],
  'days': [
    {
      'date': '2026-10-06',
      'condition': 'thunderstorm',
      'temp_max_c': 30,
      'temp_min_c': 24,
      'rain_mm': 11,
      'rain_chance': 100,
    },
    {
      'date': '2026-10-07',
      'condition': 'cloudy',
      'temp_max_c': 30,
      'temp_min_c': 25,
      'rain_mm': 0.4,
      'rain_chance': 60,
    },
    {
      'date': '2026-10-08',
      'condition': 'rain',
      'temp_max_c': 29,
      'temp_min_c': 24,
      'rain_mm': 6,
      'rain_chance': 80,
    },
  ],
  'outlook':
      outlook ??
      {
        'heat_index_max_c': 31.0,
        'heat_peak_at': iso(13),
        'heat_level': 'caution',
        'rain_level': 'none',
        'rain_starts_at': null,
        'thunder_at': null,
        'uv_max': 5,
        'wind_max_kmh': 12,
      },
  'watch': watch,
  'place': {'lat': 11.55, 'lng': 124.4},
  'source': 'Open-Meteo',
  'fetched_at': fetchedAt,
  'stale': false,
};

WeatherForecast fc({
  Map<String, dynamic>? current,
  List<Map<String, dynamic>>? hours,
  Map<String, dynamic>? outlook,
  List<Map<String, dynamic>> watch = const [],
  String fetchedAt = '2026-10-06T02:15:00+00:00',
}) => WeatherForecast.fromJson(
  forecastJson(
    current: current,
    hours: hours,
    outlook: outlook,
    watch: watch,
    fetchedAt: fetchedAt,
  ),
);

Map<String, dynamic> window(
  String kind,
  String level,
  int start,
  int end, {
  double peak = 5,
  int day = 6,
}) => {
  'kind': kind,
  'level': level,
  'starts_at': iso(start, day: day),
  'ends_at': iso(end, day: day),
  'peak_at': iso(start, day: day),
  'peak': peak,
};

Map<String, dynamic> outlook({
  double hi = 31,
  int peak = 13,
  String heat = 'caution',
  String rain = 'none',
  int? rainAt,
  int? thunderAt,
  double uv = 5,
  double wind = 12,
}) => {
  'heat_index_max_c': hi,
  'heat_peak_at': iso(peak),
  'heat_level': heat,
  'rain_level': rain,
  'rain_starts_at': rainAt == null ? null : iso(rainAt),
  'thunder_at': thunderAt == null ? null : iso(thunderAt),
  'uv_max': uv,
  'wind_max_kmh': wind,
};

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('Ziren\'s headline', () {
    test('a thunderstorm within six hours comes first', () {
      final a = WeatherAdvice.from(
        fc(
          outlook: outlook(
            heat: 'extreme_caution',
            hi: 35,
            thunderAt: 15,
            rain: 'moderate',
            rainAt: 15,
          ),
          watch: [
            window('thunderstorm', 'moderate', 15, 16),
            window('rain', 'moderate', 15, 16),
          ],
        ),
        now,
      );
      expect(a.headline.kind, WeatherHeadlineKind.thunderSoon);
      expect(a.headline.at, DateTime.parse(iso(15)));
      expect(a.tips.first, WeatherTip.thunderIndoors);
      // Heat is still said, after the rain.
      expect(a.tips, contains(WeatherTip.heatWater));
      expect(a.tips.length, lessThanOrEqualTo(WeatherAdvice.maxTips));
    });

    test('heavy rain for three hours brings the landslide reminder', () {
      final a = WeatherAdvice.from(
        fc(
          outlook: outlook(rain: 'heavy', rainAt: 13),
          watch: [window('rain', 'heavy', 13, 16, peak: 9)],
        ),
        now,
      );
      expect(a.headline.kind, WeatherHeadlineKind.heavyRainSoon);
      expect(a.tips.take(2), [
        WeatherTip.heavyRainFlood,
        WeatherTip.landslideWatch,
      ]);
    });

    test('rain more than six hours away is not "soon"', () {
      final a = WeatherAdvice.from(
        fc(
          outlook: outlook(rain: 'moderate', rainAt: 18),
          watch: [window('rain', 'moderate', 18, 19)],
        ),
        now,
      );
      expect(a.headline.kind, isNot(WeatherHeadlineKind.rainSoon));
    });

    test('light rain soon: bring an umbrella', () {
      final a = WeatherAdvice.from(
        fc(outlook: outlook(rain: 'light', rainAt: 12)),
        now,
      );
      expect(a.headline.kind, WeatherHeadlineKind.rainSoon);
      expect(a.tips, [WeatherTip.umbrella]);
    });

    test('raining now', () {
      final a = WeatherAdvice.from(
        fc(
          current: {
            'time': iso(10),
            'temperature_c': 25.0,
            'heat_index_c': 25.0,
            'condition': 'rain',
            'is_day': true,
            'rain_level': 'moderate',
            'heat_level': 'none',
            'precip_mm': 3.0,
          },
          hours: [
            hourJson(10, mm: 3, rain: 'moderate', cond: 'rain'),
            for (var h = 11; h < 34; h++) hourJson(h),
          ],
        ),
        now,
      );
      expect(a.headline.kind, WeatherHeadlineKind.rainingNow);
      expect(a.tips, [WeatherTip.umbrella, WeatherTip.roadSlippery]);
    });

    test('dangerous heat', () {
      final a = WeatherAdvice.from(
        fc(outlook: outlook(heat: 'danger', hi: 44, peak: 13, uv: 10)),
        now,
      );
      expect(a.headline.kind, WeatherHeadlineKind.heatDanger);
      expect(a.headline.value, 44);
      expect(a.tips, [
        WeatherTip.heatDangerWork,
        WeatherTip.heatStrokeSigns,
        WeatherTip.heatWater,
      ]);
    });

    test('hot ("extreme caution") with a strong sun', () {
      final a = WeatherAdvice.from(
        fc(outlook: outlook(heat: 'extreme_caution', hi: 36, uv: 9)),
        now,
      );
      expect(a.headline.kind, WeatherHeadlineKind.heatHigh);
      expect(a.tips, [
        WeatherTip.heatWater,
        WeatherTip.heatShade,
        WeatherTip.uvStrong,
      ]);
    });

    test('a fair day suggests checking the go-bag', () {
      final a = WeatherAdvice.from(fc(), now);
      expect(a.headline.kind, WeatherHeadlineKind.fairDay);
      expect(a.headline.value, 28.4);
      expect(a.tips, [WeatherTip.goBagCheck]);
    });

    test('a saved forecast never talks about a storm that is over', () {
      // Fetched at 8 AM; the storm was 12-1 PM; it is now 3:30 PM.
      final later = DateTime.parse('2026-10-06T15:30:00+08:00');
      final a = WeatherAdvice.from(
        fc(
          outlook: outlook(
            thunderAt: 12,
            rain: 'heavy',
            rainAt: 12,
            heat: 'extreme_caution',
            peak: 11,
          ),
          watch: [window('thunderstorm', 'heavy', 12, 13)],
          fetchedAt: '2026-10-06T00:00:00+00:00',
        ),
        later,
      );
      expect(a.headline.kind, isNot(WeatherHeadlineKind.thunderSoon));
      expect(a.headline.kind, isNot(WeatherHeadlineKind.heavyRainSoon));
      expect(a.headline.kind, isNot(WeatherHeadlineKind.heatHigh));
      expect(a.headline.kind, isNot(WeatherHeadlineKind.rainingNow));
    });
  });

  group('weather push', () {
    Map<String, String> push({
      String slot = 'rain',
      String level = 'heavy',
      String thunder = '0',
      int start = 15,
      int end = 17,
    }) => {
      'ziren_weather': slot,
      'level': level,
      'thunder': thunder,
      'starts_at': iso(start),
      'ends_at': iso(end),
      'town': 'Naval',
    };

    test('is read back into a reminder', () {
      final p = WeatherReminderPlan.fromPush(push(thunder: '1'))!;
      expect(p.slot, ReminderSlot.rain);
      expect(p.thunder, isTrue);
      expect(p.rainLevel, RainLevel.heavy);
      expect(p.startsAt, DateTime.parse(iso(15)));
      final heat =
          WeatherReminderPlan.fromPush(push(slot: 'heat', level: 'danger'))!;
      expect(heat.slot, ReminderSlot.heat);
      expect(heat.heatLevel, HeatLevel.danger);
      expect(heat.rainLevel, RainLevel.none);
    });

    test('anything else is not a weather reminder', () {
      expect(WeatherReminderPlan.fromPush({'ziren_alert': 'nearby'}), isNull);
      expect(
        WeatherReminderPlan.fromPush({
          'ziren_weather': 'snow',
          'starts_at': iso(15),
          'ends_at': iso(16),
        }),
        isNull,
      );
      expect(WeatherReminderPlan.fromPush({'ziren_weather': 'rain'}), isNull);
    });

    test('the notification words', () {
      final words = WeatherWords(en, 'en');
      final storm =
          WeatherReminderPlan.fromPush(push(thunder: '1', level: 'moderate'))!;
      expect(words.reminderTitle(storm), 'Thunderstorm in about an hour');
      expect(words.reminderBody(storm), en.weatherTipThunderIndoors);
      final heavy = WeatherReminderPlan.fromPush(push())!;
      expect(words.reminderTitle(heavy), 'Heavy rain in about an hour');
      expect(words.reminderBody(heavy), en.weatherTipHeavyRainFlood);
      final rain = WeatherReminderPlan.fromPush(push(level: 'moderate'))!;
      expect(words.reminderTitle(rain), 'Rain in about an hour');
      final heat =
          WeatherReminderPlan.fromPush(
            push(slot: 'heat', level: 'danger', start: 12),
          )!;
      expect(
        words.reminderTitle(heat),
        'Dangerous heat from ${words.time(DateTime.parse(iso(12)))}',
      );
    });

    test(
      'a push that arrives after the weather started shows nothing',
      () async {
        SharedPreferences.setMockInitialValues({});
        final shown = await WeatherReminders.showFromPush(
          push(start: 10, end: 12),
          now: DateTime.parse('2026-10-06T10:20:00+08:00'),
        );
        expect(shown, isFalse);
      },
    );

    test('reminders switched off: nothing is shown', () async {
      SharedPreferences.setMockInitialValues({
        'weather.reminders.enabled': false,
      });
      final shown = await WeatherReminders.showFromPush(push(), now: now);
      expect(shown, isFalse);
    });
  });

  test('a backend window with an unknown kind is skipped, not a crash', () {
    final f = WeatherForecast.fromJson(
      forecastJson(
        watch: [
          window('snow', 'heavy', 12, 13),
          window('rain', 'moderate', 14, 15),
        ],
      ),
    );
    expect(f.watch.map((w) => w.kind), [WatchKind.rain]);
  });

  group('Home card', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pump(WidgetTester tester, WeatherForecast f) async {
      final store = WeatherStore.forTest(const WeatherRepository())
        ..debugSet(f);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeatherCard(store: store, now: now),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows now, the heat class and Ziren\'s reminders', (
      tester,
    ) async {
      await pump(
        tester,
        fc(
          current: {
            'time': iso(10),
            'temperature_c': 30.0,
            'heat_index_c': 36.0,
            'condition': 'partly_cloudy',
            'is_day': true,
            'rain_level': 'none',
            'heat_level': 'extreme_caution',
            'precip_mm': 0,
          },
          outlook: outlook(heat: 'extreme_caution', hi: 36, uv: 9),
          fetchedAt: '2026-10-06T02:15:00+00:00',
        ),
      );
      expect(find.textContaining('30°C', findRichText: true), findsOneWidget);
      expect(find.text('Feels like 36°C'), findsOneWidget);
      expect(find.text('Extreme caution'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weather-tip-heatWater')),
        findsOneWidget,
      );
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.textContaining('PAGASA'), findsOneWidget);
    });

    // User report 2026-10-08: the card did not make it plain whether the day
    // was about rain or about heat. The top now says it in colour, picture
    // and words, with a Rain and a Heat gauge side by side.
    testWidgets('rain coming: the top says rain, the rain gauge is filled', (
      tester,
    ) async {
      await pump(
        tester,
        fc(
          outlook: outlook(rain: 'heavy', rainAt: 13),
          watch: [window('rain', 'heavy', 13, 16, peak: 9)],
        ),
      );
      expect(find.byKey(const ValueKey('weather-hero-rain')), findsOneWidget);
      expect(find.text('Heavy rain from 1 PM'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);
      expect(find.text('from 1 PM'), findsOneWidget);
      expect(find.byKey(const ValueKey('weather-meter-heat')), findsOneWidget);
    });

    testWidgets('a hot day: the top says heat, not rain', (tester) async {
      await pump(
        tester,
        fc(
          current: {
            'time': iso(10),
            'temperature_c': 33.0,
            'heat_index_c': 43.0,
            'condition': 'clear',
            'is_day': true,
            'rain_level': 'none',
            'heat_level': 'danger',
            'precip_mm': 0,
          },
          outlook: outlook(heat: 'danger', hi: 44, peak: 13),
          watch: [window('heat', 'danger', 11, 15, peak: 44)],
        ),
      );
      expect(find.byKey(const ValueKey('weather-hero-heat')), findsOneWidget);
      expect(find.byKey(const ValueKey('weather-hero-rain')), findsNothing);
      expect(find.text('Dangerous heat'), findsOneWidget);
      expect(find.text('No rain'), findsOneWidget);
      expect(find.text('Danger'), findsOneWidget);
      expect(find.text('feels 44°C at 1 PM'), findsOneWidget);
    });

    testWidgets('the chance of rain shows only for hours that rain', (
      tester,
    ) async {
      await pump(
        tester,
        fc(
          hours: [
            hourJson(10, chance: 100),
            hourJson(11, chance: 70, mm: 1.2, rain: 'light', cond: 'drizzle'),
            for (var h = 12; h < 34; h++) hourJson(h, chance: 95),
          ],
        ),
      );
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      expect(find.text('95%'), findsNothing);
    });

    testWidgets('the reminder switch turns reminders off and on', (
      tester,
    ) async {
      await pump(tester, fc());
      final sw = find.byKey(const ValueKey('weather-reminders-switch'));
      expect(tester.widget<Switch>(sw).value, isTrue);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(sw).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('weather.reminders.enabled'), isFalse);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(prefs.getBool('weather.reminders.enabled'), isTrue);
    });
  });
}
