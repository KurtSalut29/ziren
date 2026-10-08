import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// What a face crop attempt produced.
enum FaceCropOutcome {
  /// A face was found and aligned. [FaceCrop.rgb] is populated.
  ok,

  /// No face in the image at all.
  none,

  /// A face was found but ML Kit did not return the eye and mouth landmarks
  /// the alignment needs. Treated as a failure rather than fudged: a crop
  /// aligned on guessed points is worse than no crop, because the score it
  /// produces still looks like a measurement.
  noLandmarks,

  /// More than one face. On an ID card that usually means the ghost portrait
  /// many Philippine IDs print alongside the main photo; in a selfie it means
  /// somebody else is in shot. Either way the largest face is used and this is
  /// reported so the caller can say so.
  multiple,

  /// Could not read or decode the file.
  unreadable,
}

/// One aligned face, ready to embed.
class FaceCrop {
  const FaceCrop({required this.outcome, this.rgb, this.faceRatio});

  final FaceCropOutcome outcome;

  /// Area of the LARGEST face as a fraction of the whole photo, or null when
  /// no face was found or the photo's size could not be read.
  ///
  /// On a photographed card the portrait is a small corner (a few percent of
  /// the picture); in a selfie the face fills the frame. That difference is how
  /// a selfie uploaded as an ID is told apart - see kMaxIdFaceRatio.
  final double? faceRatio;

  /// 112 * 112 * 3 bytes of raw RGB, or null when [outcome] is not `ok`.
  final Uint8List? rgb;

  bool get isUsable => rgb != null;
}

/// Crops and aligns a face to the frame an ArcFace recogniser expects.
///
/// WHY ALIGNMENT AND NOT JUST A CROP
///
/// ArcFace is trained on faces that have been warped so the eyes, nose and
/// mouth sit at fixed pixel positions. Feeding it a plain bounding-box crop
/// gives it a face at an arbitrary rotation and scale, and the embedding it
/// returns is then dominated by pose rather than identity — two photographs of
/// the same person at different head angles score lower than two of different
/// people at the same angle. The alignment below is not a nicety; without it
/// the whole comparison is noise wearing a decimal point.
///
/// The five points ML Kit returns — both eyes, the nose base, both mouth
/// corners — are exactly the five InsightFace aligns on, which is what makes
/// this possible on-device without a second model.
///
/// WHICH EYE IS WHICH: BY POSITION, NOT BY NAME
///
/// The InsightFace template is in IMAGE coordinates - its first point sits at
/// x=38 of 112, on the left of the frame. This used to map ML Kit's `rightEye`
/// there, on the reading that ML Kit names landmarks from the subject's point
/// of view. On a real phone it does not: logged 2026-10-08 on the Infinix,
/// `leftEye` (111, 326) and `rightEye` (223, 328) on a front-facing portrait -
/// the "left" eye is on the left of the picture.
///
/// The crossover therefore swapped both eyes and both mouth corners, and a
/// similarity transform cannot fit a mirrored point set: the least-squares
/// scale collapsed to a fraction of the real one, and every "aligned face" was
/// the whole photograph shrunk into 112 x 112 with the face a dot in it. The
/// recogniser has no notion of "not a face" (face_match_service.py), so every
/// pair scored as a match - Biden against Harris 0.83. Every ID/selfie
/// verdict stored before this fix was measured on such crops.
///
/// So the points are put in template order by where they ARE: of the two
/// eyes, the one further left goes first, and the same for the mouth corners
/// ([templateOrder]). Correct whatever a plugin version calls them, for any
/// head that is not upside down.
class FaceAlignService {
  FaceAlignService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
          // Much smaller than the liveness detector's 0.15. The portrait on an
          // ID card occupies a small corner of the photographed card, and at
          // the default minimum it is simply never found — which would report
          // every genuine ID as having no face on it.
          minFaceSize: 0.04,
        ),
      );

  final FaceDetector _detector;

  /// Side of the aligned crop, in pixels. The frame ArcFace expects.
  ///
  /// The five-point template it is aligned TO lives at the bottom of this
  /// file, next to the isolate code that uses it.
  static const int size = 112;

  Future<void> dispose() => _detector.close();

  /// Find the largest face in [imagePath] and return it aligned.
  ///
  /// The split of work here is deliberate and was wrong the first time.
  ///
  /// ML Kit detection stays on the main isolate: it is a platform channel to
  /// native code, so the Dart thread is idle while it runs and cannot be moved
  /// to a background isolate anyway.
  ///
  /// The DECODE AND WARP go to a background isolate. Decoding a phone photo in
  /// pure Dart is seconds of synchronous CPU, and doing it inline blocked the
  /// UI thread for exactly as long — which on the selfie screen looked like
  /// the capture spinner hanging forever, with no error and nothing to press.
  Future<FaceCrop> crop(String imagePath) async {
    final Uint8List bytes;
    final List<Face> faces;

    try {
      bytes = await File(imagePath).readAsBytes();
      faces = await _detector.processImage(InputImage.fromFilePath(imagePath));
    } catch (e) {
      debugPrint('[FaceAlignService.crop] $e');
      return const FaceCrop(outcome: FaceCropOutcome.unreadable);
    }

    if (faces.isEmpty) return const FaceCrop(outcome: FaceCropOutcome.none);

    // Largest by bounding box. On an ID card the main portrait is always
    // bigger than the ghost print beside it; in a selfie the subject is
    // nearer the camera than anyone behind them.
    faces.sort(
      (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
        a.boundingBox.width * a.boundingBox.height,
      ),
    );

    // The share of the photo the largest face takes. The photo's pixel count
    // is width * height whichever way the EXIF tag says it is turned, so the
    // ratio needs no rotation handling.
    final ratio = _faceRatio(faces.first, bytes);

    final points = _fivePoints(faces.first);
    if (points == null) {
      return FaceCrop(outcome: FaceCropOutcome.noLandmarks, faceRatio: ratio);
    }

    // Flattened to a plain List<double>: nested lists cross an isolate
    // boundary fine, but a flat buffer is one allocation instead of five.
    final flat = <double>[for (final p in points) ...p];

    try {
      final rgb = await compute(_alignJob, (bytes: bytes, points: flat));
      if (rgb == null) {
        return FaceCrop(outcome: FaceCropOutcome.unreadable, faceRatio: ratio);
      }
      return FaceCrop(
        outcome:
            faces.length > 1 ? FaceCropOutcome.multiple : FaceCropOutcome.ok,
        rgb: rgb,
        faceRatio: ratio,
      );
    } catch (e) {
      debugPrint('[FaceAlignService.crop/warp] $e');
      return const FaceCrop(outcome: FaceCropOutcome.unreadable);
    }
  }

  /// [face]'s bounding-box area over the photo's area, or null if the photo's
  /// dimensions cannot be read from its header.
  double? _faceRatio(Face face, Uint8List bytes) {
    try {
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      final box = face.boundingBox;
      return (box.width * box.height) / (info.width * info.height);
    } catch (e) {
      debugPrint('[FaceAlignService._faceRatio] $e');
      return null;
    }
  }

  /// The five landmarks, in the template's image-coordinate order.
  ///
  /// Returns null if any is missing. ML Kit omits landmarks it is not
  /// confident about — a face in profile loses one eye, a hand over the mouth
  /// loses both corners — and substituting a bounding-box estimate for a
  /// missing point would produce a plausible-looking crop that is warped in a
  /// way nobody downstream can detect.
  List<List<double>>? _fivePoints(Face face) {
    List<double>? at(FaceLandmarkType t) {
      final p = face.landmarks[t]?.position;
      return p == null ? null : [p.x.toDouble(), p.y.toDouble()];
    }

    return templateOrder(
      eyes: [at(FaceLandmarkType.leftEye), at(FaceLandmarkType.rightEye)],
      nose: at(FaceLandmarkType.noseBase),
      mouth: [at(FaceLandmarkType.leftMouth), at(FaceLandmarkType.rightMouth)],
    );
  }
}

