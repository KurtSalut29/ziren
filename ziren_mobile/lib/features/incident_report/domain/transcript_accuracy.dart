/// Word Error Rate between what was said and what the recogniser heard.
///
/// WER is the standard measure for speech recognition, which matters here
/// because the result is going in a thesis: it is a number a panel can check
/// against published work, not one invented for this project.
///
///     WER = (substitutions + deletions + insertions) / words in reference
///
/// 0.0 is perfect. It can exceed 1.0 when the recogniser produces more words
/// than were spoken — the live sample did exactly that, turning one spoken
/// "Caibiran" into "kaibigan kaibigan".
///
/// Read it alongside the transcript, never on its own. The recorded Waray
/// sample scores badly while getting every word that decides severity right,
/// because the errors landed on a place name the app takes from GPS anyway.
/// A single number cannot see that; a person reading both columns can.
class TranscriptAccuracy {
  const TranscriptAccuracy._();

  /// Compare [heard] against [said]. Case and punctuation are ignored — a
  /// recogniser that omits a comma has not misheard anything.
  static WerResult compare({required String said, required String heard}) {
    final ref = _tokenise(said);
    final hyp = _tokenise(heard);

    if (ref.isEmpty) {
      return WerResult(
        substitutions: 0,
        deletions: 0,
        insertions: hyp.length,
        referenceWords: 0,
        correct: 0,
      );
    }

    // Levenshtein over words, tracking which operation each step took.
    final rows = ref.length + 1;
    final cols = hyp.length + 1;
    final dist = List.generate(rows, (_) => List<int>.filled(cols, 0));
    for (var i = 0; i < rows; i++) {
      dist[i][0] = i;
    }
    for (var j = 0; j < cols; j++) {
      dist[0][j] = j;
    }

    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final cost = ref[i - 1] == hyp[j - 1] ? 0 : 1;
        dist[i][j] = [
          dist[i - 1][j] + 1, // deletion
          dist[i][j - 1] + 1, // insertion
          dist[i - 1][j - 1] + cost, // substitution or match
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    // Walk back to count each operation separately. The totals matter more
    // than the score: deletions mean words were lost, insertions mean words
    // were invented, and those call for different fixes.
    var i = ref.length;
    var j = hyp.length;
    var subs = 0, dels = 0, ins = 0, correct = 0;

    while (i > 0 || j > 0) {
      if (i > 0 &&
          j > 0 &&
          dist[i][j] ==
              dist[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1)) {
        if (ref[i - 1] == hyp[j - 1]) {
          correct++;
        } else {
          subs++;
        }
        i--;
        j--;
      } else if (i > 0 && dist[i][j] == dist[i - 1][j] + 1) {
        dels++;
        i--;
      } else {
        ins++;
        j--;
      }
    }

    return WerResult(
      substitutions: subs,
      deletions: dels,
      insertions: ins,
      referenceWords: ref.length,
      correct: correct,
    );
  }

  /// Which reference words survived, so the tester can see *what* was lost
  /// rather than only how much. `sunog` surviving and `Caibiran` not is the
  /// whole finding in the recorded sample.
  static List<WordOutcome> wordOutcomes({
    required String said,
    required String heard,
  }) {
    final hyp = _tokenise(heard).toSet();
    return [
      for (final w in _tokenise(said))
        WordOutcome(word: w, heard: hyp.contains(w)),
    ];
  }

  static List<String> _tokenise(String s) =>
      s
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s'\-]"), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
}

class WerResult {
  const WerResult({
    required this.substitutions,
    required this.deletions,
    required this.insertions,
    required this.referenceWords,
    required this.correct,
  });

  final int substitutions;
  final int deletions;
  final int insertions;
  final int referenceWords;
  final int correct;

  int get errors => substitutions + deletions + insertions;

  /// 0.0 = perfect. May exceed 1.0 when words are invented.
  double get wer => referenceWords == 0 ? 0 : errors / referenceWords;

  /// The friendlier direction, clamped so an over-producing recogniser reads
  /// as 0% rather than as a negative.
  double get accuracy => (1 - wer).clamp(0.0, 1.0);

  String get summary =>
      'WER ${(wer * 100).toStringAsFixed(0)}% · '
      '$correct/$referenceWords correct · '
      '${substitutions}S ${deletions}D ${insertions}I';
}

class WordOutcome {
  const WordOutcome({required this.word, required this.heard});

  final String word;
  final bool heard;
}
