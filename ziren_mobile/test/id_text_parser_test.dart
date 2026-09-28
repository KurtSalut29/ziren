import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/features/registration/data/id_text_parser.dart';

/// Reading a Philippine ID card, rule by rule.
///
/// These run on a laptop in under a second because IdTextParser imports no
/// plugin. That is the entire reason the parsing was split out of
/// IdOcrService: every one of these cases used to require a rebuild, a cable
/// and a physical card to check.
///
/// The cases are written as the text ML Kit actually returns — a flat list of
/// lines in reading order, with the label and value sometimes on one line and
/// sometimes on two, because that is what varies between cards and it is what
/// the rules have to survive.
void main() {
  group('is the typed number the one on the card?', () {
    // The ID step now refuses a photo that is not an ID, and the number field
    // is only worth anything if it has to agree with the card.
    const raw =
        'REPUBLIC OF THE PHILIPPINES\n'
        "DRIVER'S LICENSE\n"
        'License No. H07-24-000792\n'
        'Expiration 2028/07/31';

    test('the number OCR read is accepted, however it is punctuated', () {
      expect(
        IdTextParser.numberIsOnCard(
          typed: 'H07-24-000792',
          detected: 'H07-24-000792',
          rawText: raw,
        ),
        isTrue,
      );
      expect(
        IdTextParser.numberIsOnCard(
          typed: 'h07 24 000792',
          detected: 'H07-24-000792',
          rawText: raw,
        ),
        isTrue,
      );
    });

    test('one wrong character is a typo or an OCR slip, not a different card', () {
      // OCR read the licence as ...000782; the person fixes it to ...000792.
      expect(
        IdTextParser.numberIsOnCard(
          typed: 'H07-24-000792',
          detected: 'H07-24-000782',
          rawText: 'License No. H07-24-000782',
        ),
        isTrue,
      );
    });

    test('a number that is nowhere on the card is refused', () {
      expect(
        IdTextParser.numberIsOnCard(
          typed: '1234-5678-9012',
          detected: 'H07-24-000792',
          rawText: raw,
        ),
        isFalse,
      );
    });

    test('an empty or tiny value is refused', () {
      expect(
        IdTextParser.numberIsOnCard(typed: '', detected: 'H07-24-000792', rawText: raw),
        isFalse,
      );
      expect(
        IdTextParser.numberIsOnCard(typed: '12', detected: null, rawText: raw),
        isFalse,
      );
    });

    test('a number seen in the text but not chosen as THE number still counts', () {
      // detected is null (nothing scored as the number) but the digits are
      // printed on the card, and the person typed them.
      expect(
        IdTextParser.numberIsOnCard(typed: '000792', detected: null, rawText: raw),
        isTrue,
      );
    });

    test('letters OCR swaps for digits are folded on both sides', () {
      // The card prints H07-24-000792; OCR returned an O for the first zero.
      expect(
        IdTextParser.numberIsOnCard(
          typed: 'H07-24-000792',
          detected: null,
          rawText: 'License No. HO7-24-000792',
        ),
        isTrue,
      );
    });

    test('a random photograph has no number to agree with', () {
      expect(
        IdTextParser.numberIsOnCard(
          typed: 'H07-24-000792',
          detected: null,
          rawText: 'a dog in a park',
        ),
        isFalse,
      );
    });
  });

  group('the ID number', () {
    test('a year on the number line is not welded onto the number', () {
      // THE REPORTED BUG, and the reason this file exists.
      //
      // A card printing "24-000792" gave back "24-000792 2028": the old
      // pattern allowed a space inside a number, matched greedily across it,
      // and the old scorer then preferred the longest candidate. On a
      // barangay ID there is no published format to overrule that, so the
      // merged value won every time.
      expect(
        IdTextParser.bestNumber(['ID No. 24-000792 2028'], null),
        '24-000792',
      );
    });

    test('and not when the year is on its own line either', () {
      expect(
        IdTextParser.bestNumber([
          'BARANGAY CLEARANCE',
          'ID No. 24-000792',
          'Valid until 2028',
        ], 'barangay_id'),
        '24-000792',
      );
    });

    test('a full expiry date beside the number does not survive', () {
      expect(
        IdTextParser.bestNumber(['Control No. 24-000792 05/12/2028'], null),
        '24-000792',
      );
    });

    test('two space-separated groups are never joined on their own', () {
      // Equal length and adjacent is still not enough. Three is the rule,
      // because two is what the failure above looks like.
      expect(IdTextParser.bestNumber(['Control No 0792 2028'], null), '0792');
    });

    test('a number printed in equal blocks is joined back together', () {
      // PhilSys prints its 16 digits 4-4-4-4, sometimes with spaces.
      expect(
        IdTextParser.bestNumber([
          'Republic of the Philippines',
          'Philippine Identification Card',
          '1234 5678 9012 3456',
        ], 'philsys'),
        '1234 5678 9012 3456',
      );
    });

    test('a hyphenated number is one token', () {
      expect(
        IdTextParser.bestNumber([
          'LAND TRANSPORTATION OFFICE',
          "Driver's License",
          'License No. N01-23-456789',
        ], 'drivers_license'),
        'N01-23-456789',
      );
    });

    test('a bare year is never the answer', () {
      expect(IdTextParser.bestNumber(['Issued 2024'], null), isNull);
    });

    test('a written date is never the answer', () {
      expect(IdTextParser.bestNumber(['05/12/2028'], null), isNull);
    });

    test('a run of one repeated digit is a rule line, not a number', () {
      expect(IdTextParser.bestNumber(['00000000'], null), isNull);
    });

    test('something too short to be an ID number is ignored', () {
      expect(IdTextParser.bestNumber(['No. 12'], null), isNull);
    });

    test('a label matches as a word, not as a substring', () {
      // 'no' used to be matched with String.contains, so "Cebuano" scored as
      // a labelled number line and lifted whatever digits shared it.
      final labelled = IdTextParser.bestNumber([
        'Cebuano 4444555',
        'ID No. 24-000792',
      ], null);
      expect(labelled, '24-000792');
    });

    test('a format match beats a longer unlabelled run', () {
      expect(
        IdTextParser.bestNumber([
          'SOCIAL SECURITY SYSTEM',
          '9988776655443322110',
          'SSS No. 03-1234567-8',
        ], 'sss'),
        '03-1234567-8',
      );
    });

    test('the format check reports three states, not two', () {
      expect(IdTextParser.checkFormat('03-1234567-8', 'sss'), isTrue);
      expect(IdTextParser.checkFormat('24-000792', 'sss'), isFalse);
      // No published format for a barangay ID: "not checked", not "fine".
      expect(IdTextParser.checkFormat('24-000792', 'barangay_id'), isNull);
      expect(IdTextParser.checkFormat(null, 'sss'), isNull);
    });
  });

  group('which document this is', () {
    test('the issuer names itself', () {
      expect(
        IdTextParser.inferType([
          'Republic of the Philippines',
          'PhilSys',
          'Philippine Identification Card',
        ]),
        'philsys',
      );
      expect(
        IdTextParser.inferType(['LAND TRANSPORTATION OFFICE']),
        'drivers_license',
      );
      expect(IdTextParser.inferType(['PhilHealth']), 'philhealth');
      expect(
        IdTextParser.inferType(['OFFICE FOR SENIOR CITIZENS AFFAIRS']),
        'senior_citizen_id',
      );
    });

    test('"barangay" in an address does not make it a barangay ID', () {
      // Every card in the country prints a barangay in its address block, so
      // this marker is checked last. Getting the order wrong would relabel
      // most national IDs as barangay IDs — and a barangay ID is the one that
      // proves Biliran residency, so the mistake would silently upgrade what
      // the submission claims to prove.
      expect(
        IdTextParser.inferType([
          'LAND TRANSPORTATION OFFICE',
          "Driver's License",
          'Address: Purok 3, Barangay Calumpang, Naval, Biliran',
        ]),
        'drivers_license',
      );
    });

    test('an unrecognised card is null, not a guess', () {
      expect(IdTextParser.inferType(['ACME CORPORATION', 'STAFF']), isNull);
    });
  });

  group('the name', () {
    test('stacked labels with the value underneath', () {
      final r = IdTextParser.parse([
        'Republic of the Philippines',
        'APELYIDO/Last Name',
        'DELA CRUZ',
        'MGA PANGALAN/Given Names',
        'JUAN PABLO',
        'GITNANG APELYIDO/Middle Name',
        'SANTOS',
      ]);
      expect(r.lastName, 'Dela Cruz');
      expect(r.firstName, 'Juan');
      expect(r.middleName, 'Santos');
      expect(r.nameConfidence, ReadConfidence.labelled);
    });

    test('a combined header maps values by the header order', () {
      final r = IdTextParser.parse([
        'Last Name, First Name, Middle Name',
        'DELA CRUZ, JUAN, SANTOS',
      ]);
      expect(r.lastName, 'Dela Cruz');
      expect(r.firstName, 'Juan');
      expect(r.middleName, 'Santos');
      expect(r.nameConfidence, ReadConfidence.labelled);
    });

    test('a header printed the other way round is not read backwards', () {
      final r = IdTextParser.parse([
        'First Name, Last Name',
        'JUAN, DELA CRUZ',
      ]);
      expect(r.firstName, 'Juan');
      expect(r.lastName, 'Dela Cruz');
    });

    test('one box for the whole name', () {
      final r = IdTextParser.parse([
        'BARANGAY CALUMPANG',
        'Name: JUAN SANTOS DELA CRUZ',
      ]);
      expect(r.firstName, 'Juan');
      expect(r.lastName, 'Cruz');
      expect(r.nameConfidence, ReadConfidence.labelled);
    });

    test('a surname-first value keeps the comma as the separator', () {
      final r = IdTextParser.parse(['Name', 'DELA CRUZ, JUAN SANTOS']);
      expect(r.lastName, 'Dela Cruz');
      expect(r.firstName, 'Juan');
      expect(r.middleName, 'Santos');
    });

    test('a suffix is pulled out rather than left on a given name', () {
      final r = IdTextParser.parse(['Name: JUAN DELA CRUZ JR.']);
      expect(r.suffix, 'Jr.');
      expect(r.lastName, 'Cruz');
    });

    test('an unlabelled card is guessed, and says so', () {
      final r = IdTextParser.parse([
        'REPUBLIC OF THE PHILIPPINES',
        'BARANGAY CALUMPANG',
        'CERTIFICATE OF RESIDENCY',
        'JUAN SANTOS DELA CRUZ',
        'Purok 3, Naval, Biliran',
      ]);
      expect(r.lastName, 'Cruz');
      expect(r.firstName, 'Juan');
      // The honesty requirement: a guess must be reportable as a guess, so
      // the screen can ask the person to look twice at this one field rather
      // than at the whole form.
      expect(r.nameConfidence, ReadConfidence.guessed);
    });

    test('boilerplate is never mistaken for a name', () {
      final r = IdTextParser.parse([
        'REPUBLIC OF THE PHILIPPINES',
        'IDENTIFICATION CARD',
        'OFFICE OF THE PUNONG BARANGAY',
      ]);
      expect(r.lastName, isNull);
      expect(r.nameConfidence, isNull);
    });

    test('capitals are normalised but mixed case is left alone', () {
      expect(IdTextParser.parse(['Name: JUAN DELA CRUZ']).firstName, 'Juan');
      expect(
        IdTextParser.parse(['Name: Juan de la Cruz']).lastName,
        'Cruz',
      );
    });
  });

  group('date of birth', () {
    test('a birthday before the year 2000 is read', () {
      // The old date pattern only accepted 20xx because it was written for
      // expiry dates. Reusing it for a date of birth silently failed for
      // everybody born last century, which is very nearly everybody.
      final r = IdTextParser.parse(['Date of Birth: 05/12/1985']);
      expect(r.dateOfBirth, DateTime(1985, 5, 12));
    });

    test('a month name is read in either order', () {
      expect(
        IdTextParser.parse(['Date of Birth', '12 MAY 1985']).dateOfBirth,
        DateTime(1985, 5, 12),
      );
      expect(
        IdTextParser.parse(['Date of Birth', 'MAY 12, 1985']).dateOfBirth,
        DateTime(1985, 5, 12),
      );
    });

    test('a day above twelve settles the ambiguous order', () {
      expect(
        IdTextParser.parse(['Petsa ng Kapanganakan: 25/12/1985']).dateOfBirth,
        DateTime(1985, 12, 25),
      );
    });

    test('an impossible date is nothing, not a rolled-over date', () {
      // DateTime(1985, 13, 40) is legal Dart and quietly means Feb 1986.
      expect(IdTextParser.parse(['Date of Birth: 40/13/1985']).dateOfBirth,
          isNull);
    });

    test('a date that could not be a birthday is refused', () {
      // An expiry misread into the birthday field is a plausible-looking
      // wrong answer, which is worse than an empty field.
      expect(
        IdTextParser.parse(['Date of Birth: 05/12/2030']).dateOfBirth,
        isNull,
      );
    });

    test('an unlabelled date is not taken as a birthday', () {
      expect(IdTextParser.parse(['05/12/1985']).dateOfBirth, isNull);
    });
  });

  group('sex', () {
    test('the printed initial is enough', () {
      expect(IdTextParser.parse(['Sex: M']).sex, 'male');
      expect(IdTextParser.parse(['Kasarian: F']).sex, 'female');
      expect(IdTextParser.parse(['Sex', 'FEMALE']).sex, 'female');
    });

    test('a word starting with M elsewhere on the row is not the answer', () {
      // "Sex: F  Civil Status: MARRIED" — reading the first M would flip it.
      expect(IdTextParser.parse(['Sex: F  Civil Status: MARRIED']).sex,
          'female');
    });

    test('no label means no answer', () {
      expect(IdTextParser.parse(['MALE NURSE ASSOCIATION']).sex, isNull);
    });
  });

  group('address and expiry', () {
    test('the address block is joined, and stops at the next label', () {
      final r = IdTextParser.parse([
        'Address',
        'Purok 3, Barangay Calumpang',
        'Naval, Biliran',
        'Date of Birth: 05/12/1985',
      ]);
      expect(r.address, 'Purok 3, Barangay Calumpang, Naval, Biliran');
    });

    test('expiry is label-anchored so a birthday is never read as one', () {
      final r = IdTextParser.parse([
        'Date of Birth: 05/12/1985',
        'Valid until: 05/12/2030',
      ]);
      expect(r.expiryDate, DateTime(2030, 5, 12));
      expect(r.dateOfBirth, DateTime(1985, 5, 12));
    });

    test('no expiry label means no expiry, not "does not expire"', () {
      expect(IdTextParser.parse(['Date of Birth: 05/12/1985']).expiryDate,
          isNull);
    });
  });

  group('surname matching', () {
    test('punctuation and case do not decide whether a name matched', () {
      expect(
        IdTextParser.surnameAppears('DELA CRUZ, JUAN', 'dela cruz'),
        isTrue,
      );
    });

    test('nothing to compare against is null, not false', () {
      expect(IdTextParser.surnameAppears('DELA CRUZ', null), isNull);
      expect(IdTextParser.surnameAppears('DELA CRUZ', ' '), isNull);
    });

    test('an absent surname is false', () {
      expect(IdTextParser.surnameAppears('DELA CRUZ', 'Reyes'), isFalse);
    });
  });

  group('a real LTO driver\'s licence', () {
    /// The lines ML Kit returned from a photograph of an actual card.
    ///
    /// Kept verbatim, including the stray comma OCR inserted after "SAN" and
    /// the O-for-zero in the licence number, because those two artefacts are
    /// what broke it. A tidied-up version of this text passes the old code.
    const lines = [
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

    test('the name comes from the name row, not the address', () {
      // WHAT WENT WRONG ON THE REAL CARD.
      //
      // The fallback picked whichever name-shaped line was LONGEST, and an
      // address is nearly always longer than a name. "SITIO SAN,ROQUE,
      // LARRAZABAL, NAVAL" beat "SALUT, KURT MICHAEL SENO" by ten characters,
      // and the comma OCR dropped after "SAN" then split it into a
      // plausible-looking three-part name: Sitio San / Roque. / Larrazabal
      // Naval.
      final r = IdTextParser.parse(lines);

      expect(r.lastName, 'Salut');
      expect(r.firstName, 'Kurt Michael');
      expect(r.middleName, 'Seno');
    });

    test('the header names three parts and the card prints two', () {
      // "Last Name. First Name. Middle Name" over "SALUT, KURT MICHAEL SENO".
      // Only one comma, so the middle name is not its own group — on a
      // Philippine licence it is the LAST word of what follows the surname,
      // which is the mother's maiden name.
      final r = IdTextParser.parse(lines);
      expect(r.nameConfidence, ReadConfidence.labelled);
    });

    test('an O misread as a zero is repaired against the printed format', () {
      // OCR returned "HO7-24-000792"; the card says "H07-24-000792". A
      // driver's licence number is one letter and ten digits by regulation,
      // so the O cannot be a letter and the repair is not a guess.
      final r = IdTextParser.parse(lines);
      expect(r.idNumber, 'H07-24-000792');
      expect(IdTextParser.checkFormat(r.idNumber, 'drivers_license'), isTrue);
    });

    test('the rest of the card still reads', () {
      final r = IdTextParser.parse(lines);
      expect(r.idType, 'drivers_license');
      expect(r.dateOfBirth, DateTime(2005, 7, 31));
      expect(r.sex, 'male');
      expect(r.address, contains('SITIO SAN'));
      expect(r.expiryDate, DateTime(2028, 7, 31));
    });

    test('the signatory printed on every licence is not the holder', () {
      // "ATTY. VIGOR D. MENDOZA II" is longer than the holder's name and sits
      // in the same all-caps style. Length alone would pick it once the
      // address is excluded, which is why length is no longer the rule.
      final r = IdTextParser.parse(lines);
      expect(r.lastName, isNot('Mendoza'));
      expect(r.firstName, isNot('Vigor'));
    });

    test('a card whose faint label row was not read still finds the name', () {
      // The label row is small grey print and OCR misses it often. Everything
      // above must still work without it.
      final withoutHeader = [
        for (final l in lines)
          if (l != 'Last Name. First Name. Middle Name') l,
      ];
      final r = IdTextParser.parse(withoutHeader);

      expect(r.lastName, 'Salut');
      expect(r.firstName, 'Kurt Michael');
      expect(r.middleName, 'Seno');
      // Nothing labelled it, so it is reported as the guess it is.
      expect(r.nameConfidence, ReadConfidence.guessed);
    });

    test('only "Last Name" survived, and it swallowed the whole name', () {
      // WHAT THE REAL HANDSET DID, and it is the reason a value with a comma
      // in it is now re-read.
      //
      // The label row is tiny grey print. ML Kit recovered the words "Last
      // Name" from it and nothing else, so the surname lookup found its label,
      // took the row beneath as the value, and stored the entire name as the
      // surname:
      //
      //     Last name:  Salut, Kurt Michael Seno
      //     First name: (empty)
      //
      // No part of a person's name contains a comma, so the comma is the card
      // saying this box was never one part.
      final onlySurnameLabel = [
        for (final l in lines)
          if (l != 'Last Name. First Name. Middle Name') l,
      ]..insert(4, 'Last Name');

      final r = IdTextParser.parse(onlySurnameLabel);
      expect(r.lastName, 'Salut');
      expect(r.firstName, 'Kurt Michael');
      expect(r.middleName, 'Seno');
    });

    test('the same when only the given-name label survived', () {
      final onlyGivenLabel = [
        for (final l in lines)
          if (l != 'Last Name. First Name. Middle Name') l,
      ]..insert(4, 'First Name');

      final r = IdTextParser.parse(onlyGivenLabel);
      expect(r.lastName, 'Salut');
      expect(r.firstName, 'Kurt Michael');
    });
  });

  group('a name part never holds a comma', () {
    test('a surname box containing a whole name is re-read as one', () {
      final r = IdTextParser.parse(['Surname', 'DELA CRUZ, JUAN SANTOS']);
      expect(r.lastName, 'Dela Cruz');
      expect(r.firstName, 'Juan');
      expect(r.middleName, 'Santos');
    });

    test('a genuine two-word surname is left alone', () {
      // "DELA CRUZ" has no comma and is a real surname. The rule must not
      // start splitting those.
      final r = IdTextParser.parse([
        'Surname',
        'DELA CRUZ',
        'Given Names',
        'JUAN',
      ]);
      expect(r.lastName, 'Dela Cruz');
      expect(r.firstName, 'Juan');
    });

    test('labels that all worked are trusted over the inference', () {
      // If the card gave up a separate given name, the labels really did read
      // and they are better evidence than anything inferred from punctuation.
      final r = IdTextParser.parse([
        'Surname',
        'DELA CRUZ, JR',
        'Given Names',
        'JUAN',
      ]);
      expect(r.firstName, 'Juan');
    });
  });

  group('address lines are never names', () {
    test('a line naming a sitio or purok is not a name candidate', () {
      for (final line in [
        'SITIO SAN ROQUE, LARRAZABAL, NAVAL',
        'PUROK 3, CALUMPANG',
        'BLK 4 LOT 12, GREENHILLS SUBDIVISION',
        'POBLACION, CAIBIRAN',
      ]) {
        final r = IdTextParser.parse([line]);
        expect(
          r.lastName,
          isNull,
          reason: 'took a name out of the address line "$line"',
        );
      }
    });

    test('a title is not a name', () {
      final r = IdTextParser.parse(['ATTY. VIGOR D. MENDOZA II']);
      expect(r.lastName, isNull);
    });
  });

  group('a whole card', () {
    test('a barangay ID fills in what a person would have typed', () {
      final r = IdTextParser.parse([
        'REPUBLIC OF THE PHILIPPINES',
        'PROVINCE OF BILIRAN',
        'MUNICIPALITY OF NAVAL',
        'BARANGAY CALUMPANG',
        'BARANGAY IDENTIFICATION CARD',
        'ID No. 24-000792 2028',
        'Name: JUAN SANTOS DELA CRUZ',
        'Address: Purok 3, Calumpang, Naval, Biliran',
        'Date of Birth: 05/12/1985',
        'Sex: M',
      ]);

      expect(r.idNumber, '24-000792');
      expect(r.idType, 'barangay_id');
      expect(r.firstName, 'Juan');
      expect(r.lastName, 'Cruz');
      expect(r.dateOfBirth, DateTime(1985, 5, 12));
      expect(r.sex, 'male');
      expect(r.address, contains('Purok 3'));
      expect(r.hasAnything, isTrue);
    });

    test('an unreadable photo produces nothing rather than nonsense', () {
      final r = IdTextParser.parse(['', '  ', '|']);
      expect(r.hasAnything, isFalse);
    });
  });
}
