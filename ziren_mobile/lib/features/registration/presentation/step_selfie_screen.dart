import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../data/face_liveness_service.dart';
import '../data/face_match_client.dart';
import '../data/selfie_orientation.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The selfie step, with an on-device liveness challenge.
///
/// Read the caveat in [FaceLivenessService] and migration 020 before treating
/// a pass here as proof of anything. Short version: it runs on the handset, so
/// the server cannot verify it happened, and a modified client can claim
/// anything. It is here to stop an honest person submitting a photo of a photo
/// or an unusable blurred frame — the real check is an administrator comparing
/// this picture to the ID.
///
/// The challenge is chosen at random each time. A fixed one ("blink") would be
/// trivially defeated by a prepared video, and randomising costs nothing.
class StepSelfieScreen extends StatefulWidget {
  const StepSelfieScreen({super.key});

  @override
  State<StepSelfieScreen> createState() => _StepSelfieScreenState();
}

class _StepSelfieScreenState extends State<StepSelfieScreen>
    with WidgetsBindingObserver {
  final _liveness = FaceLivenessService();

  CameraController? _controller;
  CameraDescription? _camera;
  late LivenessChallenge _challenge;

  bool _initialising = true;
  String? _fatalError;
  bool _streaming = false;
  bool _capturing = false;

  FaceFraming _framing = FaceFraming.none;
  bool _passed = false;

  /// Shown after a while without a usable frame, and immediately when the
  /// handset gives us frames ML Kit cannot read.
  ///
  /// The liveness check is a UX guard, not a security control -- that is stated
  /// in the service and in migration 020. It therefore must never be the only
  /// way past this screen, and in the first build of this flow it was: with no
  /// manual shutter, a phone whose frames could not be analysed left the person
  /// stuck staring at "Put your face inside the circle" with nothing to press.
  /// The only way on was the skip link, which is how the first real test of
  /// this screen ended.
  bool _offerManual = false;
  Timer? _troubleTimer;

  final _faces = FaceMatchClient();

  /// The ID-vs-selfie comparison, once it has run.
  ///
  /// Null while it has not been attempted; [_matching] covers the seconds in
  /// between. Both are needed: "checking..." and "we did not check" are
  /// different things to show someone waiting to press Continue.
  FaceMatchResult? _match;
  bool _matching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _challenge =
        LivenessChallenge.values[Random().nextInt(
          LivenessChallenge.values.length,
        )];
    // After the first frame, not during initState.
    //
    // _start() calls setState(), and setState() during initState is
    // "setState() called during build" — the element is mid-mount and cannot
    // be marked dirty. It is also the only safe point at which this State may
    // touch inherited widgets; see the note in _start().
    //
    // This is the pattern the rest of the app already uses to kick off work
    // from a State (the responder screens all load their data this way), and
    // this screen was the one place that did not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _troubleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _controller?.dispose();
    _liveness.dispose();
    _faces.dispose();
    super.dispose();
  }

  /// Release the camera when the app goes to the background, and take it back
  /// on return. Android will revoke it anyway, and a controller that has lost
  /// its camera throws on the next frame rather than recovering.
  ///
  /// THE GUARD IS PER-BRANCH, AND THAT IS THE WHOLE FIX.
  ///
  /// This used to open with a single early return shared by both branches:
  ///
  ///     if (controller == null || !controller.value.isInitialized) return;
  ///
  /// which is the right test for `inactive` — there is nothing to dispose —
  /// and exactly backwards for `resumed`, which needs to run PRECISELY when
  /// there is no live controller. And since the `inactive` branch sets
  /// `_controller = null` on its way out, that shared guard then rejected
  /// every subsequent `resumed`. The camera was released once and never taken
  /// back.
  ///
  /// The screen has no error state for that, because nothing failed: build()
  /// falls through to `_initialising || _controller == null` and renders the
  /// placeholder spinner, under coaching text telling the person to put their
  /// face in a circle that is never going to appear. A notification banner, a
  /// permission dialog, returning from the ID step's system camera, or a hot
  /// restart — any of them, once, and the step was dead until the screen was
  /// popped and pushed again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;

    if (state == AppLifecycleState.inactive) {
      if (controller == null || !controller.value.isInitialized) return;
      debugPrint('[selfie] releasing camera (inactive)');
      _stopStream();
      controller.dispose();
      _controller = null;
      // Back to the placeholder deliberately. The alternative is a frozen last
      // frame that looks live while the camera is gone.
      if (mounted) setState(() => _initialising = true);
    } else if (state == AppLifecycleState.resumed) {
      // Nothing to do if a live preview survived; re-initialising over a
      // working controller is how you end up with two of them.
      if (controller != null && controller.value.isInitialized) return;
      debugPrint('[selfie] reacquiring camera (resumed)');
      _start();
    }
  }

  /// Guards against two _start() calls overlapping.
  ///
  /// Every await below is long enough for another lifecycle event to arrive
  /// mid-flight — the permission dialog alone drives inactive then resumed —
  /// and two concurrent runs build two CameraControllers for one camera. The
  /// second then blocks on hardware the first is holding, which presents as
  /// the same infinite spinner this screen has already produced once.
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) {
      debugPrint('[selfie] start already in flight, ignoring');
      return;
    }
    _starting = true;

    // NO AppLocalizations.of(context) here, and that is not a style choice.
    //
    // It used to be the first statement of this method, which threw outright:
    //
    //   dependOnInheritedWidgetOfExactType<_LocalizationsScope>() was called
    //   before _StepSelfieScreenState.initState() completed
    //
    // _start() is reached from initState, and an async function runs
    // synchronously up to its first await — so this line executed while the
    // element was still mounting, every single time. The method died on its
    // first statement: no camera call was ever made, no log was written, and
    // no error state was set, because the throw happened before the try block.
    //
    // What the person saw was the placeholder spinner, forever, under coaching
    // text telling them to put their face in a circle that could not appear.
    // The exception went to the console, which nobody watching a phone reads.
    //
    // The string is resolved in the catch instead, after an await and behind a
    // mounted check, where the element is fully mounted and `of(context)` is
    // legal.
    setState(() {
      _initialising = true;
      _fatalError = null;
    });

    // Armed FIRST, and that ordering is the bug this replaces.
    //
    // It used to be armed after `await _startStream()` — that is, after every
    // await that could hang. The timer's whole job is to rescue someone whose
    // camera never comes up, and it was scheduled only on the path where the
    // camera had already come up successfully. A stall anywhere above it left
    // an infinite spinner with nothing to press and nothing logged: the exact
    // report this fixes.
    _armTroubleTimer();

    try {
      // Every await here gets a deadline. None of them had one, and none of
      // them is guaranteed to complete: availableCameras() and initialize()
      // both sit on a platform channel, and on Android initialize() also waits
      // behind the CAMERA permission dialog — which never resolves at all if
      // the user has previously chosen "Don't ask again". A hung Future is
      // indistinguishable from a slow one on screen, so it is turned into a
      // real error instead.
      //
      // The stage names are logged so the next failure report says WHICH of
      // the three stalled. Guessing between them cost a round trip once
      // already.
      // Ask for CAMERA ourselves rather than letting the plugin do it.
      //
      // The camera plugin requests permission internally on Android, and when
      // that request cannot be shown — the user picked "Don't ask again", or
      // the dialog is already queued behind another one — its initialize()
      // Future simply never completes. No throw, no log, no dialog: just a
      // spinner. Asking here makes the answer explicit and observable, and a
      // refusal becomes the error message that already exists for it, which
      // tells the person exactly which setting to change.
      debugPrint('[selfie] requesting camera permission');
      final camPerm = await Permission.camera.request();
      debugPrint('[selfie] camera permission: $camPerm');
      if (!camPerm.isGranted) {
        throw CameraException('permission_denied', camPerm.toString());
      }

      debugPrint('[selfie] enumerating cameras');
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('availableCameras'),
      );
      if (cameras.isEmpty) throw CameraException('no_cameras', 'none reported');

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = front;

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        // Single-plane formats, so the frame can go to ML Kit as one copy.
        // The default yuv420 would need three planes stitched per frame.
        imageFormatGroup:
            Platform.isAndroid
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
      );

      debugPrint('[selfie] initialising ${front.name}');
      // The longest deadline of the three: this is the one that shows the
      // permission dialog on a first run, and a person reading it needs time.
      await controller.initialize().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('initialize'),
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _liveness.resetChallengeState();

      debugPrint('[selfie] starting frame stream');
      await _startStream().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('startImageStream'),
      );

      debugPrint('[selfie] preview live');
      if (mounted) setState(() => _initialising = false);
    } catch (e) {
      debugPrint('[selfie] start failed: $e');
      if (mounted) {
        setState(() {
          _initialising = false;
          _fatalError = AppLocalizations.of(context).selfieCameraError;
        });
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _startStream() async {
    final controller = _controller;
    final camera = _camera;
    if (controller == null || camera == null || _streaming) return;
    _streaming = true;
    await controller.startImageStream((image) async {
      if (!mounted || _passed || _capturing) return;
      final frame = await _liveness.analyse(
        image: image,
        camera: camera,
        deviceOrientation:
            MediaQuery.of(context).orientation == Orientation.portrait
                ? DeviceOrientation.portraitUp
                : DeviceOrientation.landscapeLeft,
        challenge: _challenge,
      );
      if (frame == null || !mounted) return;

      if (frame.framing != _framing) setState(() => _framing = frame.framing);

      // A phone that cannot give ML Kit a readable frame will never detect a
      // face, so stop pretending a challenge is coming and hand over the
      // shutter straight away.
      if (_liveness.isUnsupported && !_offerManual) {
        setState(() => _offerManual = true);
      }

      if (frame.challengeMet && !_passed) {
        _passed = true;
        await _captureNow(viaChallenge: true);
      }
    });
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  /// Twelve seconds is long enough that someone genuinely mid-challenge is
  /// not nagged, and short enough that someone stuck is not abandoned.
  void _armTroubleTimer() {
    _troubleTimer?.cancel();
    _troubleTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && !_passed) setState(() => _offerManual = true);
    });
  }

  Future<void> _captureNow({required bool viaChallenge}) async {
    final t = AppLocalizations.of(context);
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);

    // Streaming and stills contend for the same pipeline on Android; taking a
    // picture mid-stream fails intermittently rather than cleanly.
    await _stopStream();

    try {
      final shot = await controller.takePicture();

      // Un-mirror, straighten and downscale BEFORE anything reads the file.
      //
      // A front camera previews mirrored because that is what a mirror does,
      // and many Android HALs save the still the same way. That photograph is
      // what an admin holds up against an ID card, so a flipped copy makes the
      // one comparison this whole flow exists for harder than it needs to be.
      // Done here rather than at display time so the stored file, the crop fed
      // to the face matcher and what the person sees on the review screen are
      // all the same image.
      //
      // It also caps the long edge at 1600px. takePicture() returns the
      // sensor's full still resolution — 12 MP and up — whatever the preview
      // preset says, and that is the single biggest cost in this whole step.
      // Runs on a background isolate; see SelfieOrientation.
      await SelfieOrientation.normalise(shot.path);

      if (!mounted) return;
      final d = context.read<RegistrationDraft>();
      d.selfiePath = shot.path;
      // 'none' is a real value in migration 020's liveness_method CHECK, and
      // recording it honestly matters: the reviewing admin should be able to
      // tell a photo that passed a challenge from one that simply was not
      // checked. Writing the challenge name for a manual capture would put a
      // false signal in the audit trail.
      d.livenessMethod = viaChallenge ? _challenge.dbValue : 'none';
      d.livenessAssertedAt = viaChallenge ? DateTime.now() : null;
      d.commit();
      setState(() {});

      // Not awaited before the frame is shown. The person should see their
      // photo immediately; the comparison takes a second or two and fills in
      // underneath it.
      unawaited(_runFaceMatch(d, shot.path));
    } catch (_) {
      if (mounted) {
        setState(() {
          _passed = false;
          _fatalError = t.selfieCaptureError;
        });
        await _startStream();
        _armTroubleTimer();
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Compare the selfie against the portrait cropped from the ID.
  ///
  /// ADVISORY, ALWAYS. Nothing this returns blocks the Continue button. A
  /// mismatch is a prompt to check you photographed your own card, and a
  /// signal that moves this submission to the top of the admin's queue — see
  /// migration 023, which says the same thing at more length and in the place
  /// somebody changing the schema will read it.
  Future<void> _runFaceMatch(RegistrationDraft d, String selfiePath) async {
    if (!mounted) return;
    setState(() {
      _matching = true;
      _match = null;
    });

    FaceMatchResult result;

    final idCrop = d.idFaceCropB64;
    if (idCrop == null) {
      // No face was found on the ID, or the ID step was skipped entirely.
      // Reported as its own verdict rather than as a failed comparison,
      // because the fix is different: retake the CARD, not the selfie.
      result = FaceMatchResult(
        verdict: d.idImagePath == null ? 'unavailable' : 'no_face_on_id',
        message:
            d.idImagePath == null
                ? 'No ID photo to compare against. An admin will review your account.'
                : 'We could not find a face on your ID photo, so there is nothing '
                    'to compare your selfie against. Go back and retake the ID.',
      );
    } else {
      final selfieFace = await _faces.alignFace(selfiePath);
      if (selfieFace.b64 == null) {
        result = const FaceMatchResult(
          verdict: 'no_face_in_selfie',
          message:
              'We could not find your face in that photo. Please retake it.',
        );
      } else {
        // Only here — with a face confirmed in BOTH images — does the
        // recogniser get called. It has no concept of "not a face" and will
        // score two photographs of walls as a match, so this gate is the
        // feature's correctness, not a shortcut. See face_match_service.py.
        result = await _faces.compare(
          idFaceB64: idCrop,
          selfieFaceB64: selfieFace.b64!,
        );
      }
    }

    if (!mounted) return;
    d.faceMatchVerdict = result.verdict;
    d.faceMatchScore = result.score;
    d.faceMatchModel = result.model;
    d.faceMatchCheckedAt = DateTime.now();
    d.commit();

    setState(() {
      _match = result;
      _matching = false;
    });
  }

  Future<void> _retake(RegistrationDraft d) async {
    d.selfiePath = null;
    d.livenessMethod = null;
    d.livenessAssertedAt = null;
    d.faceMatchVerdict = null;
    d.faceMatchScore = null;
    d.faceMatchModel = null;
    d.faceMatchCheckedAt = null;
    _match = null;
    _matching = false;
    d.commit();
    _passed = false;
    _offerManual = false;
    _framing = FaceFraming.none;
    _liveness.resetChallengeState();
    _armTroubleTimer();
    _challenge =
        LivenessChallenge.values[Random().nextInt(
          LivenessChallenge.values.length,
        )];
    setState(() {});
    await _startStream();
  }

  String _coachingFor(AppLocalizations t) => switch (_framing) {
    FaceFraming.none => t.selfieFramingNone,
    FaceFraming.multiple => t.selfieFramingMultiple,
    FaceFraming.tooFar => t.selfieFramingTooFar,
    FaceFraming.tooClose => t.selfieFramingTooClose,
    FaceFraming.offCentre => t.selfieFramingOffCentre,
    FaceFraming.good => _challenge.instruction,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final captured = d.selfiePath;

    // Taking the photo gets its own full-height layout, not the scrolling form
    // frame. In the form frame the preview, the coaching text and the shutter
    // were stacked in one column taller than a phone, so the person either
    // saw their face and had no button, or scrolled down to the button and
    // lost the face - which is exactly what testers reported. Here the preview
    // takes whatever height is left and the shutter is pinned under it, so both
    // are on screen at once at every phone height.
    if (captured == null) return _buildCapture(context, t, d);

    return RegistrationScaffold(
      step: RegStep.selfie,
      title: t.selfieReviewTitle,
      subtitle: t.selfieReviewSubtitle,
      continueLabel: 'Continue',
      onContinue: () => context.go(d.next(RegStep.selfie)!.path),
      footer: TextButton(
        onPressed: () => _retake(d),
        child: Text(t.actionRetake),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CapturedPreview(path: captured),
          const SizedBox(height: ZirenTokens.space16),
          _MatchNotice(matching: _matching, result: _match),
        ],
      ),
    );
  }

  Widget _buildCapture(
    BuildContext context,
    AppLocalizations t,
    RegistrationDraft d,
  ) {
    final steps = d.steps.length;
    final index = d.indexOf(RegStep.selfie);
    final ready = _controller != null && !_initialising && _fatalError == null;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final page = Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: back, where we are, and the way out ─────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space4,
                ZirenTokens.space4,
                ZirenTokens.space8,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: Icon(
                      LucideIcons.chevron_left,
                      color: ZirenTokens.textPrimary,
                    ),
                    onPressed:
                        () => RegistrationScaffold.goBackFrom(
                          context,
                          RegStep.selfie,
                        ),
                  ),
                  Expanded(
                    child: Text(
                      'Step ${index + 1} of $steps',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ),
                  // Balances the back button: there is no skipping this step.
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space24,
                ZirenTokens.space4,
                ZirenTokens.space24,
                0,
              ),
              child: Column(
                children: [
                  Text(
                    t.selfieTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    t.selfieSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── The preview takes what height is left ────────────────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (_fatalError != null) {
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(ZirenTokens.space24),
                        child: _CameraError(
                          message: _fatalError!,
                          onRetry: _start,
                        ),
                      ),
                    );
                  }
                  // An oval, 4:5, as large as fits: never taller than the space
                  // left, never wider than the screen minus a margin.
                  final height = box.maxHeight.clamp(160.0, 380.0).toDouble();
                  final width = (height * 0.8).clamp(
                    128.0,
                    box.maxWidth - ZirenTokens.space48,
                  );
                  if (!ready) {
                    return Center(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }
                  return Center(
                    child: _LivePreview(
                      controller: _controller!,
                      ready: _framing == FaceFraming.good,
                      capturing: _capturing,
                      width: width,
                      height: height,
                    ),
                  );
                },
              ),
            ),

            // ── What to do, and the shutter - always on screen ───────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space24,
                ZirenTokens.space8,
                ZirenTokens.space24,
                0,
              ),
              child: Column(
                children: [
                  Text(
                    _fatalError != null ? '' : _coachingFor(t),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          _framing == FaceFraming.good
                              ? ZirenTokens.brandOrange
                              : ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    _offerManual ? t.selfieOrManual : t.selfieAutoCapture,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                ZirenTokens.space12,
                0,
                ZirenTokens.space16,
              ),
              child: _Shutter(
                label: _capturing ? t.selfieCapturing : t.selfieCapture,
                // Enabled as soon as the camera is live. The automatic
                // challenge is a convenience; the person is never made to wait
                // for it, and a phone that cannot run it still has this.
                enabled: ready && !_capturing,
                busy: _capturing,
                onPressed: () => _captureNow(viaChallenge: false),
              ),
            ),
          ],
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // This screen has no AppBar to set the status bar, so it kept the LIGHT
      // icons the hero screen before it asked for - white clock and battery on
      // a near-white page, nearly invisible.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      // The phone's Back button: one step back, like the arrow (finding #19).
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) RegistrationScaffold.goBackFrom(context, RegStep.selfie);
        },
        child: page,
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.controller,
    required this.ready,
    required this.capturing,
    this.width = 260,
    this.height = 320,
  });

  final CameraController controller;
  final bool ready;
  final bool capturing;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? width,
                  height: controller.value.previewSize?.width ?? height,
                  child: CameraPreview(controller),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(
                    color:
                        ready
                            ? ZirenTokens.brandOrange
                            : ZirenTokens.surfaceBorder,
                    width: ready ? 4 : 2,
                  ),
                ),
              ),
            ),
            if (capturing)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapturedPreview extends StatelessWidget {
  const _CapturedPreview({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(125),
        child: Image.file(
          File(path),
          width: 200,
          height: 250,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space20),
      decoration: BoxDecoration(
        color: ZirenTokens.severityHighBg,
        border: Border.all(color: ZirenTokens.severityHighBorder),
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
      ),
      child: Column(
        children: [
          const Icon(
            LucideIcons.video_off,
            size: 32,
            color: ZirenTokens.severityHigh,
          ),
          const SizedBox(height: ZirenTokens.space12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: ZirenTokens.space16),
          ZirenButton(label: t.actionTryAgain, onPressed: onRetry),
        ],
      ),
    );
  }
}

