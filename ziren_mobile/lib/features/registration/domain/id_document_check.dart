/// Is the photographed thing an ID at all - and is it the ID that was chosen?
///
/// PURE DART. It works on the text lines ML Kit read off the photo, so every
/// rule here runs in a unit test on a laptop (test/id_document_check_test.dart)
/// and the recorded card reads there are real ones.
///
/// WHY THIS EXISTS
/// ---------------
/// The ID step used to accept a photo that had SOME text, ANY face and a
/// number-shaped token. A selfie in front of a curtain clears all three, and
/// testers uploaded exactly that as a "Voter's ID" and were told "ID photo
/// accepted". Nothing asked the one question that matters: does this carry the
/// wording a real card of the CHOSEN type prints?
///
/// Every Philippine ID names its issuer somewhere on its face - "LAND
/// TRANSPORTATION OFFICE", "PASAPORTE", "COMMISSION ON ELECTIONS" - so that
/// wording is the evidence. A selfie has none of it. A driver's licence
/// uploaded under "Passport" has the wrong one, and is refused for that.
///
/// The verdict is deliberately not "genuine": a human still decides that. It is
/// only "this is an ID of this type", which is what a person can be asked to fix
/// on the spot instead of an admin discovering it three days later.
library;

/// How the photo stands against the ID type that was chosen.
enum IdDocVerdict {
  /// Carries the chosen type's own wording (or, for a type that has no fixed
  /// template, plainly is an ID).
  matches,

  /// A real ID - but of a different type than the one chosen.
  wrongType,

  /// Looks like an ID, yet nothing on it proves it is the chosen type. Only
  /// returned for types that DO have fixed wording, where its absence is the
  /// answer.
  typeUnconfirmed,

  /// No ID wording at all: a face, a wall, a receipt, a screenshot.
  notAnId,
}

class IdDocCheck {
  const IdDocCheck(this.verdict, {this.foundType, this.genericHits = 0});

  final IdDocVerdict verdict;

  /// The `valid_id_type` the photo looks like, when one was recognised. For
  /// [IdDocVerdict.wrongType] this is what to tell the person it looks like.
  final String? foundType;

  /// How many generic ID field labels (Date of Birth, Signature, ...) were
  /// found, for diagnostics.
  final int genericHits;

  bool get isAcceptable => verdict == IdDocVerdict.matches;
}

/// The evidence one ID type is recognised by.
///
/// [strong] is issuer wording that only that card prints: one hit settles it.
/// [support] is weaker on its own (a field label the card shares with others),
/// so two are needed. Everything is written squashed - lower case, letters and
/// digits only - because that is the form it is matched in.
class _TypeEvidence {
  const _TypeEvidence({
    this.strong = const [],
    this.support = const [],
    this.strongWords = const [],
    this.supportWords = const [],
    this.strongPattern,
    this.supportPattern,
  });

  final List<String> strong;
  final List<String> support;

  /// Short tokens (acronyms) matched as whole words in the spaced text; in
  /// squashed text "osca" would be found inside any longer word.
  final List<String> strongWords;
  final List<String> supportWords;

  /// A structural pattern on the RAW text (a number's shape, a passport's
  /// machine-readable line).
  final RegExp? strongPattern;
  final RegExp? supportPattern;
}

abstract final class IdDocumentClassifier {
  /// The types whose cards are issued by a local government office to its own
  /// format. There is no fixed template to demand, so wording that proves the
  /// type is welcome but its absence on an otherwise ID-like card is not a
  /// reason to refuse it - see [classify].
  static const lguIssued = {'barangay_id', 'pwd_id', 'senior_citizen_id'};

