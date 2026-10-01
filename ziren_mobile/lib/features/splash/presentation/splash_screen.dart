import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/auth_provider.dart';
import '../../../features/onboarding/data/onboarding_repository.dart';
import '../../../shared/theme/app_tokens.dart';

/// The routing gate that runs while the app decides where to send you, and
/// the logo animation (branding/ZIREN_Logo_Splash_Transparent.webm) played
/// while it does.
///
/// THE TWO LAUNCH SCREENS
///
/// Android draws its own launch screen before Flutter exists; it cannot be
/// skipped. It used to show the finished mark, which this screen then held
/// still. With an animation here, a finished logo before it would vanish and
/// draw itself again — so the native one is now a plain #FAFAFA screen
/// (values-v31/styles.xml, drawable/launch_background.xml) and the logo
/// appears once, here, drawing itself in.
///
/// The clip is an animated WebP with transparency, made from the video (and a
/// copy with the ink near-white for the dark theme), played once and held on
/// its last frame. In the dark theme the background eases from the native
/// screen's light grey to the dark surface as the first strokes appear,
/// rather than cutting.
///
/// It is still the gate: the onboarding check and the session restore below
/// decide between four destinations, and neither answer is available
/// synchronously. It leaves when both they and the animation are done; a tap
/// skips the rest of the animation.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// The logo animation's length (the video is 3.5 s), at full speed.
  static const clipLength = Duration(milliseconds: 3500);

  /// Frames in the clip (30 fps; identical frames merged). The splash moves
  /// on when the last one is on screen, not after a fixed time: a slow phone
  /// decodes it slower than real time, and a fixed timer cut the finished
  /// logo short there.
  static const clipFrames = 99;

  /// How long the finished logo stays before the app opens.
  static const finishedHold = Duration(milliseconds: 400);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// The colour Android paints its launch screen (res/values/colors.xml
/// zirenBackground), which this screen starts from.
const Color kNativeLaunchColor = Color(0xFFFAFAFA);

class _SplashScreenState extends State<SplashScreen> {
  /// Guards against navigating twice.
  bool _navigated = false;

  final _onboarding = OnboardingRepository();

  /// With "Remove animations" on there is no animation to wait for: the
  /// finished logo holds this long, so the screen does not flicker past (and
  /// the reset gesture stays pressable).
  static const _stillHold = Duration(milliseconds: 500);

  /// Completes once the animation's last frame has been on screen for
  /// [SplashScreen.finishedHold], or at once when skipped.
  final _played = Completer<void>();
  Timer? _clipTimer;

  @override
  void initState() {
    super.initState();
    // After the first frame. _navigate reads an inherited widget, which is
    // illegal until this State is mounted — the selfie step has already paid
    // for learning that once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  Future<void> _start() async {
    if (_still) {
      _clipTimer = Timer(_stillHold, _finishClip);
    } else {
      // Should the clip never draw (a decode failure) or crawl, the gate must
      // not wait on it for ever.
      Timer(SplashScreen.clipLength * 2, _finishClip);
    }
    // The animation and the checks run TOGETHER: the slower of the two sets
    // the pace, not their sum.
    await _navigate();
  }

  /// A frame of the clip is on screen; the last one ends it.
  void _clipFrame(int frame) {
    if (frame < SplashScreen.clipFrames - 1) return;
    if (_clipTimer != null || _played.isCompleted) return;
    _clipTimer = Timer(SplashScreen.finishedHold, _finishClip);
  }

  void _finishClip() {
    if (!_played.isCompleted) _played.complete();
  }

  /// Tapping skips the rest of the animation. Deliberately no visible "Skip".
  void _skip() {
    _clipTimer?.cancel();
    _finishClip();
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    super.dispose();
  }

  Future<void> _navigate() async {
    if (_navigated) return;
    _navigated = true;

    final auth = context.read<AuthProvider>();

    // The onboarding gate. This is a local preferences read, so it settles in
    // well under a frame — but it is awaited rather than assumed, because
    // getting it wrong in the optimistic direction would drop a first-time
    // user straight onto a login form having agreed to nothing.
    final onboarded = await _onboarding.isDeviceOnboarded();
    if (!mounted) return;

    // A signed-in session is restored while the logo still draws. Role is not
    // recoverable synchronously, and navigateAfterAuth() routes on it: without
    // waiting for this a restored responder session is routed as a resident.
    final restoring =
        onboarded && auth.isAuthenticated ? auth.restoreSession() : null;
    await _played.future;
    if (restoring != null) await restoring;
    if (!mounted) return;

    if (!onboarded) {
      // Also the path an existing user takes after an app update that bumps
      // a document version: they pass through the same screens, and the
      // consent screen notices they are already signed in and sends them on
      // to where they were going.
      context.go('/onboarding/language');
      return;
    }

    if (auth.isAuthenticated) {
      auth.navigateAfterAuth();
    } else {
      auth.navigateToLogin();
    }
  }

  /// Clears the device's onboarding flag so the language and consent screens
  /// show again on the next launch.
  ///
  /// Hidden behind a long press because it is a demo and QA affordance, not a
  /// resident feature — there is no reason for someone reporting a fire to
  /// re-read the privacy notice, and the alternative during a defence is
  /// uninstalling the app between runs.
  Future<void> _resetOnboarding() async {
    await _onboarding.resetDevice();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Onboarding reset. Restart the app to see it again.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ZirenTokens.isDark ? 'dark' : 'light';
    final clip =
        _still
            ? 'assets/images/splash/splash_${theme}_still.webp'
            : 'assets/images/splash/splash_$theme.webp';
    return TweenAnimationBuilder<Color?>(
      // From the native launch screen's colour to the theme's surface (the
      // same colour in the light theme, so nothing moves there).
      tween: ColorTween(
        begin: kNativeLaunchColor,
        end: ZirenTokens.surfaceBase,
      ),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder:
          (context, color, child) =>
              Scaffold(backgroundColor: color, body: child),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        onLongPress: _resetOnboarding,
        child: Semantics(
          label: 'Ziren. Starting.',
          child: ExcludeSemantics(
            child: Center(
              child: Image.asset(
                clip,
                width: 260,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (frame != null && !_still) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _clipFrame(frame),
                    );
                  }
                  return child;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
