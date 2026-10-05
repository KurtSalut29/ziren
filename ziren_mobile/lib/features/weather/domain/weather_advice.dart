/// What Ziren says about the weather on Home, and the reminder a weather push
/// carries. Pure: a forecast and a clock in, decisions out, so every rule
/// here is tested without a phone (test/weather_advice_test.dart).
///
/// The words live in the ARB files (WeatherWords); this file only picks which
/// ones.
library;

import 'weather_forecast.dart';

/// How far ahead Ziren talks about rain or a thunderstorm on Home: far enough
/// to plan a trip out, near enough to still be what the resident cares about
/// when they look.
const kWeatherSoon = Duration(hours: 6);

/// The one thing Ziren says first, in the mascot card.
enum WeatherHeadlineKind {
  thunderSoon,
  heavyRainSoon,
  rainingNow,
  rainSoon,
  heatDanger,
  heatHigh,
  fairDay,
  fairNight,
}

class WeatherHeadline {
  const WeatherHeadline(this.kind, {this.at, this.value});

  final WeatherHeadlineKind kind;

  /// When it starts (rain, thunderstorm) or peaks (heat).
  final DateTime? at;

  /// Heat index for the heat lines, temperature for the fair lines.
  final double? value;
}

/// Ziren's reminders, most important first.
enum WeatherTip {
  thunderIndoors,
  heavyRainFlood,
  landslideWatch,
  umbrella,
  roadSlippery,
  heatDangerWork,
  heatStrokeSigns,
  heatWater,
  heatShade,
  uvStrong,
  windStrong,
  goBagCheck,
}

class WeatherAdvice {
  const WeatherAdvice({required this.headline, required this.tips});

  final WeatherHeadline headline;
  final List<WeatherTip> tips;

  static const maxTips = 3;