/// The five points in [_template]'s order - eye on the left of the image,
/// eye on the right, nose, mouth corner on the left, on the right - decided by
/// x position, never by the landmark's name (see the class comment for the
/// defect the names caused). Null when any point is missing.
@visibleForTesting
List<List<double>>? templateOrder({
  required List<List<double>?> eyes,
  required List<double>? nose,
  required List<List<double>?> mouth,
}) {
  if (nose == null || eyes.any((p) => p == null) || mouth.any((p) => p == null)) {
    return null;
  }
  List<List<double>> byX(List<List<double>?> pair) =>
      [pair[0]!, pair[1]!]..sort((a, b) => a[0].compareTo(b[0]));
  return [...byX(eyes), nose, ...byX(mouth)];
}

/// Align [source] on five points already in template order. A seam for tests:
/// the isolate job does the same after decoding.
@visibleForTesting
Uint8List alignForTest(img.Image source, List<List<double>> points) =>
    _warp(source, points);

// ── Isolate work ────────────────────────────────────────────
//
// Top-level, because `compute` addresses its entry point by symbol and cannot
// send a closure or an instance method to another isolate. Everything below
// runs OFF the UI thread — see FaceAlignService.crop for why that matters.

/// The canonical 112x112 destination, in IMAGE coordinates.
///
/// The standard InsightFace five-point template. Order is:
///   0  eye on the left of the image
///   1  eye on the right of the image
///   2  nose base
///   3  mouth corner on the left of the image
///   4  mouth corner on the right of the image
/// By position, whatever ML Kit names them - see [templateOrder].
const List<List<double>> _template = [
  [38.2946, 51.6963],
  [73.5318, 51.5014],
  [56.0252, 71.7366],
  [41.5493, 92.3655],
  [70.7299, 92.2041],
];

