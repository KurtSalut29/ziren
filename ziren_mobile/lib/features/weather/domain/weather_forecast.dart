/// The forecast GET /weather/ returns, already graded by the backend
/// (weather_service.py): rain on PAGASA's rainfall-intensity scale, heat on
/// PAGASA's heat-index classes, and the windows worth a reminder.
///
/// The app only reads it and puts it into words. Every judgement about what
/// counts as heavy rain or dangerous heat lives on the backend, once.
library;

enum WeatherCondition {
  clear,
  mostlyClear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  heavyRain,
  thunderstorm;

  static WeatherCondition parse(Object? v) => switch (v) {
    'clear' => clear,
    'mostly_clear' => mostlyClear,
    'partly_cloudy' => partlyCloudy,
    'fog' => fog,
    'drizzle' => drizzle,
    'rain' => rain,
    'heavy_rain' => heavyRain,
    'thunderstorm' => thunderstorm,
    _ => cloudy,
  };

  bool get isWet =>
      this == drizzle ||
      this == rain ||
      this == heavyRain ||
      this == thunderstorm;
}

/// PAGASA rainfall intensity, by the amount forecast for the hour.
enum RainLevel {
  none,
  light,
  moderate,
  heavy,
  intense,
  torrential;

  static RainLevel parse(Object? v) =>
      RainLevel.values.firstWhere((l) => l.name == v, orElse: () => none);

  bool atLeast(RainLevel other) => index >= other.index;
}

/// PAGASA heat index classes.
enum HeatLevel {
  none,
  caution,
  extremeCaution,
  danger,
  extremeDanger;

  static HeatLevel parse(Object? v) => switch (v) {
    'caution' => caution,
    'extreme_caution' => extremeCaution,
    'danger' => danger,
    'extreme_danger' => extremeDanger,
    _ => none,
  };

  bool atLeast(HeatLevel other) => index >= other.index;
}

enum WatchKind {
  rain,
  thunderstorm,
  heat;

  static WatchKind? parse(Object? v) => switch (v) {
    'rain' => rain,
    'thunderstorm' => thunderstorm,
    'heat' => heat,
    _ => null,
  };
}

double? _d(Object? v) => v is num ? v.toDouble() : null;
DateTime? _t(Object? v) => v is String ? DateTime.tryParse(v) : null;

class WeatherNow {
  const WeatherNow({
    required this.temperatureC,
    required this.heatIndexC,
    required this.condition,
    required this.isDay,
    required this.rainLevel,
    required this.heatLevel,
    this.humidity,
    this.windKmh,
  });

  final double? temperatureC;
  final double? heatIndexC;
  final double? humidity;
  final double? windKmh;
  final WeatherCondition condition;
  final bool isDay;
  final RainLevel rainLevel;
  final HeatLevel heatLevel;

  factory WeatherNow.fromJson(Map<String, dynamic> j) => WeatherNow(
    temperatureC: _d(j['temperature_c']),
    heatIndexC: _d(j['heat_index_c']),
    humidity: _d(j['humidity']),
    windKmh: _d(j['wind_kmh']),
    condition: WeatherCondition.parse(j['condition']),
    isDay: j['is_day'] == true,
    rainLevel: RainLevel.parse(j['rain_level']),
    heatLevel: HeatLevel.parse(j['heat_level']),
  );
}

class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temperatureC,
    required this.heatIndexC,
    required this.rainChance,
    required this.precipMm,
    required this.condition,
    required this.isDay,
    required this.rainLevel,
    required this.heatLevel,
    this.uvIndex,
  });

  final DateTime time;
  final double? temperatureC;
  final double? heatIndexC;
  final double? rainChance;
  final double? precipMm;
  final double? uvIndex;
  final WeatherCondition condition;
  final bool isDay;
  final RainLevel rainLevel;
  final HeatLevel heatLevel;

  factory WeatherHour.fromJson(Map<String, dynamic> j) => WeatherHour(
    time: _t(j['time'])!,
    temperatureC: _d(j['temperature_c']),
    heatIndexC: _d(j['heat_index_c']),
    rainChance: _d(j['rain_chance']),
    precipMm: _d(j['precip_mm']),
    uvIndex: _d(j['uv_index']),
    condition: WeatherCondition.parse(j['condition']),
    isDay: j['is_day'] == true,
    rainLevel: RainLevel.parse(j['rain_level']),
    heatLevel: HeatLevel.parse(j['heat_level']),
  );
}

