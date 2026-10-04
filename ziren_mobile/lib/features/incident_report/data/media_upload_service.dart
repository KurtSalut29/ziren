import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';

/// Handles photo/video attachment upload to Supabase Storage.
///
/// Bucket: incident-media (private)
/// Path:   incident-media/{user_id}/{incident_id}/{filename}
///
/// Media is optional evidence — it is NOT fed into the NLP pipeline.
class MediaUploadService {
  MediaUploadService({SupabaseClient? client}) : _injected = client;

  // Looked up when first used, not when constructed: the report provider
  // builds one of these up front, and an eager lookup made that provider
  // impossible to create in a unit test (no Supabase there).
  final SupabaseClient? _injected;
  SupabaseClient get _client => _injected ?? Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  static const String _bucket = 'incident-media';

  /// Shown on the form and checked when a file is chosen, not only here.
  static const int maxSizeMb = 50;
  static const int maxBytes = maxSizeMb * 1024 * 1024;
  static const int maxFiles = 5;
  static const Duration maxVideoLength = Duration(minutes: 2);
  static const int _maxSizeMb = maxSizeMb;

  /// Whether a file of [bytes] is over the per-file limit.
  static bool exceedsLimit(int bytes) => bytes > maxBytes;

  /// Pick a photo from gallery or camera.
  Future<File?> pickPhoto({required ImageSource source}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      return picked != null ? File(picked.path) : null;
    } catch (_) {
      return null;
    }
  }

  /// Pick a video from gallery or camera.
  Future<File?> pickVideo({required ImageSource source}) async {
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: maxVideoLength,
      );
      return picked != null ? File(picked.path) : null;
    } catch (_) {
      return null;
    }
  }

  /// Upload a single file to Supabase Storage.
  /// Returns the storage path on success.
  /// Throws [ServerFailure] if Storage refuses the file or it is too large, and
  /// [NetworkFailure] if the network could not carry it.
  Future<String> uploadFile({
    required File file,
    required String userId,
    required String incidentId,
  }) async {
    final bytes = file.lengthSync();
    if (bytes > _maxSizeMb * 1024 * 1024) {
      throw ServerFailure(
        'File is too large. Maximum size is ${_maxSizeMb}MB.',
      );
    }

    final ext = file.path.split('.').last.toLowerCase();
    final filename = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '$userId/$incidentId/$filename';

    try {
      await _client.storage
          .from(_bucket)
          .upload(path, file, fileOptions: const FileOptions(upsert: false))
          .timeout(_uploadTimeout);
      return path;
    } catch (e) {
      // The cause used to be discarded here, and it cost real time: voice
      // notes were being rejected by Storage for a MIME type the bucket did
      // not allow, and every one of them surfaced as this same sentence. The
      // resident still gets a sentence they can act on; the log keeps what
      // actually happened.
      debugPrint('[MediaUpload] $path failed: $e');
      // No connection is not the same failure as a refused file, and the
      // caller treats them oppositely: a refused photo stops the report so the
      // resident can fix it, but a photo that cannot travel because nothing can
      // must never hold the report hostage. Everything used to arrive here as
      // a ServerFailure, so a resident with a photo attached and no data got
      // "Upload failed" and no report at all, when the report itself — much
      // smaller than a photo — might still have gone through on its own.
      if (isNetworkError(e)) {
        throw const NetworkFailure('Could not reach the server.');
      }
      throw ServerFailure('Upload failed. Please try again.');
    }
  }

  /// A photo has to cross the same weak link the report does. Long enough for
  /// an honest upload over a slow connection, short enough that a link which
  /// is up but carrying nothing does not stall the report for minutes.
  static const Duration _uploadTimeout = Duration(seconds: 45);

  /// Whether [e] is the network failing (nothing to connect to, a dropped
  /// connection, no answer in time) rather than Storage refusing the file.
  ///
  /// The storage client sometimes wraps the transport error in its own
  /// exception and keeps only the text, so the message is checked too.
  @visibleForTesting
  static bool isNetworkError(Object e) {
    if (e is SocketException ||
        e is TimeoutException ||
        e is HandshakeException ||
        e is http.ClientException) {
      return true;
    }
    final text = e.toString();
    return const [
      'SocketException',
      'HandshakeException',
      'TimeoutException',
      'Failed host lookup',
      'Connection closed',
      'Connection reset',
      'Connection refused',
      'Network is unreachable',
    ].any(text.contains);
  }

  /// Get a short-lived signed URL for display (1 hour).
  Future<String?> getSignedUrl(String storagePath) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 3600);
    } catch (_) {
      return null;
    }
  }
}
