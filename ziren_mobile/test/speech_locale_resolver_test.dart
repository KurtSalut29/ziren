import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart' show LocaleName;

import 'package:ziren/features/incident_report/domain/speech_locale_resolver.dart';

/// The app listened in `en_PH` while residents report mostly in Waray and
/// Bisaya. These tests pin the replacement, including the part that is a
/// linguistic argument rather than an obvious default: when Waray is
/// unavailable, Cebuano is tried before Filipino, because Waray and Cebuano
/// are both Visayan and share far more with each other than either does with
/// Tagalog.
void main() {
  LocaleName loc(String id, [String? name]) => LocaleName(id, name ?? id);

  // A plausible Philippine handset: no Waray recogniser anywhere.
  final typicalDevice = [
    loc('en_US', 'English (United States)'),
    loc('en_PH', 'English (Philippines)'),
    loc('fil_PH', 'Filipino (Philippines)'),
    loc('ceb_PH', 'Cebuano (Philippines)'),
  ];

  group('fallback ordering', () {
    test('Waray prefers its own recogniser, then Cebuano, then Filipino', () {
      expect(
        SpeechLocaleResolver.candidatesFor('Waray'),
        ['war', 'ceb', 'fil', 'en'],
      );
    });

    test('Bisaya prefers Cebuano', () {
      expect(SpeechLocaleResolver.candidatesFor('Bisaya').first, 'ceb');
    });

    test('an unknown language name does not throw and lands on Filipino', () {
      expect(SpeechLocaleResolver.candidatesFor('Ilocano').first, 'fil');
    });
  });

  group('resolve against a real device list', () {
    test('Waray falls through to Cebuano, not Filipino', () {
      // The whole point of the ordering. If this ever returns fil_PH, the
      // Visayan argument has been quietly dropped.
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Waray',
          available: typicalDevice,
        ),
        'ceb_PH',
      );
    });

    test('Waray uses a real Waray recogniser when one exists', () {
      final withWaray = [...typicalDevice, loc('war_PH', 'Waray')];
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Waray',
          available: withWaray,
        ),
        'war_PH',
      );
    });

    test('Waray falls all the way to Filipino when Cebuano is missing', () {
      final noCebuano =
          typicalDevice.where((l) => !l.localeId.startsWith('ceb')).toList();
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Waray',
          available: noCebuano,
        ),
        'fil_PH',
      );
    });

    test('English and Filipino resolve to themselves', () {
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'English',
          available: typicalDevice,
        ),
        'en_US', // first en_* in the list
      );
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Filipino',
          available: typicalDevice,
        ),
        'fil_PH',
      );
    });

    test('an empty device list returns null, not a guess', () {
      // Null lets the platform pick its own default. Inventing 'fil_PH' here
      // would hand the recogniser a locale it may not have.
      expect(
        SpeechLocaleResolver.resolve(languageName: 'Waray', available: const []),
        isNull,
      );
    });
  });

  group('locale id shapes', () {
    test('hyphen and underscore separators both match', () {
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Bisaya',
          available: [loc('ceb-PH')],
        ),
        'ceb-PH',
      );
    });

    test('a bare language code matches', () {
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Bisaya',
          available: [loc('ceb')],
        ),
        'ceb',
      );
    });

    test('case is ignored', () {
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'Bisaya',
          available: [loc('CEB_PH')],
        ),
        'CEB_PH',
      );
    });

    test('a language prefix does not match a different language', () {
      // 'en' must not be satisfied by 'enm' or similar.
      expect(
        SpeechLocaleResolver.resolve(
          languageName: 'English',
          available: [loc('enm_GB')],
        ),
        isNull,
      );
    });
  });

  group('native support reporting', () {
    test('false for Waray on a device without a Waray recogniser', () {
      // This is what tells the UI to lean on the attached audio instead of
      // presenting the transcript as the record.
      expect(
        SpeechLocaleResolver.hasNativeSupport(
          languageName: 'Waray',
          available: typicalDevice,
        ),
        isFalse,
      );
    });

    test('true for Bisaya when Cebuano is installed', () {
      expect(
        SpeechLocaleResolver.hasNativeSupport(
          languageName: 'Bisaya',
          available: typicalDevice,
        ),
        isTrue,
      );
    });
  });

  group('availableCandidates', () {
    test('keeps preference order and drops what is not installed', () {
      expect(
        SpeechLocaleResolver.availableCandidates(
          languageName: 'Waray',
          available: typicalDevice,
        ),
        ['ceb', 'fil', 'en'], // 'war' dropped — not on the device
      );
    });

    test('is empty when nothing matches', () {
      expect(
        SpeechLocaleResolver.availableCandidates(
          languageName: 'Waray',
          available: [loc('de_DE')],
        ),
        isEmpty,
      );
    });
  });
}
