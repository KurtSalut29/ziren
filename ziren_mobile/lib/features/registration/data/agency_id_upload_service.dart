import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';

/// Uploads a responder's agency ID into the PRIVATE `responder-ids` bucket.
///
/// Bucket: responder-ids (PRIVATE)
/// Path:   responder-ids/{user_id}/{filename}
///
/// Why a separate bucket and a separate service, rather than a `bucket`
/// parameter on [IdUploadService] — the reader sets are genuinely different.
/// A resident's ID is reviewed by whichever admin is verifying residents; an
/// agency ID is evidence for that agency's own admin approving one of their
/// own people. Expressing that as one service with a string parameter would
/// hide the difference at exactly the point someone is most likely to widen
/// it by accident.
///
/// Until migration 020 this had no equivalent at all: the registration screen
/// passed `validIdImage: null` for responders, so an Agency Admin approved a
/// badge number with no document attached to it.
class AgencyIdUploadService {
  AgencyIdUploadService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _bucket = 'responder-ids';
  static const int _maxSizeMb = 10;

  /// [userId] must be the authenticated user's own id — storage RLS scopes
  /// writes to `<auth.uid()>/...`, so any other value is rejected server-side.
  Future<String> upload({required File file, required String userId}) async {
    if (file.lengthSync() > _maxSizeMb * 1024 * 1024) {
      throw ServerFailure(
        'That image is too large. Maximum size is ${_maxSizeMb}MB.',
      );
    }

    final ext = file.path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext)) {
      throw const ServerFailure('Please use a photo (JPG, PNG, WEBP or HEIC).');
    }

    final path = '$userId/agency_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _client.storage
          .from(_bucket)
          .upload(path, file, fileOptions: const FileOptions(upsert: false));
      return path;
    } catch (e) {
      throw ServerFailure('Could not upload your agency ID. $e');
    }
  }

  Future<String> signedUrl(String path, {int expiresInSeconds = 300}) =>
      _client.storage.from(_bucket).createSignedUrl(path, expiresInSeconds);

  Future<void> delete(String path) async {
    await _client.storage.from(_bucket).remove([path]);
  }
}