  static final Map<String, _TypeEvidence> _evidence = {
    'drivers_license': _TypeEvidence(
      strong: [
        'driverslicense',
        'driverslicence',
        'landtransportationoffice',
        'dlcodes',
        'signatureoflicensee',
      ],
      support: ['departmentoftransportation', 'licenseno', 'agencycode'],
      // N01-23-456789. OCR reads the zeros as O often enough to allow it.
      supportPattern: RegExp(r'\b[A-Z][0-9O]{2}-[0-9O]{2}-[0-9O]{6}\b'),
    ),
    'passport': _TypeEvidence(
      strong: ['pasaporte', 'passport', 'kodigongbansa'],
      support: ['countrycode', 'departmentofforeignaffairs', 'issuingauthority'],
      supportWords: ['dfa'],
      // The machine-readable line at the foot of the data page:
      // P<PHLSURNAME<<GIVEN<NAMES<<<<...  ML Kit often reads "<" as K or C.
      strongPattern: RegExp(r'P\s*[<KC«]\s*PHL|PHL[A-Z]{3,}[<KC]{2}'),
    ),
    'philsys': _TypeEvidence(
      strong: [
        'philsys',
        'philippineidentificationcard',
        'pambansangpagkakakilanlan',
        'philippineidentificationsystem',
        'philid',
      ],
      support: ['philippinestatisticsauthority'],
      supportWords: ['pcn'],
      supportPattern: RegExp(r'\b\d{4}[- ]\d{4}[- ]\d{4}[- ]\d{4}\b'),
    ),
    'umid': _TypeEvidence(
      strong: ['unifiedmultipurposeid', 'unifiedmultipurpose'],
      strongWords: ['umid'],
      supportWords: ['crn'],
      supportPattern: RegExp(r'\b\d{4}-\d{7}-\d\b'),
    ),
    'postal_id': _TypeEvidence(
      strong: [
        'postalidentitycard',
        'postalidentity',
        'postalid',
        'philippinepostalcorporation',
        'phlpost',
        'philpost',
      ],
      supportWords: ['prn'],
    ),
    'philhealth': _TypeEvidence(
      strong: ['philhealth', 'philippinehealthinsurancecorporation'],
    ),
    'sss': _TypeEvidence(
      strong: ['socialsecuritysystem', 'sssid', 'ssnumber'],
      supportWords: ['sss'],
    ),
    'tin': _TypeEvidence(
      strong: [
        'bureauofinternalrevenue',
        'taxpayeridentification',
        'taxidentificationnumber',
        'tinid',
      ],
      supportWords: ['tin'],
    ),
    'voters_id': _TypeEvidence(
      strong: [
        'commissiononelections',
        'comelec',
        'votersidentification',
        'votersid',
      ],
      support: ['precinct'],
      supportWords: ['voter', 'voters'],
    ),
    'pwd_id': _TypeEvidence(
      strong: [
        'personwithdisability',
        'personswithdisability',
        'nationalcouncilondisabilityaffairs',
        'republicact7277',
        'republicact10754',
        'pwdid',
      ],
      strongWords: ['pdao', 'ncda'],
      support: ['disability', 'mswdo'],
      supportWords: ['pwd'],
    ),
    'senior_citizen_id': _TypeEvidence(
      strong: [
        'seniorcitizen',
        'officeofseniorcitizens',
        'officeforseniorcitizens',
        'republicact9994',
      ],
      strongWords: ['osca'],
      support: ['senior'],
    ),
    'barangay_id': _TypeEvidence(
      strong: [
        'barangayid',
        'barangayidentification',
        'barangayclearance',
        'barangaycertification',
        'barangaycertificate',
        'punongbarangay',
        'barangaycaptain',
        'barangaychairman',
        'officeofthebarangay',
      ],
      // "barangay" is in the ADDRESS block of almost every other card, so it
      // counts only alongside another word a barangay-issued card prints.
      support: [
        'barangay',
        'resident',
        'residency',
        'kagawad',
        'thisistocertify',
      ],
      supportWords: ['brgy'],
    ),
  };

  /// Labels printed on ID cards generally. Not specific to any type - they say
  /// "this is an identity card", not which one.
  static const _genericPhrases = [
    'republicofthephilippines',
    'republikangpilipinas',
    'republikaphilippines',
    'dateofbirth',
    'birthdate',
    'petsangkapanganakan',
    'validuntil',
    'validthru',
    'expirationdate',
    'expirydate',
    'dateissued',
    'issuedon',
    'idnumber',
    'idno',
    'nationality',
    'citizenship',
    'surname',
    'lastname',
    'givenname',
    'firstname',
    'middlename',
    'apelyido',
    'bloodtype',
    'civilstatus',
    'signature',
    'lagda',
    'tirahan',
  ];
  static const _genericWords = ['sex', 'address', 'kasarian', 'dob'];

  /// How many generic labels make a photo "an ID of some kind".
  static const _genericNeeded = 3;

