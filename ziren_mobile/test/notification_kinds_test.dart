import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ziren/features/notifications/domain/notification_provider.dart';

/// What the resident is told, and - as important - what they are NOT told.
///
/// The bug that started this: a tester moved a report to Trash and a moment later
/// the app announced "Report update - Cancelled - Your report was cancelled." for
/// something they had just done themselves. Trash is wire status `cancelled` with
/// `withdrawn_at`, and the same status is what an agency cancelling a report
/// looks like - so the provider has to tell the two apart, and say the right
/// thing about each.
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

String _iso(Duration ago) =>
    DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _row(
  String status, {
  String review = 'pending',
  Map<String, dynamic> extra = const {},
}) => {
  'id': 'inc-1',
  'report_text': 'smoke from a house',
  'status': status,
  'review_status': review,
  ...extra,
};

void main() {
  group('the resident\'s own actions are not announced back to them', () {
    test('moving a report to Trash says nothing', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'received');
      n.handleIncidentUpdate(
        _update(_row('cancelled', extra: {'withdrawn_at': _iso(Duration.zero)})),
      );
      expect(n.unreadCount, 0);
    });

    test('and not once more when the row is touched again', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(
        _update(_row('cancelled', extra: {'withdrawn_at': _iso(Duration.zero)})),
      );
      n.handleIncidentUpdate(
        _update(_row('cancelled', extra: {'withdrawn_at': _iso(Duration.zero)})),
      );
      expect(n.unreadCount, 0);
    });
  });

  group('an agency cancelling is a different thing, and says so', () {
    test('cancelled without withdrawn_at is the agency, not the resident', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'dispatched');
      n.handleIncidentUpdate(_update(_row('cancelled')));
      expect(n.unreadCount, 1);
      expect(n.unread.single.kind, NotificationKind.cancelled);
      expect(n.unread.single.newStatus, 'cancelled');
    });

    test('announced once', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'dispatched');
      n.handleIncidentUpdate(_update(_row('cancelled')));
      n.handleIncidentUpdate(_update(_row('cancelled')));
      expect(n.unreadCount, 1);
    });

    test('a rejection is a rejection, not also a cancellation', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'received');
      n.handleIncidentUpdate(
        _update(
          _row(
            'cancelled',
            review: 'rejected',
            extra: {
              'reviewed_at': _iso(const Duration(seconds: 5)),
              'rejection_reason': 'Duplicate of another report',
            },
          ),
        ),
      );
      expect(n.unreadCount, 1);
      expect(n.unread.single.kind, NotificationKind.rejected);
      expect(n.unread.single.detail, 'Duplicate of another report');
    });
  });

  group('the agency accepting a report', () {
    test('is announced, with nothing else', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'received');
      n.handleIncidentUpdate(
        _update(
          _row(
            'received',
            review: 'accepted',
            extra: {'reviewed_at': _iso(const Duration(seconds: 3))},
          ),
        ),
      );
      expect(n.unread.map((e) => e.kind), [NotificationKind.accepted]);
    });

    test('is not announced twice for the same acceptance', () {
      final n = NotificationProvider();
      final at = _iso(const Duration(seconds: 3));
      for (var i = 0; i < 3; i++) {
        n.handleIncidentUpdate(
          _update(_row('received', review: 'accepted', extra: {'reviewed_at': at})),
        );
      }
      expect(n.unreadCount, 1);
    });

    test('an old acceptance is not "just happened"', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(
        _update(
          _row(
            'received',
            review: 'accepted',
            extra: {'reviewed_at': _iso(const Duration(days: 2))},
          ),
        ),
      );
      expect(n.unreadCount, 0);
    });

    test('dispatching a pending report accepts it too - and only "on the way" is said', () {
      final n = NotificationProvider();
      n.rememberStatus('inc-1', 'received');
      final now = _iso(Duration.zero);
      n.handleIncidentUpdate(
        _update(
          _row(
            'dispatched',
            review: 'accepted',
            extra: {'reviewed_at': now, 'dispatched_at': now},
          ),
        ),
      );
      expect(n.unreadCount, 1);
      expect(n.unread.single.kind, NotificationKind.status);
      expect(n.unread.single.newStatus, 'dispatched');
    });
  });

  group('the crew\'s progress is announced in its own terms', () {
    test('each move is its own notice', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(
        _update(_row('dispatched', extra: {'dispatched_at': _iso(Duration.zero)})),
      );
      n.handleIncidentUpdate(_update(_row('en_route')));
      n.handleIncidentUpdate(_update(_row('arrived')));
      n.handleIncidentUpdate(
        _update(_row('resolved', extra: {'resolved_at': _iso(Duration.zero)})),
      );
      expect(n.unread.map((e) => e.newStatus), [
        'resolved',
        'arrived',
        'en_route',
        'dispatched',
      ]);
      expect(n.unread.every((e) => e.kind == NotificationKind.status), isTrue);
    });

    test('the ETA rides along', () {
      final n = NotificationProvider();
      n.handleIncidentUpdate(
        _update(
          _row(
            'dispatched',
            extra: {
              'dispatched_at': _iso(Duration.zero),
              'eta_minutes': 7,
              'responding_agency': 'BFP Naval',
            },
          ),
        ),
      );
      expect(n.unread.single.etaMinutes, 7);
      expect(n.unread.single.respondingAgency, 'BFP Naval');
    });
  });

  group('the live copy and the stored copy are one event', () {
    test('the same instant, written two ways, is the same key', () {
      // Postgres and Python format one moment differently.
      expect(
        reviewEventKey('i', NotificationKind.accepted, '2026-09-25T01:02:03.500000+00:00'),
        reviewEventKey('i', NotificationKind.accepted, '2026-09-25T01:02:03.500Z'),
      );
    });

    test('dispatch and resolution are keyed by their time, other moves once', () {
      expect(
        statusEventKey('i', 'dispatched', '2026-09-25T01:00:00Z'),
        isNot(statusEventKey('i', 'dispatched', '2026-09-25T02:00:00Z')),
      );
      expect(
        statusEventKey('i', 'en_route', '2026-09-25T01:00:00Z'),
        statusEventKey('i', 'en_route', '2026-09-25T02:00:00Z'),
      );
    });

    test('a message is keyed by its own id', () {
      expect(messageEventKey('i', 'n1'), isNot(messageEventKey('i', 'n2')));
      expect(cancelEventKey('i'), 'i:cancelled');
    });

    test('a live notice keeps the key the stored one will be matched on', () {
      final n = NotificationProvider();
      final at = _iso(const Duration(seconds: 2));
      n.handleIncidentUpdate(
        _update(_row('dispatched', extra: {'dispatched_at': at})),
      );
      expect(n.unread.single.eventKey, statusEventKey('inc-1', 'dispatched', at));
    });
  });

  group('AppNotification', () {
    test('learning the row id keeps what was already known', () {
      final n = AppNotification(
        incidentId: 'inc-1',
        reportText: 't',
        newStatus: 'cancelled',
        receivedAt: _epoch,
        kind: NotificationKind.cancelled,
        eventKey: 'inc-1:cancelled',
      );
      final withRow = n.withServerId('row-9', detail: 'Duplicate');
      expect(withRow.serverId, 'row-9');
      expect(withRow.detail, 'Duplicate');
      expect(withRow.eventKey, 'inc-1:cancelled');
      expect(withRow.kind, NotificationKind.cancelled);
    });

    test('an agency act is told apart from the workflow moving', () {
      final status = AppNotification(
        incidentId: 'i', reportText: '', newStatus: 'dispatched', receivedAt: _epoch,
      );
      final cancelled = AppNotification(
        incidentId: 'i', reportText: '', newStatus: 'cancelled', receivedAt: _epoch,
        kind: NotificationKind.cancelled,
      );
      expect(status.isAgencyAct, isFalse);
      expect(cancelled.isAgencyAct, isTrue);
    });
  });
}

final _epoch = DateTime.utc(2026, 9, 25);
