import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import 'face_align_service.dart';

/// The outcome of comparing an ID portrait with a selfie.
class FaceMatchResult {
  const FaceMatchResult({
    required this.verdict,
    required this.message,
    this.score,
    this.model,
  });

  /// One of: match, uncertain, no_match, no_face_on_id, no_face_in_selfie,
  /// unavailable. Mirrors the CHECK constraint in migration 023.
  final String verdict;

  /// A sentence for the person on the screen.
  final String message;

  final double? score;
  final String? model;

  bool get isMatch => verdict == 'match';
  bool get isMismatch => verdict == 'no_match';

  /// Whether anything went wrong that a RETAKE would fix.
  ///
  /// Distinct from a mismatch. "We could not find a face on the card" is the
  /// person's photo being bad; "these do not look like the same person" is not
  /// something a better photo changes.
  bool get needsRetake =>
      verdict == 'no_face_on_id' || verdict == 'no_face_in_selfie';

  Map<String, dynamic> toDraftFields() => {
    'verdict': verdict,
    'score': score,
    'model': model,
  };
}

/// Runs the ID-portrait / selfie comparison.
///
/// SPLIT ACROSS THE PHONE AND THE SERVER, ON PURPOSE
///
/// Detection and alignment happen here, on the handset, with ML Kit — which is
/// already integrated for the liveness challenge and is the best-tested piece
/// of this pipeline. The 512-dimension embedding and the comparison happen on
/// the server, because the recogniser is a 13 MB ONNX model that would have to
/// be shipped inside the APK and run through a second inference runtime to do
/// it here.
///
/// What crosses the network is two 112x112 aligned face crops, not the
/// photographs — about 50 KB each as base64 raw RGB. The full images are
/// uploaded to Supabase storage moments later anyway, so this adds no new
/// exposure of anything.
///
/// THE DETECTION RESULT IS THE GATE, NOT A HINT
///
/// If ML Kit finds no face in either image, [compare] returns the
/// corresponding verdict WITHOUT calling the server. That is not an
/// optimisation. The recogniser has no notion of "not a face" — two images of
/// blank walls score above the match threshold against each other — so sending
/// it something that is not a face produces a confident number about nothing.
/// See the module docstring in face_match_service.py.
///
/// NOTHING HERE BLOCKS REGISTRATION
///
/// Every failure path returns a verdict and lets the person continue. A
/// network failure, a missing model on the server, an unreadable photo: all of
/// them end with an admin comparing the two images by eye, which is exactly
/// what happened before this existed.
class FaceMatchClient {
  FaceMatchClient({FaceAlignService? aligner})
    : _aligner = aligner ?? FaceAlignService();

  final FaceAlignService _aligner;

  Future<void> dispose() => _aligner.dispose();

  /// Align the face in [imagePath] and return it as base64 raw RGB.
  ///
  /// Returns null when no usable face was found. The caller decides what that
  /// means — it is a different verdict for an ID than for a selfie.
  ///
  /// [faceRatio] is how much of the photo the face fills (null if unknown); an
  /// ID photo has a small portrait, a selfie a face that fills the frame.
  Future<({String? b64, FaceCropOutcome outcome, double? faceRatio})> alignFace(
    String imagePath,
  ) async {
    final crop = await _aligner.crop(imagePath);
    if (!crop.isUsable) {
      return (b64: null, outcome: crop.outcome, faceRatio: crop.faceRatio);
    }
    return (
      b64: base64Encode(crop.rgb as Uint8List),
      outcome: crop.outcome,
      faceRatio: crop.faceRatio,
    );
  }

  /// Compare two already-aligned crops.
  Future<FaceMatchResult> compare({
    required String idFaceB64,
    required String selfieFaceB64,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/auth/face-match'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id_face': idFaceB64,
              'selfie_face': selfieFaceB64,
            }),
            // Generous. This is one CPU inference on a 13 MB network, but it
            // may be the first call after a cold start, which pays the model
            // load as well.
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return FaceMatchResult(
          verdict: body['verdict'] as String? ?? 'unavailable',
          message: body['message'] as String? ?? '',
          score: (body['score'] as num?)?.toDouble(),
          model: body['model'] as String?,
        );
      }

      debugPrint(
        '[FaceMatchClient] HTTP ${response.statusCode}: ${response.body}',
      );
      return const FaceMatchResult(
        verdict: 'unavailable',
        message:
            'We could not check the photos automatically. An admin will '
            'compare them.',
      );
    } catch (e) {
      // Offline is the normal case in half of Biliran. Registration must
      // finish regardless; the admin still has both images.
      debugPrint('[FaceMatchClient] $e');
      return const FaceMatchResult(
        verdict: 'unavailable',
        message:
            'We could not reach the server to check the photos. You can '
            'continue — an admin will compare them.',
      );
    }
  }
}
