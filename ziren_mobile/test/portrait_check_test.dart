// The 2x2 ID photo for the Ziren ID card (user request 2026-10-08): an
// ID-style photo, and the resident's own face - "baka mag upload lang sya ng
// kahit ano". The rule is domain/portrait_check.dart; these pin each
// threshold, and the background measure on synthetic photos.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/registration/domain/portrait_check.dart';

/// A good 2x2: one face, a fifth of the photo, straight on, eyes open, plain.
PortraitFacts good({
  int faces = 1,
  double ratio = 0.2,
  double yaw = 2,
  double roll = 1,
  double? leftEye = 0.9,
  double? rightEye = 0.9,
  double? bgStd = 8,
  double? bgEdge = 1.5,
  bool aligned = true,
}) => PortraitFacts(
  faceCount: faces,
  faceRatio: ratio,
  yaw: yaw,
  roll: roll,
  leftEyeOpen: leftEye,
  rightEyeOpen: rightEye,
  backgroundStd: bgStd,
  backgroundEdge: bgEdge,
  aligned: aligned,
);

/// A 96 x 128 grey photo with a face box in the middle, whose background is
/// drawn by [paint] (x, y -> 0..255).
({double std, double edge})? background(int Function(int x, int y) paint) {
  const w = 96, h = 128;
  return measureBackground(
    grey: [
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) paint(x, y),
    ],
    width: w,
    height: h,
    faceLeft: 30,
    faceTop: 40,
    faceRight: 66,
    faceBottom: 82,
  );
}

