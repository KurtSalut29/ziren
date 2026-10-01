import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/splash/presentation/splash_screen.dart';

/// The splash logo animation (branding/ZIREN_Logo_Splash_Transparent.webm,
/// as animated WebP) and the native launch screen it follows.
void main() {
  test('both splash clips play once, with transparency, and have a still of the finished logo', () {
    for (final theme in ['light', 'dark']) {
      final clip = File('assets/images/splash/splash_$theme.webp').readAsBytesSync();
      expect(String.fromCharCodes(clip.sublist(8, 16)), 'WEBPVP8X', reason: theme);
      expect(clip[20] & 0x10, 0x10, reason: '$theme clip has an alpha channel');
      expect(clip[20] & 0x02, 0x02, reason: '$theme clip is animated');
      // ANIM chunk loop count 1 = play once, then hold the last frame.
      final anim = String.fromCharCodes(clip).indexOf('ANIM');
      expect(clip[anim + 12] | clip[anim + 13] << 8, 1, reason: '$theme clip plays once');

      final still = File('assets/images/splash/splash_${theme}_still.webp').readAsBytesSync();
      expect(String.fromCharCodes(still.sublist(8, 12)), 'WEBP', reason: '$theme still');
    }
  });

  test("the splash waits for the clip's last frame: its frame count and length match the files", () {
    for (final theme in ['light', 'dark']) {
      final b = File('assets/images/splash/splash_$theme.webp').readAsBytesSync();
      var frames = 0;
      var ms = 0;
      for (var i = 12; i + 8 <= b.length;) {
        final id = String.fromCharCodes(b.sublist(i, i + 4));
        final size = b[i + 4] | b[i + 5] << 8 | b[i + 6] << 16 | b[i + 7] << 24;
        if (id == 'ANMF') {
          frames++;
          ms += b[i + 8 + 12] | b[i + 8 + 13] << 8 | b[i + 8 + 14] << 16;
        }
        i += 8 + size + (size & 1);
      }
      expect(frames, SplashScreen.clipFrames, reason: '$theme frame count');
      expect(ms, closeTo(SplashScreen.clipLength.inMilliseconds, 10), reason: '$theme length');
    }
  });

  test('the native launch screen is a plain background, so the logo appears once', () {
    for (final f in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      expect(File(f).readAsStringSync(), contains('windowSplashScreenAnimatedIcon">@drawable/splash_blank<'), reason: f);
    }
    for (final f in [
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ]) {
      expect(File(f).readAsStringSync(), isNot(contains('<bitmap')), reason: f);
    }
    // Starts from the colour Android paints, so there is no seam.
    expect(
      File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
      contains('<color name="zirenBackground">#FAFAFA</color>'),
    );
    expect(kNativeLaunchColor.toARGB32(), 0xFFFAFAFA);
  });
}
