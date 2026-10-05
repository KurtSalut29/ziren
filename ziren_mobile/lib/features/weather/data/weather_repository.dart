import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';

/// GET /weather/ — the forecast for where the resident is.
///
/// The position is rounded to two decimals (about 1 km) before it is sent;
/// the backend snaps it further to a 5 km grid before asking Open-Meteo.
class WeatherRepository {
  const WeatherRepository();

  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// The raw JSON body, so the caller can keep a copy for offline.
  Future<String> fetchJson({double? lat, double? lng}) async {
    final query = <String, String>{
      if (lat != null && lng != null) ...{
        'lat': lat.toStringAsFixed(2),
        'lng': lng.toStringAsFixed(2),
      },
    };
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/weather/',
    ).replace(queryParameters: query.isEmpty ? null : query);
    try {
      final response = await withAuthRetry(
        () => http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12)),
      );
      if (response.statusCode == 200) {
        // Parsed here once so a body that is not a forecast never reaches the
        // offline copy.
        jsonDecode(response.body) as Map<String, dynamic>;
        return response.body;
      }
      throw ServerFailure('Weather unavailable (${response.statusCode}).');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[WeatherRepository] $e');
      throw const NetworkFailure('Could not reach the server.');
    }
  }
}
