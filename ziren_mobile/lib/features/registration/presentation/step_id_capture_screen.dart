import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../auth/data/id_upload_service.dart';
import '../data/face_align_service.dart';
import '../data/face_match_client.dart';
import '../data/id_ocr_service.dart';
import '../domain/id_catalogue.dart';
import '../domain/id_photo_check.dart';
import '../domain/registration_draft.dart';
import 'id_check_notice.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../shared/widgets/ziren_photo_sheet.dart';

/// Step 6 (residents) — photograph the ID, then confirm what was read off it.
///
/// Why the system camera rather than a custom one
/// ----------------------------------------------
/// A bespoke camera with a card-shaped cut-out looks better in a demo. It also
/// means owning focus, torch, orientation and permission handling on every
/// handset in the province, to photograph a stationary object. The system
/// camera already does all of that, and people already know it. The custom
/// camera is spent where it actually buys something — the selfie step, where a
/// liveness challenge needs a live frame stream and a still photo cannot work.
///
/// The photo has to BE an ID
/// -------------------------
/// This step used to take any photograph at all - a selfie, a wall, a receipt -
/// and let the resident carry on, on the reasoning that verification must never
/// gate reporting. It still does not: "Skip verification" is right under the
/// button and registers the account unverified. But once someone chooses to
/// verify, an upload that cannot possibly be an ID proves nothing and only fills
/// the review queue with junk, so Continue now needs a photo that:
///
///   - has readable text on it,
///   - has a face on it (the portrait the selfie will be compared with), and
///   - has an ID number on it, which the number field must then agree with.
///
/// Anything else is told, in words, what is missing and how to fix it.
///
/// A name mismatch, an expired card and a number that does not fit the chosen
/// type stay ADVISORY: married names and middle initials differ from cards
/// legitimately and constantly, and an admin decides those.
///
/// What the card is NOT used for
/// -----------------------------
/// It does not fill in the name, the date of birth, the sex or the address.
/// That was tried and taken back out: reading a whole identity off a
/// photograph is only as good as the OCR, and a wrong value sitting in a box
/// that looks exactly like one the person typed is worse than an empty box —
/// nobody re-reads a field that already looks answered. The number is offered
/// because it is checkable against a published format and it is the field
/// people most often mistype.
///
/// The verification this flow actually performs is the ID against the SELFIE:
/// a face is cropped from the card here, the selfie step crops another, and
/// the two are compared. See face_match_service.py.
class StepIdCaptureScreen extends StatefulWidget {
  const StepIdCaptureScreen({super.key});

  @override
  State<StepIdCaptureScreen> createState() => _StepIdCaptureScreenState();
}

class _StepIdCaptureScreenState extends State<StepIdCaptureScreen> {
  final _uploads = IdUploadService();
  final _ocr = IdOcrService();
  final _faces = FaceMatchClient();
  late final TextEditingController _number;

  bool _reading = false;
  IdOcrResult? _result;

  /// Whether a face was found on the photographed card.
  ///
  /// Null while unknown. This is the strongest of the ID checks by a distance:
  /// a photograph of the BACK of a card, of a receipt, or of a blurred mess
  /// has no face on it, and that is knowable on the phone in a second rather
  /// than by an admin three days later.
  bool? _faceOnId;

  /// How much of the photo the face fills. A card's portrait is a small corner;
  /// a selfie is a face filling the frame - see [kMaxIdFaceRatio].
  double? _faceRatio;

