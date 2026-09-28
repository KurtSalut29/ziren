import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Makes a freshly captured selfie fit to store: un-mirrored, upright, and a
/// sane size.
///
/// THE MIRROR
///
/// A front camera shows a MIRRORED preview on purpose, because that is what a
/// mirror does, and many Android camera HALs save the still the same way. That
/// photograph is what an administrator holds up against an ID card, so a
/// flipped copy makes the one comparison this whole flow exists for harder
/// than it needs to be — asymmetric faces, which is all of them, read subtly
/// like a different person when reversed.
///
/// Android's Camera2 specification says the JPEG should be the un-mirrored
/// sensor view, but a large number of OEM builds (and the vendor "save selfies
/// as previewed" setting many ship enabled) apply the preview transform to the
/// still as well. The Flutter camera plugin passes through whatever the device
/// produced, so what lands on disk depends on the handset.
///
/// THE SIZE, AND WHY IT IS NOT OPTIONAL
///
/// `takePicture()` captures at the sensor's STILL resolution — 12 MP and up on
/// a current phone — regardless of the `ResolutionPreset.medium` used for the
/// preview stream. Nothing downstream wants that: an admin comparing two faces
/// on a dashboard does not need 4000px, the face recogniser reduces it to
/// 112x112 anyway, and it is uploaded over a rural connection.
///
/// So this also caps the long edge at [_maxEdge]. That is the same ceiling
/// `IdUploadService.pickIdPhoto` already applies to the ID photo, and it is
/// what makes the second decode — the one the face alignment does — cheap.
///
/// EVERYTHING RUNS OFF THE MAIN ISOLATE
///
/// This is the part that was wrong the first time and it is worth being blunt
/// about, because the symptom was indistinguishable from a hang. Decoding a
/// 12 MP JPEG in pure Dart, flipping it and re-encoding takes many seconds,
/// and doing it inline froze the UI thread for that whole time — the capture
/// spinner simply never went away. `compute` moves the pixel work to a
/// background isolate; the main isolate does file I/O and nothing else.
///
/// THE HONEST CAVEAT ON THE FLIP
///
/// There is no reliable runtime test for "was this image mirrored" — a face
/// gives no clue, and EXIF records rotation but has no mirror flag that phone
/// cameras populate. So the flip is a fixed correction, not a detection, and
/// on a device whose HAL follows the specification it would introduce the very
/// problem it removes elsewhere.
///
/// [mirrorFrontCamera] is the single switch for that. To check a handset: take
/// a selfie holding something with writing on it. If the writing reads
/// correctly on the review screen, this device needs no correction and the
/// flag should be false for it; if it reads backwards, leave it on. iOS is
/// excluded already — AVCapturePhotoOutput does not mirror unless asked to,
/// and the plugin does not ask.
abstract final class SelfieOrientation {
  /// Longest edge of the stored selfie, in pixels.
  static const _maxEdge = 1600;

  /// JPEG quality for the re-encode. High enough that nothing a recogniser or
  /// a reviewing admin looks at is lost.
  static const _quality = 90;

  /// Whether a front-camera still needs flipping on this platform.
  ///
  /// Android only. See the caveat in the class docstring before changing it.
  static bool get mirrorFrontCamera =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Rewrite [path] un-mirrored, upright and downscaled. Returns the path.
  ///
  /// Failure is deliberately non-fatal and silent to the user: a selfie that
  /// is the wrong way round is a nuisance, and a selfie that failed to save
  /// because the normalisation threw is a person who cannot finish
  /// registering. The original file is left exactly as it was in that case.
  static Future<String> normalise(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();

      final out = await compute(_normaliseBytes, (
        bytes: bytes,
        mirror: mirrorFrontCamera,
        maxEdge: _maxEdge,
        quality: _quality,
      ));
      if (out == null) return path;

      await file.writeAsBytes(out);
      return path;
    } catch (e) {
      debugPrint('[SelfieOrientation.normalise] $e');
      return path;
    }
  }
}

/// The pixel work, run on a background isolate by [SelfieOrientation.normalise].
///
/// Top-level because `compute` requires an entry point it can address by
/// symbol; a closure or an instance method cannot be sent to an isolate.
Uint8List? _normaliseBytes(
  ({Uint8List bytes, bool mirror, int maxEdge, int quality}) job,
) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;

  // Orientation is baked FIRST. The EXIF rotation tag describes the original
  // pixel layout, so flipping or resizing before baking leaves a tag that no
  // longer describes the data — every later reader then rotates an
  // already-corrected image and the face ends up sideways.
  var image = img.bakeOrientation(decoded);

  if (job.mirror) image = img.flipHorizontal(image);

  final longest = image.width > image.height ? image.width : image.height;
  if (longest > job.maxEdge) {
    image =
        image.width >= image.height
            ? img.copyResize(image, width: job.maxEdge)
            : img.copyResize(image, height: job.maxEdge);
  }

  return img.encodeJpg(image, quality: job.quality);
}