class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.condition,
    this.tempMaxC,
    this.tempMinC,
    this.rainMm,
    this.rainChance,
  });

  /// Calendar date in Manila (no time part).
  final DateTime date;
  final WeatherCondition condition;
  final double? tempMaxC;
  final double? tempMinC;
  final double? rainMm;
  final double? rainChance;

  factory WeatherDay.fromJson(Map<String, dynamic> j) => WeatherDay(
    date: DateTime.parse(j['date'] as String),
    condition: WeatherCondition.parse(j['condition']),
    tempMaxC: _d(j['temp_max_c']),
    tempMinC: _d(j['temp_min_c']),
    rainMm: _d(j['rain_mm']),
    rainChance: _d(j['rain_chance']),
  );
}

/// The next 12 hours in one line each.
class WeatherOutlook {
  const WeatherOutlook({
    this.heatIndexMaxC,
    this.heatPeakAt,
    this.heatLevel = HeatLevel.none,
    this.rainLevel = RainLevel.none,
    this.rainStartsAt,
    this.thunderAt,
    this.uvMax = 0,
    this.windMaxKmh = 0,
  });

  final double? heatIndexMaxC;
  final DateTime? heatPeakAt;
  final HeatLevel heatLevel;
  final RainLevel rainLevel;
  final DateTime? rainStartsAt;
  final DateTime? thunderAt;
  final double uvMax;
  final double windMaxKmh;

  factory WeatherOutlook.fromJson(Map<String, dynamic> j) => WeatherOutlook(
    heatIndexMaxC: _d(j['heat_index_max_c']),
    heatPeakAt: _t(j['heat_peak_at']),
    heatLevel: HeatLevel.parse(j['heat_level']),
    rainLevel: RainLevel.parse(j['rain_level']),
    rainStartsAt: _t(j['rain_starts_at']),
    thunderAt: _t(j['thunder_at']),
    uvMax: _d(j['uv_max']) ?? 0,
    windMaxKmh: _d(j['wind_max_kmh']) ?? 0,
  );
}

/// A stretch of the next 24 hours worth reminding a resident about.
class WeatherWindow {
  const WeatherWindow({
    required this.kind,
    required this.startsAt,
    required this.endsAt,
    required this.rainLevel,
    required this.heatLevel,
    this.peak,
  });

  final WatchKind kind;
  final DateTime startsAt;
  final DateTime endsAt;

  /// The worst hour's grade: rain for rain and thunderstorm windows, heat for
  /// heat windows (the other one is `none`).
  final RainLevel rainLevel;
  final HeatLevel heatLevel;

  /// mm of rain in the worst hour, or the highest heat index.
  final double? peak;

  bool overlaps(WeatherWindow o) =>
      startsAt.isBefore(o.endsAt) && o.startsAt.isBefore(endsAt);

  static WeatherWindow? fromJson(Map<String, dynamic> j) {
    final kind = WatchKind.parse(j['kind']);
    final start = _t(j['starts_at']);
    final end = _t(j['ends_at']);
    if (kind == null || start == null || end == null) return null;
    return WeatherWindow(
      kind: kind,
      startsAt: start,
      endsAt: end,
      rainLevel:
          kind == WatchKind.heat ? RainLevel.none : RainLevel.parse(j['level']),
      heatLevel:
          kind == WatchKind.heat ? HeatLevel.parse(j['level']) : HeatLevel.none,
      peak: _d(j['peak']),
    );
  }
}

class WeatherForecast {
  const WeatherForecast({
    required this.current,
    required this.hours,
    required this.days,
    required this.outlook,
    required this.watch,
    required this.fetchedAt,
    this.stale = false,
    this.source = 'Open-Meteo',
  });

  final WeatherNow current;
  final List<WeatherHour> hours;
  final List<WeatherDay> days;
  final WeatherOutlook outlook;
  final List<WeatherWindow> watch;

  /// When the backend got this forecast from Open-Meteo.
  final DateTime fetchedAt;

  /// The backend could not reach Open-Meteo and served its last copy.
  final bool stale;
  final String source;

  factory WeatherForecast.fromJson(Map<String, dynamic> j) => WeatherForecast(
    current: WeatherNow.fromJson(
      Map<String, dynamic>.from(j['current'] as Map),
    ),
    hours: [
      for (final h in (j['hours'] as List? ?? const []))
        WeatherHour.fromJson(Map<String, dynamic>.from(h as Map)),
    ],
    days: [
      for (final d in (j['days'] as List? ?? const []))
        WeatherDay.fromJson(Map<String, dynamic>.from(d as Map)),
    ],
    outlook: WeatherOutlook.fromJson(
      Map<String, dynamic>.from((j['outlook'] as Map?) ?? const {}),
    ),
    watch:
        [
          for (final w in (j['watch'] as List? ?? const []))
            WeatherWindow.fromJson(Map<String, dynamic>.from(w as Map)),
        ].whereType<WeatherWindow>().toList(),
    fetchedAt: _t(j['fetched_at']) ?? DateTime.now(),
    stale: j['stale'] == true,
    source: (j['source'] as String?) ?? 'Open-Meteo',
  );
}
