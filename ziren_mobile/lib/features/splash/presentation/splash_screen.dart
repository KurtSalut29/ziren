import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/auth_provider.dart';
import '../../../features/onboarding/data/onboarding_repository.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_logo.dart';

/// The routing gate that runs while the app decides where to send you.
///
/// WHY THERE IS NO ANIMATION HERE ANY MORE
///
/// There are two launch screens on Android and only one of them is ours to
/// remove. The first is the system's, drawn before Flutter exists — it cannot
/// be skipped, and on Android 12+ the platform draws it from
/// values-v31/styles.xml. The second was this screen, which used to spend 1.9
/// seconds fading in a mark, drawing "ZIREN" left to right and revealing a
/// tagline.
///
/// Two different-looking splashes in a row read as two splashes, because they
/// were. So this one now paints exactly what the native one paints — the mark,
/// centred, on the same #FAFAFA — and hands over as soon as its checks finish.
/// The seam between them is invisible: one logo that does not move, then the
/// app.
///
/// It still has to exist. The onboarding gate and the session restore below
/// decide between four destinations, and neither answer is available
/// synchronously; something has to be on screen while they resolve. What it
/// must not do is take longer than they do.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Guards against navigating twice — a tap-to-skip landing in the same frame
  /// the checks complete would otherwise fire `_navigate` from both.
  bool _navigated = false;

  final _onboarding = OnboardingRepository();

  /// A floor on how briefly this can flash past, not a delay added to it.
  ///
  /// The checks below usually settle in a few tens of milliseconds, and
  /// swapping the screen out that fast reads as a flicker rather than a
  /// handover. Half a second is also what the reset gesture needs to be
  /// pressable at all. Because this screen is pixel-identical to the native
  /// one, the wait is not a second splash — it is the same image holding a
  /// moment longer.
  static const _minimumHold = Duration(milliseconds: 500);

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

  Future<void> _start() async {
    // The hold and the checks run TOGETHER rather than one after the other, so
    // the slower of the two sets the pace instead of their sum.
    await Future.wait([
      Future<void>.delayed(_minimumHold),
      Future<void>(() async {
        if (mounted) await _navigate();
      }),
    ]);
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

    if (!onboarded) {
      // Also the path an existing user takes after an app update that bumps
      // a document version: they pass through the same screens, and the
      // consent screen notices they are already signed in and sends them on
      // to where they were going.
      context.go('/onboarding/language');
      return;
    }

    if (auth.isAuthenticated) {
      // Role is not recoverable synchronously, and navigateAfterAuth() routes
      // on it. Without this await a restored responder session is routed as a
      // resident.
      await auth.restoreSession();
      if (!mounted) return;
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
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping skips the remaining hold. Deliberately no visible "Skip" —
        // it would draw attention to a wait of half a second.
        onTap: _navigate,
        onLongPress: _resetOnboarding,
        child: Semantics(
          label: 'Ziren. Starting.',
          child: ExcludeSemantics(
            // Sized to sit close to what the platform draws on Android 12+,
            // where the splash icon occupies roughly 192dp. Matching it is the
            // whole point: the two screens must look like one.
            child: Center(child: ZirenLogo.mark(size: 200, onDark: ZirenTokens.isDark)),
          ),
        ),
      ),
    );
  }
}
