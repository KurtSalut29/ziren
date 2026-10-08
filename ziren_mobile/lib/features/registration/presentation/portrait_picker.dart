import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../data/portrait_check_service.dart';
import '../domain/portrait_check.dart';
import 'id_check_notice.dart';

/// Takes or picks the 2x2 ID photo for the Ziren ID card, and checks it.
///
/// Used in both places identity evidence is collected - the registration step
/// and Profile > Verify - because a check that lives in only one of them is a
/// check people route around (the ID photo learned that the hard way, see
/// project memory "ID photo lives in two screens").
///
/// [onChanged] reports the photo and, only when it was ACCEPTED, the checks to
/// store with it. A refused photo reports `checks: null`, which the callers
/// treat as "no 2x2 photo yet". When [selfiePath] changes the photo is checked
/// again: an acceptance means "same face as THIS selfie".
class PortraitPicker extends StatefulWidget {
  const PortraitPicker({
    super.key,
    required this.selfiePath,
    required this.onChanged,
    this.initialPath,
    this.initialChecks,
    this.service,
  });

  final String? selfiePath;
  final String? initialPath;
  final Map<String, dynamic>? initialChecks;
  final void Function(String? path, Map<String, dynamic>? checks) onChanged;

  /// Injected by tests; built on first use otherwise.
  final PortraitCheckService? service;

  @override
  State<PortraitPicker> createState() => _PortraitPickerState();
}

class _PortraitPickerState extends State<PortraitPicker> {
  final _picker = ImagePicker();
  PortraitCheckService? _ownService;

  String? _path;
  bool _checking = false;
  PortraitResult? _result;

  /// Set when the photo was accepted before this screen opened (a resumed
  /// draft): the verdict is shown without checking the photo again.
  String? _acceptedVerdict;

