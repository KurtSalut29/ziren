import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/core/config/locale_provider.dart';
import 'package:ziren/features/responder/domain/responder_vocabulary.dart';

/// The shared reading of an incident.
///
/// The cases that matter are the ones where two screens describe the same
/// thing: a wait computed on the phone and the same wait handed over by the
/// backend must print the same string, or the responder sees two answers to
/// one question.

void main() {
  // The labels follow the app's language; these assertions are the English.
  setUp(() => LocaleProvider.current = const Locale('en'));
  tearDown(() => LocaleProvider.current = const Locale('fil'));

  group('waiting', () {
    test('truncates days rather than rounding them', () {
      // 2 days 22 hours. Rounding would call this three days, which claims a
      // day that has not happened.
      expect(ResponderVocabulary.waiting(2 * 1440 + 22 * 60), '2d');
    });

    test('truncates hours the same way', () {
      expect(ResponderVocabulary.waiting(119), '1h');
    });

    test('reads minutes exactly under an hour', () {
      expect(ResponderVocabulary.waiting(59), '59m');
      expect(ResponderVocabulary.waiting(60), '1h');
    });

    test('a fresh call is "just now", not "0m"', () {
      expect(ResponderVocabulary.waiting(0), 'just now');
    });

    test('nothing waiting is a dash, never a zero', () {
      // Null and zero are different answers: null means the queue is empty,
      // zero would mean a call arrived this minute.
      expect(ResponderVocabulary.waiting(null), '—');
    });

    test('a clock running backwards does not print a negative wait', () {
      expect(ResponderVocabulary.waiting(-5), 'just now');
    });
  });

  group('elapsed and waiting agree', () {
    // THE REGRESSION THIS PINS
    //
    // Home draws one incident's wait twice: the pending card computes it from
    // created_at on the phone, the longest-waiting card takes the backend's
    // oldest_waiting_minutes. Those went through different formatters, and an
    // incident open for about 2.9 days rendered "2d" in one and "3d" in the
    // other, one above the other on the same screen.
    for (final minutes in [0, 1, 59, 60, 90, 1439, 1440, 4176, 10080]) {
      test('$minutes minutes formats identically both ways', () {
        final from = DateTime.now().subtract(Duration(minutes: minutes));
        expect(
          ResponderVocabulary.elapsed(from),
          ResponderVocabulary.waiting(minutes),
        );
      });
    }
  });

  group('rank', () {
    test('orders worst first', () {
      expect(
        ResponderVocabulary.rank('critical'),
        lessThan(ResponderVocabulary.rank('high')),
      );
      expect(
        ResponderVocabulary.rank('low'),
        lessThan(ResponderVocabulary.rank(null)),
      );
    });

    test('an untriaged incident sorts last but is still ranked', () {
      // Last because an unknown tier cannot be compared against a known one —
      // not because it is assumed harmless.
      expect(ResponderVocabulary.rank('nonsense'), ResponderVocabulary.rank(null));
    });
  });

  group('label', () {
    test('every tier has a word, including the absence of one', () {
      // Severity is never carried by colour alone: critical is red and low is
      // green, the one pair a red-green deficient reader cannot separate.
      for (final tier in [...ResponderVocabulary.tiers, null]) {
        expect(ResponderVocabulary.label(tier), isNotEmpty);
      }
      expect(ResponderVocabulary.label(null), 'NOT TRIAGED');
    });
  });

  group('minutes', () {
    test('still rounds, because it measures rather than counts up', () {
      // The typical-time figure wants the nearest value, not a floor.
      expect(ResponderVocabulary.minutes(2 * 1440 + 22 * 60), '3d');
      expect(ResponderVocabulary.minutes(null), '—');
    });
  });
}
