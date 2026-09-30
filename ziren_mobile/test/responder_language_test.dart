import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/core/config/locale_provider.dart';
import 'package:ziren/features/incident_report/presentation/incident_labels.dart';
import 'package:ziren/features/responder/domain/responder_vocabulary.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Tester's report, 2026-09-30: a responder who chose English still read
/// Filipino on the responder screens. The category labels, the status button
/// ("Papunta Na (En Route)") and a few messages were written in Filipino in
/// the code itself, and report texts carry a stored Filipino category prefix.
void main() {
  tearDown(() => LocaleProvider.current = const Locale('fil'));

  test('category labels follow the chosen language', () {
    LocaleProvider.current = const Locale('en');
    expect(ResponderVocabulary.categoryLabel('fire'), 'Fire');
    expect(ResponderVocabulary.categoryLabel('vehicular'), 'Road Accident');
    expect(
      ResponderVocabulary.categoryLabel('domestic_dispute_crime'),
      'Disturbance / Crime',
    );
    expect(ResponderVocabulary.categoryLabel('other'), 'Other');
    expect(ResponderVocabulary.categoryLabel('missing_person'), 'Missing person');
    expect(ResponderVocabulary.categoryLabel(null), 'Emergency');

    LocaleProvider.current = const Locale('fil');
    expect(ResponderVocabulary.categoryLabel('fire'), 'Sunog');
    expect(ResponderVocabulary.categoryLabel('vehicular'), 'Aksidente sa Daan');
    expect(ResponderVocabulary.categoryLabel('other'), 'Iba pa');
  });

  test('setLanguageName keeps the context-free locale in step', () async {
    final locale = LocaleProvider();
    await locale.setLanguageName('English');
    expect(LocaleProvider.current.languageCode, 'en');
    await locale.setLanguageName('Filipino');
    expect(LocaleProvider.current.languageCode, 'fil');
  }, skip: false);

  group('report text', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final fil = lookupAppLocalizations(const Locale('fil'));

    test('the stored Filipino category prefix is shown in English', () {
      expect(
        IncidentLabels.reportText(
          en,
          'Aksidente sa Daan — nagbangga ang motor ug dyip',
        ),
        'Road Accident — nagbangga ang motor ug dyip',
      );
      expect(IncidentLabels.reportText(en, 'Sunog / Fire'), 'Fire');
    });

    test('the person\'s own words are never changed', () {
      const raw = 'May sunog sa amin, tulong po';
      expect(IncidentLabels.reportText(en, raw), raw);
      expect(IncidentLabels.reportText(fil, raw), raw);
    });

    test('in Filipino the prefix reads as Filipino', () {
      expect(
        IncidentLabels.reportText(fil, 'Sunog / Fire — nasusunog ang bahay'),
        'Sunog — nasusunog ang bahay',
      );
    });
  });
}
