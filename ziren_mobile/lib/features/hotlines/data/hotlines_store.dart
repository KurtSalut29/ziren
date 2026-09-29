import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/station_hotlines.dart';

/// The station hotlines the app shows, kept usable with no connection.
///
/// Three layers, best first: the numbers the database holds right now (when
/// online), the numbers it held the last time the app was online (saved on
/// the phone), and the list shipped inside the app. Whatever the network is
/// doing, [entries] is never empty and never waits on a request.
class HotlinesStore extends ChangeNotifier {
  HotlinesStore._();

  static final HotlinesStore instance = HotlinesStore._();

  static const _prefsKey = 'hotlines.contact_numbers.v1';

  Map<String, String?> _live = const {};
  bool _loadedCache = false;
  DateTime? _lastRefresh;

  List<StationHotline> get entries => StationHotlines.directory(live: _live);

  /// Reads the saved numbers, then asks the database for fresh ones. Safe to
  /// call often: the network half runs at most once a minute and a failure
  /// leaves what is already known in place.
  Future<void> refresh() async {
    if (!_loadedCache) {
      _loadedCache = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw != null) {
          _live = Map<String, String?>.from(jsonDecode(raw) as Map);
          notifyListeners();
        }
      } catch (_) {
        // A corrupt cache just means the bundled numbers stand.
      }
    }

    final last = _lastRefresh;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastRefresh = DateTime.now();
    try {
      final rows = await Supabase.instance.client
          .from('agencies')
          .select('id, contact_number')
          .timeout(const Duration(seconds: 6));
      final live = <String, String?>{
        for (final r in rows as List) (r['id'] as String): r['contact_number'] as String?,
      };
      _live = live;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(live));
    } catch (_) {
      // Offline — exactly the case this store exists for.
    }
  }

  @visibleForTesting
  void debugSetLive(Map<String, String?> live) {
    _live = live;
    notifyListeners();
  }
}
