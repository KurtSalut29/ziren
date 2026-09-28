import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/responder/domain/responder_incident_model.dart';
import 'package:ziren/features/responder/domain/responder_trends.dart';

/// The arithmetic behind the responder's Home charts.
///
/// Worth testing rather than eyeballing, because every failure mode here is
/// silent: a chart drawn from a wrong bucket still looks like a chart. The
/// cases that matter are the boundaries — a closure at one minute past
/// midnight, a cancelled incident with no resolved time, and the history cap
/// that can quietly hide closures inside the window being drawn.

ResponderIncidentModel _incident({
  String id = 'x',
  String status = 'resolved',
  String? severity = 'high',
  required DateTime createdAt,
  DateTime? dispatchedAt,
  DateTime? resolvedAt,
}) => ResponderIncidentModel(
  id: id,
  reportText: 'test',
  status: status,
  createdAt: createdAt,
  severity: severity,
  dispatchedAt: dispatchedAt,
  resolvedAt: resolvedAt,
);

void main() {
  // A fixed "now" so the tests do not drift with the wall clock, and one that
  // is mid-morning rather than near midnight — a bug that puts a closure in
  // the wrong bucket by a few hours would hide behind a boundary "now".
  final now = DateTime(2026, 9, 7, 10, 30);

  group('closedPerDay', () {
    test('always returns one bucket per day, oldest first', () {
      final days = ResponderTrends.closedPerDay([], now: now);

      expect(days, hasLength(7));
      expect(days.first.day, DateTime(2026, 9, 1));
      expect(days.last.day, DateTime(2026, 9, 7));
      // A quiet week is seven zeros, not an empty list. Dropping empty days
      // would compress the axis and make an irregular week look steady.
      expect(days.map((d) => d.count), everyElement(0));
    });

    test('counts a closure on the day it closed, not the day it arrived', () {
      // Reported late on the 5th, closed after midnight on the 6th.
      final incident = _incident(
        createdAt: DateTime(2026, 9, 5, 23, 40),
        resolvedAt: DateTime(2026, 9, 6, 0, 20),
      );

      final days = ResponderTrends.closedPerDay([incident], now: now);
      final byDay = {for (final d in days) d.day: d.count};

      expect(byDay[DateTime(2026, 9, 5)], 0);
      expect(byDay[DateTime(2026, 9, 6)], 1);
    });

    test('ignores closures older than the window', () {
      final old = _incident(
        createdAt: DateTime(2026, 8, 20),
        resolvedAt: DateTime(2026, 8, 21),
      );

      final days = ResponderTrends.closedPerDay([old], now: now);
      expect(days.fold<int>(0, (a, d) => a + d.count), 0);
    });

    test('files a cancelled incident by when it was reported', () {
      // A cancelled incident never resolves, so resolvedAt is null. Dropping
      // those rows would make cancellations invisible in a record that is
      // partly about how often they happen.
      final cancelled = _incident(
        status: 'cancelled',
        createdAt: DateTime(2026, 9, 4, 9, 0),
      );

      final days = ResponderTrends.closedPerDay([cancelled], now: now);
      final byDay = {for (final d in days) d.day: d.count};

      expect(byDay[DateTime(2026, 9, 4)], 1);
    });

    test('counts today', () {
      final today = _incident(
        createdAt: DateTime(2026, 9, 7, 8, 0),
        resolvedAt: DateTime(2026, 9, 7, 9, 0),
      );

      final days = ResponderTrends.closedPerDay([today], now: now);
      expect(days.last.count, 1);
    });
  });

  group('windowIsTruncated', () {
    List<ResponderIncidentModel> filled(DateTime oldest) => [
      for (var i = 0; i < ResponderTrends.historyCap; i++)
        _incident(
          id: '$i',
          createdAt: oldest,
          // One row sits at the oldest moment; the rest are recent.
          resolvedAt: i == 0 ? oldest : DateTime(2026, 9, 7, 9),
        ),
    ];

    test('a short history is never truncated', () {
      expect(
        ResponderTrends.windowIsTruncated([
          _incident(
            createdAt: DateTime(2026, 9, 6),
            resolvedAt: DateTime(2026, 9, 6),
          ),
        ], now: now),
        isFalse,
      );
    });

    test('a full history reaching back past the window is complete', () {
      // The cap cut off history OLDER than anything being charted, which costs
      // the chart nothing — every day in the window is fully represented.
      expect(
        ResponderTrends.windowIsTruncated(
          filled(DateTime(2026, 8, 25)),
          now: now,
        ),
        isFalse,
      );
    });

    test('a full history that starts inside the window may be hiding rows', () {
      expect(
        ResponderTrends.windowIsTruncated(
          filled(DateTime(2026, 9, 3)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('severityMix', () {
    test('keeps a bucket per tier even when the tier is unused', () {
      final mix = ResponderTrends.severityMix([
        _incident(createdAt: now, severity: 'critical'),
        _incident(createdAt: now, severity: 'critical'),
        _incident(createdAt: now, severity: 'low'),
      ]);

      expect(mix['critical'], 2);
      expect(mix['high'], 0);
      expect(mix['medium'], 0);
      expect(mix['low'], 1);
      expect(mix['unscored'], 0);
    });

    test('an unscored incident is counted, not dropped', () {
      // Untriaged does not mean harmless — it means the rubric has not run.
      // Silently discarding those rows would make the totals disagree with the
      // list they were derived from.
      final mix = ResponderTrends.severityMix([
        _incident(createdAt: now, severity: null),
        _incident(createdAt: now, severity: 'nonsense'),
      ]);

      expect(mix['unscored'], 2);
    });
  });

  group('medianMinutes', () {
    test('is null, not zero, when nothing has been resolved', () {
      expect(ResponderTrends.medianMinutes([]), isNull);
      expect(
        ResponderTrends.medianMinutes([
          _incident(status: 'cancelled', createdAt: now),
        ]),
        isNull,
      );
    });

    test('takes the middle value of an odd count', () {
      final base = DateTime(2026, 9, 7, 8);
      final incidents = [
        for (final m in [10, 90, 20])
          _incident(
            dispatchedAt: base,
            resolvedAt: base.add(Duration(minutes: m)),
            createdAt: base,
          ),
      ];

      expect(ResponderTrends.medianMinutes(incidents), 20);
    });

    test('averages the middle pair of an even count', () {
      final base = DateTime(2026, 9, 7, 8);
      final incidents = [
        for (final m in [10, 20, 30, 40])
          _incident(
            dispatchedAt: base,
            resolvedAt: base.add(Duration(minutes: m)),
            createdAt: base,
          ),
      ];

      expect(ResponderTrends.medianMinutes(incidents), 25);
    });

    test('is not dragged by one incident that ran overnight', () {
      // The reason it is a median at all. A mean over these is 189 minutes,
      // which describes none of the five calls.
      final base = DateTime(2026, 9, 7, 8);
      final incidents = [
        for (final m in [12, 15, 18, 20, 880])
          _incident(
            dispatchedAt: base,
            resolvedAt: base.add(Duration(minutes: m)),
            createdAt: base,
          ),
      ];

      expect(ResponderTrends.medianMinutes(incidents), 18);
    });

    test('ignores an incident that was dispatched but never closed', () {
      final base = DateTime(2026, 9, 7, 8);
      final incidents = [
        _incident(
          status: 'en_route',
          dispatchedAt: base,
          resolvedAt: null,
          createdAt: base,
        ),
        _incident(
          dispatchedAt: base,
          resolvedAt: base.add(const Duration(minutes: 30)),
          createdAt: base,
        ),
      ];

      expect(ResponderTrends.medianMinutes(incidents), 30);
    });
  });
}
