import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' show LocaleName;
import 'package:ziren/features/incident_report/data/incident_repository.dart';
import 'package:ziren/features/incident_report/data/station_repository.dart';
import 'package:ziren/features/incident_report/domain/incident_provider.dart';
import 'package:ziren/features/incident_report/domain/speech_locale_resolver.dart';

/// Evaluator finding #22 (2026-10-05): Bisaya voice-to-text came out wrong
/// because every report was heard by the Filipino recogniser: no screen said
/// which language was being spoken. The resident now chooses it beside the
/// microphone, the phone remembers it, and Bisaya is heard as Cebuano.
class _NoStations implements StationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The provider owns a voice recorder; its plugin has no implementation in a
  // unit test, and constructing it is all this test does with it.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (call) async => null,
  );

  final phone = [
    LocaleName('fil_PH', 'Filipino'),
    LocaleName('ceb_PH', 'Cebuano'),
    LocaleName('en_US', 'English'),
  ];

  test('Bisaya is heard by the Cebuano recogniser when the phone has one', () {
    expect(SpeechLocaleResolver.resolve(languageName: 'Bisaya', available: phone), 'ceb_PH');
    expect(SpeechLocaleResolver.resolve(languageName: 'Filipino', available: phone), 'fil_PH');
  });

  test('without Cebuano on the phone, Bisaya falls back and says it is not native', () {
    final noCeb = [LocaleName('fil_PH', 'Filipino'), LocaleName('en_US', 'English')];
    expect(SpeechLocaleResolver.resolve(languageName: 'Bisaya', available: noCeb), 'fil_PH');
    expect(SpeechLocaleResolver.hasNativeSupport(languageName: 'Bisaya', available: noCeb), isFalse);
  });

  test('the chosen speaking language is remembered on the phone', () async {
    SharedPreferences.setMockInitialValues({});
    IncidentProvider make() => IncidentProvider(
          repository: IncidentRepository(accessToken: () => null),
          stationRepository: _NoStations(),
        );

    final first = make();
    await first.loadSpokenLanguage();
    expect(IncidentProvider.spokenLanguages, contains('Bisaya'));
    await first.setSpokenLanguage('Bisaya');
    expect(first.spokenLanguage, 'Bisaya');

    final later = make();
    await later.loadSpokenLanguage();
    expect(later.spokenLanguage, 'Bisaya', reason: 'next launch keeps the choice');
  });

  test('an unknown language is ignored', () async {
    SharedPreferences.setMockInitialValues({'ziren.spoken_language': 'Klingon'});
    final p = IncidentProvider(
      repository: IncidentRepository(accessToken: () => null),
      stationRepository: _NoStations(),
    );
    await p.loadSpokenLanguage();
    expect(IncidentProvider.spokenLanguages, contains(p.spokenLanguage));
  });
}