  PortraitCheckService get _service =>
      widget.service ?? (_ownService ??= PortraitCheckService());

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    if (_path != null) {
      if (widget.initialChecks != null) {
        _acceptedVerdict = widget.initialChecks!['verdict'] as String?;
      } else {
        // A photo kept without checks has not been compared with the current
        // selfie (it was retaken). Check it now rather than make them re-pick.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _check();
        });
      }
    }
  }

  @override
  void didUpdateWidget(PortraitPicker old) {
    super.didUpdateWidget(old);
    if (old.selfiePath != widget.selfiePath && _path != null) {
      _acceptedVerdict = null;
      // After the frame: the check tells the parent at once, and the parent
      // is mid-build right now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    }
  }

  @override
  void dispose() {
    _ownService?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        // A 2x2 is small; 1200 px keeps the face sharp on the printed card
        // and the upload light on a rural connection.
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
    } catch (_) {
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _path = picked!.path;
      _acceptedVerdict = null;
    });
    await _check();
  }

  Future<void> _check() async {
    final path = _path;
    if (path == null) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    widget.onChanged(path, null);
    PortraitResult result;
    try {
      result = await _service.check(
        portraitPath: path,
        selfiePath: widget.selfiePath,
      );
    } catch (_) {
      result = const PortraitResult(
        facts: PortraitFacts.unreadable,
        problem: PortraitProblem.unreadable,
      );
    }
    // A newer pick or a removal while this ran: its answer is stale.
    if (!mounted || _path != path) return;
    setState(() {
      _checking = false;
      _result = result;
    });
    widget.onChanged(path, result.accepted ? result.toChecks() : null);
  }

  void _remove() {
    setState(() {
      _path = null;
      _result = null;
      _acceptedVerdict = null;
      _checking = false;
    });
    widget.onChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Guide(t: t),
        const SizedBox(height: ZirenTokens.space16),
        if (_path == null) ...[
          FilledButton.icon(
            key: const ValueKey('portrait-take'),
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(LucideIcons.camera, size: 18),
            label: Text(t.portraitTakePhoto),
          ),
          const SizedBox(height: ZirenTokens.space8),
          OutlinedButton.icon(
            key: const ValueKey('portrait-choose'),
            onPressed: () => _pick(ImageSource.gallery),
            icon: const Icon(LucideIcons.image, size: 18),
            label: Text(t.portraitChoosePhoto),
          ),
        ] else ...[
          Center(
            child: _Preview(
              path: _path!,
              busy: _checking,
              onRemove: _checking ? null : _remove,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          _verdict(t),
        ],
      ],
    );
  }

  Widget _verdict(AppLocalizations t) {
    if (_checking) {
      return Row(
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Flexible(
            child: Text(
              t.portraitChecking,
              style: TextStyle(
                fontSize: 12.5,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    final verdict = _result?.match?.verdict ?? _acceptedVerdict;
    final problem = _result?.problem;
    if (problem != null) {
      return IdCheckNotice(
        key: const ValueKey('portrait-refused'),
        icon: problem == PortraitProblem.notSamePerson
            ? LucideIcons.user_x
            : LucideIcons.scan_face,
        tint: ZirenTokens.systemError,
        bg: ZirenTokens.systemErrorBg,
        title: t.portraitProblemTitle,
        text: portraitProblemText(t, problem),
      );
    }
    if (_result == null && _acceptedVerdict == null) {
      return const SizedBox.shrink();
    }
    final sure = verdict == 'match';
    return IdCheckNotice(
      key: const ValueKey('portrait-accepted'),
      icon: sure ? LucideIcons.circle_check : LucideIcons.info,
      tint: sure ? ZirenTokens.systemSuccess : ZirenTokens.systemInfo,
      bg: sure ? ZirenTokens.systemSuccessBg : ZirenTokens.systemInfoBg,
      text: sure ? t.portraitAccepted : t.portraitAcceptedReview,
    );
  }
}

/// The sentence for each refusal.
String portraitProblemText(AppLocalizations t, PortraitProblem p) =>
    switch (p) {
      PortraitProblem.unreadable => t.portraitUnreadable,
      PortraitProblem.noFace => t.portraitNoFace,
      PortraitProblem.manyFaces => t.portraitManyFaces,
      PortraitProblem.tooFar => t.portraitTooFar,
      PortraitProblem.tooClose => t.portraitTooClose,
      PortraitProblem.turned => t.portraitTurned,
      PortraitProblem.tilted => t.portraitTilted,
      PortraitProblem.eyesClosed => t.portraitEyesClosed,
      PortraitProblem.noFeatures => t.portraitNoFeatures,
      PortraitProblem.busyBackground => t.portraitBusyBackground,
      PortraitProblem.notSamePerson => t.portraitNotSamePerson,
      PortraitProblem.noFaceInSelfie => t.portraitNoSelfie,
    };

/// What a 2x2 ID photo is, beside a sketch of one.
class _Guide extends StatelessWidget {
  const _Guide({required this.t});

  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (LucideIcons.square, t.portraitGuidePlain),
      (LucideIcons.scan_face, t.portraitGuideFace),
      (LucideIcons.user, t.portraitGuideOnlyYou),
      (LucideIcons.glasses, t.portraitGuideNoCover),
    ];
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A sketch of a 2x2: square, plain, head and shoulders centred.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ZirenTokens.radius8),
              border: Border.all(color: ZirenTokens.surfaceBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZirenTokens.radius8),
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: Color(0xFF8A94A6),
                ),
              ),
            ),
          ),
          const SizedBox(width: ZirenTokens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.portraitGuideTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                for (final (icon, text) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ZirenTokens.space4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            icon,
                            size: 14,
                            color: ZirenTokens.textMuted,
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space8),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo as picked, whole, in a square frame.
class _Preview extends StatelessWidget {
  const _Preview({required this.path, required this.busy, this.onRemove});

  final String path;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              // The WHOLE photo, not a square crop of it: the check reads
              // all of it, and a crop hid the second face that refused a
              // screenshot (user report 2026-10-08).
              child: ColoredBox(
                color: ZirenTokens.surfaceRaised,
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: ZirenTokens.space8,
            right: ZirenTokens.space8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              child: IconButton(
                key: const ValueKey('portrait-remove'),
                tooltip: 'Remove photo',
                iconSize: 18,
                icon: const Icon(LucideIcons.x, color: Colors.white),
                onPressed: onRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
