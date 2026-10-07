// The typed name must be the name on the ID (user request 2026-10-07).

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/registration/domain/id_name_match.dart';

IdNameMatch check(String card, String first, String middle, String last) =>
    IdNameMatch.check(
      cardText: card,
      firstName: first,
      middleName: middle,
      lastName: last,
    );

void main() {
  const philId = '''
REPUBLIKA NG PILIPINAS
Republic of the Philippines
PAMBANSANG PAGKAKAKILANLAN
Philippine Identification Card
Apelyido/Last Name
DELA CRUZ
Mga Pangalan/Given Names
JUAN MIGUEL
Gitnang Apelyido/Middle Name
SANTOS
Petsa ng Kapanganakan/Date of Birth
JANUARY 01, 1990
''';

  const licence = '''
REPUBLIC OF THE PHILIPPINES
DEPARTMENT OF TRANSPORTATION
LAND TRANSPORTATION OFFICE
DRIVER'S LICENSE
Last Name, First Name, Middle Name
DELA CRUZ, JUAN MIGUEL SANTOS
Nationality Sex Date of Birth
PHL M 1990/01/01
''';

  test('the name on a PhilSys card matches', () {
    expect(check(philId, 'Juan Miguel', 'Santos', 'Dela Cruz').matches, isTrue);
  });

  test('the name on a driver licence (one line) matches', () {
    expect(check(licence, 'Juan Miguel', 'Santos', 'Dela Cruz').matches, isTrue);
  });

  test('case, accents and ñ do not matter', () {
    const card = 'Last Name PEÑA\nGiven Names JOSÉ\nMiddle Name REYES';
    expect(check(card, 'jose', 'reyes', 'Pena').matches, isTrue);
    expect(check(card, 'José', 'Reyes', 'Peña').matches, isTrue);
  });

  test('a wrong first name is refused, and named', () {
    final r = check(philId, 'Pedro', 'Santos', 'Dela Cruz');
    expect(r.matches, isFalse);
    expect(r.missing, [NamePart.first]);
  });

  test('a wrong middle and last name are both named', () {
    final r = check(philId, 'Juan Miguel', 'Reyes', 'Garcia');
    expect(r.missing, [NamePart.middle, NamePart.last]);
  });

  test('a short name must be a whole word, not letters inside another word', () {
    const card = 'Last Name MANALO\nGiven Names CARLO\nMiddle Name BANAAG';
    // "ANA" is inside MANALO and BANAAG; it is not on this card.
    expect(check(card, 'Ana', 'Banaag', 'Manalo').missing, [NamePart.first]);
  });

  test('a one-letter OCR slip in a longer word is forgiven', () {
    // OCR read "DELA CRUZ" as "DELA CRUS" and "MIGUEL" as "MIGUFL".
    const card = 'Last Name DELA CRUS\nGiven Names JUAN MIGUFL\nMiddle Name SANT0S';
    expect(check(card, 'Juan Miguel', 'Santos', 'Dela Cruz').matches, isTrue);
  });

  test('a short word must be exact', () {
    const card = 'Last Name LIM\nGiven Names JON';
    expect(check(card, 'Jun', '', 'Lim').missing, [NamePart.first]);
  });

  test('a surname the card runs together, or splits, still matches', () {
    expect(check('DELACRUZ, JUAN', 'Juan', '', 'Dela Cruz').matches, isTrue);
    expect(check('SAN JUAN, MARIA', 'Maria', '', 'Sanjuan').matches, isTrue);
  });

  test('a middle name printed only as an initial passes', () {
    const card = 'JUAN S. DELA CRUZ\nPROFESSIONAL REGULATION COMMISSION';
    expect(check(card, 'Juan', 'Santos', 'Dela Cruz').matches, isTrue);
    // ...but not a different initial.
    expect(check(card, 'Juan', 'Reyes', 'Dela Cruz').missing, [NamePart.middle]);
  });

  test('no middle name typed: nothing to check for it', () {
    const card = 'Last Name CRUZ\nGiven Names ANA';
    expect(check(card, 'Ana', '', 'Cruz').matches, isTrue);
  });

  test('an unreadable photo matches nothing', () {
    expect(check('', 'Juan', 'Santos', 'Cruz').missing,
        [NamePart.first, NamePart.middle, NamePart.last]);
  });

  group('a full name only (verifying later from Profile)', () {
    test('every word on the card passes', () {
      expect(IdNameMatch.missingFromFullName(philId, 'Juan Miguel Santos Dela Cruz'), isEmpty);
    });
    test('a middle word printed as an initial passes; a suffix is not needed', () {
      expect(IdNameMatch.missingFromFullName('JUAN S. DELA CRUZ', 'Juan Santos Dela Cruz Jr.'), isEmpty);
    });
    test("someone else's ID names the words that are missing", () {
      expect(IdNameMatch.missingFromFullName(philId, 'Pedro Santos Garcia'), ['PEDRO', 'GARCIA']);
    });
  });

  group('a middle name typed as only its initial (user report 2026-10-08)', () {
    // How a Driver's License prints it: "S." could be Seno or Santos.
    const license = "DRIVER'S LICENSE\nLast Name, First Name, Middle Name\n"
        'SALUT, KURT MICHAEL SENO\nNationality Sex Date of Birth\nPHL M 2005/07/31';

    test('is told apart from a full one', () {
      expect(IdNameMatch.isInitialOnly('S.'), isTrue);
      expect(IdNameMatch.isInitialOnly(' s '), isTrue);
      expect(IdNameMatch.isInitialOnly('Seno'), isFalse);
      expect(IdNameMatch.isInitialOnly(''), isFalse);
      expect(IdNameMatch.isInitialOnly('M. S.'), isFalse);
    });

    test('does not pass when the card prints the middle name in full', () {
      expect(check(license, 'Kurt Michael', 'S.', 'Salut').missing, [NamePart.middle]);
      expect(check(license, 'Kurt Michael', 'Seno', 'Salut').matches, isTrue);
    });

    test('a stray letter elsewhere on the card is not the initial', () {
      // The "S" of "DRIVER'S" and the "M" under Sex used to pass "S." and "M.".
      expect(check(license, 'Kurt Michael', 'S.', 'Salut').missing, [NamePart.middle]);
      expect(check(license, 'Kurt Michael', 'M.', 'Salut').missing, [NamePart.middle]);
      expect(IdNameMatch.missingFromFullName(license, 'Kurt Michael M. Salut'), ['M']);
    });

    test('passes when the card itself prints only the initial', () {
      expect(check('SALUT, KURT MICHAEL S.', 'Kurt Michael', 'S.', 'Salut').matches, isTrue);
    });

    test('an account name saved with the initial names that initial', () {
      expect(IdNameMatch.missingFromFullName(license, 'Kurt Michael S. Salut'), ['S']);
      expect(IdNameMatch.missingFromFullName(license, 'Kurt Michael Seno Salut'), isEmpty);
    });
  });
}
