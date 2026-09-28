import 'package:flutter_test/flutter_test.dart';
import 'package:Ziren/features/registration/domain/id_document_check.dart';
import 'package:Ziren/features/registration/domain/id_photo_check.dart';

/// The rule that decides whether a photographed ID can be accepted. It is
/// applied on two screens (registration, and "Finish verifying your account"),
/// and the second used to take ANY photo - a wall, a receipt, a face.
///
/// Every failing case below is a photograph somebody really could take.
const _cardText =
    'REPUBLIC OF THE PHILIPPINES\nNATIONAL ID\nSALUT, KURT MICHAEL\n'
    'PSN 1234-5678-9012-3456\nBORN 2001-01-01';

const _matches = IdDocCheck(IdDocVerdict.matches);

IdPhotoCheck _judge({
  bool hasPhoto = true,
  bool reading = false,
  bool? readable = true,
  bool? faceOnId = true,
  double? faceRatio = 0.05,
  String? detectedNumber = '1234-5678-9012-3456',
  String rawText = _cardText,
  String typedNumber = '1234-5678-9012-3456',
  IdDocCheck? docCheck = _matches,
}) => judgeIdPhoto(
  hasPhoto: hasPhoto,
  reading: reading,
  readable: readable,
  faceOnId: faceOnId,
  faceRatio: faceRatio,
  detectedNumber: detectedNumber,
  rawText: rawText,
  typedNumber: typedNumber,
  docCheck: docCheck,
);

void main() {
  group('a photographed ID is accepted only if it looks like one', () {
    test('a real card: text, a face, and the number that is in the field', () {
      expect(_judge(), IdPhotoCheck.ok);
    });

    test('nothing photographed yet', () {
      expect(_judge(hasPhoto: false), IdPhotoCheck.none);
    });

    test('still being read', () {
      expect(_judge(reading: true), IdPhotoCheck.checking);
    });

    test('a dark or blurred photo with no usable text', () {
      expect(
        _judge(readable: false, detectedNumber: null),
        IdPhotoCheck.unreadable,
      );
    });

    test('reading it failed outright - nothing was verified, so no pass', () {
      expect(
        _judge(
          readable: null,
          faceOnId: null,
          faceRatio: null,
          detectedNumber: null,
          rawText: '',
        ),
        IdPhotoCheck.unreadable,
      );
    });

    test('the document check never ran - not a pass', () {
      expect(_judge(docCheck: null), IdPhotoCheck.unreadable);
    });

    test('a receipt or the back of a card: text but no face', () {
      expect(_judge(faceOnId: false), IdPhotoCheck.noFace);
    });

    test('the face pass never finished', () {
      expect(_judge(faceOnId: null), IdPhotoCheck.noFace);
    });

    test('a face and text but no ID number anywhere on it', () {
      expect(_judge(detectedNumber: null), IdPhotoCheck.noNumber);
    });

    test('an empty number field is not the number on the card', () {
      expect(_judge(typedNumber: ''), IdPhotoCheck.numberMismatch);
      expect(_judge(typedNumber: '   '), IdPhotoCheck.numberMismatch);
    });

    test('a number that is not on the card', () {
      expect(
        _judge(typedNumber: '9999-8888-7777-6666'),
        IdPhotoCheck.numberMismatch,
      );
    });

    test('one misread character is forgiven (worn cards), two are not', () {
      expect(_judge(typedNumber: '1234-5678-9012-3457'), IdPhotoCheck.ok);
      expect(
        _judge(typedNumber: '1234-5678-9012-3499'),
        IdPhotoCheck.numberMismatch,
      );
    });

    test('a number the card shows elsewhere is accepted', () {
      // OCR picked a different candidate as "the number", the person typed the
      // one that is really the ID number and it is in the text read off the card
      expect(
        _judge(
          detectedNumber: '2001-01-01',
          rawText: '$_cardText\nDL 05-1234-567890',
          typedNumber: '05-1234-567890',
        ),
        IdPhotoCheck.ok,
      );
    });
  });

  group('a selfie or a random photo is refused as "not an ID"', () {
    test('a face filling the frame is a selfie, whatever text it has', () {
      // The reported bug: face found, text found, a number-shaped token found,
      // and it was accepted. The face is 45% of the photo.
      expect(_judge(faceRatio: 0.45), IdPhotoCheck.notAnId);
    });

    test('even with a number that matches, a selfie stays refused', () {
      expect(
        _judge(faceRatio: 0.6, typedNumber: '1234-5678-9012-3456'),
        IdPhotoCheck.notAnId,
      );
    });

    test('a face of a card\'s size is not a selfie', () {
      // A licence portrait is ~3% of the picture, a tight passport crop ~7%.
      expect(_judge(faceRatio: 0.03), IdPhotoCheck.ok);
      expect(_judge(faceRatio: 0.07), IdPhotoCheck.ok);
      expect(_judge(faceRatio: kMaxIdFaceRatio), IdPhotoCheck.ok);
    });

    test('text with none of an ID\'s wording is not an ID', () {
      expect(
        _judge(docCheck: const IdDocCheck(IdDocVerdict.notAnId)),
        IdPhotoCheck.notAnId,
      );
    });

    test('a face and no text at all is what a selfie reads as', () {
      expect(
        _judge(
          readable: false,
          faceOnId: true,
          faceRatio: null,
          detectedNumber: null,
          rawText: '',
        ),
        IdPhotoCheck.notAnId,
      );
    });
  });

  group('the card has to be the ID type that was chosen', () {
    test('an ID of another type is refused', () {
      expect(
        _judge(
          docCheck: const IdDocCheck(
            IdDocVerdict.wrongType,
            foundType: 'drivers_license',
          ),
        ),
        IdPhotoCheck.wrongType,
      );
    });

    test('an ID-shaped card with nothing proving the type is refused', () {
      expect(
        _judge(docCheck: const IdDocCheck(IdDocVerdict.typeUnconfirmed)),
        IdPhotoCheck.typeUnconfirmed,
      );
    });

    test('the type is judged before the face and the number', () {
      // A licence uploaded as a passport has a face and a number and must
      // still be refused for being the wrong card.
      expect(
        _judge(
          faceOnId: true,
          docCheck: const IdDocCheck(IdDocVerdict.wrongType),
        ),
        IdPhotoCheck.wrongType,
      );
    });
  });
}
