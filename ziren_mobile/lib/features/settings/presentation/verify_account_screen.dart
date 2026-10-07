import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_error_banner.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../auth/data/id_upload_service.dart';
import '../../registration/data/face_align_service.dart';
import '../../registration/data/face_match_client.dart';
import '../../registration/data/id_ocr_service.dart';
import '../../registration/domain/id_catalogue.dart';
import '../../registration/domain/id_name_match.dart';
import '../../registration/domain/id_photo_check.dart';
import '../../registration/presentation/id_check_notice.dart';
import '../data/profile_repository.dart';
import '../domain/profile_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Finish identity verification for an account that skipped it at signup.
///
/// This is the other half of the "I need help right now" escape hatch. That
/// link only defensible if there is a way back — otherwise skipping is
/// permanent and the province ends up with a population of level-0 accounts.
///
/// Deliberately simpler than the registration equivalent
/// -----------------------------------------------------
/// One screen, and the selfie comes from the system camera rather than the
/// liveness flow. Someone doing this has already got an account and is doing
/// a chore; the priority is that it is short enough to finish in one sitting.
/// The selfie therefore records `liveness_method = 'none'`, which is honest —
/// the reviewing admin can see it was not challenged, and the real check was
/// always a human comparing the two photographs anyway.
///
/// The ID photo has to BE an ID
/// ----------------------------
/// This screen used to submit whatever was photographed - a wall, a receipt,
/// the person's own face - because OCR here was only a convenience that filled
/// the number box. It now holds Submit until the photo passes the same rules the
/// registration step applies (readable text, a face, an ID number that matches
/// the field): see [judgeIdPhoto]. Someone who chose to verify and sends
/// something that cannot be an ID proves nothing and only fills the review queue.
class VerifyAccountScreen extends StatefulWidget {
  const VerifyAccountScreen({super.key});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  final _uploads = IdUploadService();
  final _ocr = IdOcrService();
  final _faces = FaceMatchClient();
  final _picker = ImagePicker();
  final _number = TextEditingController();

  /// The account's name, editable here: the ID has to carry it, and the usual
  /// slip - a middle name saved as "S." while the card prints "SENO" - is
  /// fixed on this screen instead of a trip to Settings. Saved with Submit.
  late final _name = TextEditingController(
    text: context.read<ProfileProvider>().profile?.fullName ?? '',
  );

  String? _idType;
  File? _idImage;
  File? _selfie;

  bool _submitting = false;
  bool _reading = false;
  String? _error;
  bool _done = false;

  /// What reading the photographed card found, and whether a face was on it.
  /// Null until the photo has been read; null again if reading failed - which
  /// is not a pass, see [judgeIdPhoto].
  IdOcrResult? _result;
  bool? _faceOnId;

  /// How much of the photo the face fills: a card's portrait is a small corner,
  /// a selfie's face fills the frame. See [kMaxIdFaceRatio].
  double? _faceRatio;

  @override
  void initState() {
    super.initState();
    // Whether Submit is allowed depends on what is typed here.
    _number.addListener(() {
      if (mounted) setState(() {});
    });
    _name.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _ocr.dispose();
    _faces.dispose();
    super.dispose();
  }

  IdPhotoCheck get _check => judgeIdPhoto(
    hasPhoto: _idImage != null,
    reading: _reading,
    readable: _result?.looksReadable,
    faceOnId: _faceOnId,
    faceRatio: _faceRatio,
    detectedNumber: _result?.detectedNumber,
    rawText: _result?.rawText ?? '',
    typedNumber: _number.text,
    // Follows the CHOSEN type: the photo can be taken before the type is
    // picked, or the type changed afterwards, and the verdict must follow it.
    docCheck: _result?.docCheckFor(_idType),
  );

  /// What is not on the card. An initial gets its own sentence ("S." could be
  /// Santos or Seno): "not found" alone leaves the person guessing.
  String _mismatchText(AppLocalizations t) {
    final missing = _missingName ?? const <String>[];
    bool initial(String w) => RegExp(r'^[A-Z]$').hasMatch(w);
    final initials = missing.where(initial).toList();
    final others = missing.where((w) => !initial(w)).toList();
    return [
      if (others.isNotEmpty || initials.isEmpty)
        '${t.regNameMismatchTitle}. ${t.regNameMismatchBody(others.map((w) => '"$w"').join(', '))}',
      for (final w in initials) t.regMiddleInitialBody('$w.'),
    ].join('\n\n');
  }

  /// "Passport", "Driver's License" - the chosen type, for the messages.
  String? get _chosenLabel => IdCatalogue.byValue(_idType)?.label;

  /// Words of the account's name that are not on the card. The ID has to be
  /// the account holder's own (see id_name_match.dart). Null until read.
  List<String>? get _missingName {
    final result = _result;
    if (result == null) return null;
    return IdNameMatch.missingFromFullName(result.rawText, _name.text);
  }

