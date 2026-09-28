import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';
import '../domain/announcement_model.dart';

/// GET /announcements/ — already filters to whatever this resident's
/// account should see (see AnnouncementModel's doc comment). No mobile-side
/// audience logic needed; the backend is the single source of it.
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
}
