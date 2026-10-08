import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';

/// Uploads a scan of a resident's valid ID so an Agency Admin can check the
/// number against the document without an in-person visit.
///
/// Bucket: resident-ids (PRIVATE)
/// Path:   resident-ids/{user_id}/{filename}
///
/// Deliberately separate from [MediaUploadService] rather than a shared
/// helper, because the access rules are not the same. Responders can read
/// incident media; they must never read ID scans, since a responder plays no
/// part in identity verification. Keeping the two services apart makes that
/// difference visible instead of hiding it behind a bucket-name parameter.
///
/// No public URL is ever produced. Reads go through short-lived signed URLs.
class IdUploadService {
  IdUploadService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final ImagePicker _picker = ImagePicker();

  static const String _bucket = 'resident-ids';
  static const int _maxSizeMb = 10;

  /// Capture or choose a photo of the ID card.
  ///
  /// Resolution is capped well below the camera's native size: an ID number
  /// stays legible at 1600px, and a smaller file means a faster upload on a
  /// rural mobile connection and less sensitive data at rest.
  Future<File?> pickIdPhoto({required ImageSource source}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      return picked != null ? File(picked.path) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _upload({
    required File file,
    required String userId,
    required String prefix,
  }) async {
    final bytes = file.lengthSync();
    if (bytes > _maxSizeMb * 1024 * 1024) {
      throw ServerFailure(
        'That image is too large. Maximum size is ${_maxSizeMb}MB.',
      );
    }

    final ext = file.path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext)) {
      throw const ServerFailure('Please use a photo (JPG, PNG, WEBP or HEIC).');
    }

    final filename = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '$userId/$filename';

    try {
      await _client.storage
          .from(_bucket)
          .upload(path, file, fileOptions: const FileOptions(upsert: false));
      return path;
    } catch (e) {
      throw ServerFailure('Could not upload your photo. $e');
    }
  }

  /// Upload the identity selfie and return its storage path.
  ///
  /// Shares the resident-ids bucket with the ID scan rather than getting its
  /// own, because the two have identical access rules and an identical
  /// retention rule: they exist so one administrator can compare them once,
  /// and both are purged together when verification is decided. Splitting them
  /// would double the RLS surface to express the same policy twice.
  ///
  /// The `selfie_` filename prefix is what distinguishes them in the bucket.
  Future<String> uploadSelfie({required File file, required String userId}) =>
      _upload(file: file, userId: userId, prefix: 'selfie');

  /// Upload the 2x2 ID photo and return its storage path.
  ///
  /// Same bucket and folder as the selfie, for the same reason. Unlike the
  /// other two it is KEPT once an administrator approves the account: it is
  /// the picture on the resident's Ziren ID card (backend
  /// user_service.decide_verification, Privacy Notice 1.2).
  Future<String> uploadPortrait({required File file, required String userId}) =>
      _upload(file: file, userId: userId, prefix: 'portrait');

  /// Upload the scan and return its storage path.
  ///
  /// [userId] must be the authenticated user's own id — storage RLS scopes
  /// writes to `<auth.uid()>/...`, so any other value is rejected server-side.
  Future<String> uploadId({required File file, required String userId}) =>
      _upload(file: file, userId: userId, prefix: 'id');

  /// Short-lived signed URL for viewing a scan. Never store the result.
  Future<String> signedUrl(String path, {int expiresInSeconds = 300}) {
    return _client.storage
        .from(_bucket)
        .createSignedUrl(path, expiresInSeconds);
  }

  /// Remove a scan. Used both when a resident withdraws their ID and by the
  /// retention sweep once verification is complete.
  Future<void> delete(String path) async {
    await _client.storage.from(_bucket).remove([path]);
  }
}
