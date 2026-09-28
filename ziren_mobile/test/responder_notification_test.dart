import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:Ziren/features/responder/domain/responder_notification_provider.dart';

/// A responder is told what happens TO them - a call, being stood down, a change
/// of priority - and nothing about what they did themselves.
///
/// Before this every update to a held incident became an "Incident update" in the
/// crew's own bell, including each tap of "I'm on my way"; being stood down by
/// dispatch raised no alert at all (so a crew already driving learned nothing and
/// the assignment alarm kept sounding); and an event for a cancelled incident the
/// app did not hold was announced as a NEW ASSIGNMENT.
PostgresChangePayload _event(Map<String, dynamic> row) => PostgresChangePayload(
  schema: 'public',
  table: 'incidents',
  commitTimestamp: DateTime.now(),
  eventType: PostgresChangeEvent.update,
  newRecord: row,
  oldRecord: {'id': row['id']},
  errors: null,
);

Map<String, dynamic> _row(
  String status, {
  String severity = 'high',
  String id = 'inc-1',
  String? address = 'Brgy. Casiawan, Cabucgayan',
}) => {
  'id': id,
  'status': status,
  'severity': severity,
  'incident_category': 'fire',
  'location_address': address,
};

void main() {
  late List<ResponderNotification> alerts;
  var reloads = 0;
  late ResponderNotificationProvider provider;

  setUp(() {
    alerts = [];
    reloads = 0;
    provider = ResponderNotificationProvider(
      onNewAssignment: () => reloads++,
      onAlert: alerts.add,
    );
  });

  group('an assignment', () {
    test('is a call: unread, the queue reloads, and the alarm is raised', () {
      provider.handleEvent(_event(_row('dispatched')));
      expect(provider.unreadCount, 1);
      expect(provider.unread.single.isNewAssignment, isTrue);
      expect(reloads, 1);
      expect(alerts.single.isNewAssignment, isTrue);
    });

    test('says what and where', () {
      provider.handleEvent(_event(_row('dispatched')));
      final n = provider.unread.single;
      expect(n.label, 'New incident assigned to you — Fire');
      expect(n.detail, 'HIGH · Brgy. Casiawan, Cabucgayan');
    });

    test('a call sent before a severity was set does not read as a fault', () {
      provider.handleEvent(_event(_row('dispatched', severity: 'pending')));
      expect(provider.unread.single.detail, startsWith('Incident '));
      expect(provider.unread.single.detail, isNot(contains('PENDING')));
    });

    test('an incident already held is not announced as new', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('dispatched')));
      expect(alerts, isEmpty);
    });

    test('a cancelled incident the app never held is not a call', () {
      provider.handleEvent(_event(_row('cancelled')));
      expect(alerts, isEmpty);
      expect(provider.unread.where((n) => n.isNewAssignment), isEmpty);
    });
  });

  group('dispatch standing the crew down', () {
    test('is announced - it is time-critical', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('cancelled')));
      expect(provider.unreadCount, 1);
      expect(provider.unread.single.isStandDown, isTrue);
      expect(provider.unread.single.label, 'Stand down — Fire incident cancelled');
      expect(provider.unread.single.detail, contains('do not need to respond'));
      expect(alerts.single.isStandDown, isTrue, reason: 'the phone must be told');
      expect(reloads, 1, reason: 'the queue must drop it');
    });

    test('once - a later update to the same row does not stand them down again', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('cancelled')));
      provider.handleEvent(_event(_row('cancelled')));
      expect(provider.unreadCount, 1);
      expect(alerts, hasLength(1));
    });
  });

  group('a change of priority', () {
    test('is announced with the change', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('dispatched', severity: 'high')));
      provider.handleEvent(_event(_row('dispatched', severity: 'critical')));
      expect(provider.unreadCount, 1);
      final n = provider.unread.single;
      expect(n.eventType, 'severity');
      expect(n.label, 'Priority changed — Fire');
      expect(n.detail, startsWith('HIGH → CRITICAL'));
      expect(alerts, isEmpty, reason: 'news, not a summons');
    });

    test('with no earlier reading there is nothing to compare', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('dispatched', severity: 'critical')));
      expect(provider.unreadCount, 0);
    });

    test('an update that leaves it alone says nothing', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('dispatched', severity: 'high')));
      provider.handleEvent(_event(_row('dispatched', severity: 'high')));
      expect(provider.unreadCount, 0);
    });
  });

  group('the crew\'s own progress is not news to the crew', () {
    test('en route, on scene and closed leave nothing unread', () {
      provider.seedKnown(['inc-1']);
      provider.handleEvent(_event(_row('en_route')));
      provider.handleEvent(_event(_row('arrived')));
      provider.handleEvent(_event(_row('resolved')));
      expect(provider.unreadCount, 0);
      expect(alerts, isEmpty);
    });
  });

  group('reading them', () {
    test('dismissing one and clearing all', () {
      provider.handleEvent(_event(_row('dispatched', id: 'a')));
      provider.handleEvent(_event(_row('dispatched', id: 'b')));
      expect(provider.unreadCount, 2);
      provider.dismiss(0);
      expect(provider.unreadCount, 1);
      provider.markAllRead();
      expect(provider.hasUnread, isFalse);
    });
  });
}
