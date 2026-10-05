// Tester report 2026-10-05: a responder near a new incident was told only in
// the notification shade - opening the app raised no alert - and with the app
// closed or the phone locked nothing woke the screen.
//
// These pin the app's half of the fix: the nearby modal and its answers, the
// push payloads the background handler accepts, and notification ids that are
// the same in the push isolate and the app (so an insistent alarm raised while
// the app was closed can still be cancelled by the answer).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/core/push/responder_alert_push.dart';
import 'package:ziren/features/responder/domain/nearby_incident.dart';
import 'package:ziren/features/responder/presentation/widgets/nearby_alert_sheet.dart';
import 'package:ziren/l10n/app_localizations.dart';

NearbyIncident _incident() => NearbyIncident(
      incidentId: 'inc-1',
      reportText: 'May sunog',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      you: const NearbyYou(state: 'free'),
      severity: 'high',
      category: 'fire',
      locationAddress: 'San Roque, Larrazabal, Naval',
      distanceKm: 1.2,
      etaMinutes: 3,
      direction: 'NE',
    );

Future<NearbyAlertChoice?> _open(WidgetTester tester, {required Key tap}) async {
  NearbyAlertChoice? choice;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async => choice = await NearbyAlertSheet.show(context, _incident()),
        child: const Text('open'),
      );
    }),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('INCIDENT NEAR YOU'), findsOneWidget);
  expect(find.textContaining('1.2 km NE'), findsOneWidget);
  expect(find.textContaining('San Roque'), findsOneWidget);
  await tester.tap(find.byKey(tap));
  await tester.pumpAndSettle();
  return choice;
}

void main() {
  group('nearby alert modal', () {
    testWidgets('"I can respond" is the answer it returns', (tester) async {
      expect(await _open(tester, tap: const ValueKey('nearby-alert-respond')), NearbyAlertChoice.canRespond);
    });

    testWidgets('"Not available" is the answer it returns', (tester) async {
      expect(await _open(tester, tap: const ValueKey('nearby-alert-unavailable')), NearbyAlertChoice.unavailable);
    });

    testWidgets('closing it answers nothing (it comes back next time)', (tester) async {
      expect(await _open(tester, tap: const ValueKey('nearby-alert-close')), NearbyAlertChoice.later);
    });
  });

  group('alarm notification ids', () {
    test('the same incident always gets the same id (push isolate and app agree)', () {
      expect(ResponderAlertIds.assignment('abc'), ResponderAlertIds.assignment('abc'));
      expect(ResponderAlertIds.nearby('abc'), ResponderAlertIds.nearby('abc'));
      // Pinned values: a change here would strand alarms raised by an older build.
      expect(ResponderAlertIds.assignment('0cbccbcf-1380-4063-9340-b1d9e68e632e'), 1765875615);
    });

    test('assignment, nearby and stand-down never collide for one incident', () {
      const id = '0cbccbcf-1380-4063-9340-b1d9e68e632e';
      final ids = {
        ResponderAlertIds.assignment(id),
        ResponderAlertIds.nearby(id),
        ResponderAlertIds.standDown(id),
      };
      expect(ids.length, 3);
      expect(ids.every((i) => i >= 0 && i <= 0x7fffffff), isTrue, reason: 'Android ids are 32-bit');
    });
  });

  group('alert push payloads', () {
    test('anything that is not a responder alert is left alone', () async {
      expect(await showResponderAlertFromPush({'type': 'incident.message', 'incident_id': 'i'}), isFalse);
      expect(await showResponderAlertFromPush({'ziren_alert': 'party', 'incident_id': 'i'}), isFalse);
      expect(await showResponderAlertFromPush({'ziren_alert': kAlertNearby}), isFalse,
          reason: 'no incident id, nothing to open');
    });
  });
}
