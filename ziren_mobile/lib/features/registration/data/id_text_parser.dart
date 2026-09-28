/// Reading a Philippine ID card from the text ML Kit found on it.
///
/// This file is deliberately PURE DART. It imports no plugin, touches no
/// method channel and knows nothing about cameras, so every rule in it is
/// unit-testable on a laptop — see test/id_text_parser_test.dart. The ML Kit
/// wrapper that feeds it lives in id_ocr_service.dart and does nothing except
/// hand over a list of lines.
///
/// That split is not tidiness. The parsing rules here are the part that turns
/// out to be wrong in the field, and they have to be corrected from a
/// photograph someone sends in — which behind a `flutter run` on a physical
/// handset is several minutes per attempt, and here is a second.
///
/// WHAT THIS IS FOR
/// ----------------
/// It fills the registration form in. Nothing here decides whether an ID is
/// genuine, and nothing here blocks anybody: every field it produces lands in
/// an editable box with the card still on screen next to it. A person who
/// finds a wrong letter fixes it in two seconds. An administrator makes the
/// actual decision, exactly as before.
///
/// It has to work on ANY of the eleven documents in IdCatalogue, which rules
/// out per-card templates. Every rule below is therefore either
/// label-anchored — find the words the card prints beside the value — or a
/// clearly-marked fallback guess, and guesses are reported as guesses so the
/// screen can ask the person to look twice.
library;

/// How a value was arrived at, so the UI can be honest about it.
enum ReadConfidence {
  /// The card printed a label ("Date of Birth") and the value sat beside or
  /// under it. As reliable as the OCR itself.
  labelled,

  /// No label was found and the value was inferred from the shape of the text
  /// — the biggest name-shaped line, and so on. Right most of the time, and
  /// the reason the screen says "check this".
  guessed,
}

/// Everything that could be read off the printed face of one ID.
///
/// Every field is nullable, and null means "not found" rather than "empty".
/// The difference matters at the call site: a null surname leaves the form
/// field alone for the person to type, an empty string would overwrite what
/// they had already entered.
class IdReading {
  const IdReading({
    this.idNumber,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    this.nameConfidence,
    this.dateOfBirth,
    this.sex,
    this.address,
    this.idType,
    this.expiryDate,
  });

  final String? idNumber;

  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;

  /// How the name parts were found. Null when no name was found at all.
  final ReadConfidence? nameConfidence;

  final DateTime? dateOfBirth;

  /// 'male', 'female', or null. Matches the values the sex chips already use.
  final String? sex;

  /// The address block as printed, joined onto one line. Free text: it is
  /// shown to the person and to an admin, and never resolved to a barangay on
  /// its own — see the note in the address step about why guessing a barangay
  /// misroutes dispatch.
  final String? address;

  /// The `valid_id_type` this card looks like, from the issuer's own wording.
  /// Null when nothing on the card identified it.
  final String? idType;

  final DateTime? expiryDate;

  /// Whether anything at all was recognised, so the screen knows whether the
  /// "we filled this in from your ID" banner has anything to talk about.
  bool get hasAnything =>
      idNumber != null ||
      lastName != null ||
      firstName != null ||
      dateOfBirth != null ||
      sex != null ||
      address != null ||
      idType != null;

  /// The name parts joined, for showing back what was read.
  String get fullName =>
      [
        firstName,
        middleName,
        lastName,
        suffix,
      ].where((p) => p != null && p.trim().isNotEmpty).join(' ').trim();
}

/// The rules. All static, all pure.
abstract final class IdTextParser {
  // ── Entry point ─────────────────────────────────────────────

