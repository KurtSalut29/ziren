import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/responder/data/responder_repository.dart';
import 'package:ziren/features/responder/domain/responder_provider.dart';
import 'package:ziren/features/responder/presentation/widgets/responder_voice_note.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Evaluator findings #2 and #3 (ISO / white-box review, 2026-10-05).
///
///   #2  A responder's latest GPS position did not reach the admin side. One
///       real cause: the app never read the duty state back from the server, so
///       every launch began "off duty" and position reporting never resumed.
///   #3  The responder app said a report had a photo or video and offered
///       nothing to open: "view it in the dashboard".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('duty state is read back from the server (#2)', () {
    test('on duty on the server means on duty in the app after launch', () async {
      final repo = _FakeRepo(dashboard: {'availability': 'on_duty'});
      final p = ResponderProvider(repository: repo);
      expect(p.isOnDuty, isFalse, reason: 'the app starts not knowing');
      await p.loadDashboard();
      expect(p.isOnDuty, isTrue);
      p.stopLocationReporting();
    });

    test('off duty stays off duty', () async {
      final p = ResponderProvider(repository: _FakeRepo(dashboard: {'availability': 'off_duty'}));
      await p.loadDashboard();
      expect(p.isOnDuty, isFalse);
    });

    test('an unreadable state changes nothing', () async {
      final p = ResponderProvider(repository: _FakeRepo(dashboard: {'availability': null}));
      p.setAvailabilityLocal('on_duty');
      await p.loadDashboard();
      expect(p.isOnDuty, isTrue, reason: 'a failed read must not flip anyone off duty');
      p.stopLocationReporting();
    });

    test('a tap on the duty switch is not undone by a read that started before it', () async {
      final gate = Completer<Map<String, dynamic>>();
      final repo = _FakeRepo(dashboardFuture: gate.future);
      final p = ResponderProvider(repository: repo);

      final loading = p.loadDashboard(); // server will say on_duty...
      await p.toggleAvailability(); // ...but the responder switches on first
      expect(p.isOnDuty, isTrue);
      await p.toggleAvailability(); // and then off again
      expect(p.isOnDuty, isFalse);

      gate.complete({'availability': 'on_duty'});
      await loading;
      expect(p.isOnDuty, isFalse, reason: 'the stale read must not switch them back on');
    });
  });

  group('photos and videos are shown to the crew (#3)', () {
    Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> media) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResponderVoiceNote(incidentId: 'inc-1', repository: _FakeRepo(media: media)),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a photo and a video become tiles, not a "see the dashboard" note', (tester) async {
      await pump(tester, [
        {'path': 'u/1/a.jpg', 'url': 'https://example.invalid/a.jpg', 'kind': 'image', 'source': 'reporter'},
        {'path': 'u/1/b.mp4', 'url': 'https://example.invalid/b.mp4', 'kind': 'video', 'source': 'reporter'},
      ]);

      expect(find.text('Photos and videos from the caller'), findsOneWidget);
      expect(find.textContaining('dashboard'), findsNothing);
      expect(find.bySemanticsLabel('Play video'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('a file that could not be signed says so instead of a dead tile', (tester) async {
      await pump(tester, [
        {'path': 'u/1/gone.jpg', 'url': null, 'kind': 'image', 'source': 'reporter'},
      ]);
      expect(find.bySemanticsLabel('Could not open this file.'), findsOneWidget);
    });

    testWidgets('a typed report with nothing attached draws nothing', (tester) async {
      await pump(tester, const []);
      expect(find.text('Photos and videos from the caller'), findsNothing);
    });
  });
}

class _FakeRepo extends ResponderRepository {
  _FakeRepo({this.dashboard, this.dashboardFuture, this.media = const []});

  final Map<String, dynamic>? dashboard;
  final Future<Map<String, dynamic>>? dashboardFuture;
  final List<Map<String, dynamic>> media;

  @override
  Future<Map<String, dynamic>> getDashboard() async =>
      dashboardFuture != null ? await dashboardFuture! : (dashboard ?? const {});

  @override
  Future<void> setAvailability(String availability) async {}

  @override
  Future<bool> updateLocation(double lat, double lng) async => true;

  @override
  Future<List<Map<String, dynamic>>> getIncidentMedia(String incidentId) async => media;
}
