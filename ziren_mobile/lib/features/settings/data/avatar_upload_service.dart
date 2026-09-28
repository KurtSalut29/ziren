import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';

/// Uploads a resident's or responder's own profile picture.
///
/// Bucket: avatars (PRIVATE) — see migration 033. Shared by both roles: the
/// access rule is identical (owner reads and writes their own folder only),
/// so a second bucket would express the same policy twice.
///
/// One object per user, not one per upload. Every other upload service in
/// this app timestamps its filename because the object is written once and
/// kept — an ID scan, an incident photo. An avatar is something people
/// change their mind about, so this fixes the name to `avatar.<ext>` and
/// removes whatever was there first; otherwise a resident who swaps JPEG for
/// PNG a few times leaves an unbounded number of orphaned images behind,
/// each one still billable storage nobody will ever look at again.
///
/// No public URL is ever produced here. Display goes through the signed
/// avatar_url the backend hands out on GET/PATCH /users/me — see
/// UserProfile.avatar_url and user_service._with_avatar_url.
class AvatarUploadService {
  AvatarUploadService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final ImagePicker _picker = ImagePicker();

  static const String _bucket = 'avatars';
  static const int _maxSizeMb = 5;

  /// Capture or choose the picture. Capped well below camera-native size —
  /// an avatar is shown at most at a few hundred pixels, so anything larger
  /// only costs upload time on a rural connection for no visible gain.
  Future<File?> pickAvatarPhoto({required ImageSource source}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      return picked != null ? File(picked.path) : null;
    } catch (_) {
      return null;
    }
  }

  /// Upload the picture and return its storage path.
  ///
  /// [userId] must be the authenticated user's own id — storage RLS scopes
  /// writes to `<auth.uid()>/...`, so any other value is rejected server-side.
  Future<String> upload({required File file, required String userId}) async {
    final bytes = file.lengthSync();
    if (bytes > _maxSizeMb * 1024 * 1024) {
      throw ServerFailure(
        'That image is too large. Maximum size is ${_maxSizeMb}MB.',
      );
    }

    final ext = file.path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      throw const ServerFailure('Please use a photo (JPG, PNG or WEBP).');
    }

    final path = '$userId/avatar.$ext';

    try {
      // Clear out a previous avatar under a different extension first —
      // upsert only overwrites an exact key match, so switching from .jpg
      // to .png would otherwise leave the old .jpg behind forever.
      final existing = await _client.storage.from(_bucket).list(path: userId);
      final stale =
          existing
              .map((f) => '$userId/${f.name}')
              .where((p) => p != path)
              .toList();
      if (stale.isNotEmpty) {
        await _client.storage.from(_bucket).remove(stale);
      }
    } catch (_) {
      // Listing/cleanup is best-effort — a stray old file costs storage, not
      // correctness, and must never block the new upload from landing.
    }

    try {
      await _client.storage
          .from(_bucket)
          .upload(path, file, fileOptions: const FileOptions(upsert: true));
      return path;
    } catch (e) {
      throw ServerFailure('Could not upload your picture. $e');
    }
  }

  /// Remove the picture entirely (all extensions, in case of a stale one).
  Future<void> deleteAll(String userId) async {
    try {
      final existing = await _client.storage.from(_bucket).list(path: userId);
      final paths = existing.map((f) => '$userId/${f.name}').toList();
      if (paths.isNotEmpty) {
        await _client.storage.from(_bucket).remove(paths);
      }
    } catch (_) {
      // Same reasoning as upload's cleanup step: best-effort.
    }
  }
}
