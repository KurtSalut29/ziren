import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/features/incident_report/domain/transcript_accuracy.dart';

/// Word Error Rate, checked against the sample recorded on a real handset so
/// the number in the Results chapter can be traced back to something.
void main() {
  group('WER basics', () {
    test('a perfect transcript scores zero', () {
      final r = TranscriptAccuracy.compare(
        said: 'mayda sunog didi ha Caibiran',
        heard: 'mayda sunog didi ha Caibiran',
      );
      expect(r.wer, 0);
      expect(r.errors, 0);
      expect(r.correct, 5);
      expect(r.accuracy, 1.0);
    });

    test('case and punctuation are not errors', () {
      final r = TranscriptAccuracy.compare(
        said: 'Mayda sunog, didi ha Caibiran!',
        heard: 'mayda sunog didi ha caibiran',
      );
      expect(r.wer, 0);
    });

    test('a substitution costs one', () {
      final r = TranscriptAccuracy.compare(
        said: 'mayda sunog',
        heard: 'mayda tubig',
      );
      expect(r.substitutions, 1);
      expect(r.correct, 1);
      expect(r.wer, 0.5);
    });

    test('a dropped word is a deletion', () {
      final r = TranscriptAccuracy.compare(
        said: 'mayda sunog didi',
        heard: 'mayda didi',
      );
      expect(r.deletions, 1);
      expect(r.insertions, 0);
    });

    test('an invented word is an insertion', () {
      final r = TranscriptAccuracy.compare(
        said: 'mayda sunog',
        heard: 'mayda sunog sunog',
      );
      expect(r.insertions, 1);
      expect(r.deletions, 0);
    });

    test('an empty transcript loses every word', () {
      final r = TranscriptAccuracy.compare(said: 'mayda sunog', heard: '');
      expect(r.deletions, 2);
      expect(r.correct, 0);
      expect(r.wer, 1.0);
      expect(r.accuracy, 0.0);
    });

    test('nothing said and nothing heard does not divide by zero', () {
      final r = TranscriptAccuracy.compare(said: '', heard: '');
      expect(r.wer, 0);
    });

    test('accuracy is clamped when the recogniser over-produces', () {
      // WER above 1.0 is real and worth reporting; a negative accuracy is not
      // a thing anyone can read.
      final r = TranscriptAccuracy.compare(
        said: 'sunog',
        heard: 'kaibigan kaibigan kaibigan',
      );
      expect(r.wer, greaterThan(1.0));
      expect(r.accuracy, 0.0);
    });
  });

  group('the sample recorded on a handset', () {
    // Spoken in Waray into the Cebuano (ceb) recogniser.
    const said = 'Mayda sunog didi ha Caibiran';
    const heard = 'mayda sunog didiha kaibigan kaibigan';

    test('scores badly overall', () {
      final r = TranscriptAccuracy.compare(said: said, heard: heard);
      expect(r.correct, 2); // mayda, sunog
      expect(r.wer, greaterThan(0.5));
    });

    test('but the words that decide severity survived', () {
      // The whole point. A single score says this transcript was poor; the
      // word-level view says the emergency vocabulary came through and the
      // failure landed on a place name the app takes from GPS anyway.
      final outcomes = TranscriptAccuracy.wordOutcomes(
        said: said,
        heard: heard,
      );
      final heardWords = {
        for (final o in outcomes)
          if (o.heard) o.word,
      };
      expect(heardWords, contains('mayda'));
      expect(heardWords, contains('sunog'));
      expect(heardWords, isNot(contains('caibiran')));
    });

    test('wordOutcomes reports one entry per spoken word', () {
      final outcomes = TranscriptAccuracy.wordOutcomes(
        said: said,
        heard: heard,
      );
      expect(outcomes.length, 5);
    });
  });
}
