import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';
import '../domain/announcement_model.dart';

/// GET /announcements/ - already filters to whatever this resident's account
/// should see (role and place; see AnnouncementModel's doc comment). No
/// mobile-side audience logic needed; the backend is the single source of it.
///
/// Also the resident's answer to a safety alert: POST /announcements/{id}/respond.
class AnnouncementRepository {
  AnnouncementRepository();

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  Future<List<AnnouncementModel>> getAnnouncements() async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/announcements/'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final items =
            data
                .map(
                  (e) => AnnouncementModel.fromJson(e as Map<String, dynamic>),
                )
                .toList();
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return items;
      }
      throw const ServerFailure('Could not load announcements.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[getAnnouncements] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// One announcement - still readable after it ended, so a notice opened late
  /// can say "this has ended" instead of failing. Null when it is not for this
  /// account (or no longer exists).
  Future<AnnouncementModel?> getAnnouncement(String id) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/announcements/$id'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode == 200) {
        return AnnouncementModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      if (response.statusCode == 404) return null;
      throw ServerFailure(_detail(response) ?? 'Could not load this announcement.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[getAnnouncement] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// "I am safe" (`safe`) or "I need help" (`need_help`). Answering again
  /// replaces the answer. Throws [AlertEndedException] when the alert has ended.
  Future<AlertResponse> respond(
    String id, {
    required String status,
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/announcements/$id/respond'),
              headers: _headers,
              body: jsonEncode({
                'status': status,
                if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
                if (latitude != null && longitude != null) ...{
                  'latitude': latitude,
                  'longitude': longitude,
                },
              }),
            )
            .timeout(const Duration(seconds: 15)),
      );
      if (response.statusCode == 200) {
        return AlertResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      if (response.statusCode == 409) {
        throw AlertEndedException(_detail(response) ?? 'This alert has ended.');
      }
      throw ServerFailure(_detail(response) ?? 'Your answer could not be sent.');
    } on ServerFailure {
      rethrow;
    } on AlertEndedException {
      rethrow;
    } catch (e) {
      debugPrint('[respond] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  static String? _detail(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      final d = body is Map ? body['detail'] : null;
      return d is String && d.isNotEmpty ? d : null;
    } catch (_) {
      return null;
    }
  }
}

/// The alert ended (an all clear, or it expired) before the answer arrived.
/// Not a [Failure]: that family is sealed, and this is not a failure of the
/// app - the danger is over.
class AlertEndedException implements Exception {
  const AlertEndedException(this.message);
  final String message;
}
