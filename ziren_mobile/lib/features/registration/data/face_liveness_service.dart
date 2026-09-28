import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// What the person is being asked to do to show they are a live human.
enum LivenessChallenge { blink, turnLeft, turnRight, smile }

extension LivenessChallengeInfo on LivenessChallenge {
  /// Must be one of the values in migration 020's `liveness_method` CHECK.
  String get dbValue => switch (this) {
    LivenessChallenge.blink => 'mlkit_blink',
    LivenessChallenge.turnLeft ||
    LivenessChallenge.turnRight => 'mlkit_head_turn',
    LivenessChallenge.smile => 'mlkit_smile',
  };

  String get instruction => switch (this) {
    LivenessChallenge.blink => 'Blink slowly',
    LivenessChallenge.turnLeft => 'Turn your head slowly to the left',
    LivenessChallenge.turnRight => 'Turn your head slowly to the right',
    LivenessChallenge.smile => 'Smile',
  };
}

/// How the face is sitting in frame, so the UI can coach before challenging.
enum FaceFraming { none, multiple, tooFar, tooClose, offCentre, good }

/// Result of analysing one frame.
class LivenessFrame {
  const LivenessFrame({required this.framing, this.challengeMet = false});
  final FaceFraming framing;
  final bool challengeMet;
}

