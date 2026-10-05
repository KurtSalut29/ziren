import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/weather_advice.dart';
import '../domain/weather_forecast.dart';

/// The words and icons for the weather, in the app's language. Shared by the
/// Home card, Ziren's message and the reminder notifications, so all three say
/// the same thing the same way.
class WeatherWords {
  const WeatherWords(this.t, this.localeTag);

  final AppLocalizations t;
  final String localeTag;

  /// "29°C".
  static String temp(double? c) => c == null ? '–' : '${c.round()}°C';

  /// "3 PM", or "3:30 PM" off the hour, in the phone's time zone.
  String time(DateTime at) {
    final local = at.toLocal();
    try {
      return (local.minute == 0
              ? DateFormat.j(localeTag)
              : DateFormat.jm(localeTag))
          .format(local);
    } catch (_) {
      // Date symbols not loaded for this locale (tests).
      return DateFormat.jm().format(local);
    }
  }

  String headline(WeatherHeadline h, String name) {
    final at = h.at == null ? '' : time(h.at!);
    final value = temp(h.value);
    return switch (h.kind) {
      WeatherHeadlineKind.thunderSoon => t.weatherHeadThunderSoon(at, name),
      WeatherHeadlineKind.heavyRainSoon => t.weatherHeadHeavyRainSoon(at, name),
      WeatherHeadlineKind.rainingNow => t.weatherHeadRainingNow(name),
      WeatherHeadlineKind.rainSoon => t.weatherHeadRainSoon(at, name),
      WeatherHeadlineKind.heatDanger => t.weatherHeadHeatDanger(
        value,
        at,
        name,
      ),
      WeatherHeadlineKind.heatHigh => t.weatherHeadHeatHigh(value, at, name),
      WeatherHeadlineKind.fairDay => t.weatherHeadFairDay(value, name),
      WeatherHeadlineKind.fairNight => t.weatherHeadFairNight(value, name),
    };
  }

  String tip(WeatherTip tip) => switch (tip) {
    WeatherTip.thunderIndoors => t.weatherTipThunderIndoors,
    WeatherTip.heavyRainFlood => t.weatherTipHeavyRainFlood,
    WeatherTip.landslideWatch => t.weatherTipLandslideWatch,
    WeatherTip.umbrella => t.weatherTipUmbrella,
    WeatherTip.roadSlippery => t.weatherTipRoadSlippery,
    WeatherTip.heatDangerWork => t.weatherTipHeatDangerWork,
    WeatherTip.heatStrokeSigns => t.weatherTipHeatStrokeSigns,
    WeatherTip.heatWater => t.weatherTipHeatWater,
    WeatherTip.heatShade => t.weatherTipHeatShade,
    WeatherTip.uvStrong => t.weatherTipUvStrong,
    WeatherTip.windStrong => t.weatherTipWindStrong,
    WeatherTip.goBagCheck => t.weatherTipGoBagCheck,
  };

  static IconData tipIcon(WeatherTip tip) => switch (tip) {
    WeatherTip.thunderIndoors => LucideIcons.zap,
    WeatherTip.heavyRainFlood => LucideIcons.droplets,
    WeatherTip.landslideWatch => LucideIcons.mountain,
    WeatherTip.umbrella => LucideIcons.umbrella,
    WeatherTip.roadSlippery => LucideIcons.car,
    WeatherTip.heatDangerWork => LucideIcons.hard_hat,
    WeatherTip.heatStrokeSigns => LucideIcons.heart_pulse,
    WeatherTip.heatWater => LucideIcons.glass_water,
    WeatherTip.heatShade => LucideIcons.shirt,
    WeatherTip.uvStrong => LucideIcons.sun,
    WeatherTip.windStrong => LucideIcons.wind,
    WeatherTip.goBagCheck => LucideIcons.backpack,
  };

  String condition(WeatherCondition c) => switch (c) {
    WeatherCondition.clear => t.weatherCondClear,
    WeatherCondition.mostlyClear => t.weatherCondMostlyClear,
    WeatherCondition.partlyCloudy => t.weatherCondPartlyCloudy,
    WeatherCondition.cloudy => t.weatherCondCloudy,
    WeatherCondition.fog => t.weatherCondFog,
    WeatherCondition.drizzle => t.weatherCondDrizzle,
    WeatherCondition.rain => t.weatherCondRain,
    WeatherCondition.heavyRain => t.weatherCondHeavyRain,
    WeatherCondition.thunderstorm => t.weatherCondThunderstorm,
  };

  static IconData conditionIcon(WeatherCondition c, {bool isDay = true}) =>
      switch (c) {
        WeatherCondition.clear => isDay ? LucideIcons.sun : LucideIcons.moon,
        WeatherCondition.mostlyClear || WeatherCondition.partlyCloudy =>
          isDay ? LucideIcons.cloud_sun : LucideIcons.cloud_moon,
        WeatherCondition.cloudy => LucideIcons.cloud,
        WeatherCondition.fog => LucideIcons.cloud_fog,
        WeatherCondition.drizzle => LucideIcons.cloud_drizzle,
        WeatherCondition.rain => LucideIcons.cloud_rain,
        WeatherCondition.heavyRain => LucideIcons.cloud_rain_wind,
        WeatherCondition.thunderstorm => LucideIcons.cloud_lightning,
      };

  /// Null below "caution": an ordinary day gets no heat label.
  String? heat(HeatLevel level) => switch (level) {
    HeatLevel.none => null,
    HeatLevel.caution => t.weatherHeatCaution,
    HeatLevel.extremeCaution => t.weatherHeatExtremeCaution,
    HeatLevel.danger => t.weatherHeatDanger,
    HeatLevel.extremeDanger => t.weatherHeatExtremeDanger,
  };

  // ── Reminder notifications ─────────────────────────────────────────

  String reminderTitle(WeatherReminderPlan p) {
    if (p.slot == ReminderSlot.heat) {
      return t.weatherNotifHeatTitle(time(p.startsAt));
    }
    if (p.thunder) return t.weatherNotifThunderTitle;
    if (p.rainLevel.atLeast(RainLevel.heavy)) {
      return t.weatherNotifHeavyRainTitle;
    }
    return t.weatherNotifRainTitle;
  }

  String reminderBody(WeatherReminderPlan p) {
    if (p.slot == ReminderSlot.heat) {
      return '${t.weatherTipHeatWater} ${t.weatherTipHeatDangerWork}';
    }
    if (p.thunder) return t.weatherTipThunderIndoors;
    if (p.rainLevel.atLeast(RainLevel.heavy)) return t.weatherTipHeavyRainFlood;
    return '${t.weatherTipUmbrella} ${t.weatherTipRoadSlippery}';
  }
}
