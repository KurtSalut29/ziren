// The face crop the recogniser compares (FaceAlignService).
//
// Found 2026-10-08 with real ML Kit landmarks on the phone: the eyes and mouth
// corners were mapped onto the template mirrored (ML Kit's `leftEye` is on the
// LEFT of the picture, the code assumed the right), the similarity fit
// collapsed, and every "face" sent to the server was the whole photo shrunk
// into 112 x 112. The recogniser cannot tell a face from no face, so every
// pair scored as a match. Nothing tested the crop; these do.

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ziren/features/registration/data/face_align_service.dart';

// The InsightFace template (face_align_service.dart's _template).
const template = [
  [38.2946, 51.6963],
  [73.5318, 51.5014],
  [56.0252, 71.7366],
  [41.5493, 92.3655],
  [70.7299, 92.2041],
];

const colours = [
  [255, 0, 0],
  [0, 255, 0],
  [0, 0, 255],
  [255, 255, 0],
  [255, 0, 255],
];

/// A grey photo with a coloured dot at each "landmark": the template scaled
/// up 4x and moved, as a face 450 px wide in a phone photo would be.
({img.Image photo, List<List<double>> points}) photo() {
  final im = img.Image(width: 700, height: 700);
  img.fill(im, color: img.ColorRgb8(128, 128, 128));
  final points = <List<double>>[];
  for (var i = 0; i < 5; i++) {
    final x = template[i][0] * 4 + 120, y = template[i][1] * 4 + 90;
    points.add([x, y]);
    img.fillCircle(
      im,
      x: x.round(),
      y: y.round(),
      radius: 9,
      color: img.ColorRgb8(colours[i][0], colours[i][1], colours[i][2]),
    );
  }
  return (photo: im, points: points);
}

List<int> pixel(List<int> rgb, double x, double y) {
  final o = (y.round() * 112 + x.round()) * 3;
  return [rgb[o], rgb[o + 1], rgb[o + 2]];
}

void main() {
  test('the template order comes from where the points are, not their names', () {
    // Named the way this phone names them: "left" eye on the left.
    final asLogged = templateOrder(
      eyes: [
        [111, 326],
        [223, 328],
      ],
      nose: [169, 401],
      mouth: [
        [106, 444],
        [224, 446],
      ],
    );
    // Named the other way round: the same order comes out.
    final swapped = templateOrder(
      eyes: [
        [223, 328],
        [111, 326],
      ],
      nose: [169, 401],
      mouth: [
        [224, 446],
        [106, 444],
      ],
    );
    final expected = [
      [111.0, 326.0],
      [223.0, 328.0],
      [169.0, 401.0],
      [106.0, 444.0],
      [224.0, 446.0],
    ];
    expect(asLogged, expected);
    expect(swapped, expected);
    expect(
      templateOrder(eyes: [null, [1, 1]], nose: [2, 2], mouth: [[3, 3], [4, 4]]),
      isNull,
    );
  });

  test('aligned, each landmark lands on its template point', () {
    final p = photo();
    final rgb = alignForTest(p.photo, p.points);
    for (var i = 0; i < 5; i++) {
      final got = pixel(rgb, template[i][0], template[i][1]);
      for (var c = 0; c < 3; c++) {
        expect((got[c] - colours[i][c]).abs(), lessThan(40),
            reason: 'point $i landed on $got, not ${colours[i]}');
      }
    }
  });

  test('the face fills the crop: the dots are as far apart as the template\'s', () {
    // The defect's signature: the crop shrank the whole photo, so the face
    // was a few pixels across. Mirrored input reproduces it.
    final p = photo();
    final mirrored = [p.points[1], p.points[0], p.points[2], p.points[4], p.points[3]];
    final bad = alignForTest(p.photo, mirrored);
    final red = pixel(bad, template[0][0], template[0][1]);
    expect(red, isNot([255, 0, 0])); // not on its point
    final good = alignForTest(p.photo, templateOrder(
      eyes: [p.points[1], p.points[0]],
      nose: p.points[2],
      mouth: [p.points[4], p.points[3]],
    )!);
    expect(pixel(good, template[0][0], template[0][1])[0], greaterThan(200));
  });
}