  /// Read [lines] — the text lines ML Kit found, in the order it found them.
  ///
  /// [declaredType] is the ID type the person chose, when they chose one. It
  /// is used only to give the number search a published format to check
  /// candidates against; it never overrides what the card itself says.
  static IdReading parse(List<String> lines, {String? declaredType}) {
    final clean = [
      for (final line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ];

    // Type first: it is read from the issuer's own wording, and knowing it
    // turns the number search from a guess into a checked one.
    final inferred = inferType(clean);
    final names = _readName(clean);

    return IdReading(
      idNumber: bestNumber(clean, inferred ?? declaredType),
      firstName: names.first,
      middleName: names.middle,
      lastName: names.last,
      suffix: names.suffix,
      nameConfidence: names.confidence,
      dateOfBirth: _readDateOfBirth(clean),
      sex: _readSex(clean),
      address: _readAddress(clean),
      idType: inferred,
      expiryDate: readExpiry(clean),
    );
  }

  // ── ID number ───────────────────────────────────────────────
  //
  // THE BUG THIS REPLACES, written down because it will otherwise come back.
  //
  // The old pattern was:
  //
  //     RegExp(r'\b[0-9][0-9\- ]{5,20}[0-9]\b')
  //
  // and the character class contains a SPACE. A card that prints its number
  // and a year close enough for OCR to put them on one line —
  //
  //     ID No. 24-000792   2028
  //
  // — is therefore matched as the single token "24-000792 2028", because the
  // pattern is greedy and a space is a legal interior character. The old
  // scorer then preferred the LONGEST candidate when no published format
  // applied, which is precisely the merged one. For every LGU-issued card —
  // barangay, PWD, senior citizen, the documents that actually prove Biliran
  // residency — there IS no published format, so the merged candidate always
  // won. The reported symptom was a correct number with a stray year welded
  // to the end of it.
  //
  // What replaces it treats a space as a boundary rather than a character,
  // and rejoins across one only when there is a reason to:
  //
  //   * three or more groups of equal length, which is how a long number gets
  //     printed in blocks (PhilSys prints 1234 5678 9012 3456);
  //   * or when the joined form matches the published format for this card
  //     type and the parts on their own do not.
  //
  // Two groups is deliberately not enough for the first rule: "24-000792
  // 2028" would qualify under any looser version of it, which is the whole
  // failure being fixed.
  //
  // Dashes are treated differently and kept inside a token: no Philippine ID
  // prints two unrelated numbers on either side of a hyphen with no space.

  /// One printed token: digits, optionally with a short letter prefix, and
  /// optionally hyphenated. Never contains a space.
  static final _token = RegExp(r'[A-Z]{0,2}[0-9][0-9A-Z]*(?:-[0-9A-Z]+)*');

  /// A token that is only a year. Cards print issue and expiry years beside
  /// everything, and a bare year is never an ID number.
  static final _yearOnly = RegExp(r'^(19|20)\d{2}$');

  /// A whole token that is a written date.
  static final _dateToken = RegExp(r'^\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}$');

  /// Words a card prints beside its number.
  ///
  /// Matched with word boundaries, and that is a fix rather than a detail:
  /// the old code used String.contains, so the entry 'no' matched the letters
  /// inside "Cebuano", "Norte" and "Nombre", and any line containing one of
  /// those was treated as labelling a number.
  static const _numberLabelWords = [
    'no',
    'nos',
    'number',
    'num',
    'id',
    'idno',
    'crn',
    'psn',
    'pcn',
    'pin',
    'license',
    'licence',
    'passport',
    'tin',
    'sss',
    'philhealth',
    'control',
    'serial',
    'reference',
    'ref',
    'registration',
    'osca',
    'pwd',
  ];

  static final _numberLabel = RegExp(
    '\\b(${_numberLabelWords.join('|')})\\b',
    caseSensitive: false,
  );

  /// Words that mean this line is about a date, not about the ID number.
  static final _dateLine = RegExp(
    r'\b(birth|birthday|birthdate|kapanganakan|issued|issue|petsa|valid|'
    r'expiry|expiration|expires|thru|until)\b',
    caseSensitive: false,
  );

  /// Printed formats, by the `valid_id_type` values in IdCatalogue.
  ///
  /// Matched against the number with separators stripped, so a card printing
  /// 1234-5678-9012-3456 and one printing 1234 5678 9012 3456 are the same
  /// number.
  ///
  /// The LGU-issued types are absent on purpose, and their absence is the
  /// answer rather than a gap: a barangay ID, a PWD ID and a senior citizen
  /// ID are numbered however the issuing office chooses, with no national
  /// scheme to check against. Inventing a pattern for them would reject valid
  /// cards, which for the documents that actually prove Biliran residency is
  /// the worst possible place to be wrong.
  static final Map<String, RegExp> formats = {
    // PhilSys Card Number: 16 digits, printed 4-4-4-4.
    'philsys': RegExp(r'^\d{16}$'),
    // UMID Common Reference Number: 12 digits, printed 4-7-1.
    'umid': RegExp(r'^\d{12}$'),
    // Driver's licence: one letter, then ten digits (e.g. N01-23-456789).
    'drivers_license': RegExp(r'^[A-Z]\d{10}$'),
    // Passport: a letter, seven digits, and on newer books a trailing letter.
    'passport': RegExp(r'^[A-Z]{1,2}\d{7}[A-Z]?$'),
    // PhilHealth Identification Number: 12 digits, printed 2-9-1.
    'philhealth': RegExp(r'^\d{12}$'),
    // SSS: 10 digits, printed 2-7-1.
    'sss': RegExp(r'^\d{10}$'),
    // TIN: 9 digits, or 12 with the branch code.
    'tin': RegExp(r'^\d{9}(\d{3})?$'),
    // Voter's Identification Number: 22 digits.
    'voters_id': RegExp(r'^\d{22}$'),
  };

  /// The best candidate for the printed ID number, or null if nothing on the
  /// card looked like one.
  static String? bestNumber(List<String> lines, String? idType) {
    final format = idType == null ? null : formats[idType];

    String? best;
    var bestScore = double.negativeInfinity;

    for (final line in lines) {
      final labelled = _numberLabel.hasMatch(line);
      final dateish = _dateLine.hasMatch(line);

      for (final candidate in _candidatesIn(line, format)) {
        final bare = strip(candidate);
        if (!_plausibleNumber(candidate, bare)) continue;

        // OCR CONFUSION, REPAIRED AGAINST THE PRINTED FORMAT.
        //
        // A real licence read back as "HO7-24-000792" where the card says
        // "H07-24-000792": the zero came through as a capital O. That is
        // the commonest OCR error there is on a worn card, and it is not a
        // guess to correct it here — a driver's licence number is one
        // letter followed by ten digits by regulation, so a letter in the
        // second position cannot be right.
        //
        // The guard is what makes this safe: a repair is accepted ONLY when
        // the candidate fails the published format and the repaired form
        // passes it. Anything already conformant is left alone, and a card
        // type with no published format is never touched at all. So the
        // repair can never turn a good number into a different good one.
        var text = candidate;
        var repairedBare = bare;
        if (format != null && !format.hasMatch(bare)) {
          final mended = _mendDigits(candidate);
          if (format.hasMatch(strip(mended))) {
            text = mended;
            repairedBare = strip(mended);
          }
        }

        var score = 0.0;
        // A match against the card's own published format settles it, so this
        // term dwarfs every other one deliberately.
        if (format != null && format.hasMatch(repairedBare)) score += 1000;
        // Printed next to "No." or "CRN" or similar.
        if (labelled) score += 100;
        // Hyphenated: the card itself grouped these digits together, which is
        // strong evidence they are one value rather than two.
        if (candidate.contains('-')) score += 40;
        // On a line that is about a date. Still eligible — plenty of cards
        // print the number and the issue date together — but it loses to an
        // equally good candidate from a line that is not.
        if (dateish) score -= 60;
        // Length breaks ties, and ONLY breaks ties. Capped so that a long
        // accidental run can never outweigh a format match or a label, which
        // is how the old scorer went wrong.
        score += bare.length.clamp(0, 24);

        if (score > bestScore) {
          bestScore = score;
          best = text;
        }
      }
    }
    return best;
  }

  /// Every number-shaped candidate on one line.
  ///
  /// Each space-separated token is a candidate on its own. Joins across a
  /// space are added only under the two rules described above.
  static List<String> _candidatesIn(String line, RegExp? format) {
    final tokens =
        _token.allMatches(line.toUpperCase()).map((m) => m.group(0)!).toList();
    if (tokens.isEmpty) return const [];

    final out = <String>[...tokens];

    // Rule 1 — regular grouping. Three or more consecutive all-digit tokens
    // of the same length is how a long number is printed in blocks.
    for (var i = 0; i < tokens.length; i++) {
      for (var j = i + 2; j < tokens.length; j++) {
        final run = tokens.sublist(i, j + 1);
        if (!run.every(_allDigits)) break;
        if (!run.every((t) => t.length == run.first.length)) break;
        // A run that ENDS in a year, with no published format asking for it,
        // is the same mistake as before wearing a different shape: four
        // digits of expiry sitting in the same column width as the number's
        // own groups. Longer and shorter runs are generated separately, so
        // dropping this one costs nothing when it really is part of the
        // number and there are more groups after it.
        if (format == null && _yearOnly.hasMatch(run.last)) continue;
        out.add(run.join(' '));
      }
    }

    // Rule 2 — the join is what the published format wants and the parts on
    // their own are not. Only fires when there is a real format to satisfy,
    // so it cannot invent a number on a barangay ID.
    if (format != null) {
      for (var i = 0; i < tokens.length; i++) {
        for (var j = i + 1; j < tokens.length; j++) {
          final run = tokens.sublist(i, j + 1);
          if (run.any((t) => !format.hasMatch(strip(t)))) {
            final joined = run.join(' ');
            if (format.hasMatch(strip(joined))) out.add(joined);
          }
        }
      }
    }

    return out;
  }

  /// The letters OCR substitutes for digits, and what they should be.
  ///
  /// One direction only. Digits misread as letters is the failure that
  /// happens on a number, because a number is mostly digits and the reader
  /// has no dictionary to fall back on; going the other way would mangle
  /// the letter prefixes that passports and licences legitimately carry.
  static const _digitLookalikes = {
    'O': '0',
    'Q': '0',
    'D': '0',
    'I': '1',
    'L': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'B': '8',
  };

  /// Every lookalike letter turned into its digit. Separators untouched, so
  /// the number keeps the grouping the card printed.
  static String _mendDigits(String s) =>
      s.split('').map((c) => _digitLookalikes[c] ?? c).join();

  static bool _allDigits(String s) => RegExp(r'^\d+$').hasMatch(s);

  /// Reject the things that are number-shaped but are not ID numbers.
  static bool _plausibleNumber(String candidate, String bare) {
    if (bare.length < 4) return false;
    // A bare year — the specific rubbish that used to be welded onto the end
    // of a correct number.
    if (_yearOnly.hasMatch(candidate)) return false;
    if (_dateToken.hasMatch(candidate)) return false;
    // One digit repeated: a placeholder, a rule line, or a misread.
    if (RegExp(r'^(\d)\1+$').hasMatch(bare)) return false;
    // At least four digits. A letter run with one or two digits in it is a
    // restriction code, a blood type or a licence class, not a number.
    if (RegExp(r'\d').allMatches(bare).length < 4) return false;
    return true;
  }

  /// Is the number the person typed the one that is on the photographed card?
  ///
  /// The ID step used to accept ANY photograph: a picture of a person, of a
  /// wall, of a receipt. The photo has to be a real ID now, and that check would
  /// be worth nothing if the number field beside it could hold anything - so
  /// the number has to be one the card actually shows. Three ways to be:
  ///
  ///   * it is the number OCR read off the card;
  ///   * it is one character away from it. OCR misreads a single digit on a
  ///     worn card all the time, and someone correcting that must not be
  ///     locked out for it;
  ///   * it appears in the text read off the card at all, where "appears" is
  ///     judged after folding the letters OCR confuses with digits (O/0, I/1,
  ///     S/5, B/8 ...) on both sides.
  ///
  /// A number that is none of those is not on this card.
  static bool numberIsOnCard({
    required String typed,
    required String? detected,
    required String rawText,
  }) {
    final t = strip(typed);
    if (t.length < 4) return false;

    if (detected != null) {
      final d = strip(detected);
      if (t == d) return true;
      if (t.length >= 6 && _editDistance(t, d) <= 1) return true;
    }
    return _mendDigits(strip(rawText)).contains(_mendDigits(t));
  }

  /// Levenshtein distance. Numbers are short, so the plain O(n*m) form is fine.
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [
          cur[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Whether [number] matches the printed format for [idType].
  ///
  /// Three states, and the third matters. True means it matched; false means
  /// a number was found and did not match the declared type — which usually
  /// means the wrong type was picked, not that the card is fake. Null means
  /// we have no published format for that type and there is nothing to check
  /// against.
  static bool? checkFormat(String? number, String? idType) {
    if (number == null || idType == null) return null;
    final format = formats[idType];
    if (format == null) return null;
    return format.hasMatch(strip(number));
  }

  // ── ID type ─────────────────────────────────────────────────

  /// Issuer wording → `valid_id_type`, most specific first.
  ///
  /// ORDER IS LOAD-BEARING. 'barangay' is last because it appears in the
  /// ADDRESS block of almost every other card in the country; matching it
  /// earlier would label a driver's licence as a barangay ID for anyone whose
  /// address is printed on it, which is everyone.
  static const _typeMarkers = <(String, List<String>)>[
    (
      'philsys',
      [
        'philsys',
        'philippine identification card',
        'pambansang pagkakakilanlan',
        'philippine identification system',
      ],
    ),
    ('umid', ['unified multi-purpose', 'unified multipurpose', 'umid']),
    (
      'drivers_license',
      [
        "driver's license",
        'drivers license',
        "driver's licence",
        'drivers licence',
        'land transportation office',
        'non-professional',
        'professional driver',
      ],
    ),
    ('passport', ['passport', 'pasaporte']),
    ('philhealth', ['philhealth', 'philippine health insurance']),
    ('sss', ['social security system', 'sss']),
    ('tin', ['bureau of internal revenue', 'taxpayer identification', 'tin']),
    ('postal_id', ['philippine postal', 'phlpost', 'postal']),
    (
      'voters_id',
      [
        'commission on elections',
        'comelec',
        "voter's identification",
        'voters identification',
        'voter',
      ],
    ),
    ('pwd_id', ['persons with disability', 'person with disability', 'pwd']),
    ('senior_citizen_id', ['senior citizen', 'osca', 'office for senior']),
    ('barangay_id', ['barangay']),
  ];

  /// Which document this looks like, from what the issuer printed on it.
  static String? inferType(List<String> lines) {
    final text = lines.join(' ').toLowerCase();
    for (final (type, markers) in _typeMarkers) {
      for (final marker in markers) {
        // Short markers are acronyms and need word boundaries: 'tin' is
        // inside "printing" and 'sss' is not inside anything, but applying
        // the rule uniformly means nobody has to work out which is which.
        final hit =
            marker.length <= 4
                ? RegExp('\\b${RegExp.escape(marker)}\\b').hasMatch(text)
                : text.contains(marker);
        if (hit) return type;
      }
    }
    return null;
  }

  // ── Name ────────────────────────────────────────────────────

  static const _surnameLabels = [
    'surname',
    'last name',
    'apelyido',
    'family name',
  ];
  static const _givenLabels = [
    'given names',
    'given name',
    'first name',
    'mga pangalan',
    'pangalan',
  ];
  static const _middleLabels = [
    'middle name',
    'gitnang apelyido',
    'middle initial',
  ];

  static const _suffixes = ['jr', 'sr', 'ii', 'iii', 'iv'];

  /// Words that appear on ID cards and are never part of a person's name.
  ///
  /// This list is what makes the unlabelled fallback usable at all. A
  /// barangay ID often prints the holder's name with no label, in the same
  /// weight as the words "BARANGAY CLEARANCE" above it — so the only way to
  /// tell them apart is to know that one of them is boilerplate.
  static const _notNameWords = [
    'republic', 'republika', 'philippines', 'pilipinas', 'identification',
    'identity', 'card', 'national', 'pambansang', 'pagkakakilanlan',
    'barangay', 'city', 'municipality', 'province', 'lungsod', 'bayan',
    'lalawigan', 'office', 'official', 'address', 'tirahan', 'date', 'birth',
    'kapanganakan', 'sex', 'kasarian', 'gender', 'blood', 'type', 'signature',
    'lagda', 'valid', 'until', 'expiry', 'expiration', 'expires', 'issued',
    'issue', 'petsa', 'holder', 'chairman', 'captain', 'punong', 'secretary',
    'clearance', 'certificate', 'resident', 'residency', 'driver', 'drivers',
    'license', 'licence', 'agency', 'code', 'nationality', 'citizenship',
    'weight', 'height', 'eyes', 'restriction', 'restrictions', 'conditions',
    'department', 'transportation', 'land', 'social', 'security', 'system',
    'health', 'insurance', 'corporation', 'philhealth', 'postal',
    'commission', 'elections', 'comelec', 'senior', 'citizen', 'persons',
    'person', 'disability', 'passport', 'pasaporte', 'government', 'service',
    'employees', 'bureau', 'internal', 'revenue', 'taxpayer', 'unified',
    'purpose', 'number', 'place', 'status', 'civil', 'precinct', 'voter',
    'emergency', 'contact', 'case', 'telephone', 'mobile', 'signed',
    'surname', 'given', 'middle', 'first', 'last', 'name', 'names',
    'apelyido', 'pangalan', 'gitnang', 'nickname',
    // Address vocabulary. A card carries the holder's address in the same
    // capitals and the same type size as their name, and on a driver's
    // licence it is the LONGER of the two — which is how
    // "SITIO SAN,ROQUE, LARRAZABAL, NAVAL" came to be read as somebody's
    // name. None of these words appears in a Filipino name; 'street',
    // 'road' and 'avenue' are spelled out rather than abbreviated because
    // 'St' and 'Ave' are too close to real name fragments to reject.
    'sitio', 'purok', 'brgy', 'subdivision', 'subd', 'poblacion',
    'capital', 'zone', 'blk', 'street', 'road', 'avenue', 'highway',
    'village', 'compound', 'phase',
    // Titles. Every Philippine ID is signed by an official whose name is
    // printed on the front, in the same style as the holder's and often
    // longer. The title is the thing that distinguishes them.
    'atty', 'engr', 'hon', 'gov', 'mayor', 'usec', 'asst', 'assistant',
    'undersecretary', 'administrator', 'director', 'licensee',
  ];

  static final _notName = RegExp(
    '\\b(${_notNameWords.join('|')})\\b',
    caseSensitive: false,
  );

  /// Labels for a card that prints the whole name in one box.
  ///
  /// Only consulted once the per-part labels have found nothing, because
  /// 'name' is a substring of "Last Name", "Given Names" and "Middle Name" and
  /// would otherwise match all three.
  static const _wholeNameLabels = [
    'name of holder',
    "holder's name",
    'complete name',
    'full name',
    'name',
  ];

  static ({
    String? first,
    String? middle,
    String? last,
    String? suffix,
    ReadConfidence? confidence,
  })
  _readName(List<String> lines) {
    // 1. A combined header with the values on the row beneath. Must be tried
    //    first: on such a card every per-part label sits on the SAME line, so
    //    the per-part search below would take the whole value row as the
    //    answer for each of them and report the full name three times.
    final combined = _combinedHeader(lines);
    if (combined != null) {
      return (
        first: combined.first,
        middle: combined.middle,
        last: combined.last,
        suffix: combined.suffix,
        confidence: ReadConfidence.labelled,
      );
    }

    // 2. One label per part, each with its own value. Middle before surname:
    //    'gitnang apelyido' contains 'apelyido', so checking surname first
    //    would read every middle-name label on a PhilSys card as a surname
    //    label.
    final middle = _valueFor(lines, _middleLabels);
    final last = _valueFor(lines, _surnameLabels, skip: _middleLabels);
    final given = _valueFor(lines, _givenLabels, skip: _middleLabels);

    // NO PART OF A NAME CONTAINS A COMMA, and that is the whole rule here.
    //
    // The label row on a driver's licence is small grey print, and on the real
    // card ML Kit recovered only the words "Last Name" from it. The surname
    // lookup then found its label, took the row beneath as the value, and
    // stored the entire name — "SALUT, KURT MICHAEL SENO" — as the surname,
    // with the first and middle name boxes left empty for the person to fill
    // in themselves. Everything downstream believed it: the review screen, the
    // surname check against the card, and the administrator reading the queue.
    //
    // A comma inside a value that is supposed to be ONE part is the card
    // telling us the box was never one part. So it is re-read as a whole name
    // printed surname-first, which is what it is.
    //
    // Only when it is the sole part we found. If the card gave up a separate
    // given name as well, then the labels really did work and they are better
    // evidence than this inference.
    final found = [last, given, middle].nonNulls.toList();
    if (found.length == 1 && found.first.contains(',')) {
      final split = _splitWholeName(found.first);
      if (split != null) {
        return (
          first: split.first,
          middle: split.middle,
          last: split.last,
          suffix: split.suffix,
          confidence: ReadConfidence.labelled,
        );
      }
    }

    if (last != null || given != null) {
      final parts = _splitGiven(given);
      return (
        first: parts.first,
        middle: _titleCase(middle) ?? parts.middle,
        last: _titleCase(last),
        suffix: parts.suffix,
        confidence: ReadConfidence.labelled,
      );
    }

    // 3. One box for the whole name — how most barangay and LGU cards print
    //    it. Still labelled, so still trustworthy; only the split into parts
    //    is by convention.
    final whole = _wholeName(lines);
    if (whole != null) {
      final split = _splitWholeName(whole);
      if (split != null) {
        return (
          first: split.first,
          middle: split.middle,
          last: split.last,
          suffix: split.suffix,
          confidence: ReadConfidence.labelled,
        );
      }
    }

    // 4. Nothing labelled anywhere. Fall back to the shape of the text, and
    //    say out loud that this one is a guess.
    final guess = _guessNameLine(lines);
    if (guess == null) {
      return (
        first: null,
        middle: null,
        last: null,
        suffix: null,
        confidence: null,
      );
    }
    return (
      first: guess.first,
      middle: guess.middle,
      last: guess.last,
      suffix: guess.suffix,
      confidence: ReadConfidence.guessed,
    );
  }

  /// A header row naming several parts at once, with the values beneath it.
  ///
  ///     Last Name, First Name, Middle Name
  ///     DELA CRUZ, JUAN, SANTOS
  ///
  /// The header's own left-to-right order decides which value is which, so a
  /// card that prints "First Name, Last Name" is read correctly rather than
  /// backwards. Returns null unless the value row has as many comma-separated
  /// parts as the header named — a partial match is a worse answer than
  /// letting the ordinary per-part search try.
  static ({String? first, String? middle, String? last, String? suffix})?
  _combinedHeader(List<String> lines) {
    for (var i = 0; i < lines.length - 1; i++) {
      final lower = lines[i].toLowerCase();

      // Where each family's label appears, with overlapping matches already
      // collapsed — 'gitnang apelyido' contains 'apelyido', so a header
      // naming only the middle name must not look like it named the surname
      // as well. See _labelSpans.
      final spans = _labelSpans(lower);
      if (spans.length < 2) continue;

      final order =
          spans.keys.toList()
            ..sort((a, b) => spans[a]!.$1.compareTo(spans[b]!.$1));

      // The value row: the next line that reads as a name.
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final value = _cleanNameValue(lines[j]);
        if (value == null) continue;
        final parts =
            value
                .split(',')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList();
        // The Philippine driver's licence prints a three-part header over a
        // value with ONE comma in it:
        //
        //     Last Name. First Name. Middle Name
        //     SALUT, KURT MICHAEL SENO
        //
        // The comma separates the surname from everything else; the middle
        // name is not its own group. It is the LAST word of the remainder,
        // because on a Philippine document the middle name is the mother's
        // maiden surname and is printed last. The header is what licenses
        // that reading — it says a middle name is present, so the trailing
        // word is one rather than a second given name.
        if (parts.length == 2 && order.length == 3 && order.first == 'last') {
          final rest = _splitTrailingMiddle(parts[1]);
          return (
            first: rest.first,
            middle: rest.middle,
            last: _titleCase(parts[0]),
            suffix: rest.suffix,
          );
        }
        if (parts.length != order.length) return null;

        final byKey = {
          for (var k = 0; k < order.length; k++) order[k]: parts[k],
        };
        final given = _splitGiven(byKey['first']);
        return (
          first: given.first,
          middle: _titleCase(byKey['middle']) ?? given.middle,
          last: _titleCase(byKey['last']),
          suffix: given.suffix,
        );
      }
    }
    return null;
  }

  /// The value beside a single whole-name label.
  static String? _wholeName(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      // Skip a line that names a PART — those were handled above, and 'name'
      // matches inside every one of them.
      if ([
        ..._surnameLabels,
        ..._givenLabels,
        ..._middleLabels,
      ].any(lower.contains)) {
        continue;
      }
      final label = _wholeNameLabels
          .where(lower.contains)
          .fold<String?>(
            null,
            (best, l) => best == null || l.length > best.length ? l : best,
          );
      if (label == null) continue;

      final at = lower.lastIndexOf(label);
      final inline = _cleanNameValue(lines[i].substring(at + label.length));
      if (inline != null) return inline;

      for (var j = i + 1; j < lines.length && j <= i + 1; j++) {
        final below = _cleanNameValue(lines[j]);
        if (below != null) return below;
      }
    }
    return null;
  }

  /// The value printed beside or beneath one of [labels].
  ///
  /// Cards do both. A driver's licence prints "Last Name, First Name, Middle
  /// Name" as a header with the values on the row below; a barangay ID prints
  /// "Name: JUAN DELA CRUZ" inline. Both are handled, inline first, because
  /// an inline value is unambiguous and a following line is a guess about
  /// layout.
  static String? _valueFor(
    List<String> lines,
    List<String> labels, {
    List<String> skip = const [],
  }) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (skip.any(lower.contains)) continue;
      // A row naming several parts at once belongs to _combinedHeader. Read
      // here it would hand the whole value row back for each part in turn,
      // so the surname, the given name and the middle name would all come
      // out as "SALUT, KURT MICHAEL SENO".
      if (_namesSeveralParts(lower)) continue;

      // Longest matching label, so "given names" wins over "given name" and
      // the tail is not left starting with a stray "s".
      final label = labels
          .where(lower.contains)
          .fold<String?>(
            null,
            (best, l) => best == null || l.length > best.length ? l : best,
          );
      if (label == null) continue;

      final at = lower.lastIndexOf(label);
      final inline = _cleanNameValue(lines[i].substring(at + label.length));
      if (inline != null) return inline;

      // Beneath: the next line or two. Two rather than one because a card
      // sometimes prints the Filipino and English labels on separate rows
      // before the value.
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final below = _cleanNameValue(lines[j]);
        if (below != null) return below;
      }
    }
    return null;
  }

  /// Where each part of the name is labelled on one line, as spans.
  ///
  /// SPANS RATHER THAN A COUNT, because the label vocabularies overlap.
  /// A PhilSys card prints
  ///
  ///     GITNANG APELYIDO/Middle Name
  ///
  /// and 'apelyido' — the surname label — sits INSIDE 'gitnang apelyido'.
  /// Counting matches called that line a two-part header and skipped it,
  /// which lost the middle name on every national ID. A family whose span
  /// falls inside another's is the same printed words being matched twice.
  static Map<String, (int, int)> _labelSpans(String lower) {
    final spans = <String, (int, int)>{};
    for (final (key, labels) in [
      ('last', _surnameLabels),
      ('first', _givenLabels),
      ('middle', _middleLabels),
    ]) {
      // Longest match wins, so 'gitnang apelyido' beats 'apelyido' and the
      // span covers the whole printed label.
      String? found;
      for (final label in labels) {
        if (!lower.contains(label)) continue;
        if (found == null || label.length > found.length) found = label;
      }
      if (found == null) continue;
      final at = lower.indexOf(found);
      spans[key] = (at, at + found.length);
    }

    // Drop any family whose span is contained in another's.
    return {
      for (final entry in spans.entries)
        if (!spans.entries.any(
          (other) =>
              other.key != entry.key &&
              other.value.$1 <= entry.value.$1 &&
              other.value.$2 >= entry.value.$2 &&
              (other.value.$2 - other.value.$1) >
                  (entry.value.$2 - entry.value.$1),
        ))
          entry.key: entry.value,
    };
  }

  /// Whether one line labels more than one part of the name.
  static bool _namesSeveralParts(String lower) => _labelSpans(lower).length > 1;

  /// Trim a candidate value and reject it if it is not a name.
  static String? _cleanNameValue(String raw) {
    // Strip a separator left over from "APELYIDO/Last Name:".
    final s = raw.trim().replaceFirst(RegExp(r'^[\s:/|.,\-]+'), '').trim();
    if (s.isEmpty) return null;
    if (RegExp(r'[0-9]').hasMatch(s)) return null;
    if (!RegExp(r"^[A-Za-zÑñ' .,\-]+$").hasMatch(s)) return null;
    if (_notName.hasMatch(s)) return null;
    if (s.replaceAll(RegExp(r'[^A-Za-zÑñ]'), '').length < 2) return null;
    return s;
  }

  /// Split a given-names value into first name, middle name and suffix.
  static ({String? first, String? middle, String? suffix}) _splitGiven(
    String? given,
  ) {
    if (given == null) return (first: null, middle: null, suffix: null);

    final words =
        given
            .replaceAll(',', ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.trim().isNotEmpty)
            .toList();
    if (words.isEmpty) return (first: null, middle: null, suffix: null);

    String? suffix;
    if (words.length > 1) {
      final tail = words.last.replaceAll('.', '').toLowerCase();
      if (_suffixes.contains(tail)) suffix = _titleCase(words.removeLast());
    }
    if (words.isEmpty) return (first: null, middle: null, suffix: suffix);

    final first = _titleCase(words.first);
    final middle =
        words.length > 1 ? _titleCase(words.sublist(1).join(' ')) : null;
    return (first: first, middle: middle, suffix: suffix);
  }

  /// Split given-names-plus-middle where the middle name comes LAST.
  ///
  /// "KURT MICHAEL SENO" is Kurt Michael, middle name Seno — not Kurt,
  /// middle name Michael Seno. Only used where a header has said a middle
  /// name is present without giving it a column of its own; a card with a
  /// separate middle-name box is read from that box instead.
  static ({String? first, String? middle, String? suffix}) _splitTrailingMiddle(
    String value,
  ) {
    final words =
        value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return (first: null, middle: null, suffix: null);

    String? suffix;
    if (words.length > 2) {
      final tail = words.last.replaceAll('.', '').toLowerCase();
      if (_suffixes.contains(tail)) suffix = _titleCase(words.removeLast());
    }
    // One word is a given name, not a middle name.
    if (words.length < 2) {
      return (
        first: _titleCase(words.firstOrNull),
        middle: null,
        suffix: suffix,
      );
    }
    final middle = _titleCase(words.removeLast());
    return (first: _titleCase(words.join(' ')), middle: middle, suffix: suffix);
  }

  /// No labels anywhere: pick the line that looks most like a printed name.
  ///
  /// A GUESS, and reported as one. The rule is the longest line made only of
  /// name characters, two to five words, carrying none of the boilerplate
  /// above. On the LGU-issued cards this exists for it is right most of the
  /// time; when it is wrong the person retypes one field, which is what they
  /// would have done for every field before this existed.
  static ({String? first, String? middle, String? last, String? suffix})?
  _guessNameLine(List<String> lines) {
    String? best;
    var bestScore = double.negativeInfinity;

    for (var i = 0; i < lines.length; i++) {
      final value = _cleanNameValue(lines[i]);
      if (value == null) continue;
      final words = value.split(RegExp(r'[\s,]+')).where((w) => w.length > 1);
      if (words.length < 2 || words.length > 5) continue;
      if (value.length < 5 || value.length > 40) continue;

      // LENGTH IS NO LONGER THE RULE, and that is the fix.
      //
      // It used to be "the longest name-shaped line wins", which loses to
      // the address on every card that prints one, and loses to the
      // signing official once the address is excluded. Both are longer
      // than a person's name and neither is one.
      var score = 0.0;
      // A comma is the card telling us where the surname ends. Cards print
      // the holder's name that way; they do not print addresses or
      // signatories that way.
      if (value.contains(',')) score += 30;
      // The holder's name is at the top; the signature block is at the
      // bottom. Weak on its own — ML Kit's block order is only roughly
      // visual — so it is worth a few points, not the decision.
      score += (1 - i / lines.length) * 10;
      // Printed beside a signature line. That is somebody attesting to the
      // card, not the person it was issued to.
      if (_nearSignature(lines, i)) score -= 40;
      // Length still breaks ties, and is capped so it cannot outweigh any
      // of the above.
      score += value.length.clamp(0, 30) * 0.3;

      if (score > bestScore) {
        bestScore = score;
        best = value;
      }
    }
    if (best == null) return null;
    return _splitWholeName(best);
  }

  static final _signatureWord = RegExp(
    r'\b(signature|signed|secretary|administrator|authorized|authorised|'
    r'licensee|issuing|officer|chairman|punong)\b',
    caseSensitive: false,
  );

  /// Whether the line before or after [i] is part of a signature block.
  static bool _nearSignature(List<String> lines, int i) {
    for (var j = i - 1; j <= i + 1; j++) {
      if (j < 0 || j >= lines.length || j == i) continue;
      if (_signatureWord.hasMatch(lines[j])) return true;
    }
    return false;
  }

  /// Split a whole printed name into parts.
  ///
  /// Two conventions, and the card usually tells us which one it is using.
  ///
  ///   "DELA CRUZ, JUAN SANTOS"  — the comma marks where the surname ends,
  ///                               and it is the only fully reliable
  ///                               separator on a card with no labels.
  ///   "JUAN SANTOS DELA CRUZ"   — no comma, so the Philippine convention of
  ///                               given-names-first is assumed.
  ///
  /// The second is a genuine guess. A two-word surname ("DELA CRUZ") printed
  /// without a comma is read as a middle name plus a surname, which is wrong
  /// and is exactly why the field it lands in stays editable with the card
  /// still on screen beside it.
  static ({String? first, String? middle, String? last, String? suffix})?
  _splitWholeName(String value) {
    if (value.contains(',')) {
      final parts = value.split(',');
      // The remainder is "GIVEN NAMES MIDDLE NAME", with the middle name last.
      //
      // On a Philippine ID the surname-first comma form always means
      // SURNAME, GIVEN-NAMES MIDDLE-NAME — the middle name is the mother's
      // maiden surname and is printed at the end. So "SALUT, KURT MICHAEL
      // SENO" is Kurt Michael, middle name Seno; reading it the other way
      // round gives a first name of Kurt and a middle name of Michael Seno,
      // which is wrong on every card that prints two given names.
      //
      // With only one word after the comma there is no middle name to take,
      // and _splitTrailingMiddle leaves it as the given name.
      final rest = _splitTrailingMiddle(parts.sublist(1).join(' ').trim());
      final last = _titleCase(parts.first.trim());
      if (last == null) return null;
      return (
        first: rest.first,
        middle: rest.middle,
        last: last,
        suffix: rest.suffix,
      );
    }

    final words =
        value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    String? suffix;
    if (words.length > 2) {
      final tail = words.last.replaceAll('.', '').toLowerCase();
      if (_suffixes.contains(tail)) suffix = _titleCase(words.removeLast());
    }
    if (words.length < 2) return null;

    final last = _titleCase(words.removeLast());
    final first = _titleCase(words.first);
    final middle =
        words.length > 1 ? _titleCase(words.sublist(1).join(' ')) : null;
    return (first: first, middle: middle, last: last, suffix: suffix);
  }

  /// Cards print names in capitals. A form field full of capitals reads as
  /// shouting and is harder to compare against a card at a glance, so it is
  /// normalised — but only when the whole value is upper case, so a card that
  /// printed "de la Cruz" keeps its own capitalisation.
  static String? _titleCase(String? s) {
    if (s == null) return null;
    final trimmed = s.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed != trimmed.toUpperCase()) return trimmed;
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (w) =>
              w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  // ── Column layouts ──────────────────────────────────────────
  //
  // A licence prints its middle band as a GRID:
  //
  //     Nationality   Sex   Date of Birth   Weight (kg)   Height(m)
  //     PHL           M     2005/07/31      51            1.68
  //
  // and ML Kit returns that as ten separate lines — five labels, then five
  // values. So the value belonging to "Date of Birth" is FIVE lines below
  // it, not one, and every reader here that looked at `lines[i + 1]` found
  // the next label instead and gave up. On the real card that silently cost
  // the date of birth and the sex, which are two of the five things the
  // scan exists to fill in.
  //
  // The fix reads the grid as a grid: find the run of label-only lines this
  // label belongs to, note which column it is, and take the same column
  // from the row of values that follows. Where there is no run — a label
  // with its value directly underneath — the run is one line long and this
  // degenerates to exactly the old behaviour.

  /// Field labels a card prints with the value somewhere else.
  static const _fieldLabelPhrases = [
    'nationality',
    'citizenship',
    'sex',
    'kasarian',
    'gender',
    'date of birth',
    'birth date',
    'birthdate',
    'kapanganakan',
    'place of birth',
    'weight',
    'height',
    'address',
    'tirahan',
    'license no',
    'licence no',
    'expiration date',
    'expiry date',
    'agency code',
    'blood type',
    'eyes color',
    'eye color',
    'eyes colour',
    'dl codes',
    'conditions',
    'restrictions',
    'restriction',
    'civil status',
    'precinct',
    'signature',
    'valid until',
    'valid thru',
    'control no',
    'id no',
    'serial no',
    'reference no',
    'surname',
    'last name',
    'given names',
    'given name',
    'first name',
    'middle name',
    'apelyido',
    'pangalan',
    'agency',
    'issued on',
    'date issued',
  ];

  /// Whether a line is a bare column heading with no value on it.
  ///
  /// A unit in brackets is still a heading: "Weight (kg)" and "Height(m)"
  /// name a column, they do not carry a reading.
  static bool _isLabelOnly(String line) {
    final lower = line.toLowerCase();
    final phrase = _fieldLabelPhrases
        .where(lower.contains)
        .fold<String?>(
          null,
          (best, l) => best == null || l.length > best.length ? l : best,
        );
    if (phrase == null) return false;
    final rest = lower
        .replaceFirst(phrase, ' ')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    // Anything longer than a unit abbreviation means the value is inline,
    // and this line is a label-plus-value rather than a column heading.
    return rest.length <= 2;
  }

  /// The value under the label on line [i], read as a column.
  static String? _columnValue(List<String> lines, int i) {
    if (!_isLabelOnly(lines[i])) return null;

    var start = i;
    while (start > 0 && _isLabelOnly(lines[start - 1])) {
      start--;
    }
    var end = i;
    while (end + 1 < lines.length && _isLabelOnly(lines[end + 1])) {
      end++;
    }

    final column = i - start;
    final at = end + 1 + column;
    if (at >= lines.length) return null;
    // The values must not themselves be labels — that would mean the run
    // was cut short and this is another heading, not a reading.
    if (_isLabelOnly(lines[at])) return null;
    return lines[at];
  }

  /// Every line that could hold the value for the label on line [i]:
  /// the label's own line, its column value, then the next line or two.
  static List<String> _valueLines(List<String> lines, int i) {
    final out = <String>[lines[i]];
    final column = _columnValue(lines, i);
    if (column != null) out.add(column);
    for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
      out.add(lines[j]);
    }
    return out;
  }

  // ── Date of birth ───────────────────────────────────────────

  static const _dobLabels = [
    'date of birth',
    'birth date',
    'birthdate',
    'birthday',
    'petsa ng kapanganakan',
    'kapanganakan',
    'dob',
  ];

  static DateTime? _readDateOfBirth(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (!_dobLabels.any(lower.contains)) continue;
      for (final candidate in _valueLines(lines, i)) {
        final parsed = parseDate(candidate);
        if (parsed != null && _plausibleBirthday(parsed)) return parsed;
      }
    }
    return null;
  }

  /// A birthday has to be in the past and belong to someone old enough to be
  /// registering. Without this an OCR misread of an expiry date lands in the
  /// date-of-birth field, where it is a plausible-looking wrong answer that
  /// nobody re-reads.
  static bool _plausibleBirthday(DateTime d) {
    final age = DateTime.now().difference(d).inDays / 365.25;
    return age >= 5 && age <= 110;
  }

  // ── Sex ─────────────────────────────────────────────────────

  static const _sexLabels = ['sex', 'kasarian', 'gender'];

  static String? _readSex(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      final label = _sexLabels.firstWhere(
        (l) => RegExp('\\b$l\\b').hasMatch(lower),
        orElse: () => '',
      );
      if (label.isEmpty) continue;

      final after = lower.substring(lower.indexOf(label) + label.length);
      var value = _sexFrom(after);
      if (value == null) {
        final column = _columnValue(lines, i);
        if (column != null) value = _sexFrom(column.toLowerCase());
      }
      value ??= _sexFrom(
        i + 1 < lines.length ? lines[i + 1].toLowerCase() : '',
      );
      if (value != null) return value;
    }
    return null;
  }

  /// The first sex-shaped word in [text].
  ///
  /// Whole words only. A bare "M" or "F" is accepted because that is what
  /// most cards print, but only as a standalone token — otherwise the M in
  /// "MARRIED", two fields further along the same row, would decide somebody's
  /// sex for them.
  static String? _sexFrom(String text) {
    for (final word in text.split(RegExp(r'[^a-z]+'))) {
      if (word.isEmpty) continue;
      if (word == 'm' || word == 'male' || word == 'lalaki') return 'male';
      if (word == 'f' || word == 'female' || word == 'babae') return 'female';
    }
    return null;
  }

  // ── Address ─────────────────────────────────────────────────

  static const _addressLabels = ['address', 'tirahan', 'residence'];

  static String? _readAddress(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      final label = _addressLabels
          .where(lower.contains)
          .fold<String?>(
            null,
            (best, l) => best == null || l.length > best.length ? l : best,
          );
      if (label == null) continue;

      final parts = <String>[];
      final inline =
          lines[i]
              .substring(lower.lastIndexOf(label) + label.length)
              .replaceFirst(RegExp(r'^[\s:/|.,\-]+'), '')
              .trim();
      if (inline.length > 2) parts.add(inline);

      // Address blocks wrap. Take up to two following lines, stopping at the
      // next label — otherwise the date of birth ends up in the address.
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        if (_isLabelLine(lines[j])) break;
        if (lines[j].trim().length > 2) parts.add(lines[j].trim());
      }
      if (parts.isNotEmpty) return parts.join(', ');
    }
    return null;
  }

  static final _anyLabel = RegExp(
    r'\b(sex|kasarian|gender|date of birth|birth|kapanganakan|blood|'
    r'signature|lagda|valid|expiry|expires|issued|weight|height|'
    r'nationality|citizenship|civil status|precinct)\b',
    caseSensitive: false,
  );

  static bool _isLabelLine(String s) => _anyLabel.hasMatch(s);

  // ── Expiry ──────────────────────────────────────────────────

  static const _expiryLabels = [
    'valid until',
    'valid thru',
    'valid through',
    'expiry',
    'expiration',
    'expires',
    'date of expiry',
  ];

  /// An expiry date, if the card prints one near a recognisable label.
  ///
  /// Deliberately label-anchored rather than "find any date". Philippine IDs
  /// print a date of birth and an issue date as well, and picking the wrong
  /// one would report a card as expired the day it was handed over — a claim
  /// that sends a valid resident back to the barangay hall for nothing.
  static DateTime? readExpiry(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (!_expiryLabels.any(lower.contains)) continue;
      for (final candidate in _valueLines(lines, i)) {
        final parsed = parseDate(candidate);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  // ── Dates ───────────────────────────────────────────────────

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Parse the date formats Philippine cards actually print.
  ///
  /// The year alternation is (19|20), not 20 alone. The old version accepted
  /// only 20xx because it was written for expiry dates, and reusing it for a
  /// date of birth would have silently failed for everybody born before 2000
  /// — which is very nearly everybody registering.
  static DateTime? parseDate(String text) {
    // 1985/05/12 or 1985-05-12
    final iso = RegExp(
      r'\b((?:19|20)\d{2})[/\-.](\d{1,2})[/\-.](\d{1,2})\b',
    ).firstMatch(text);
    if (iso != null) {
      return _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    // 05/12/1985 — ambiguous between MM/DD and DD/MM, so it is resolved
    // rather than guessed: if the first field cannot be a month it must be
    // the day. Where both are 12 or less the value is genuinely ambiguous and
    // the Philippine convention (MM/DD, following US practice on most
    // government forms) is used. Worst case this moves a date by a few
    // months, which a person looking at the card can see and this code
    // cannot.
    final slash = RegExp(
      r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.]((?:19|20)\d{2})\b',
    ).firstMatch(text);
    if (slash != null) {
      final a = int.parse(slash.group(1)!);
      final b = int.parse(slash.group(2)!);
      final y = int.parse(slash.group(3)!);
      return a > 12 ? _safeDate(y, b, a) : _safeDate(y, a, b);
    }

    // 12 MAY 1985
    final dmy = RegExp(
      r'\b(\d{1,2})\s+([A-Za-z]{3,})\.?,?\s+((?:19|20)\d{2})\b',
    ).firstMatch(text);
    if (dmy != null) {
      final m = _months[dmy.group(2)!.toLowerCase().substring(0, 3)];
      if (m != null) {
        return _safeDate(int.parse(dmy.group(3)!), m, int.parse(dmy.group(1)!));
      }
    }

    // MAY 12, 1985
    final mdy = RegExp(
      r'\b([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+((?:19|20)\d{2})\b',
    ).firstMatch(text);
    if (mdy != null) {
      final m = _months[mdy.group(1)!.toLowerCase().substring(0, 3)];
      if (m != null) {
        return _safeDate(int.parse(mdy.group(3)!), m, int.parse(mdy.group(2)!));
      }
    }

    return null;
  }

  /// Reject impossible dates instead of letting DateTime roll them over.
  ///
  /// DateTime(2028, 13, 40) is a valid Dart expression that silently means
  /// February 2029 — so an OCR misread of "40" as a day would produce a
  /// confident, wrong date rather than nothing.
  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != m || dt.day != d) return null;
    return dt;
  }

  // ── Shared helpers ──────────────────────────────────────────

  /// Strip the separators a card prints between groups of digits.
  static String strip(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Upper-case, letters only. Cards print names with commas, extra spacing
  /// and occasional accents; none of that should decide whether a name
  /// matched.
  static String normaliseName(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

  /// Does [surname] appear anywhere in the text read off the card?
  ///
  /// Null when there is no surname to compare against — "we did not check"
  /// and "we checked and it was absent" must never collapse into one value on
  /// an admin's screen.
  static bool? surnameAppears(String text, String? surname) {
    if (surname == null || surname.trim().length < 2) return null;
    final needle = normaliseName(surname);
    if (needle.isEmpty) return null;
    return normaliseName(text).contains(needle);
  }
}