void main() {
  group('is it an ID photo', () {
    test('a plain, straight, single-face photo passes', () {
      expect(judgePortraitPhoto(good()), isNull);
    });

    test('nothing to read, no face, or someone else in shot', () {
      expect(judgePortraitPhoto(PortraitFacts.unreadable), PortraitProblem.unreadable);
      expect(judgePortraitPhoto(const PortraitFacts(faceCount: 0)), PortraitProblem.noFace);
      expect(judgePortraitPhoto(good(faces: 2)), PortraitProblem.manyFaces);
    });

    test('a speck of a face (an ID card, a full-length photo) or a cut-off one', () {
      expect(judgePortraitPhoto(good(ratio: 0.03)), PortraitProblem.tooFar);
      expect(judgePortraitPhoto(good(ratio: kPortraitMinFaceRatio)), isNull);
      expect(judgePortraitPhoto(good(ratio: kPortraitMaxFaceRatio)), isNull);
      expect(judgePortraitPhoto(good(ratio: 0.7)), PortraitProblem.tooClose);
    });

    test('turned or tipped heads, either way', () {
      expect(judgePortraitPhoto(good(yaw: 15)), isNull);
      expect(judgePortraitPhoto(good(yaw: -16)), PortraitProblem.turned);
      expect(judgePortraitPhoto(good(yaw: 30)), PortraitProblem.turned);
      expect(judgePortraitPhoto(good(roll: 12)), isNull);
      expect(judgePortraitPhoto(good(roll: -13)), PortraitProblem.tilted);
    });

    test('closed eyes or sunglasses; one closed eye or no reading is not refused', () {
      expect(judgePortraitPhoto(good(leftEye: 0.1, rightEye: 0.05)), PortraitProblem.eyesClosed);
      expect(judgePortraitPhoto(good(leftEye: 0.1, rightEye: 0.8)), isNull); // a wink
      expect(judgePortraitPhoto(good(leftEye: null, rightEye: null)), isNull);
    });

    test('a face too covered to line up (a mask) is refused', () {
      expect(judgePortraitPhoto(good(aligned: false)), PortraitProblem.noFeatures);
    });

    test('a busy background is refused; too little background to judge is not', () {
      expect(judgePortraitPhoto(good(bgEdge: 14)), PortraitProblem.busyBackground);
      expect(judgePortraitPhoto(good(bgStd: 70)), PortraitProblem.busyBackground);
      expect(judgePortraitPhoto(good(bgStd: null, bgEdge: null)), isNull);
    });

    test('the values measured on the phone (2026-10-08) land where they should', () {
      // Plain grey backdrop (the 2x2 crops), and the same with a grey fill
      // where the photo was turned.
      expect(judgePortraitPhoto(good(bgStd: 11.1, bgEdge: 0.49)), isNull);
      expect(judgePortraitPhoto(good(bgStd: 20.1, bgEdge: 1.56)), isNull);
      // A flag beside the head, the Oval Office, a soft-focus painting.
      expect(judgePortraitPhoto(good(bgStd: 61.0, bgEdge: 9.54)), PortraitProblem.busyBackground);
      expect(judgePortraitPhoto(good(bgStd: 38.8, bgEdge: 19.81)), PortraitProblem.busyBackground);
      expect(judgePortraitPhoto(good(bgStd: 39.0, bgEdge: 4.87)), PortraitProblem.busyBackground);
      // A wall lit unevenly (spread, no texture), a rough uniform wall
      // (texture, no spread): both still plain.
      expect(judgePortraitPhoto(good(bgStd: 45, bgEdge: 1.5)), isNull);
      expect(judgePortraitPhoto(good(bgStd: 14, bgEdge: 6)), isNull);
    });

    test('photo problems are named before background ones', () {
      // Fix the one that makes it "not an ID photo" first.
      expect(judgePortraitPhoto(good(yaw: 40, bgEdge: 20)), PortraitProblem.turned);
    });
  });

  group('is it the same person as the selfie', () {
    test('only a clear mismatch refuses; an admin settles the rest', () {
      expect(judgePortraitMatch('no_match'), PortraitProblem.notSamePerson);
      expect(judgePortraitMatch('no_face_in_selfie'), PortraitProblem.noFaceInSelfie);
      expect(judgePortraitMatch('match'), isNull);
      expect(judgePortraitMatch('uncertain'), isNull);
      expect(judgePortraitMatch('unavailable'), isNull); // offline, or no model
      expect(judgePortraitMatch(null), isNull);
    });
  });

  group('the background measure', () {
    test('a plain white wall', () {
      final bg = background((x, y) => 240)!;
      expect(bg.std, lessThan(1));
      expect(bg.edge, lessThan(1));
      expect(judgePortraitPhoto(good(bgStd: bg.std, bgEdge: bg.edge)), isNull);
    });

    test('a wall lit from one side, with a soft shadow, is still plain', () {
      final bg = background((x, y) => (150 + x * 0.9 - y * 0.3).round().clamp(0, 255))!;
      expect(bg.edge, lessThan(kPortraitMaxBackgroundEdge));
      expect(bg.std, lessThan(kPortraitMaxBackgroundStd));
    });

    test('a cluttered room is busy', () {
      final rnd = Random(7);
      // Blocks of 3 px - shelves, posters, a doorway - not single-pixel noise.
      final blocks = List.generate(50 * 50, (_) => rnd.nextInt(256));
      final bg = background((x, y) => blocks[(y ~/ 3) * 50 + (x ~/ 3)])!;
      expect(bg.edge, greaterThan(kPortraitMaxBackgroundEdge));
      expect(judgePortraitPhoto(good(bgStd: bg.std, bgEdge: bg.edge)), PortraitProblem.busyBackground);
    });

    test('stripes (a curtain, a fence) are busy', () {
      final bg = background((x, y) => (x ~/ 2).isEven ? 40 : 210)!;
      expect(judgePortraitPhoto(good(bgStd: bg.std, bgEdge: bg.edge)), PortraitProblem.busyBackground);
    });

    test('the face itself is not counted as background', () {
      // Wild pixels inside the face box (and the hair and ears beside it),
      // a plain wall everywhere else.
      final bg = background((x, y) {
        final nearFace = x >= 12 && x <= 84 && y >= 15 && y <= 82;
        return nearFace ? ((x * 37 + y * 91) % 256) : 235;
      })!;
      expect(bg.edge, lessThan(1));
    });

    test('a face that fills the photo leaves nothing to judge', () {
      final bg = measureBackground(
        grey: List.filled(20 * 20, 128),
        width: 20,
        height: 20,
        faceLeft: 2,
        faceTop: 2,
        faceRight: 18,
        faceBottom: 18,
      );
      expect(bg, isNull);
    });
  });

  test('the stored checks are rounded and carry no image', () {
    final checks = good(ratio: 0.123456, yaw: 3.14159, bgEdge: 1.23456).toChecks();
    expect(checks['face_ratio'], 0.123);
    expect(checks['yaw'], 3.1);
    expect(checks['background_edge'], 1.23);
    expect(checks.values.whereType<List>(), isEmpty);
  });
}
