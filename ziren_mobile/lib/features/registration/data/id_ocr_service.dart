import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/id_document_check.dart';
import 'id_text_parser.dart';

// Re-exported so the screens keep importing one file. The rules live in
// id_text_parser.dart because they are pure Dart and therefore testable
// without a handset; this file is the ML Kit plumbing and nothing else.
export 'id_text_parser.dart';

/// What was read off a photographed ID.
class IdOcrResult {
  IdOcrResult({
    required this.rawText,
    required this.reading,
    this.numberFormatOk,
    this.nameMatched,
    this.lineCount = 0,
    this.lines = const [],
  });

  final String rawText;

  /// The text lines ML Kit found, in reading order.
  final List<String> lines;

  final Map<String?, IdDocCheck> _docChecks = {};

  /// Is this an ID, and is it a [declaredType]?
  ///
  /// A method rather than a field because the ID type can be chosen (or
  /// changed) AFTER the photo is read - the Verify screen takes the photo first
  /// - and the answer must follow the type, not the moment of reading. Cached
  /// per type; the classifier runs a fuzzy search and this is asked on every
  /// rebuild.
  IdDocCheck docCheckFor(String? declaredType) => _docChecks.putIfAbsent(
    declaredType,
    () => IdDocumentClassifier.classify(lines, declaredType: declaredType),
  );

  /// Everything the parser recognised: the number, the name parts, the date
  /// of birth, the sex, the address and which document this is.
  final IdReading reading;

  /// Best candidate for the ID number, or null if nothing looked like one.
  String? get detectedNumber => reading.idNumber;

  /// Expiry printed on the card, when one was found and parsed.
  DateTime? get expiryDate => reading.expiryDate;

  /// Whether [detectedNumber] matches the printed format for the ID type.
  ///
  /// Three states, and the third matters. True means it matched; false means
  /// a number was found and did not match the type — which usually means the
  /// wrong type was chosen, not that the card is fake. Null means we have no
  /// published format for that type (a barangay ID is whatever the barangay
  /// prints) and there is nothing to check against.
  final bool? numberFormatOk;

  /// Whether the surname the person typed appears on the card. Null when we
  /// had no surname to compare against — which is now the normal case on the
  /// first pass, because the card is photographed BEFORE the name is typed.
  final bool? nameMatched;

  final int lineCount;

  /// Did we read anything usable at all? A dark or blurred photo comes back
  /// with almost no lines, and telling someone to retake it right away is far
  /// better than an admin rejecting them days later.
  bool get looksReadable => lineCount >= 3 && rawText.trim().length >= 20;

  /// Whether the card's own expiry has already passed.
  ///
  /// Null, not false, when no expiry was found — most Philippine IDs a
  /// resident will present do not print one at all, and "no expiry found"
  /// must never be shown to an admin as "not expired".
  bool? get expired => expiryDate?.isBefore(DateTime.now());

  /// The shape stored in users.id_checks (migration 023).
  ///
  /// Deliberately a plain map of nullable booleans rather than a typed object:
  /// the set of checks will grow as real cards are seen in the field, and the
  /// column is JSONB precisely so that adding one is not a migration.
  Map<String, dynamic> toChecks({bool? faceFound, IdDocCheck? docCheck}) => {
    'readable': looksReadable,
    'line_count': lineCount,
    if (faceFound != null) 'face_found': faceFound,
    // Whether the photo carried the chosen ID type's own wording, so the
    // reviewing admin sees what the phone concluded, not only what it passed.
    if (docCheck != null) 'doc_verdict': docCheck.verdict.name,
    if (docCheck?.foundType != null) 'doc_found_type': docCheck!.foundType,
    if (numberFormatOk != null) 'number_format_ok': numberFormatOk,
    if (nameMatched != null) 'name_matched': nameMatched,
    if (reading.idType != null) 'detected_type': reading.idType,
    // How the name was arrived at, so an admin can see at a glance whether
    // the person confirmed a labelled read or a shape-based guess.
    if (reading.nameConfidence != null)
      'name_source': reading.nameConfidence!.name,
    if (expiryDate != null)
      'expiry_date': expiryDate!.toIso8601String().split('T').first,
    if (expired != null) 'expired': expired,
  };
}

/// Reads text off a photograph of an ID card, entirely on the device.
///
/// This exists to make the form fill itself, which is the single biggest
/// difference in feel between this flow and a stack of empty text fields. It
/// is a convenience and a PRE-SCREEN, not a verdict:
///
///   - Everything it reads is offered filled in and stays editable. OCR
///     misreads 0/O and 1/I on worn cards constantly.
///   - A format mismatch is surfaced as a warning, never as a block. The
///     commonest cause by far is the card type being read wrong.
///   - A name mismatch is a warning to the reviewing admin. Married names,
///     middle initials and suffixes all legitimately differ between a card
///     and what someone types.
///
/// Nothing here decides whether an ID is genuine. A human does that.
class IdOcrService {
  IdOcrService()
    : _recogniser = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recogniser;

  Future<IdOcrResult> read({
    required String imagePath,
    String? expectedSurname,
    String? idType,
  }) async {
    final recognised = await _recogniser.processImage(
      InputImage.fromFilePath(imagePath),
    );

    final lines = <String>[
      for (final block in recognised.blocks)
        for (final line in block.lines) line.text,
    ];

    final reading = IdTextParser.parse(lines, declaredType: idType);

    // What the phone actually read, for tuning the ID-type wording against a
    // real photograph (adb logcat -s flutter). Off unless a build asks for it
    // with --dart-define=ID_OCR_DEBUG=true: it is the card's text - a name, an
    // address, a number - and the APK handed to testers must never log it.
    if (const bool.fromEnvironment('ID_OCR_DEBUG')) {
      debugPrint('[IdOcr] ${lines.length} lines, declared=$idType');
      for (final l in lines) {
        debugPrint('[IdOcr]   | $l');
      }
    }

    return IdOcrResult(
      rawText: recognised.text,
      lines: lines,
      reading: reading,
      // Checked against what the CARD says it is, falling back to what the
      // person declared. Reading the type off the card is the better source:
      // it is why a number can be format-checked at all now that the type is
      // no longer asked for before the photograph is taken.
      numberFormatOk: IdTextParser.checkFormat(
        reading.idNumber,
        reading.idType ?? idType,
      ),
      nameMatched: IdTextParser.surnameAppears(
        recognised.text,
        expectedSurname,
      ),
      lineCount: lines.length,
    );
  }

  Future<void> dispose() => _recogniser.close();
}
