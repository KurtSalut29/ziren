import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/weather_reminders.dart';
import '../data/weather_store.dart';
import '../domain/weather_advice.dart';
import '../domain/weather_forecast.dart';
import 'weather_words.dart';

/// Resident Home's weather card: now, the next hours, Ziren's reminders for
/// them, the next days, and the switch for the phone reminders.
///
/// Colours follow the app's rules: rain is info blue, heat is warning amber
/// (even at "danger" - red stays reserved for critical incidents), and an
/// ordinary day is neutral.
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key, required this.store, this.now});

  final WeatherStore store;

  /// Fixed clock for tests and previews.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final f = store.forecast;
        if (f == null) {
          return _Shell(
            child: _Placeholder(
              loading: store.loading || !store.failed,
              text: store.failed ? t.weatherUnavailable : t.weatherLoading,
            ),
          );
        }
        return _Shell(
          child: _Body(
            forecast: f,
            fromCache: store.fromCache,
            now: now ?? DateTime.now(),
          ),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.loading, required this.text});

  final bool loading;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child:
                loading
                    ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ZirenTokens.textMuted,
                    )
                    : Icon(
                      LucideIcons.cloud_off,
                      size: 20,
                      color: ZirenTokens.textMuted,
                    ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: ZirenTokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The accent for what the forecast is mostly about.
Color _accent(WeatherHeadlineKind k) => switch (k) {
  WeatherHeadlineKind.thunderSoon ||
  WeatherHeadlineKind.heavyRainSoon ||
  WeatherHeadlineKind.rainingNow ||
  WeatherHeadlineKind.rainSoon => ZirenTokens.systemInfo,
  WeatherHeadlineKind.heatDanger ||
  WeatherHeadlineKind.heatHigh => ZirenTokens.systemWarning,
  WeatherHeadlineKind.fairDay ||
  WeatherHeadlineKind.fairNight => ZirenTokens.systemSuccess,
};

class _Body extends StatelessWidget {
  const _Body({
    required this.forecast,
    required this.fromCache,
    required this.now,
  });

  final WeatherForecast forecast;
  final bool fromCache;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final words = WeatherWords(
      t,
      Localizations.localeOf(context).toLanguageTag(),
    );
    final advice = WeatherAdvice.from(forecast, now);
    final accent = _accent(advice.headline.kind);

    // Hours not yet over, so a saved copy never shows this morning as "now".
    final hours =
        forecast.hours
            .where((h) => h.time.add(const Duration(hours: 1)).isAfter(now))
            .take(12)
            .toList();
    final first = hours.isNotEmpty ? hours.first : null;
    final fresh = !fromCache && now.difference(forecast.fetchedAt).inHours < 1;
    final cond =
        fresh
            ? forecast.current.condition
            : (first?.condition ?? forecast.current.condition);
    final isDay = fresh ? forecast.current.isDay : (first?.isDay ?? true);
    final temp = fresh ? forecast.current.temperatureC : first?.temperatureC;
    final feels = fresh ? forecast.current.heatIndexC : first?.heatIndexC;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Now: what kind of day it is, at a glance ────
        _Hero(
          mood: _Mood.of(advice.headline),
          moodLabel: _moodLabel(t, words, advice.headline),
          temp: temp,
          feels: feels,
          condition: words.condition(cond),
          conditionIcon: WeatherWords.conditionIcon(cond, isDay: isDay),
          title: t.weatherCardTitle,
          meters: [
            _Meter(
              key: const ValueKey('weather-meter-rain'),
              icon: LucideIcons.cloud_rain,
              label: t.weatherMeterRain,
              value: _rainWord(t, forecast.outlook.rainLevel),
              detail:
                  forecast.outlook.rainLevel == RainLevel.none ||
                          forecast.outlook.rainStartsAt == null
                      ? t.weatherMeterToday
                      : t.weatherMeterFrom(
                        words.time(forecast.outlook.rainStartsAt!),
                      ),
              steps: 5,
              filled: forecast.outlook.rainLevel.index,
              color: ZirenTokens.systemInfo,
            ),
            _Meter(
              key: const ValueKey('weather-meter-heat'),
              icon: LucideIcons.thermometer_sun,
              label: t.weatherMeterHeat,
              value:
                  words.heat(forecast.outlook.heatLevel) ?? t.weatherHeatNormal,
              detail:
                  forecast.outlook.heatIndexMaxC == null
                      ? t.weatherMeterToday
                      : forecast.outlook.heatPeakAt == null
                      ? WeatherWords.temp(forecast.outlook.heatIndexMaxC)
                      : t.weatherMeterPeak(
                        WeatherWords.temp(forecast.outlook.heatIndexMaxC),
                        words.time(forecast.outlook.heatPeakAt!),
                      ),
              steps: 4,
              filled: forecast.outlook.heatLevel.index,
              color: ZirenTokens.systemWarning,
            ),
          ],
        ),

        // ── Next hours ───────────────────────────────────
        if (hours.isNotEmpty) ...[
          _Rule(),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space12,
                vertical: ZirenTokens.space10,
              ),
              itemCount: hours.length,
              separatorBuilder:
                  (_, _) => const SizedBox(width: ZirenTokens.space4),
              itemBuilder:
                  (context, i) => _HourCell(
                    hour: hours[i],
                    label: i == 0 ? t.weatherNow : words.time(hours[i].time),
                    rainLabel: t.weatherRainChanceLabel,
                  ),
            ),
          ),
        ],

        // ── Ziren's reminders ────────────────────────────
        _Rule(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            ZirenTokens.space4,
          ),
          child: Text(
            t.weatherTipsTitle.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color:
                  ZirenTokens.isDark
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.brandActive,
            ),
          ),
        ),
        for (final tip in advice.tips)
          _TipRow(
            key: ValueKey('weather-tip-${tip.name}'),
            icon: WeatherWords.tipIcon(tip),
            text: words.tip(tip),
            color: accent,
          ),
        const SizedBox(height: ZirenTokens.space8),

        // ── Next days ────────────────────────────────────
        if (forecast.days.length > 1) ...[
          _Rule(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZirenTokens.space12,
              vertical: ZirenTokens.space10,
            ),
            child: Row(
              children: [
                for (final (i, d) in forecast.days.take(3).indexed)
                  Expanded(
                    child: _DayCell(
                      day: d,
                      label: _dayLabel(context, t, d.date, i),
                      condition: words.condition(d.condition),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ── Phone reminders + source ─────────────────────
        _Rule(),
        const _ReminderSwitch(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            0,
            ZirenTokens.space16,
            ZirenTokens.space12,
          ),
          child: Text(
            fromCache || forecast.stale
                ? t.weatherOldNote(_stamp(context, words, forecast.fetchedAt))
                : t.weatherSourceNote(
                  _stamp(context, words, forecast.fetchedAt),
                ),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: ZirenTokens.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  static String _rainWord(AppLocalizations t, RainLevel l) => switch (l) {
    RainLevel.none => t.weatherRainNone,
    RainLevel.light => t.weatherRainLight,
    RainLevel.moderate => t.weatherRainModerate,
    RainLevel.heavy => t.weatherRainHeavy,
    RainLevel.intense => t.weatherRainIntense,
    RainLevel.torrential => t.weatherRainTorrential,
  };

  /// The verdict in a few words: rain or heat, and from when.
  static String _moodLabel(
    AppLocalizations t,
    WeatherWords words,
    WeatherHeadline h,
  ) {
    final at = h.at == null ? '' : words.time(h.at!);
    return switch (h.kind) {
      WeatherHeadlineKind.thunderSoon =>
        at.isEmpty ? t.weatherCondThunderstorm : t.weatherMoodStorm(at),
      WeatherHeadlineKind.heavyRainSoon =>
        at.isEmpty ? t.weatherCondHeavyRain : t.weatherMoodHeavyRain(at),
      WeatherHeadlineKind.rainingNow => t.weatherMoodRainingNow,
      WeatherHeadlineKind.rainSoon =>
        at.isEmpty ? t.weatherCondRain : t.weatherMoodRainSoon(at),
      WeatherHeadlineKind.heatDanger => t.weatherMoodHeatDanger,
      WeatherHeadlineKind.heatHigh => t.weatherMoodHeat,
      WeatherHeadlineKind.fairDay => t.weatherMoodFair,
      WeatherHeadlineKind.fairNight => t.weatherMoodFairNight,
    };
  }

  String _stamp(BuildContext context, WeatherWords words, DateTime at) {
    final local = at.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final clock = words.time(local);
    if (day == today) return clock;
    return '${MaterialLocalizations.of(context).formatShortMonthDay(local)}, $clock';
  }

  String _dayLabel(
    BuildContext context,
    AppLocalizations t,
    DateTime date,
    int index,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final diff =
        DateTime(date.year, date.month, date.day).difference(today).inDays;
    if (diff == 0) return t.weatherToday;
    if (diff == 1) return t.weatherTomorrow;
    return MaterialLocalizations.of(context).formatShortMonthDay(date);
  }
}

class _Rule extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: ZirenTokens.surfaceBorder);
}

class _HourCell extends StatelessWidget {
  const _HourCell({
    required this.hour,
    required this.label,
    required this.rainLabel,
  });

  final WeatherHour hour;
  final String label;
  final String Function(String chance) rainLabel;

  @override
  Widget build(BuildContext context) {
    // The chance of rain is shown only for hours with rain worth the name:
    // the models say 90-100 % most afternoons here, often for no rain at all.
    final wet = hour.rainLevel.atLeast(RainLevel.light);
    final chance = hour.rainChance;
    final hot = hour.heatLevel.atLeast(HeatLevel.extremeCaution);
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
          Icon(
            WeatherWords.conditionIcon(hour.condition, isDay: hour.isDay),
            size: 20,
            color:
                wet
                    ? ZirenTokens.systemInfo
                    : hot
                    ? ZirenTokens.systemWarning
                    : ZirenTokens.textSecondary,
          ),
          Text(
            WeatherWords.temp(hour.temperatureC).replaceAll('C', ''),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ZirenTokens.textPrimary,
            ),
          ),
          SizedBox(
            height: 14,
            child:
                wet && chance != null
                    ? Semantics(
                      label: rainLabel('${chance.round()}%'),
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.droplet,
                            size: 10,
                            color: ZirenTokens.systemInfo,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${chance.round()}%',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: ZirenTokens.systemInfo,
                            ),
                          ),
                        ],
                      ),
                    )
                    : null,
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space6,
        ZirenTokens.space16,
        ZirenTokens.space6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.condition,
  });

  final WeatherDay day;
  final String label;
  final String condition;

  @override
  Widget build(BuildContext context) {
    final wet = (day.rainMm ?? 0) >= 2.5;
    String deg(double? c) => c == null ? '–' : '${c.round()}°';
    return Semantics(
      label: '$label, $condition, ${deg(day.tempMinC)} – ${deg(day.tempMaxC)}',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            WeatherWords.conditionIcon(day.condition),
            size: 20,
            color: wet ? ZirenTokens.systemInfo : ZirenTokens.textSecondary,
          ),
          const SizedBox(height: 4),
          Text(
            '${deg(day.tempMinC)} – ${deg(day.tempMaxC)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: ZirenTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderSwitch extends StatefulWidget {
  const _ReminderSwitch();

  @override
  State<_ReminderSwitch> createState() => _ReminderSwitchState();
}

class _ReminderSwitchState extends State<_ReminderSwitch> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    WeatherReminders.isEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final on = _on ?? true;
    return MergeSemantics(
      child: InkWell(
        onTap: _on == null ? null : () => _set(!on),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space10,
            ZirenTokens.space8,
            ZirenTokens.space8,
          ),
          child: Row(
            children: [
              Icon(
                on ? LucideIcons.bell_ring : LucideIcons.bell_off,
                size: 18,
                color: on ? ZirenTokens.brandOrange : ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.weatherRemindersToggle,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.weatherRemindersHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('weather-reminders-switch'),
                value: on,
                activeTrackColor: ZirenTokens.brandOrange,
                onChanged: _on == null ? null : _set,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _set(bool v) async {
    setState(() => _on = v);
    await WeatherReminders.setEnabled(v);
  }
}

/// What kind of day the card is about. One look at the colour, the big
/// picture and the label should answer "rain or heat?" (user report
/// 2026-10-08: the old small icon left that unclear).
enum _Mood {
  storm,
  rain,
  heat,
  fair,
  night;

  static _Mood of(WeatherHeadline h) => switch (h.kind) {
    WeatherHeadlineKind.thunderSoon => storm,
    WeatherHeadlineKind.heavyRainSoon ||
    WeatherHeadlineKind.rainingNow ||
    WeatherHeadlineKind.rainSoon => rain,
    WeatherHeadlineKind.heatDanger || WeatherHeadlineKind.heatHigh => heat,
    WeatherHeadlineKind.fairDay => fair,
    WeatherHeadlineKind.fairNight => night,
  };

  /// Rain is info blue and heat warning amber, as everywhere in the app (red
  /// stays for critical incidents); a fair day is the calm green.
  Color get color => switch (this) {
    storm || rain => ZirenTokens.systemInfo,
    heat => ZirenTokens.systemWarning,
    fair => ZirenTokens.systemSuccess,
    night => ZirenTokens.textSecondary,
  };

  IconData get icon => switch (this) {
    storm => LucideIcons.cloud_lightning,
    rain => LucideIcons.cloud_rain,
    heat => LucideIcons.sun,
    fair => LucideIcons.cloud_sun,
    night => LucideIcons.moon,
  };
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.mood,
    required this.moodLabel,
    required this.temp,
    required this.feels,
    required this.condition,
    required this.conditionIcon,
    required this.title,
    required this.meters,
  });

  final _Mood mood;
  final String moodLabel;
  final double? temp;
  final double? feels;
  final String condition;
  final IconData conditionIcon;
  final String title;
  final List<Widget> meters;

  @override
  Widget build(BuildContext context) {
    final c = mood.color;
    final dark = ZirenTokens.isDark;
    final feelsHigher =
        feels != null && temp != null && feels!.round() > temp!.round();
    return Container(
      key: ValueKey('weather-hero-${mood.name}'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.withValues(alpha: dark ? 0.30 : 0.20),
            c.withValues(alpha: dark ? 0.08 : 0.04),
          ],
        ),
      ),
      child: Stack(
        children: [
          // The picture of the day, large and faint behind the words.
          Positioned(
            right: -18,
            top: -14,
            child: ExcludeSemantics(
              child: Icon(
                mood.icon,
                size: 132,
                color: c.withValues(alpha: 0.16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                // The verdict: a solid pill in the day's colour.
                Container(
                  key: const ValueKey('weather-mood'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    // Deepened so white text on it stays readable (the bare
                    // sky blue and amber are too light for small white type).
                    color: Color.lerp(c, Colors.black, 0.24),
                    borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(mood.icon, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          moodLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZirenTokens.space10),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: ZirenTokens.surfaceCard,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.withValues(alpha: 0.45)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(conditionIcon, size: 28, color: c),
                    ),
                    const SizedBox(width: ZirenTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: WeatherWords.temp(temp),
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.8,
                                    color: ZirenTokens.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: '  $condition',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: ZirenTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (feelsHigher)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Wrap(
                                spacing: ZirenTokens.space6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    ).weatherFeelsLike(WeatherWords.temp(feels)),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: ZirenTokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, m) in meters.indexed) ...[
                      if (i > 0) const SizedBox(width: ZirenTokens.space8),
                      Expanded(child: m),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Rain: Heavy, from 3 PM" over a bar of steps - how much of it today.
class _Meter extends StatelessWidget {
  const _Meter({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.steps,
    required this.filled,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final int steps;
  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final on = filled > 0;
    final tint = on ? color : ZirenTokens.textMuted;
    return Semantics(
      label: '$label: $value, $detail',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          border: Border.all(
            color:
                on ? color.withValues(alpha: 0.45) : ZirenTokens.surfaceBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: tint),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: on ? ZirenTokens.textPrimary : ZirenTokens.textSecondary,
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var k = 0; k < steps; k++) ...[
                  if (k > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: k < filled ? color : ZirenTokens.surfaceBorder,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
