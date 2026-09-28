import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ziren/features/notifications/domain/notification_provider.dart';

/// Realtime tells the app that a row of the resident's reports changed - but
/// not WHICH column. For this table the old row in the event is only its id, so
/// the provider has to remember the last status itself to know whether the
/// status moved. Found on a phone: answering an agency's question (which only
/// flips review_status back to 'pending') popped "Report update - Being
/// reviewed" for a status that had not changed.
PostgresChangePayload _update(Map<String, dynamic> row) =>
    PostgresChangePayload(
      schema: 'public',
      table: 'incidents',
      commitTimestamp: DateTime.now(),
      eventType: PostgresChangeEvent.update,
      newRecord: row,
      oldRecord: {'id': row['id']},
      errors: null,
    );

Map<String, dynamic> _row(String status, {String review = 'pending'}) => {
  'id': 'inc-1',
  'report_text': 'smoke from a house',
  'status': status,
  'review_status': review,
};

void main() {
  group('a status is announced only when it moves', () {
    test('the first move is announced', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(_update(_row('dispatched')));
      expect(n.unreadCount, 1);
      expect(n.unread.single.newStatus, 'dispatched');
    });

    test('a later update that leaves the status alone is not', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(_update(_row('dispatched')));
      // e.g. the agency corrects a field, or the resident writes a note
      n.handleIncidentUpdate(_update(_row('dispatched')));
      n.handleIncidentUpdate(_update(_row('dispatched')));
      expect(n.unreadCount, 1);
    });

    test('a further move is announced again', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(_update(_row('dispatched')));
      n.handleIncidentUpdate(_update(_row('resolved')));
      expect(n.unread.map((e) => e.newStatus), ['resolved', 'dispatched']);
    });

    test('answering a question - review_status only - says nothing', () {
      final n = NotificationProvider();
      // Where the report stood when the app learned of it (the list it fetches
      // at start-up), before the agency asked and the resident answered.
      n.rememberStatus('inc-1', 'processing');
      n.handleIncidentUpdate(_update(_row('processing', review: 'pending')));
      expect(n.unreadCount, 0);
    });

    test('a status the app was told about at start-up is not "new"', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'dispatched');
      n.handleIncidentUpdate(_update(_row('dispatched')));
      expect(n.unreadCount, 0);
      // ...but it is still a move when it really changes
      n.handleIncidentUpdate(_update(_row('resolved')));
      expect(n.unreadCount, 1);
    });

    test('an early event is not overwritten by an older list', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(_update(_row('dispatched')));
      n.rememberStatus('inc-1', 'processing'); // the list was fetched before
      n.handleIncidentUpdate(_update(_row('dispatched')));
      expect(n.unreadCount, 1);
    });

    test("'received' is never announced (the resident is still submitting)", () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(_update(_row('received')));
      expect(n.unreadCount, 0);
    });

    test('two reports are tracked separately', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(_update(_row('dispatched')));
      n.handleIncidentUpdate(
        _update({..._row('dispatched'), 'id': 'inc-2'}),
      );
      expect(n.unreadCount, 2);
    });
  });
}