/// The shutter: a round button, always on screen under the preview.
///
/// It used to be a "Having trouble?" box with an outlined button in it that
/// only appeared after twelve seconds - or straight away on a phone whose camera
/// frames ML Kit cannot read - at the very bottom of a scrolling column. A
/// tester who wanted to take the photo could not find it, and one who scrolled
/// to it lost sight of their own face. It is now the camera's own control:
/// visible from the first frame, the same place every time.
///
/// The liveness challenge (blink, turn) can still take the photo automatically
/// when it is met; this is for everyone who would rather press.
class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ring = enabled ? ZirenTokens.brandOrange : ZirenTokens.surfaceBorder;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: enabled ? onPressed : null,
            child: AnimatedContainer(
              duration: ZirenTokens.motionQuick,
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 4),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled ? ZirenTokens.brandOrange : ZirenTokens.surfaceRaised,
                ),
                alignment: Alignment.center,
                child:
                    busy
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                        : Icon(
                          LucideIcons.camera,
                          size: 28,
                          color: enabled ? Colors.white : ZirenTokens.textMuted,
                        ),
              ),
            ),
          ),
          const SizedBox(height: ZirenTokens.space6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: enabled ? ZirenTokens.textPrimary : ZirenTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the automatic ID/selfie comparison found.
///
/// EVERY STATE HERE IS INFORMATION, NOT A GATE
///
/// The Continue button above is enabled the moment a selfie exists and stays
/// enabled whatever this says. That is deliberate and it is the rule the whole
/// verification design rests on: migration 012 states that verification never
/// gates reporting, so somebody standing in a flooded street with a
/// fifteen-year-old ID photograph must be able to finish registering and call
/// for help. A model that scored their face badly does not get a say in that.
///
/// So the wording never rejects. "Does not look like" and "an admin will
/// check" are both true, and the second half is the part that stops the first
/// reading as a verdict.
class _MatchNotice extends StatelessWidget {
  const _MatchNotice({required this.matching, required this.result});

  final bool matching;
  final FaceMatchResult? result;

  @override
  Widget build(BuildContext context) {
    if (matching) {
      return Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: ZirenTokens.space12),
          Flexible(child: Text(
            'Checking your photo against your ID…',
            style: TextStyle(fontSize: 12.5, color: ZirenTokens.textSecondary),
          )),
        ],
      );
    }

    final r = result;
    if (r == null) return const SizedBox.shrink();

    final (IconData icon, Color tint, Color bg) = switch (r.verdict) {
      'match' => (
        LucideIcons.shield_check,
        ZirenTokens.systemSuccess,
        ZirenTokens.systemSuccessBg,
      ),
      'no_match' => (
        LucideIcons.user_search,
        ZirenTokens.systemWarning,
        ZirenTokens.systemWarningBg,
      ),
      'no_face_on_id' || 'no_face_in_selfie' => (
        LucideIcons.camera,
        ZirenTokens.systemWarning,
        ZirenTokens.systemWarningBg,
      ),
      // 'uncertain' and 'unavailable' both mean "a human will look", which is
      // the ordinary path rather than a problem, so neither wears a warning
      // colour.
      _ => (
        LucideIcons.info,
        ZirenTokens.systemInfo,
        ZirenTokens.systemInfoBg,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              r.message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
