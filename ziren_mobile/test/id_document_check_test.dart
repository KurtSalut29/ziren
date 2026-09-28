import 'package:flutter_test/flutter_test.dart';
import 'package:Ziren/features/registration/domain/id_document_check.dart';

/// Is the photo an ID, and the ID that was chosen?
///
/// The report this answers: testers uploaded a SELFIE as their Voter's ID and
/// were told "ID photo accepted"; and a driver's licence would have been
/// accepted as a passport. Every "refused" case below is a photograph somebody
/// really could take, and the card reads are ones ML Kit really produced.
void main() {
  /// The lines ML Kit returned from a photograph of an actual LTO licence,
  /// verbatim - stray comma, O-for-zero and all.
  const licence = [
    'REPUBLIC OF THE PHILIPPINES',
    'DEPARTMENT OF TRANSPORTATION',
    'LAND TRANSPORTATION OFFICE',
    "DRIVER'S LICENSE",
    'Last Name. First Name. Middle Name',
    'SALUT, KURT MICHAEL SENO',
    'Nationality',
    'Sex',
    'Date of Birth',
    'Weight (kg)',
    'Height(m)',
    'PHL',
    'M',
    '2005/07/31',
    '51',
    '1.68',
    'Address',
    'SITIO SAN,ROQUE, LARRAZABAL, NAVAL',
    '(CAPITAL), BILIRAN, 6543',
    'License No.',
    'Expiration Date',
    'Agency Code',
    'HO7-24-000792',
    '2028/07/31',
    'H07',
    'Blood Type',
    'Eyes Color',
    'BROWN',
    'DL Codes',
    'Conditions',
    'A',
    'NONE',
    'ATTY. VIGOR D. MENDOZA II',
    'Signature of Licensee',
    'Assistant Secretary',
  ];

  /// A Philippine passport's data page as OCR reads it: bilingual headings and
  /// the machine-readable lines, with "<" filler.
  const passport = [
    'REPUBLIKA NG PILIPINAS | REPUBLIC OF THE PHILIPPINES',
    'PASAPORTE/',
    'PASSPORT',
    'Uri/Type',
    'Kodigo ng bansa/Country code',
    'PHL',
    'Apelyido/Surname',
    'VERA',
    'Pangalan/Given names',
    'MARJON',
    'P<PHLVERA<<MARJON<<<<<<<<<<<<<<<<<<<<<<<<<<<<',
    'P02346050D4PHL0503051M3508068<<<<<<<<<<<<<<06',
  ];

  /// What a selfie in front of a curtain reads as: a shirt logo, a wall label.
  const selfie = ['KOLIN', 'AC 3', 'B'];

  IdDocVerdict verdictOf(List<String> lines, String? type) =>
      IdDocumentClassifier.classify(lines, declaredType: type).verdict;

  group('the right card for the chosen type is accepted', () {
    test('a real driver\'s licence as a driver\'s licence', () {
      final r = IdDocumentClassifier.classify(
        licence,
        declaredType: 'drivers_license',
      );
      expect(r.verdict, IdDocVerdict.matches);
      expect(r.foundType, 'drivers_license');
    });

    test('a passport as a passport', () {
      expect(verdictOf(passport, 'passport'), IdDocVerdict.matches);
    });

    test('a passport whose printed words were badly read, from the MRZ alone', () {
      const worn = ['P<PHLVERA<<MARJON<<<<<<<<<<<<<<<<<<<<<<<<<<<<', 'x'];
      expect(verdictOf(worn, 'passport'), IdDocVerdict.matches);
    });

    test('OCR typos do not turn a real card away', () {
      // LICENCE for LICENSE, a 1 for the I in TRANSPORTATION.
      expect(
        verdictOf([
          'REPUBLIC OF THE PHILIPPINES',
          "DRIVER'S LICENCE",
          'LAND TRANSPORTAT1ON OFFICE',
        ], 'drivers_license'),
        IdDocVerdict.matches,
      );
    });

    test('no type chosen yet: it is enough that it is an ID', () {
      final r = IdDocumentClassifier.classify(licence);
      expect(r.verdict, IdDocVerdict.matches);
      expect(r.foundType, 'drivers_license');
    });

    test('a voter\'s ID is recognised by the COMELEC wording', () {
      const voter = [
        'REPUBLIC OF THE PHILIPPINES',
        'COMMISSION ON ELECTIONS',
        "VOTER'S IDENTIFICATION CARD",
        'Precinct 0012A',
      ];
      expect(verdictOf(voter, 'voters_id'), IdDocVerdict.matches);
    });

    test('a UMID is an SSS ID, so it is not refused as one', () {
      const umid = [
        'REPUBLIC OF THE PHILIPPINES',
        'UNIFIED MULTI-PURPOSE ID',
        'CRN-0012-3456789-1',
      ];
      expect(verdictOf(umid, 'umid'), IdDocVerdict.matches);
      expect(verdictOf(umid, 'sss'), IdDocVerdict.matches);
    });

    test('a barangay-issued card has no fixed layout: an ID-shaped one is taken', () {
      const local = [
        'BARANGAY LARRAZABAL',
        'Date of Birth 05/12/1990',
        'Address SITIO SAN ROQUE',
        'Signature',
        'Valid until 2027',
      ];
      expect(verdictOf(local, 'barangay_id'), IdDocVerdict.matches);
    });
  });

  group('what must be refused', () {
    test('a selfie is not an ID', () {
      expect(verdictOf(selfie, 'voters_id'), IdDocVerdict.notAnId);
      expect(verdictOf(selfie, 'passport'), IdDocVerdict.notAnId);
      expect(verdictOf(selfie, null), IdDocVerdict.notAnId);
    });

    test('a photo with no text at all is not an ID', () {
      expect(verdictOf(const [], 'drivers_license'), IdDocVerdict.notAnId);
    });

    test('a receipt is not an ID', () {
      const receipt = [
        'SARI-SARI STORE',
        'Total 245.00',
        'Cash 300.00',
        'Change 55.00',
        'THANK YOU',
      ];
      expect(verdictOf(receipt, 'philsys'), IdDocVerdict.notAnId);
    });

    test('a driver\'s licence uploaded as a passport is the wrong type', () {
      final r = IdDocumentClassifier.classify(licence, declaredType: 'passport');
      expect(r.verdict, IdDocVerdict.wrongType);
      expect(r.foundType, 'drivers_license');
    });

    test('a passport uploaded as a driver\'s licence is the wrong type', () {
      final r = IdDocumentClassifier.classify(
        passport,
        declaredType: 'drivers_license',
      );
      expect(r.verdict, IdDocVerdict.wrongType);
      expect(r.foundType, 'passport');
    });

    test('a driver\'s licence uploaded as a voter\'s ID is the wrong type', () {
      expect(verdictOf(licence, 'voters_id'), IdDocVerdict.wrongType);
    });

    test('"barangay" in the address does not make a licence a barangay ID', () {
      final withBarangay = [...licence, 'BARANGAY LARRAZABAL'];
      final r = IdDocumentClassifier.classify(
        withBarangay,
        declaredType: 'barangay_id',
      );
      expect(r.verdict, IdDocVerdict.wrongType);
      expect(r.foundType, 'drivers_license');
    });

    test('ID-shaped but nothing proves it is a PhilSys ID', () {
      const generic = [
        'Date of Birth 05/12/1990',
        'Address SITIO SAN ROQUE',
        'Signature',
        'Valid until 2027',
        'Sex M',
      ];
      expect(verdictOf(generic, 'philsys'), IdDocVerdict.typeUnconfirmed);
    });
  });

  test('a card that is NOT the chosen type never passes as it', () {
    // Every type against a licence and a passport: only the right pairs pass.
    const types = [
      'philsys',
      'umid',
      'postal_id',
      'philhealth',
      'sss',
      'tin',
      'voters_id',
      'pwd_id',
      'senior_citizen_id',
      'barangay_id',
    ];
    for (final type in types) {
      expect(
        verdictOf(licence, type),
        isNot(IdDocVerdict.matches),
        reason: 'a driver\'s licence must not pass as $type',
      );
      expect(
        verdictOf(passport, type),
        isNot(IdDocVerdict.matches),
        reason: 'a passport must not pass as $type',
      );
    }
    expect(verdictOf(licence, 'passport'), isNot(IdDocVerdict.matches));
    expect(verdictOf(passport, 'drivers_license'), isNot(IdDocVerdict.matches));
  });
}