  bool get _canSubmit =>
      _idType != null &&
      _check == IdPhotoCheck.ok &&
      (_missingName?.isEmpty ?? false) &&
      // Required, as at registration: the administrator compares the face on
      // the ID with this one.
      _selfie != null &&
      !_submitting;

  Future<void> _pickId() async {
    final file = await _uploads.pickIdPhoto(source: ImageSource.camera);
    if (file == null || !mounted) return;
    // A number still exactly as OCR read it off the PREVIOUS photo belongs to
    // that photo; left in the box it would block the new one.
    final previousRead = _result?.detectedNumber?.trim();
    if (previousRead != null && _number.text.trim() == previousRead) {
      _number.clear();
    }
    setState(() {
      _idImage = file;
      _reading = true;
      _result = null;
      _faceOnId = null;
      _faceRatio = null;
    });
    try {
      // Text and portrait are read together: they are independent, and each
      // takes about a second on a mid-range handset.
      final results = await Future.wait([
        _ocr.read(
          imagePath: file.path,
          expectedSurname: _name.text.trim().split(' ').last,
          idType: _idType,
        ),
        _faces.alignFace(file.path),
      ]);
      if (!mounted) return;
      final result = results[0] as IdOcrResult;
      final face =
          results[1]
              as ({String? b64, FaceCropOutcome outcome, double? faceRatio});
      // Only fill an empty field: overwriting something the person typed with
      // an OCR guess is how a correct number becomes a wrong one. And only
      // from a photo that is plausibly THE chosen ID - a digit run read off a
      // screenshot or a selfie is not "your number".
      if (result.looksReadable &&
          face.b64 != null &&
          result.docCheckFor(_idType).isAcceptable &&
          (face.faceRatio ?? 0) <= kMaxIdFaceRatio &&
          _number.text.trim().isEmpty &&
          result.detectedNumber != null) {
        _number.text = result.detectedNumber!;
      }
      setState(() {
        _result = result;
        _faceOnId = face.b64 != null;
        _faceRatio = face.faceRatio;
      });
    } catch (_) {
      // Reading failed. The photo is then "unreadable" - not accepted, since
      // nothing about it was verified - and retaking it is the fix.
      if (mounted) {
        setState(() {
          _result = null;
          _faceOnId = null;
          _faceRatio = null;
        });
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _pickSelfie() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;
    setState(() => _selfie = File(picked.path));
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _submitting = false;
        _error = t.verifyNotSignedIn;
      });
      return;
    }

