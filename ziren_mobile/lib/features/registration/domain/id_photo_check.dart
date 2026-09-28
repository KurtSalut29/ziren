import '../data/id_text_parser.dart';
import 'id_document_check.dart';

/// Where a photographed ID stands against the rules for accepting it.
///
/// One rule set for both places an ID is photographed: the registration step
/// (`StepIdCaptureScreen`) and "Finish verifying your account" later on
/// (`VerifyAccountScreen`). They had drifted apart - the second took ANY photo
/// and let it be submitted - which is exactly the "any picture uploads" report.
enum IdPhotoCheck {
  /// No photo yet.
  none,

  /// The photo is being read.
  checking,

  /// No usable text on it - dark, blurred, or not a card at all.
  unreadable,

  /// Not an ID: a selfie, a wall, a receipt, a screenshot. Nothing on it is
  /// the wording any ID prints. Refused outright.
  notAnId,

  /// An ID, but not the type that was chosen (a driver's licence uploaded as a
  /// passport). Refused; the person picks the right type or the right card.
  wrongType,

  /// Looks like an ID, but nothing on it proves it is the chosen type.
  typeUnconfirmed,

  /// Text, but no face: the back of a card, or a document without a portrait.
  noFace,

  /// A face and text, but no ID number that could be read.
  noNumber,

  /// The number typed is not the one the card shows.
  numberMismatch,

  /// Accepted.
  ok,
}

/// A face taking up more of the photo than this is a selfie, not a card.
///
/// The portrait on a card is a small corner of the picture - about 3% of a
/// photographed licence, 7% of a tightly-cropped passport page - while a selfie
/// is a face filling the frame (40% and up). Anywhere between is a card held
/// very close, which cannot also be read; 30% is well clear of every real card.
const double kMaxIdFaceRatio = 0.30;

/// Decide whether a photographed ID can be accepted.
///
/// In order, and the order is the point:
///
///   1. a face that fills the frame is a selfie - refused as "not an ID" even
///      before anything is read;
///   2. it has to have readable text;
///   3. that text has to be an ID, and the CHOSEN type of ID ([docCheck]);
///   4. it has to have a face (the portrait the selfie is compared with);
///   5. it has to have an ID number, and the number in the field has to be the
///      one on the card.
///
/// A name that does not match and an expired card stay advisory and are not
/// judged here.
///
/// Takes plain values rather than the OCR result so the rules run in a test
/// without ML Kit.
///
/// [readable], [faceOnId] and [faceRatio] are null when the check itself could
/// not run (OCR threw, the face pass never finished). That is not a pass:
/// nothing was verified.
IdPhotoCheck judgeIdPhoto({
  required bool hasPhoto,
  required bool reading,
  required bool? readable,
  required bool? faceOnId,
  required String? detectedNumber,
  required String rawText,
  required String typedNumber,
  required IdDocCheck? docCheck,
  double? faceRatio,
}) {
  if (!hasPhoto) return IdPhotoCheck.none;
  if (reading) return IdPhotoCheck.checking;

  if (faceRatio != null && faceRatio > kMaxIdFaceRatio) {
    return IdPhotoCheck.notAnId;
  }
  if (readable != true) {
    // A face and no text at all is what a selfie reads as. Only a face with
    // nothing else is called "not an ID"; a dark photo with neither stays a
    // retake.
    if (faceOnId == true && (rawText.trim().isEmpty)) {
      return IdPhotoCheck.notAnId;
    }
    return IdPhotoCheck.unreadable;
  }

  switch (docCheck?.verdict) {
    case IdDocVerdict.notAnId:
      return IdPhotoCheck.notAnId;
    case IdDocVerdict.wrongType:
      return IdPhotoCheck.wrongType;
    case IdDocVerdict.typeUnconfirmed:
      return IdPhotoCheck.typeUnconfirmed;
    case IdDocVerdict.matches:
      break;
    case null:
      // The document check never ran. Not a pass.
      return IdPhotoCheck.unreadable;
  }

  if (faceOnId != true) return IdPhotoCheck.noFace;
  if (detectedNumber == null) return IdPhotoCheck.noNumber;
  final typed = typedNumber.trim();
  if (typed.isEmpty ||
      !IdTextParser.numberIsOnCard(
        typed: typed,
        detected: detectedNumber,
        rawText: rawText,
      )) {
    return IdPhotoCheck.numberMismatch;
  }
  return IdPhotoCheck.ok;
}
