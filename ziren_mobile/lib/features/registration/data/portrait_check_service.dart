import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../domain/portrait_check.dart';
import 'face_match_client.dart';

/// The outcome of checking a 2x2 ID photo: what was measured, the comparison
/// with the selfie, and the one problem (if any) that refuses it.
class PortraitResult {
  const PortraitResult({required this.facts, this.match, this.problem});

  final PortraitFacts facts;
  final FaceMatchResult? match;
  final PortraitProblem? problem;

  bool get accepted => problem == null;

  /// What is stored in users.id_checks.portrait beside the photo's path
  /// (backend app/core/id_portrait.py). Advisory, like every on-device check.
  Map<String, dynamic> toChecks() => {
    'verdict': match?.verdict ?? 'unavailable',
    'score': match?.score,
    'model': match?.model,
    'checked_at': DateTime.now().toUtc().toIso8601String(),
    'frontal': true,
    'plain_background': true,
    ...facts.toChecks(),
  };
}

/// Measures a 2x2 ID photo and compares its face with the selfie.
///
/// The rule lives in domain/portrait_check.dart; this only gathers the facts:
/// ML Kit for the faces, the head's angle and the eyes, and a background
/// isolate for how busy the wall behind the head is (decoding a phone photo
/// in Dart is seconds of CPU, which on the UI thread froze the selfie screen
/// once already - see FaceAlignService.crop).
///
/// The comparison is the same server call the ID/selfie check uses, and the
/// same gate guards it: the recogniser is only called with a face found in
/// BOTH photos, because it scores two walls as a match (face_match_service.py).
class PortraitCheckService {
  PortraitCheckService({FaceMatchClient? faces})
    : _faces = faces ?? FaceMatchClient(),
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
          // Small enough to find the face in a photographed printed 2x2, and
          // to COUNT a second person standing behind.
          minFaceSize: 0.05,
        ),
      );

  final FaceMatchClient _faces;
  final FaceDetector _detector;

  Future<void> dispose() async {
    await _detector.close();
    await _faces.dispose();
  }

  Future<PortraitResult> check({
    required String portraitPath,
    required String? selfiePath,
  }) async {
    final facts = await _measure(portraitPath);
    final photoProblem = judgePortraitPhoto(facts);
    if (photoProblem != null) {
      return PortraitResult(facts: facts, problem: photoProblem);
    }

    final portrait = await _faces.alignFace(portraitPath);
    if (portrait.b64 == null) {
      return PortraitResult(facts: facts, problem: PortraitProblem.noFeatures);
    }
    if (selfiePath == null) {
      // Registration always has the selfie by now; the Verify screen asks for
      // it before this. Kept as a refusal so a missing selfie is never read as
      // "nothing to compare, so fine".
      return PortraitResult(facts: facts, problem: PortraitProblem.noFaceInSelfie);
    }
    final selfie = await _faces.alignFace(selfiePath);
    if (selfie.b64 == null) {
      return PortraitResult(facts: facts, problem: PortraitProblem.noFaceInSelfie);
    }
    final match = await _faces.compare(
      idFaceB64: portrait.b64!,
      selfieFaceB64: selfie.b64!,
    );
    return PortraitResult(
      facts: facts,
      match: match,
      problem: judgePortraitMatch(match.verdict),
    );
  }

  Future<PortraitFacts> _measure(String path) async {
    final List<Face> faces;
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
      faces = await _detector.processImage(InputImage.fromFilePath(path));
    } catch (e) {
      debugPrint('[PortraitCheckService] $e');
      return PortraitFacts.unreadable;
    }
    // People, not detections: a tiny or duplicate detection is not a second
    // person (see countPeople). The largest face is the one measured.
    final people = countPeople([
      for (final f in faces)
        (
          left: f.boundingBox.left,
          top: f.boundingBox.top,
          right: f.boundingBox.right,
          bottom: f.boundingBox.bottom,
        ),
    ]);
    if (people != 1) return PortraitFacts(faceCount: people);

    final face = faces.reduce(
      (a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
                  b.boundingBox.width * b.boundingBox.height
              ? a
              : b,
    );
    final box = face.boundingBox;
    final measured = await compute(_backgroundJob, (
      bytes: bytes,
      box: [box.left, box.top, box.right, box.bottom],
    ));
    if (measured == null) return PortraitFacts.unreadable;

    return PortraitFacts(
      faceCount: 1,
      faceRatio: measured.faceRatio,
      yaw: face.headEulerAngleY,
      roll: face.headEulerAngleZ,
      leftEyeOpen: face.leftEyeOpenProbability,
      rightEyeOpen: face.rightEyeOpenProbability,
      backgroundStd: measured.std,
      backgroundEdge: measured.edge,
    );
  }
}

// ── Isolate work ─────────────────────────────────────────────

({double faceRatio, double? std, double? edge})? _backgroundJob(
  ({Uint8List bytes, List<double> box}) job,
) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  // ML Kit's box is in the photo as displayed (EXIF rotation applied); the
  // decoder's pixels are not until this. See FaceAlignService._alignJob.
  final photo = img.bakeOrientation(decoded);
  final w = photo.width, h = photo.height;
  if (w <= 0 || h <= 0) return null;

  final b = job.box;
  final ratio = ((b[2] - b[0]) * (b[3] - b[1])) / (w * h);

  // 96 pixels wide: enough to tell a wall from a room, cheap to scan, and the
  // same scale whatever camera took it.
  const target = 96;
  final scale = target / w;
  final small = img.copyResize(
    photo,
    width: target,
    height: (h * scale).round().clamp(1, 4096),
    interpolation: img.Interpolation.average,
  );
  final grey = <int>[
    for (var y = 0; y < small.height; y++)
      for (var x = 0; x < small.width; x++)
        img.getLuminance(small.getPixel(x, y)).round(),
  ];
  final bg = measureBackground(
    grey: grey,
    width: small.width,
    height: small.height,
    faceLeft: b[0] * scale,
    faceTop: b[1] * scale,
    faceRight: b[2] * scale,
    faceBottom: b[3] * scale,
  );
  return (faceRatio: ratio, std: bg?.std, edge: bg?.edge);
}
