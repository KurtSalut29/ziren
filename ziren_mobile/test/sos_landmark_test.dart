import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ziren/features/incident_report/domain/landmark_index.dart';
import 'package:ziren/features/sos/domain/sos_provider.dart';
import 'package:ziren/features/sos/presentation/sos_confirm_screen.dart';
import 'package:ziren/l10n/app_localizations.dart';

import 'support/fake_sos_repository.dart';

/// "Report an emergency (fastest)" finds the landmark nearest the GPS fix by
/// itself, shows it before sending, and lets the resident correct it.

// The fake fix in kNavalPosition() is 11.5836, 124.4063.
final _index = LandmarkIndex.fromPlaces(
  [
    const MapPlace(
      name: 'Naval Central School',
      kind: 'school',
      isLandmark: true,
      lat: 11.5850,
      lng: 124.4063,
    ),
  ],
  unnamed: const [
    MapPlace(
      name: 'Basketball Court',
      kind: 'pitch',
      isLandmark: true,
      lat: 11.5837,
      lng: 124.4063,
    ),
  ],
);

final _emptyIndex = LandmarkIndex.fromPlaces(const []);

/// initialize() asks the OS for location, which a test cannot do.
class _TestSos extends SosProvider {
  _TestSos({super.repository, super.landmarks});

  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SosProvider landmark', () {
    test('the nearest landmark to the fix is found and sent', () async {
      final repo = FakeSosRepository(() async => kSosResult);
      final p = SosProvider(repository: repo, landmarks: () async => _index)
        ..debugPosition = kNavalPosition();

      await p.detectLandmark();
      expect(p.detectedLandmark, 'Basketball Court');
      expect(p.landmarkNote, 'Near Basketball Court');

      await p.submit();
      expect(repo.lastLandmarkNote, 'Near Basketball Court');
    });

    test('a send that beat the lookup still carries the landmark', () async {
      final repo = FakeSosRepository(() async => kSosResult);
      final p = SosProvider(repository: repo, landmarks: () async => _index)
        ..debugPosition = kNavalPosition();

      await p.submit();
      expect(repo.lastLandmarkNote, 'Near Basketball Court');
    });

    test('what the resident typed wins; clearing it goes back', () async {
      final repo = FakeSosRepository(() async => kSosResult);
      final p = SosProvider(repository: repo, landmarks: () async => _index)
        ..debugPosition = kNavalPosition();
      await p.detectLandmark();

      p.setTypedLandmark('  tapat ng tindahan ni Aling Nena ');
      expect(p.landmarkNote, 'tapat ng tindahan ni Aling Nena');
      await p.submit();
      expect(repo.lastLandmarkNote, 'tapat ng tindahan ni Aling Nena');

      p.setTypedLandmark('   ');
      expect(p.typedLandmark, isNull);
      expect(p.landmarkNote, 'Near Basketball Court');
    });

    test('nothing nearby and nothing typed sends no landmark', () async {
      final repo = FakeSosRepository(() async => kSosResult);
      final p = SosProvider(repository: repo, landmarks: () async => _emptyIndex)
        ..debugPosition = kNavalPosition();

      await p.submit();
      expect(p.detectedLandmark, isNull);
      expect(repo.lastLandmarkNote, isNull);
    });

    test('reset forgets both landmarks', () async {
      final p = SosProvider(
        repository: FakeSosRepository(() async => kSosResult),
        landmarks: () async => _index,
      )..debugPosition = kNavalPosition();
      await p.detectLandmark();
      p.setTypedLandmark('x');

      p.reset();
      expect(p.detectedLandmark, isNull);
      expect(p.typedLandmark, isNull);
    });
  });

  group('SOS confirm screen', () {
    Future<_TestSos> pump(WidgetTester tester, LandmarkIndex index) async {
      final p = _TestSos(
        repository: FakeSosRepository(() async => kSosResult),
        landmarks: () async => index,
      )..debugPosition = kNavalPosition();
      await p.detectLandmark();
      await tester.pumpWidget(
        ChangeNotifierProvider<SosProvider>.value(
          value: p,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: SosConfirmScreen(),
          ),
        ),
      );
      await tester.pump();
      return p;
    }

    testWidgets('shows the detected landmark under the location', (
      tester,
    ) async {
      await pump(tester, _index);
      expect(find.text('Near Basketball Court'), findsOneWidget);
      expect(
        find.text('Nearest landmark on the map · tap to change'),
        findsOneWidget,
      );
    });

    testWidgets('the landmark can be changed from the screen', (tester) async {
      final p = await pump(tester, _index);

      await tester.tap(find.byKey(const Key('sos-landmark-row')));
      await tester.pumpAndSettle();
      expect(find.text('Landmark near you'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('sos-landmark-field')),
        'Beside the waiting shed',
      );
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();

      expect(p.typedLandmark, 'Beside the waiting shed');
      expect(find.text('Beside the waiting shed'), findsOneWidget);
      expect(find.text('Landmark you added · tap to change'), findsOneWidget);
    });

    testWidgets('no landmark nearby offers to add one', (tester) async {
      await pump(tester, _emptyIndex);
      expect(find.text('No landmark found nearby'), findsOneWidget);
      expect(find.text('Tap to add one — optional'), findsOneWidget);
    });
  });
}