  static WeatherAdvice from(WeatherForecast f, DateTime now) {
    final o = f.outlook;
    final soon = now.add(kWeatherSoon);
    // Starts within the next six hours and is not already over. "Over"
    // matters for a forecast read back from the phone's saved copy, where
    // this afternoon's storm may be in the past. An outlook time names an
    // hour, so it is over when that hour ends.
    bool isSoon(DateTime? t, {DateTime? until}) =>
        t != null &&
        t.isBefore(soon) &&
        (until ?? t.add(const Duration(hours: 1))).isAfter(now);
    bool windowSoon(WeatherWindow w) => isSoon(w.startsAt, until: w.endsAt);

    final thunder = f.watch.where(
      (w) => w.kind == WatchKind.thunderstorm && windowSoon(w),
    );
    final heavy = f.watch.where(
      (w) =>
          w.kind != WatchKind.heat &&
          w.rainLevel.atLeast(RainLevel.heavy) &&
          windowSoon(w),
    );
    // The hour we are in, from the forecast's list (the "current" block is
    // only current when the forecast is fresh).
    final thisHour =
        f.hours
            .where(
              (h) =>
                  !h.time.isAfter(now) &&
                  h.time.add(const Duration(hours: 1)).isAfter(now),
            )
            .firstOrNull;
    final fresh = now.difference(f.fetchedAt) < const Duration(hours: 1);
    final rainingNow =
        (fresh && f.current.rainLevel.atLeast(RainLevel.light)) ||
        (thisHour != null &&
            thisHour.rainLevel.atLeast(RainLevel.light) &&
            (thisHour.condition.isWet || (fresh && f.current.condition.isWet)));

    // The hottest hour has not passed yet (see isSoon on saved copies).
    final heatAhead =
        o.heatPeakAt == null ||
        o.heatPeakAt!.add(const Duration(hours: 1)).isAfter(now);

    final tips = <WeatherTip>[];
    void add(WeatherTip t) {
      if (!tips.contains(t)) tips.add(t);
    }

    final WeatherHeadline headline;
    if (thunder.isNotEmpty || isSoon(o.thunderAt)) {
      headline = WeatherHeadline(
        WeatherHeadlineKind.thunderSoon,
        at: thunder.isNotEmpty ? thunder.first.startsAt : o.thunderAt,
      );
      add(WeatherTip.thunderIndoors);
      if (heavy.isNotEmpty) add(WeatherTip.heavyRainFlood);
      add(WeatherTip.roadSlippery);
    } else if (heavy.isNotEmpty) {
      final w = heavy.first;
      headline = WeatherHeadline(
        WeatherHeadlineKind.heavyRainSoon,
        at: w.startsAt,
      );
      add(WeatherTip.heavyRainFlood);
      // Hours of heavy rain, or a downpour, is when slopes give way.
      if (w.rainLevel.atLeast(RainLevel.intense) ||
          w.endsAt.difference(w.startsAt) >= const Duration(hours: 3)) {
        add(WeatherTip.landslideWatch);
      }
      add(WeatherTip.roadSlippery);
    } else if (rainingNow) {
      headline = const WeatherHeadline(WeatherHeadlineKind.rainingNow);
      add(WeatherTip.umbrella);
      add(WeatherTip.roadSlippery);
    } else if (isSoon(o.rainStartsAt)) {
      headline = WeatherHeadline(
        WeatherHeadlineKind.rainSoon,
        at: o.rainStartsAt,
      );
      add(WeatherTip.umbrella);
      if (o.rainLevel.atLeast(RainLevel.moderate)) add(WeatherTip.roadSlippery);
    } else if (heatAhead && o.heatLevel.atLeast(HeatLevel.danger)) {
      headline = WeatherHeadline(
        WeatherHeadlineKind.heatDanger,
        at: o.heatPeakAt,
        value: o.heatIndexMaxC,
      );
    } else if (heatAhead && o.heatLevel == HeatLevel.extremeCaution) {
      headline = WeatherHeadline(
        WeatherHeadlineKind.heatHigh,
        at: o.heatPeakAt,
        value: o.heatIndexMaxC,
      );
    } else {
      final isDay =
          fresh ? f.current.isDay : (thisHour?.isDay ?? f.current.isDay);
      headline = WeatherHeadline(
        isDay ? WeatherHeadlineKind.fairDay : WeatherHeadlineKind.fairNight,
        value:
            fresh
                ? f.current.temperatureC
                : (thisHour?.temperatureC ?? f.current.temperatureC),
      );
    }

    // Heat is said after rain, not instead of it: a hot morning before an
    // afternoon storm needs both.
    if (heatAhead && o.heatLevel.atLeast(HeatLevel.danger)) {
      add(WeatherTip.heatDangerWork);
      add(WeatherTip.heatStrokeSigns);
      add(WeatherTip.heatWater);
    } else if (heatAhead && o.heatLevel == HeatLevel.extremeCaution) {
      add(WeatherTip.heatWater);
      add(WeatherTip.heatShade);
    }
    if (o.windMaxKmh >= 40) add(WeatherTip.windStrong);
    if (o.uvMax >= 8) add(WeatherTip.uvStrong);
    if (tips.isEmpty) add(WeatherTip.goBagCheck);

    return WeatherAdvice(
      headline: headline,
      tips: tips.take(maxTips).toList(growable: false),
    );
  }
}

/// The two reminder slots: one for rain (or a thunderstorm), one for heat.
/// Each has one notification id, so a newer reminder replaces an older one.
enum ReminderSlot { rain, heat }

/// One reminder, as the backend's weather push carries it
/// (ziren_backend app/services/weather_alerts.py decides when it is due:
/// an hour before, one per spell, only heavy rain at night).
class WeatherReminderPlan {
  const WeatherReminderPlan({
    required this.slot,
    required this.startsAt,
    required this.endsAt,
    required this.thunder,
    required this.rainLevel,
    required this.heatLevel,
    this.peak,
  });

  final ReminderSlot slot;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool thunder;
  final RainLevel rainLevel;
  final HeatLevel heatLevel;
  final double? peak;

  /// Null for any push that is not a weather reminder, or one this app
  /// version does not understand.
  static WeatherReminderPlan? fromPush(Map<String, dynamic> data) {
    final slot = switch (data['ziren_weather']) {
      'rain' => ReminderSlot.rain,
      'heat' => ReminderSlot.heat,
      _ => null,
    };
    final start = DateTime.tryParse('${data['starts_at']}');
    final end = DateTime.tryParse('${data['ends_at']}');
    if (slot == null || start == null || end == null) return null;
    final level = data['level'];
    return WeatherReminderPlan(
      slot: slot,
      startsAt: start,
      endsAt: end,
      thunder: data['thunder'] == '1',
      rainLevel:
          slot == ReminderSlot.rain ? RainLevel.parse(level) : RainLevel.none,
      heatLevel:
          slot == ReminderSlot.heat ? HeatLevel.parse(level) : HeatLevel.none,
      peak: double.tryParse('${data['peak']}'),
    );
  }
}
