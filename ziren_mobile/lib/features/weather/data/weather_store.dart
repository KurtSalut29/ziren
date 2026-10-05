import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/weather_forecast.dart';
import 'weather_reminders.dart';
import 'weather_repository.dart';

/// The forecast resident Home shows, kept usable with no connection.
///
/// Like HotlinesStore: the newest forecast when online, the last one saved on
/// the phone when not. A saved forecast older than [maxAge] is dropped rather
/// than shown — yesterday's "rain at 3 PM" is worse than nothing.
class WeatherStore extends ChangeNotifier {
  WeatherStore._({WeatherRepository repository = const WeatherRepository()})
    : _repository = repository;

  static final WeatherStore instance = WeatherStore._();

  @visibleForTesting
  factory WeatherStore.forTest(WeatherRepository repository) =>
      WeatherStore._(repository: repository);

  static const _prefsKey = 'weather.forecast.v1';
  static const maxAge = Duration(hours: 12);

  /// How often the network is asked at most. The backend caches for 30
  /// minutes anyway; asking more often only costs the resident data.
  static const refreshEvery = Duration(minutes: 15);

  final WeatherRepository _repository;

  WeatherForecast? _forecast;
  bool _loading = false;
  bool _failed = false;
  bool _loadedCache = false;
  DateTime? _lastAttempt;
  (double, double)? _lastPoint;

  WeatherForecast? get forecast => _forecast;
  bool get loading => _loading;

  /// The last attempt failed and there is nothing to show.
  bool get failed => _failed && _forecast == null;

  /// The forecast on screen came from the phone's saved copy, not this
  /// session's request (offline, or the request failed).
  bool _fromCache = false;
  bool get fromCache => _fromCache;

  /// Ask for a fresh forecast. Safe to call often: it reads the saved copy
  /// once, then reaches the network at most every [refreshEvery] unless the
  /// resident has moved ~5 km or [force] is set (pull to refresh).
  Future<void> refresh({double? lat, double? lng, bool force = false}) async {
    if (!_loadedCache) {
      _loadedCache = true;
      await _readCache();
    }
    final point = lat != null && lng != null ? (lat, lng) : null;
    final moved =
        point != null &&
        (_lastPoint == null ||
            (point.$1 - _lastPoint!.$1).abs() > 0.05 ||
            (point.$2 - _lastPoint!.$2).abs() > 0.05);
    final last = _lastAttempt;
    if (!force &&
        !moved &&
        last != null &&
        DateTime.now().difference(last) < refreshEvery) {
      return;
    }
    if (_loading) return;
    _lastAttempt = DateTime.now();
    _loading = true;
    notifyListeners();
    try {
      final body = await _repository.fetchJson(lat: lat, lng: lng);
      final f = WeatherForecast.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      _forecast = f;
      _fromCache = false;
      _failed = false;
      if (point != null) _lastPoint = point;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, body);
      } catch (_) {}
    } catch (e) {
      debugPrint('[WeatherStore] refresh failed: $e');
      _failed = true;
      // Let the next call try again rather than wait out the interval.
      _lastAttempt = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final f = WeatherForecast.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (DateTime.now().difference(f.fetchedAt) > maxAge) return;
      _forecast = f;
      _fromCache = true;
      notifyListeners();
    } catch (_) {
      // A corrupt copy just means no forecast until the network answers.
    }
  }

  /// Signing out: the next account starts clean and nothing keeps buzzing.
  Future<void> clear() async {
    _forecast = null;
    _lastAttempt = null;
    _lastPoint = null;
    _loadedCache = true;
    _failed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    await WeatherReminders.cancelAll();
    notifyListeners();
  }

  @visibleForTesting
  void debugSet(WeatherForecast? f, {bool fromCache = false}) {
    _forecast = f;
    _fromCache = fromCache;
    _loadedCache = true;
    notifyListeners();
  }
}
