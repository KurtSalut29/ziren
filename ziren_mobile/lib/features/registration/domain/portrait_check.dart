/// Is this photo a usable 2x2 ID photo of the person who took the selfie?
///
/// User request 2026-10-08: the Ziren ID card carries an ID-style photo - the
/// kind printed as a 2x2 - and the face in it has to be the resident's own,
/// "baka mag upload lang sya ng kahit ano". This file is the rule; what the
/// camera and ML Kit measured comes in as [PortraitFacts], so every threshold
/// here is tested without a phone.
///
/// Two halves, judged in order:
///
///  1. Is it an ID photo at all: exactly one face, facing the camera, head
///     straight, eyes open, the face neither a speck nor cut off, and a plain
///     background ([judgePortraitPhoto]).
///  2. Is it the same person as the selfie, which passed the liveness
///     challenge and so is the one photo known to be of whoever is holding the
///     phone ([judgePortraitMatch]). Only "no_match" refuses: an "uncertain"
///     score or an unreachable server goes to the administrator, who sees the
///     two photos side by side before approving anything.
library;

import 'dart:math' as math;

/// What was measured on the photo.
class PortraitFacts {
  const PortraitFacts({
    required this.faceCount,
    this.faceRatio,
    this.yaw,
    this.roll,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.backgroundStd,
    this.backgroundEdge,
    this.aligned = true,
  });

  /// The photo could not be opened at all.
  static const unreadable = PortraitFacts(faceCount: -1);

  /// Faces ML Kit found. -1: the file could not be read.
  final int faceCount;

  /// The face's box as a share of the whole photo's area.
  final double? faceRatio;

  /// Head turned left or right, and tipped sideways, in degrees.
  final double? yaw;
  final double? roll;

  /// ML Kit's 0..1 chance that each eye is open; null when it could not tell.
  final double? leftEyeOpen;
  final double? rightEyeOpen;

  /// How busy the area around the head is, on a 0..255 brightness scale: the
  /// spread of brightness, and the mean step between neighbouring pixels. Null
  /// when the face fills so much of the photo that too little background
  /// shows to judge.
  final double? backgroundStd;
  final double? backgroundEdge;

  /// The eyes, nose and mouth were all found, so the face could be lined up
  /// for the comparison with the selfie.
  final bool aligned;

  Map<String, dynamic> toChecks() => {
    'face_ratio': faceRatio == null ? null : _round(faceRatio!, 3),
    'yaw': yaw == null ? null : _round(yaw!, 1),
    'roll': roll == null ? null : _round(roll!, 1),
    'background_std': backgroundStd == null ? null : _round(backgroundStd!, 1),
    'background_edge':
        backgroundEdge == null ? null : _round(backgroundEdge!, 2),
  };

  static double _round(double v, int places) {
    final f = places == 1 ? 10 : (places == 2 ? 100 : 1000);
    return (v * f).round() / f;
  }
}

/// Why a photo was refused. Each one has its own message: "photo refused"
/// alone leaves the person guessing what to change.
enum PortraitProblem {
  unreadable,
  noFace,
  manyFaces,
  tooFar,
  tooClose,
  turned,
  tilted,
  eyesClosed,
  noFeatures,
  busyBackground,
  notSamePerson,
  noFaceInSelfie,
}

// ── Thresholds ───────────────────────────────────────────────
//
// A printed 2x2 photographed flat, or a head-and-shoulders shot at arm's
// length, puts the face's box at roughly 10-35% of the picture. A selfie held
// close is 30-50%. A photographed ID card's portrait is 3-7% (kMaxIdFaceRatio
// in id_photo_check.dart), and a full-body snapshot less still.

/// Below this the face is too small to be an ID photo: a full-length picture,
/// a group shot, or a 2x2 photographed from across the table.
const double kPortraitMinFaceRatio = 0.04;

/// Above this the face is cut off at the edges.
const double kPortraitMaxFaceRatio = 0.60;

/// An ID photo looks straight at the camera. 15 degrees is a slight turn that
/// still shows both sides of the face evenly; past it one ear disappears.
const double kPortraitMaxYaw = 15;

/// Head tipped to one side.
const double kPortraitMaxRoll = 12;

/// Both eyes below this chance of being open: closed, or behind sunglasses.
const double kPortraitEyesOpenMin = 0.25;

/// A plain wall, even an unevenly lit one, changes slowly from pixel to pixel;
/// a room, a curtain or a crowd does not. Measured on the photo scaled to 96
/// pixels wide, so the numbers do not depend on the camera.
const double kPortraitMaxBackgroundEdge = 9;