/// On-device face detection driving a randomised liveness challenge.
///
/// WHAT THIS IS AND IS NOT — the same caveat as migration 020, repeated here
/// because this is where someone would be tempted to over-trust it.
///
/// This runs entirely on the handset. No image leaves the phone, which is the
/// point: a face API would mean shipping biometrics to a third party for every
/// registration in the province.
///
/// The cost of that is that the result is unverifiable server-side. A modified
/// client can claim any challenge passed. So this is a UX guard — it stops an
/// honest person submitting a photo of a photo, or a blurry unusable frame —
/// and it is NOT an anti-fraud control. The actual control is an administrator
/// comparing the captured selfie against the ID photograph. Nothing here may
/// ever raise verification_level on its own.
class FaceLivenessService {
  FaceLivenessService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          // Classification gives us eye-open and smiling probabilities, which
          // are what the blink and smile challenges read.
          enableClassification: true,
          // Accurate rather than fast: this runs a few times a second on a
          // still-ish subject, not on live video, so latency matters less
          // than not failing an honest user who is holding steady.
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.15,
        ),
      );

  final FaceDetector _detector;

  /// Guards against re-entering the detector while a frame is in flight. The
  /// camera stream fires faster than detection completes, and queuing every
  /// frame would run the device out of memory within seconds.
  bool _busy = false;

  /// Set when this handset hands us frames we cannot pass to ML Kit.
  ///
  /// The controller asks for nv21 on Android, but a device is free to ignore
  /// that and deliver yuv420 anyway. When that happens every frame is
  /// discarded and detection silently never fires — from the outside the
  /// camera looks like it is working and simply refuses to see anyone. That is
  /// a miserable failure to debug from a user report, so it is surfaced
  /// explicitly instead of being swallowed.
  String? unsupportedReason;

  bool get isUnsupported => unsupportedReason != null;

  /// Blink detection needs history: a single frame with closed eyes could just
  /// be the moment the shutter caught. We require open, then closed, then open.
  bool _sawEyesOpen = false;
  bool _sawEyesClosed = false;

  void resetChallengeState() {
    _sawEyesOpen = false;
    _sawEyesClosed = false;
  }

  /// Analyse one camera frame against [challenge].
  ///
  /// Returns null when the previous frame is still being processed — the
  /// caller should simply keep the last state rather than treating it as "no
  /// face", which would make the UI flicker.
  Future<LivenessFrame?> analyse({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    required LivenessChallenge challenge,
  }) async {
    if (_busy) return null;
    _busy = true;
    try {
      final input = _toInputImage(image, camera, deviceOrientation);
      if (input == null) return const LivenessFrame(framing: FaceFraming.none);

      final faces = await _detector.processImage(input);

      if (faces.isEmpty) {
        return const LivenessFrame(framing: FaceFraming.none);
      }
      if (faces.length > 1) {
        // More than one face is a real failure mode, not a nicety: it usually
        // means someone is holding up a phone showing a photo next to their
        // own face.
        return const LivenessFrame(framing: FaceFraming.multiple);
      }

      final face = faces.first;
      final framing = _assessFraming(face, input.metadata!.size);
      if (framing != FaceFraming.good) {
        return LivenessFrame(framing: framing);
      }

      return LivenessFrame(
        framing: FaceFraming.good,
        challengeMet: _evaluate(face, challenge),
      );
    } catch (e) {
      debugPrint('FaceLivenessService: $e');
      return const LivenessFrame(framing: FaceFraming.none);
    } finally {
      _busy = false;
    }
  }

  FaceFraming _assessFraming(Face face, Size imageSize) {
    final box = face.boundingBox;
    final frameArea = imageSize.width * imageSize.height;
    if (frameArea <= 0) return FaceFraming.none;

    final ratio = (box.width * box.height) / frameArea;
    if (ratio < 0.06) return FaceFraming.tooFar;
    if (ratio > 0.60) return FaceFraming.tooClose;

    final cx = box.center.dx / imageSize.width;
    final cy = box.center.dy / imageSize.height;
    // Generous bounds. Demanding a tightly centred face punishes anyone
    // holding a phone one-handed, which is most people.
    if (cx < 0.22 || cx > 0.78 || cy < 0.18 || cy > 0.82) {
      return FaceFraming.offCentre;
    }
    return FaceFraming.good;
  }

  bool _evaluate(Face face, LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.blink:
        final l = face.leftEyeOpenProbability;
        final r = face.rightEyeOpenProbability;
        if (l == null || r == null) return false;
        final open = l > 0.75 && r > 0.75;
        final closed = l < 0.25 && r < 0.25;
        // Strict order: open -> closed -> open. A face that arrives already
        // closed, or a still photo of someone mid-blink, cannot satisfy it.
        if (open && !_sawEyesClosed) _sawEyesOpen = true;
        if (closed && _sawEyesOpen) _sawEyesClosed = true;
        return _sawEyesOpen && _sawEyesClosed && open;

      case LivenessChallenge.turnLeft:
        // headEulerAngleY is positive when the face turns toward the camera's
        // left, which is the user's right on a front camera. Named from the
        // user's point of view here, because that is what the prompt says.
        return (face.headEulerAngleY ?? 0) < -22;

      case LivenessChallenge.turnRight:
        return (face.headEulerAngleY ?? 0) > 22;

      case LivenessChallenge.smile:
        return (face.smilingProbability ?? 0) > 0.80;
    }
  }

  /// Convert a camera frame into something ML Kit will accept.
  ///
  /// The camera controller is configured with nv21 on Android and bgra8888 on
  /// iOS precisely so this stays a single-plane copy. Requesting the default
  /// yuv420 instead would mean stitching three planes by hand on every frame,
  /// which is both slower and a well-known source of subtly wrong images.
  InputImage? _toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final rotation = _rotationOf(camera, deviceOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      unsupportedReason = 'unknown camera format ${image.format.raw}';
      return null;
    }
    if (Platform.isAndroid && format != InputImageFormat.nv21) {
      unsupportedReason = 'this phone returns ${format.name} frames, not nv21';
      debugPrint('FaceLivenessService: $unsupportedReason');
      return null;
    }
    if (Platform.isIOS && format != InputImageFormat.bgra8888) {
      unsupportedReason = 'this phone returns ${format.name} frames';
      return null;
    }
    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  static const _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImageRotation? _rotationOf(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }
    final deviceDegrees = _orientationDegrees[deviceOrientation];
    if (deviceDegrees == null) return null;

    // Front camera is mirrored, so the device rotation subtracts rather than
    // adds. Getting this backwards does not fail loudly — it silently returns
    // a sideways image, and ML Kit then reports no face at all, which reads
    // as "the camera is broken".
    final rotationCompensation =
        camera.lensDirection == CameraLensDirection.front
            ? (camera.sensorOrientation + deviceDegrees) % 360
            : (camera.sensorOrientation - deviceDegrees + 360) % 360;

    return InputImageRotationValue.fromRawValue(rotationCompensation);
  }

  Future<void> dispose() => _detector.close();
}