  @override
  void initState() {
    super.initState();
    final d = context.read<RegistrationDraft>();
    _number = TextEditingController(text: d.validIdNumber)..addListener(() {
      // Whether Continue is allowed depends on what is typed here.
      if (mounted) setState(() {});
    });

    // This step is re-entered - "go back and choose the ID type that matches
    // your card" is exactly what a refusal tells the person to do - and the
    // photo survives in the draft while what was READ off it does not. Without
    // this the returning person saw "we couldn't read any text" about a photo
    // that had been read a moment before. Read it again.
    final path = d.idImagePath;
    if (path != null && File(path).existsSync()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyse(d, path);
      });
    }
  }

  /// Why the photo cannot be accepted yet, or [IdPhotoCheck.ok].
  IdPhotoCheck _check(RegistrationDraft d) => judgeIdPhoto(
    hasPhoto: d.idImagePath != null,
    reading: _reading,
    readable: _result?.looksReadable,
    faceOnId: _faceOnId,
    faceRatio: _faceRatio,
    detectedNumber: _result?.detectedNumber,
    rawText: _result?.rawText ?? '',
    typedNumber: _number.text,
    // Is it an ID, and the ID that was chosen? Follows the chosen type, which
    // can change after the photo was read.
    docCheck: _result?.docCheckFor(d.validIdType),
  );

  @override
  void dispose() {
    _number.dispose();
    _ocr.dispose();
    _faces.dispose();
    super.dispose();
  }

  /// Record where the ID number in the field actually came from.
  ///
  /// The distinction is stored rather than inferred later: a number OCR read
  /// off the card and the person left alone has been checked against the card
  /// by a machine; one they retyped has not. An admin chasing a duplicate-ID
  /// flag needs to know which they are looking at before deciding whether a
  /// mismatch is fraud or a thumb on a small keyboard. See migration 023.
  ///
  /// The comparison against what OCR read is the point. Promoting to
  /// 'ocr_edited' merely because this ran would mark every submission as
  /// edited — including the ones where the person read the filled-in number,
  /// agreed with it, and pressed Continue, which is the case the flag exists to
  /// distinguish.
  void _noteNumberEdit(RegistrationDraft d) {
    final typed = _number.text.trim();
    final read = _result?.detectedNumber?.trim();

    if (read == null || read.isEmpty) {
      d.idNumberSource = typed.isEmpty ? null : 'typed';
      return;
    }
    d.idNumberSource = typed == read ? 'ocr' : 'ocr_edited';
  }

  /// Forget an ID number that was only ever OCR's reading of a photo that is
  /// being replaced or removed.
  ///
  /// Left in the box it belongs to the wrong card: it blocks the new photo (the
  /// fill only writes into an EMPTY field) and sits beside a refusal as if it
  /// were the person's own. A number they typed themselves is theirs and stays.
  void _dropAutofilledNumber(RegistrationDraft d) {
    final read = _result?.detectedNumber?.trim();
    final fromOcr =
        d.idNumberSource == 'ocr' ||
        (read != null && read.isNotEmpty && _number.text.trim() == read);
    if (fromOcr) {
      _number.clear();
      d.validIdNumber = '';
      d.idNumberSource = null;
    }
  }

  Future<void> _capture(RegistrationDraft d, ImageSource source) async {
    final file = await _uploads.pickIdPhoto(source: source);
    if (file == null || !mounted) return;

    _dropAutofilledNumber(d);
    d.idImagePath = file.path;
    d.commit();
    await _analyse(d, file.path);
  }

  /// Read the photo at [path]: its text, and the face on it.
  Future<void> _analyse(RegistrationDraft d, String path) async {
    setState(() {
      _reading = true;
      _result = null;
      _faceOnId = null;
      _faceRatio = null;
    });

    try {
      // Both run against the same photo. The OCR reads the printed text; the
      // face pass finds the portrait and aligns it for the comparison the
      // selfie step will make. Run together rather than in sequence: they are
      // independent, and each takes about a second on a mid-range handset.
      final results = await Future.wait([
        _ocr.read(
          imagePath: path,
          expectedSurname: d.lastName,
          // The declared type is what turns a generic digit-run guess into a
          // checked one — a driver's licence prints three number-shaped things
          // and only one of them is the licence number.
          idType: d.validIdType,
        ),
        _faces.alignFace(path),
      ]);

      final result = results[0] as IdOcrResult;
      final face =
          results[1]
              as ({String? b64, FaceCropOutcome outcome, double? faceRatio});

      if (!mounted) return;

      final doc = result.docCheckFor(d.validIdType);
      d.ocrRawText = result.rawText;
      d.ocrNameMatched = result.nameMatched;
      d.idFaceCropB64 = face.b64;
      d.idChecks = result.toChecks(faceFound: face.b64 != null, docCheck: doc);

      // Only fill an empty field. Overwriting something the person typed with
      // an OCR guess is how you turn a correct number into a wrong one. And
      // only from a photo that is plausibly THE chosen ID: a digit run read off
      // a screenshot or a selfie is not "your number", and offering it as one
      // is worse than an empty box.
      if (result.looksReadable &&
          face.b64 != null &&
          doc.isAcceptable &&
          (face.faceRatio ?? 0) <= kMaxIdFaceRatio &&
          _number.text.trim().isEmpty &&
          result.detectedNumber != null) {
        _number.text = result.detectedNumber!;
        d.validIdNumber = result.detectedNumber!;
        d.idNumberSource = 'ocr';
      }
      d.commit();
      setState(() {
        _result = result;
        _faceOnId = face.b64 != null;
        _faceRatio = face.faceRatio;
      });
    } catch (_) {
      // OCR failing is not a registration problem — they can type the number.
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

  Future<void> _chooseSource(RegistrationDraft d) async {
    final t = AppLocalizations.of(context);
    final choice = await showZirenPhotoSourceSheet(
      context,
      title: t.quickAddPhoto,
      takePhoto: t.actionTakePhoto,
      chooseFromGallery: t.actionChooseFromGallery,
    );
    if (choice == null) return;
    await _capture(
      d,
      choice == ZirenPhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final option = IdCatalogue.byValue(d.validIdType);
    final hasPhoto = d.idImagePath != null;
    final check = _check(d);

    return RegistrationScaffold(
      step: RegStep.idCapture,
      title: t.regIdCaptureTitle,
      subtitle: option == null ? null : 'Showing your ${option.label}.',
      showSkipVerification: true,
      // Only a photo that passed the check goes on. See the class comment.
      onContinue:
          check == IdPhotoCheck.ok
              ? () {
                d.validIdNumber = _number.text.trim();
                _noteNumberEdit(d);
                d.commit();
                context.go(d.next(RegStep.idCapture)!.path);
              }
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Preview(
            path: d.idImagePath,
            reading: _reading,
            onTap: () => _chooseSource(d),
            onRemove: () {
              _dropAutofilledNumber(d);
              d.idImagePath = null;
              d.ocrRawText = null;
              d.ocrNameMatched = null;
              // The crop and the checks describe the removed photo. Leaving
              // them behind would carry a face-match verdict about a card the
              // person has just replaced.
              d.idFaceCropB64 = null;
              d.idChecks = null;
              d.faceMatchVerdict = null;
              d.faceMatchScore = null;
              d.commit();
              setState(() {
                _result = null;
                _faceOnId = null;
                _faceRatio = null;
              });
            },
          ),

          if (hasPhoto && !_reading) ...[
            const SizedBox(height: ZirenTokens.space16),
            if (check != IdPhotoCheck.ok)
              // Blocking: says what is wrong and what to do about it.
              IdCheckNotice.blocking(
                context,
                check,
                chosenLabel: option?.label,
                foundLabel:
                    IdCatalogue.byValue(
                      _result?.docCheckFor(d.validIdType).foundType,
                    )?.label,
              )
            else ...[
              _Banner(
                icon: LucideIcons.circle_check,
                colour: ZirenTokens.systemSuccess,
                background: ZirenTokens.systemSuccessBg,
                text: t.idCheckPassed,
              ),
              // Advisory only from here on: a name that does not match is
              // often fine (married names, initials), and an admin decides.
              if (_result?.nameMatched == false && d.lastName.trim().isNotEmpty) ...[
                const SizedBox(height: ZirenTokens.space12),
                _Banner(
                  icon: LucideIcons.circle_question_mark,
                  colour: ZirenTokens.systemWarning,
                  background: ZirenTokens.systemWarningBg,
                  text:
                      'We did not find "${d.lastName}" on this card. That is '
                      'often fine — married names and initials differ. Check '
                      'the photo is the right ID, then continue.',
                ),
              ],
            ],
            // A card that has expired. Reported, never blocking — an expired
            // barangay ID is still evidence of who someone is, and it is an
            // admin's call whether it is enough.
            if (_result?.expired == true) ...[
              const SizedBox(height: ZirenTokens.space12),
              IdCheckNotice(
                icon: LucideIcons.calendar_x,
                tint: ZirenTokens.systemWarning,
                bg: ZirenTokens.systemWarningBg,
                text:
                    'This ID looks expired. You can still continue — an admin '
                    'will decide whether it is enough.',
              ),
            ],
            // A number that does not fit the type they chose. Almost always
            // the wrong type picked from the list, so the message says that
            // instead of implying the card is wrong.
            if (_result?.numberFormatOk == false) ...[
              const SizedBox(height: ZirenTokens.space12),
              IdCheckNotice(
                icon: LucideIcons.list_checks,
                tint: ZirenTokens.systemInfo,
                bg: ZirenTokens.systemInfoBg,
                text:
                    'The number we read does not look like a '
                    '${option?.label ?? 'card of this type'} number. Check the '
                    'ID type you chose, or correct the number below.',
              ),
            ],
          ],

          const SizedBox(height: ZirenTokens.space24),
          RegField(
            label: t.fieldIdNumber,
            child: ZirenTextField(
              label: '',
              hint: t.hintIdNumber,
              controller: _number,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              prefixIcon: const Icon(LucideIcons.pin),
              // Only while the box still holds what was read off the card.
              helperText:
                  (_result?.detectedNumber != null &&
                          _number.text.trim() ==
                              _result!.detectedNumber!.trim())
                      ? t.regOcrFilled
                      : null,
            ),
          ),

          const SizedBox(height: ZirenTokens.space20),
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            decoration: BoxDecoration(
              color: ZirenTokens.systemInfoBg,
              borderRadius: BorderRadius.circular(ZirenTokens.radius16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.lock,
                  size: 18,
                  color: ZirenTokens.systemInfo,
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Text(
                    t.regIdPrivacyNote,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: ZirenTokens.textSecondary,
                    ),
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

class _Preview extends StatelessWidget {
  const _Preview({
    required this.path,
    required this.reading,
    required this.onTap,
    required this.onRemove,
  });

  final String? path;
  final bool reading;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (path == null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceRaised,
            borderRadius: BorderRadius.circular(ZirenTokens.radius20),
            border: Border.all(color: ZirenTokens.surfaceBorder, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.camera,
                size: 34,
                color: ZirenTokens.brandOrange,
              ),
              const SizedBox(height: ZirenTokens.space12),
              Text(
                t.regTakeIdPhoto,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textPrimary,
                ),
              ),
              const SizedBox(height: ZirenTokens.space4),
              Text(
                t.regIdPhotoTips,
                style: TextStyle(fontSize: 12.5, color: ZirenTokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
          child: Image.file(
            File(path!),
            height: 210,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        if (reading)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZirenTokens.radius20),
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    SizedBox(height: ZirenTokens.space12),
                  ],
                ),
              ),
            ),
          ),
        if (reading)
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 44),
                child: Text(
                  t.idCheckChecking,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
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
              onPressed: reading ? null : onRemove,
            ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.colour,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color colour;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              text,
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