/// Brightness spread. A strong shadow across a wall stays well under this; a
/// window and a dark room beside each other do not.
const double kPortraitMaxBackgroundStd = 52;

/// Together: some texture AND an uneven spread is a scene, not a wall - a
/// blurred painting or a room behind the head. Either alone is not: a plain
/// wall lit from one side spreads without texture, a uniform rough wall has
/// texture without spread.
///
/// Measured on the phone (2026-10-08, real ML Kit, public-domain portraits):
/// plain grey backdrops 0.5 edge / 4-11 spread; a flag beside the head 9.5 /
/// 61; the Oval Office 19.8 / 39; a soft-focus painting 4.9 / 39 - which only
/// this pair catches.
const double kPortraitTexturedEdge = 4;
const double kPortraitTexturedStd = 35;

/// The photo half of the rule. Null: it is an ID-style photo.
PortraitProblem? judgePortraitPhoto(PortraitFacts f) {
  if (f.faceCount < 0) return PortraitProblem.unreadable;
  if (f.faceCount == 0) return PortraitProblem.noFace;
  if (f.faceCount > 1) return PortraitProblem.manyFaces;

  final ratio = f.faceRatio;
  if (ratio != null && ratio < kPortraitMinFaceRatio) {
    return PortraitProblem.tooFar;
  }
  if (ratio != null && ratio > kPortraitMaxFaceRatio) {
    return PortraitProblem.tooClose;
  }
  if ((f.yaw ?? 0).abs() > kPortraitMaxYaw) return PortraitProblem.turned;
  if ((f.roll ?? 0).abs() > kPortraitMaxRoll) return PortraitProblem.tilted;

  final l = f.leftEyeOpen, r = f.rightEyeOpen;
  if (l != null &&
      r != null &&
      l < kPortraitEyesOpenMin &&
      r < kPortraitEyesOpenMin) {
    return PortraitProblem.eyesClosed;
  }
  // Without eyes, nose and mouth the face cannot be compared with the selfie,
  // and a face hidden that much is not an ID photo either.
  if (!f.aligned) return PortraitProblem.noFeatures;

  final edge = f.backgroundEdge ?? 0, spread = f.backgroundStd ?? 0;
  if (edge > kPortraitMaxBackgroundEdge ||
      spread > kPortraitMaxBackgroundStd ||
      (edge > kPortraitTexturedEdge && spread > kPortraitTexturedStd)) {
    return PortraitProblem.busyBackground;
  }
  return null;
}

/// The comparison half: the face-match verdict (face_match_service.py) of
/// this photo against the selfie. Null: not refused.
PortraitProblem? judgePortraitMatch(String? verdict) => switch (verdict) {
  'no_match' => PortraitProblem.notSamePerson,
  'no_face_in_selfie' => PortraitProblem.noFaceInSelfie,
  _ => null,
};

/// Background busyness of a grey image, around a face.
///
/// [grey] is row-major brightness 0..255, [width] x [height]. The face box is
/// in the same pixels. Samples the area ABOVE the head (above the box by more
/// than half a face, where hair ends) and BESIDE it (further out than half a
/// face, past ears and hair), down to the chin - below that are shoulders.
/// Returns null when fewer than 120 pixels of background show.
({double std, double edge})? measureBackground({
  required List<int> grey,
  required int width,
  required int height,
  required double faceLeft,
  required double faceTop,
  required double faceRight,
  required double faceBottom,
}) {
  final fw = faceRight - faceLeft;
  final fh = faceBottom - faceTop;
  final topLimit = faceTop - 0.6 * fh;
  final leftLimit = faceLeft - 0.5 * fw;
  final rightLimit = faceRight + 0.5 * fw;

  bool inBackground(int x, int y) {
    if (y < topLimit) return true;
    if (y > faceBottom) return false;
    return x < leftLimit || x > rightLimit;
  }

  var n = 0;
  var sum = 0.0, sumSq = 0.0;
  var edges = 0.0;
  var edgeN = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!inBackground(x, y)) continue;
      final v = grey[y * width + x].toDouble();
      n++;
      sum += v;
      sumSq += v * v;
      if (x + 1 < width && inBackground(x + 1, y)) {
        edges += (grey[y * width + x + 1] - v).abs();
        edgeN++;
      }
      if (y + 1 < height && inBackground(x, y + 1)) {
        edges += (grey[(y + 1) * width + x] - v).abs();
        edgeN++;
      }
    }
  }
  if (n < 120 || edgeN == 0) return null;
  final mean = sum / n;
  final variance = (sumSq / n) - mean * mean;
  return (
    std: variance <= 0 ? 0 : math.sqrt(variance),
    edge: edges / edgeN,
  );
}