  /// Judge [lines] against the ID type the person chose.
  ///
  /// [declaredType] may be null when no type has been chosen yet (the Verify
  /// screen lets the photo be taken first); then the only question answered is
  /// "is this an ID at all".
  static IdDocCheck classify(List<String> lines, {String? declaredType}) {
    final spaced =
        lines
            .join(' ')
            .toLowerCase()
            .replaceAll(RegExp(r"[^a-z0-9<\s]"), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final squashed = spaced.replaceAll(' ', '');
    final raw = lines.join('\n').toUpperCase();

    final confirmed = <String, int>{}; // type -> evidence weight
    for (final entry in _evidence.entries) {
      final w = _weight(entry.value, squashed, spaced, raw);
      if (w != null) confirmed[entry.key] = w;
    }

    var generic = 0;
    for (final p in _genericPhrases) {
      if (_fuzzyContains(squashed, p)) generic++;
    }
    for (final w in _genericWords) {
      if (RegExp('\\b$w\\b').hasMatch(spaced)) generic++;
    }

    // "barangay" is in the address of nearly every card, so a national ID's own
    // wording always outranks a barangay-issued reading of the same text.
    final national = {
      for (final e in confirmed.entries)
        if (e.key != 'barangay_id') e.key: e.value,
    };
    final pool = national.isNotEmpty ? national : confirmed;

    String? best;
    var bestWeight = -1;
    for (final e in pool.entries) {
      if (e.key == declaredType) continue;
      if (e.value > bestWeight) {
        best = e.key;
        bestWeight = e.value;
      }
    }

    if (declaredType == null) {
      final anyType = confirmed.isEmpty ? null : _top(pool);
      if (anyType != null || generic >= _genericNeeded) {
        return IdDocCheck(
          IdDocVerdict.matches,
          foundType: anyType,
          genericHits: generic,
        );
      }
      return IdDocCheck(IdDocVerdict.notAnId, genericHits: generic);
    }

    if (confirmed.containsKey(declaredType)) {
      return IdDocCheck(
        IdDocVerdict.matches,
        foundType: declaredType,
        genericHits: generic,
      );
    }
    // The UMID is issued by the SSS (and is the SSS ID today), so a UMID is an
    // SSS ID and must not be refused as one.
    if (declaredType == 'sss' && confirmed.containsKey('umid')) {
      return IdDocCheck(
        IdDocVerdict.matches,
        foundType: 'umid',
        genericHits: generic,
      );
    }

    if (best != null) {
      return IdDocCheck(
        IdDocVerdict.wrongType,
        foundType: best,
        genericHits: generic,
      );
    }

    if (generic >= _genericNeeded) {
      // A barangay / PWD / senior card is printed by each local office to its
      // own layout, so there is no wording to demand: an ID-shaped card is
      // taken and an admin judges the rest. Every other type has fixed wording,
      // so its absence is the answer.
      return IdDocCheck(
        lguIssued.contains(declaredType)
            ? IdDocVerdict.matches
            : IdDocVerdict.typeUnconfirmed,
        genericHits: generic,
      );
    }
    return IdDocCheck(IdDocVerdict.notAnId, genericHits: generic);
  }

  static String? _top(Map<String, int> pool) {
    String? best;
    var w = -1;
    for (final e in pool.entries) {
      if (e.value > w) {
        best = e.key;
        w = e.value;
      }
    }
    return best;
  }

  /// The evidence weight for one type, or null when it is not confirmed.
  ///
  /// Confirmed = one strong hit, or two supporting ones. The weight ranks
  /// competing readings of the same text: strong hits count for far more.
  static int? _weight(
    _TypeEvidence e,
    String squashed,
    String spaced,
    String raw,
  ) {
    var strong = 0;
    var support = 0;
    for (final p in e.strong) {
      if (_fuzzyContains(squashed, p)) strong++;
    }
    for (final w in e.strongWords) {
      if (RegExp('\\b$w\\b').hasMatch(spaced)) strong++;
    }
    if (e.strongPattern != null && e.strongPattern!.hasMatch(raw)) strong++;
    for (final p in e.support) {
      if (_fuzzyContains(squashed, p)) support++;
    }
    for (final w in e.supportWords) {
      if (RegExp('\\b$w\\b').hasMatch(spaced)) support++;
    }
    if (e.supportPattern != null && e.supportPattern!.hasMatch(raw)) {
      support++;
    }
    if (strong >= 1 || support >= 2) return strong * 10 + support;
    return null;
  }

  /// Is [needle] in [haystack], allowing for OCR typos?
  ///
  /// OCR turns "LICENSE" into "LICENCE" and "TRANSPORTATION" into
  /// "TRANSPORTAT1ON" all the time, and refusing a genuine card over one wrong
  /// letter is exactly the false rejection this must not produce. Approximate
  /// substring search (Sellers): the smallest edit distance between the needle
  /// and ANY stretch of the haystack. One edit is allowed per ~7 letters, and
  /// none for short markers, where a single typo could turn one word into
  /// another.
  static bool _fuzzyContains(String haystack, String needle) {
    if (needle.isEmpty) return true;
    if (haystack.contains(needle)) return true;
    final allowed = needle.length < 8 ? 0 : (needle.length / 7).floor();
    if (allowed == 0 || haystack.length < needle.length - allowed) return false;

    var prev = List<int>.generate(needle.length + 1, (i) => i);
    var cur = List<int>.filled(needle.length + 1, 0);
    for (var j = 0; j < haystack.length; j++) {
      cur[0] = 0; // a match may begin anywhere
      final hc = haystack.codeUnitAt(j);
      for (var i = 1; i <= needle.length; i++) {
        final cost = needle.codeUnitAt(i - 1) == hc ? 0 : 1;
        var v = prev[i - 1] + cost;
        if (prev[i] + 1 < v) v = prev[i] + 1;
        if (cur[i - 1] + 1 < v) v = cur[i - 1] + 1;
        cur[i] = v;
      }
      if (cur[needle.length] <= allowed) return true;
      final t = prev;
      prev = cur;
      cur = t;
    }
    return false;
  }
}