    // The corrected name first: evidence filed under a name the ID does not
    // carry would only be refused by the administrator.
    final profiles = context.read<ProfileProvider>();
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name != profiles.profile?.fullName.trim()) {
      try {
        await ProfileRepository().updateMyProfile({'full_name': name});
      } catch (_) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _error = t.verifyNameSaveError;
          });
        }
        return;
      }
    }

    try {
      final payload = <String, dynamic>{
        'valid_id_type': _idType,
        'residency_proof_type': IdCatalogue.residencyProofFor(_idType),
      };
      if (_number.text.trim().isNotEmpty) {
        payload['valid_id_number'] = _number.text.trim();
      }

      // Uploads first: a path written into the row that points at nothing is
      // worse than no path, because the reviewer sees an attachment and gets
      // a broken image.
      payload['valid_id_image_path'] = await _uploads.uploadId(
        file: _idImage!,
        userId: userId,
      );
      if (_selfie != null) {
        payload['selfie_image_path'] = await _uploads.uploadSelfie(
          file: _selfie!,
          userId: userId,
        );
        payload['liveness_method'] = 'none';
      }

      // Straight to Supabase, not through FastAPI. verification_level is
      // frozen by RLS either way (migration 012), so this cannot be used to
      // self-promote — it only attaches evidence for an admin to judge.
      await client.from('users').update(payload).eq('id', userId);

      if (!mounted) return;
      await context.read<ProfileProvider>().loadProfile(force: true);
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not submit. $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.verifyTitle),
        backgroundColor: ZirenTokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child:
            _done
                ? const _SubmittedState()
                : SingleChildScrollView(
                  padding: const EdgeInsets.all(ZirenTokens.space20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        ZirenErrorBanner(message: _error!),
                        const SizedBox(height: ZirenTokens.space16),
                      ],

                      Text(
                        t.verifyIntro,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: ZirenTokens.space24),

                      _Label(t.verifyWhichId),
                      const SizedBox(height: ZirenTokens.space8),
                      DropdownButtonFormField<String>(
                        value: _idType,
                        isExpanded: true,
                        dropdownColor: ZirenTokens.surfaceOverlay,
                        hint: Text(
                          t.verifyChooseId,
                          style: TextStyle(color: ZirenTokens.textMuted),
                        ),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(LucideIcons.badge, size: 20),
                        ),
                        items: [
                          for (final o in IdCatalogue.all)
                            DropdownMenuItem(
                              value: o.value,
                              child: Text(
                                o.provesResidency
                                    ? '${o.label}  ·  proves residency'
                                    : o.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _idType = v),
                      ),

                      const SizedBox(height: ZirenTokens.space20),
                      _Label(t.verifyNameLabel),
                      const SizedBox(height: ZirenTokens.space8),
                      ZirenTextField(
                        key: const ValueKey('verify-name'),
                        label: '',
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        prefixIcon: const Icon(LucideIcons.user),
                        helperText: t.verifyNameHelp,
                      ),

                      const SizedBox(height: ZirenTokens.space20),
                      _Label(t.verifyIdPhoto),
                      const SizedBox(height: ZirenTokens.space8),
                      _PhotoTile(
                        file: _idImage,
                        busy: _reading,
                        emptyLabel: t.verifyTakeIdPhoto,
                        onTap: _pickId,
                        onRemove:
                            () => setState(() {
                              // A number that is only OCR's reading of the
                              // photo being removed belongs to that photo.
                              final read = _result?.detectedNumber?.trim();
                              if (read != null &&
                                  read.isNotEmpty &&
                                  _number.text.trim() == read) {
                                _number.clear();
                              }
                              _idImage = null;
                              _result = null;
                              _faceOnId = null;
                              _faceRatio = null;
                            }),
                      ),
                      if (_idImage != null && !_reading) ...[
                        const SizedBox(height: ZirenTokens.space12),
                        // Blocking: says what is wrong and how to fix it. The
                        // Submit button below stays off until it clears.
                        if (_check != IdPhotoCheck.ok)
                          IdCheckNotice.blocking(
                            context,
                            _check,
                            canSkip: false,
                            chosenLabel: _chosenLabel,
                            foundLabel:
                                IdCatalogue.byValue(
                                  _result?.docCheckFor(_idType).foundType,
                                )?.label,
                          )
                        else if (_missingName?.isNotEmpty ?? true)
                          IdCheckNotice(
                            key: const ValueKey('name-mismatch'),
                            icon: LucideIcons.user_x,
                            tint: ZirenTokens.systemWarning,
                            bg: ZirenTokens.systemWarningBg,
                            text: _mismatchText(t),
                          )
                        else
                          IdCheckNotice(
                            icon: LucideIcons.circle_check,
                            tint: ZirenTokens.systemSuccess,
                            bg: ZirenTokens.systemSuccessBg,
                            text: t.idCheckPassed,
                          ),
                      ],

                      const SizedBox(height: ZirenTokens.space20),
                      _Label(t.verifyIdNumber),
                      const SizedBox(height: ZirenTokens.space8),
                      ZirenTextField(
                        label: '',
                        hint: 'As printed on the card',
                        controller: _number,
                        textCapitalization: TextCapitalization.characters,
                        prefixIcon: const Icon(LucideIcons.pin),
                        // Only while the box still holds what was read off the
                        // card.
                        helperText:
                            (_result?.detectedNumber != null &&
                                    _number.text.trim() ==
                                        _result!.detectedNumber!.trim())
                                ? t.regOcrFilled
                                : null,
                      ),

                      const SizedBox(height: ZirenTokens.space20),
                      _Label(t.verifySelfie),
                      const SizedBox(height: ZirenTokens.space8),
                      _PhotoTile(
                        file: _selfie,
                        busy: false,
                        emptyLabel: t.verifyTakeSelfie,
                        onTap: _pickSelfie,
                        onRemove: () => setState(() => _selfie = null),
                      ),

                      const SizedBox(height: ZirenTokens.space32),
                      ZirenButton(
                        label: t.verifySubmit,
                        isLoading: _submitting,
                        onPressed: _canSubmit ? _submit : null,
                      ),
                      const SizedBox(height: ZirenTokens.space16),
                      Text(
                        t.verifyPrivacyNote,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

class _SubmittedState extends StatelessWidget {
  const _SubmittedState();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZirenTokens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.circle_check_big,
              size: 64,
              color: ZirenTokens.systemSuccess,
            ),
            const SizedBox(height: ZirenTokens.space20),
            Text(
              t.verifySentTitle,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space12),
            Text(
              t.verifySentBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space32),
            ZirenButton(
              label: t.actionDone,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: ZirenTokens.textPrimary,
    ),
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.file,
    required this.busy,
    required this.emptyLabel,
    required this.onTap,
    required this.onRemove,
  });

  final File? file;
  final bool busy;
  final String emptyLabel;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(LucideIcons.camera, size: 18),
        label: Text(emptyLabel),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          child: Image.file(
            file!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        if (busy)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
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
              tooltip: 'Remove photo',
              iconSize: 18,
              icon: const Icon(LucideIcons.x, color: Colors.white),
              onPressed: busy ? null : onRemove,
            ),
          ),
        ),
      ],
    );
  }
}