/// Decode the photo and warp the face out of it. Runs on a background isolate.
///
/// [job.points] is the five landmarks flattened to x,y,x,y,… in the template's
/// order.
Uint8List? _alignJob(({Uint8List bytes, List<double> points}) job) {
  // decodeImage, not decodeJpg: the camera writes JPEG, but a file picked from
  // the gallery can be anything, and a heuristic decode costs nothing.
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;

  // bakeOrientation, and it is load-bearing. Phone cameras store the image in
  // sensor order and record the rotation in an EXIF tag. ML Kit's
  // fromFilePath honours that tag; the `image` package's decode does not
  // rotate by default. Without this the detector and the pixel buffer disagree
  // about which way up the photo is, so the landmark coordinates land
  // somewhere else entirely and the crop comes out of the wrong part of the
  // image.
  final source = img.bakeOrientation(decoded);

  final src = <List<double>>[
    for (var i = 0; i < job.points.length; i += 2)
      [job.points[i], job.points[i + 1]],
  ];

  return _warp(source, src);
}

/// Warp [source] so [src] lands on [_template], into a 112x112 RGB buffer.
///
/// The transform is the least-squares SIMILARITY transform — rotation,
/// uniform scale, translation, and no shear or reflection. Solved in closed
/// form rather than by SVD:
///
///   with both point sets centred on their means,
///     a = Σ(x·u + y·v) / Σ(x² + y²)
///     b = Σ(x·v − y·u) / Σ(x² + y²)
///   gives  [u v]ᵀ = [[a, −b], [b, a]] · [x y]ᵀ + t
///
/// which is the same answer Umeyama's SVD formulation produces for the 2D
/// no-reflection case, in about fifteen lines instead of a matrix library.
/// Allowing shear (a full affine fit) would let a bad landmark stretch the
/// face into the template and hide its own error; a similarity transform
/// cannot, so a poor fit stays visible as a poor fit.
Uint8List _warp(img.Image source, List<List<double>> src) {
  const size = FaceAlignService.size;
  final n = src.length;

  double sx = 0, sy = 0, du = 0, dv = 0;
  for (var i = 0; i < n; i++) {
    sx += src[i][0];
    sy += src[i][1];
    du += _template[i][0];
    dv += _template[i][1];
  }
  sx /= n;
  sy /= n;
  du /= n;
  dv /= n;

  double num1 = 0, num2 = 0, den = 0;
  for (var i = 0; i < n; i++) {
    final x = src[i][0] - sx, y = src[i][1] - sy;
    final u = _template[i][0] - du, v = _template[i][1] - dv;
    num1 += x * u + y * v;
    num2 += x * v - y * u;
    den += x * x + y * y;
  }
  // Degenerate: all five landmarks at one point. Cannot happen with a real
  // detection, but a zero divide here would produce NaN coordinates and a
  // black crop that still gets embedded and scored.
  if (den == 0) return Uint8List(size * size * 3);

  final a = num1 / den;
  final b = num2 / den;

  // Invert to sample: for each destination pixel, where does it come from?
  // Forward-mapping instead would leave unwritten holes wherever the scale
  // is greater than one.
  final det = a * a + b * b;
  if (det == 0) return Uint8List(size * size * 3);

  final out = Uint8List(size * size * 3);
  for (var yd = 0; yd < size; yd++) {
    for (var xd = 0; xd < size; xd++) {
      final cu = xd - du;
      final cv = yd - dv;
      final xs = (a * cu + b * cv) / det + sx;
      final ys = (-b * cu + a * cv) / det + sy;

      final p = _bilinear(source, xs, ys);
      final o = (yd * size + xd) * 3;
      out[o] = p[0];
      out[o + 1] = p[1];
      out[o + 2] = p[2];
    }
  }
  return out;
}

/// Bilinear sample, clamped at the edges.
///
/// Nearest-neighbour would be simpler and is wrong here: the warp usually
/// downscales a face of a few hundred pixels to 112, and point-sampling that
/// aliases fine detail into high-frequency noise — which is exactly the part
/// of the image a recogniser reads.
List<int> _bilinear(img.Image im, double x, double y) {
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x > im.width - 1) x = (im.width - 1).toDouble();
  if (y > im.height - 1) y = (im.height - 1).toDouble();

  final x0 = x.floor(), y0 = y.floor();
  final x1 = (x0 + 1).clamp(0, im.width - 1);
  final y1 = (y0 + 1).clamp(0, im.height - 1);
  final fx = x - x0, fy = y - y0;

  final p00 = im.getPixel(x0, y0);
  final p10 = im.getPixel(x1, y0);
  final p01 = im.getPixel(x0, y1);
  final p11 = im.getPixel(x1, y1);

  int mix(num a, num b, num c, num d) => (a * (1 - fx) * (1 - fy) +
          b * fx * (1 - fy) +
          c * (1 - fx) * fy +
          d * fx * fy)
      .round()
      .clamp(0, 255);

  return [
    mix(p00.r, p10.r, p01.r, p11.r),
    mix(p00.g, p10.g, p01.g, p11.g),
    mix(p00.b, p10.b, p01.b, p11.b),
  ];
}
