import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';
import '../domain/profile_model.dart';

/// All user profile API calls — GET /users/me and PATCH /users/me.
class ProfileRepository {
  ProfileRepository();

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  Future<ProfileModel> getMyProfile() async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/users/me'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        return ProfileModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      // The server's own reason, not a generic one.
      //
      // This used to throw a fixed "Failed to load profile." for every
      // non-200, which the profile screen then renders as "Details below may
      // be out of date." beside a Retry button. For a 404 — an account whose
      // profile row does not exist, which is every account created before the
      // trigger in migration 013 — that is wrong twice: nothing is stale, and
      // retrying cannot create a row. The API sends a sentence explaining
      // exactly that, and it was being discarded here.
      throw ServerFailure(
        _detailFrom(response.body) ?? 'Failed to load profile.',
      );
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// FastAPI puts the human-readable reason in `detail`.
  ///
  /// Returns null rather than throwing when the body is not the JSON we
  /// expect — a proxy's HTML error page must not turn a bad status into a
  /// crash on top of it.
  static String? _detailFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        final detail = (decoded['detail'] as String).trim();
        if (detail.isNotEmpty) return detail;
      }
    } catch (_) {}
    return null;
  }

  Future<ProfileModel> updateMyProfile(Map<String, dynamic> fields) async {
    try {
      final response = await withAuthRetry(
        () => http
            .patch(
              Uri.parse('${AppConfig.apiBaseUrl}/users/me'),
              headers: _headers,
              body: jsonEncode(fields),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        return ProfileModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      final detail =
          (jsonDecode(response.body) as Map<String, dynamic>)['detail']
              as String? ??
          'Update failed.';
      throw ServerFailure(detail);
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }
}
