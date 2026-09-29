import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/responder/domain/responder_ack.dart';
import 'package:ziren/features/responder/domain/responder_incident_model.dart';
import 'package:ziren/features/responder/domain/responder_trends.dart';
import 'package:ziren/features/responder/domain/responder_vocabulary.dart';
import 'package:ziren/features/responder/presentation/responder_reports_screen.dart';
import 'package:ziren/features/responder/presentation/widgets/assignment_cards.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/widgets/profile_kit.dart';

ResponderIncidentModel _i({
  String status = 'dispatched',
  String ack = 'accepted',
  String? severity = 'high',
  String? category = 'fire',
  DateTime? created,
  DateTime? resolved,
}) => ResponderIncidentModel(
  id: '00000000-0000-0000-0000-0000006c2d56',
  reportText: 'Grass fire near the school',
  status: status,
  createdAt: created ?? DateTime.now().subtract(const Duration(hours: 3)),
  dispatchedAt: DateTime.now().subtract(const Duration(hours: 2)),
  resolvedAt: resolved,
  severity: severity,
  incidentCategory: category,
  locationAddress: 'Caraycaray, Naval, Biliran',
  landmarkNote: 'Basketball Court',
  latitude: 11.58,
  longitude: 124.40,
  ack: ResponderAck(state: ack, deadlineSeconds: 120),
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('phase', () {
    test('dispatched splits into "answer this" and "accepted"', () {
      expect(ResponderVocabulary.phase(_i(ack: 'pending')), ResponderPhase.newAssignment);
      expect(ResponderVocabulary.phase(_i(ack: 'overdue')), ResponderPhase.newAssignment);
      expect(ResponderVocabulary.phase(_i(ack: 'accepted')), ResponderPhase.accepted);
    });

    test('each wire status has its step on the five-step track', () {
      expect(ResponderVocabulary.stepIndex(ResponderVocabulary.phase(_i(status: 'en_route'))), 2);
      expect(ResponderVocabulary.stepIndex(ResponderVocabulary.phase(_i(status: 'arrived'))), 3);
      expect(ResponderVocabulary.stepIndex(ResponderVocabulary.phase(_i(status: 'resolved'))), 4);
      expect(ResponderVocabulary.stepIndex(ResponderVocabulary.phase(_i(status: 'cancelled'))), isNull);
    });

    test('status colour is never the agency hue: in progress is not red', () {
      final onScene = ResponderVocabulary.phaseColor(ResponderPhase.onScene);
      expect(onScene, isNot(ResponderVocabulary.color('critical')));
      expect(onScene, ResponderVocabulary.phaseColor(ResponderPhase.enRoute));
    });
  });

  group('trends', () {
    final now = DateTime(2026, 9, 30, 15); // a Wednesday
    ResponderIncidentModel closedOn(DateTime d, [String cat = 'fire']) =>
        _i(status: 'resolved', category: cat, resolved: d, created: d);

    test('closures land in the week (Monday-start) they closed in', () {
      final weeks = ResponderTrends.closedPerWeek([
        closedOn(DateTime(2026, 9, 29)), // this week (Mon 28)
        closedOn(DateTime(2026, 9, 28, 1)), // this week, Monday
        closedOn(DateTime(2026, 9, 27, 23)), // last week, Sunday
        closedOn(DateTime(2026, 8, 1)), // older than 8 weeks: not drawn
      ], now: now);
      expect(weeks, hasLength(8));
      expect(weeks.last.day, DateTime(2026, 9, 28));
      expect(weeks.last.count, 2);
      expect(weeks[6].count, 1);
      expect(weeks.fold<int>(0, (a, w) => a + w.count), 3);
      expect(ResponderTrends.closedThisWeek([closedOn(DateTime(2026, 9, 29))], now: now), 1);
    });

    test('kinds of call, biggest first', () {
      final mix = ResponderTrends.categoryMix([
        closedOn(now, 'medical_trauma'),
        closedOn(now),
        closedOn(now),
      ]);
      expect(mix.map((e) => '${e.key}:${e.value}'), ['fire:2', 'medical_trauma:1']);
    });
  });

  test('initials are first name + surname everywhere', () {
    expect(initialsOf('Mark Anthony Reyes'), 'MR');
    expect(initialsOf('Kurt Salut'), 'KS');
    expect(initialsOf('Ana'), 'A');
  });

  testWidgets('the next-up card asks for an answer while one is owed', (tester) async {
    await tester.pumpWidget(_app(NextUpAssignmentCard(
      incident: _i(ack: 'pending'),
      total: 2,
      onOpen: () {},
      onNavigate: () {},
    )));
    expect(find.text('Answer now'), findsOneWidget);
    expect(find.textContaining('1 OF 2'), findsOneWidget); // eyebrow is upper-case
    expect(find.text('Landmark: Basketball Court'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('once accepted it opens the call instead', (tester) async {
    await tester.pumpWidget(_app(NextUpAssignmentCard(
      incident: _i(status: 'en_route'),
      total: 1,
      onOpen: () {},
    )));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Answer now'), findsNothing);
    // No coordinates handler -> no Navigate button.
    expect(find.text('Navigate'), findsNothing);
  });

  testWidgets('a report row says when it was assigned, or when it closed', (tester) async {
    await tester.pumpWidget(_app(Column(children: [
      ReportRow(incident: _i(status: 'arrived'), onTap: () {}),
      ReportRow(
        incident: _i(status: 'resolved', resolved: DateTime.now().subtract(const Duration(days: 9))),
        onTap: () {},
      ),
    ])));
    expect(find.text('Assigned 2h ago'), findsOneWidget);
    expect(find.text('Closed 9d ago'), findsOneWidget);
    expect(find.text('On scene'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
  });
}
