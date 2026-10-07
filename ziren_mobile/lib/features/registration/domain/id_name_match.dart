/// Does the name a person typed match the name printed on their ID?
///
/// Required, not advisory (user request, 2026-10-07): Ziren is an emergency
/// reporting system, a false report sends a crew, and an account has to belong
/// to the person on the card. A registration whose first, middle or last name
/// is not on the ID does not go on; the person is sent back to correct it, or
/// to photograph the card again.
///
/// Matched WORD BY WORD against the words the phone read off the card, not as
/// a run of letters: in "MANALO" the letters A-N-A appear, and "Ana" must not
/// pass because of it. Each word may differ by an OCR slip (one letter in five
/// to nine, two from ten up); a short word must be exact. A name part the card
/// prints as one word ("DELACRUZ") or split ("DELA" "CRUZ") is matched either
/// way. A middle name the card prints only as an initial ("JUAN S. CRUZ")
/// passes on that initial - when the letter sits beside the name, not just
/// anywhere on the card. One TYPED as an initial ("S.") passes only on such a
/// card: where the ID prints it in full, the person types it in full
/// (user request 2026-10-08).
///
/// Pure Dart, so every rule is tested without a phone
/// (test/id_name_match_test.dart).
library;

enum NamePart { first, middle, last }

class IdNameMatch {
  const IdNameMatch(this.missing);

  /// The parts of the typed name that are not on the card.
  final List<NamePart> missing;

  bool get matches => missing.isEmpty;

  static IdNameMatch check({
    required String cardText,
    required String firstName,
    required String middleName,
    required String lastName,
  }) {
    final tokens = words(cardText);
    final anchors = [...words(firstName), ...words(lastName)];
    final middle = words(middleName);
    final bool middleOk;
    if (middle.isEmpty) {
      middleOk = true;
    } else if (isInitialOnly(middleName)) {
      // Typed as "S.": only a card that ALSO prints just the initial, beside
      // the name, carries it. A lone letter anywhere else on the card (the
      // "S" of "DRIVER'S", the "M" under Sex) is not the middle name.
      middleOk = _initialNear(tokens, middle.single, anchors);
    } else {
      middleOk =
          _found(tokens, middleName) ||
          _initialNear(tokens, middle.first[0], anchors);
    }
    final missing = <NamePart>[
      if (!_found(tokens, firstName)) NamePart.first,
      if (!middleOk) NamePart.middle,
      if (!_found(tokens, lastName)) NamePart.last,
    ];
    return IdNameMatch(missing);
  }

  /// For an account that only has its full name (one that verifies later,
  /// from Profile): the words of [fullName] not on the card. A word between the
  /// first and the last may be printed as its initial (a middle name);
  /// suffixes (Jr., III) are not required.
  static List<String> missingFromFullName(String cardText, String fullName) {
    const suffixes = {'JR', 'SR', 'II', 'III', 'IV', 'V'};
    final card = words(cardText);
    final name = words(fullName).where((w) => !suffixes.contains(w)).toList();
    final missing = <String>[];
    for (var i = 0; i < name.length; i++) {
      final w = name[i];
      final inner = i > 0 && i < name.length - 1;
      final others = [...name.take(i), ...name.skip(i + 1)];
      // Same rule as [check]: an initial counts only beside the name.
      final ok =
          w.length == 1
              ? _initialNear(card, w, others)
              : _found(card, w) || (inner && _initialNear(card, w[0], others));
      if (!ok) missing.add(w);
    }
    return name.isEmpty ? const ['?'] : missing;
  }

  /// Only an initial ("S." or "S"): a middle name typed this way does not
  /// match a card that prints it in full, and the person is told to type it
  /// out (user request 2026-10-08: "S." could stand for "Seno").
  static bool isInitialOnly(String s) {
    final w = words(s);
    return w.length == 1 && w.single.length == 1;
  }

  /// Letters only, upper case, accents and ñ folded ("Peña" -> "PENA").
  static List<String> words(String s) {
    final folded = _fold(s.toUpperCase());
    return folded
        .split(RegExp(r'[^A-Z]+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  static String _fold(String s) {
    const from = 'ÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ';
    const to = 'AAAAAEEEEIIIIOOOOOUUUUNC';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i = from.indexOf(c);
      b.write(i < 0 ? c : to[i]);
    }
    return b.toString();
  }

  static bool _found(List<String> card, String part) {
    final want = words(part);
    if (want.isEmpty) return false;
    // Word by word.
    if (want.every((w) => card.any((t) => _close(w, t)))) return true;
    // The card ran the words together, or split them differently.
    final joined = want.join();
    for (var i = 0; i < card.length; i++) {
      var run = '';
      for (var k = i; k < card.length && k < i + want.length + 1; k++) {
        run += card[k];
        if (_close(joined, run)) return true;
        if (run.length > joined.length + 2) break;
      }
    }
    return false;
  }

  /// The one-letter word [letter] on the card, within two words of a word of
  /// the person's own name ([anchors]): "JUAN S. DELA CRUZ", "CRUZ, JUAN S.".
  static bool _initialNear(
    List<String> card,
    String letter,
    List<String> anchors,
  ) {
    for (var i = 0; i < card.length; i++) {
      if (card[i] != letter) continue;
      for (var j = i - 2; j <= i + 2; j++) {
        if (j == i || j < 0 || j >= card.length) continue;
        if (anchors.any((a) => a.length > 1 && _close(a, card[j]))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Equal, allowing for the OCR slips a word of this length can take.
  static bool _close(String a, String b) {
    if (a == b) return true;
    final n = a.length;
    final allowed = n < 5 ? 0 : (n < 10 ? 1 : 2);
    if (allowed == 0) return false;
    if ((a.length - b.length).abs() > allowed) return false;
    return _distance(a, b, allowed) <= allowed;
  }

  static int _distance(String a, String b, int cap) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var best = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < best) best = v;
      }
      if (best > cap) return cap + 1;
      prev = cur;
    }
    return prev[b.length];
  }
}
