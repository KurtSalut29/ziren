import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';
import '../domain/sos_result.dart';

/// All SOS-related API calls are isolated here.
/// Talks exclusively to POST /incidents/sos — not the normal /incidents/ endpoint.
class SosRepository {
  SosRepository();

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  /// Submit an SOS Quick-Report.
  ///
  /// [description] is optional — the server stores "SOS" if null.
  /// [latitude] / [longitude] are optional but strongly recommended.
  /// [incidentCategory] is optional (the wire value, e.g. "fire") — when
  /// given, the server prefers a station of the matching agency instead of
  /// the plain nearest-of-any-agency station. See SosProvider.setCategory.
  /// The server resolves the nearest station via PostGIS.
  Future<SosResult> submitSos({
    double? latitude,
    double? longitude,
    String? description,
    String? incidentCategory,
  }) async {
    final body = <String, dynamic>{
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (incidentCategory != null) 'incident_category': incidentCategory,
    };

    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/sos'),
              headers: _headers,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15)),
      );

      if (response.statusCode == 201) {
        return SosResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      // Parse structured error from FastAPI
      String detail = 'SOS submission failed.';
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        detail = err['detail'] as String? ?? detail;
      } catch (_) {}

      throw ServerFailure(detail);
    } on ServerFailure {
      rethrow;
    } catch (e) {
      throw const NetworkFailure(
        'Could not reach the server. Please call 911 directly.',
      );
    }
  }
}
