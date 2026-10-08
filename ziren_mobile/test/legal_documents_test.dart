// The Terms and the Privacy Notice cannot change without a version decision.
//
// Week 10: the server began refusing reports from unverified residents on
// 2026-10-07, while the bundled Terms still said "You can skip this and still
// report emergencies" and the consent screen "You can always report an
// emergency, verified or not". Nothing linked the policy to the words every
// resident had agreed to. A changed text also reaches no one already
// onboarded unless its version is bumped (onboarding_repository compares the
// stored version with LegalDocuments): this pins each document's text to its
// version, so a change has to come with a decision - bump (everyone is asked
// again) or, for a typo, update the fingerprint here on purpose.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/onboarding/domain/legal_documents.dart';
import 'package:ziren/l10n/app_localizations_en.dart';
import 'package:ziren/l10n/app_localizations_fil.dart';

/// FNV-1a over the text with line endings normalised (a Windows checkout must
/// not look like an edit).
String fingerprint(String text) {
  // 32-bit, so every step stays inside Dart's signed 64-bit int.
  var h = 0x811c9dc5;
  for (final unit in text.replaceAll('\r\n', '\n').codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// The text each shipped version was published with.
const signedOff = <String, String>{
  'privacy 1.1 en': '20f2c932',
  'privacy 1.1 fil': 'a4960df5',
  'terms 1.2 en': '0d683a84',
  'terms 1.2 fil': '708db005',
  // 2026-10-08: the first 7 days, and the 2x2 ID photo on the Ziren ID.
  'privacy 1.2 en': '900da7ee',
  'privacy 1.2 fil': 'fe65a329',
  'terms 1.3 en': 'e08d7702',
  'terms 1.3 fil': '17428ee0',
};

String read(LegalDoc doc, String lang) =>
    File(LegalDocuments.assetPath(doc, lang)).readAsStringSync();

void main() {
  for (final doc in LegalDoc.values) {
    for (final lang in ['en', 'fil']) {
      final version = LegalDocuments.versionOf(doc);
      final key = '${doc.name} $version $lang';

      test('$key: the header states the version consent is recorded against', () {
        final header = read(doc, lang).split('\n').take(5).join('\n');
        expect(
          header,
          contains(lang == 'en' ? 'Version $version ' : 'Bersyon $version '),
        );
      });

      test('$key: the text is the one this version was signed off with', () {
        expect(
          signedOff.containsKey(key),
          isTrue,
          reason: 'No fingerprint for $key: a new version needs one here.',
        );
        expect(
          fingerprint(read(doc, lang)),
          signedOff[key],
          reason:
              '${doc.name}_$lang.md changed but its version is still $version. '
              'Bump LegalDocuments.${doc.name}Version (every resident is asked '
              'to accept again), or, for a typo, update this fingerprint.',
        );
      });
    }
  }

  test('what residents agree to matches what the server enforces', () {
    // incident_standing.refuse_if_unverified + resident_trust.GRACE_DAYS: a
    // resident reports for their first 7 days, then only at level 2. The
    // words they accept must say exactly that - not "verified or not", and
    // not "only verified" with no first week either.
    for (final t in [AppLocalizationsEn(), AppLocalizationsFil()]) {
      expect(t.consentSummaryReporting.toLowerCase(), isNot(contains('verified or not')));
      expect(t.consentSummaryReporting.toLowerCase(), isNot(contains('beripikado man o hindi')));
      expect(t.consentSummaryReporting, contains('7'));
    }
    final terms = read(LegalDoc.terms, 'en').replaceAll(RegExp(r'\s+'), ' ');
    expect(terms, contains('A new account can send reports for its first 7 days'));
    expect(terms, contains('only a verified account can send reports'));
    expect(terms, isNot(contains('You can skip this and still report')));
    final filTerms = read(LegalDoc.terms, 'fil').replaceAll(RegExp(r'\s+'), ' ');
    expect(filTerms, contains('unang 7 araw'));
  });

  test('the Privacy Notice says which photo is kept', () {
    // user_service.decide_verification: approval keeps the 2x2 ID photo and
    // deletes the ID scan and the selfie; a rejection keeps nothing.
    final privacy = read(LegalDoc.privacy, 'en').replaceAll(RegExp(r'\s+'), ' ');
    expect(privacy, contains('Your selfie** is deleted once an administrator has finished checking it'));
    expect(privacy, contains('Your 2x2 ID photo** is deleted too if your ID is not approved'));
    expect(privacy, contains('kept as the picture on your Ziren ID'));
  });
}
