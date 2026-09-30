import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/core/errors/failures.dart';
import 'package:ziren/features/announcements/data/announcement_repository.dart';
import 'package:ziren/features/announcements/domain/announcement_model.dart';
import 'package:ziren/features/announcements/presentation/active_alerts_card.dart';
import 'package:ziren/features/announcements/presentation/alert_response_panel.dart';
import 'package:ziren/features/announcements/presentation/announcement_detail_screen.dart';
import 'package:ziren/features/announcements/presentation/announcement_style.dart';
import 'package:ziren/features/notifications/domain/notification_provider.dart';
import 'package:ziren/features/notifications/presentation/notice_view.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/l10n/app_localizations_en.dart';
import 'package:ziren/l10n/app_localizations_fil.dart';

/// Safety alerts on the phone (2026-10-01): an evacuation order aimed at the
/// resident's barangay pops up, opens to "Are you safe?", and the answer goes to
/// the server - with the phone's position when they need help. And when the
/// answer cannot be sent, "I need help" points at the hotlines instead of
/// failing quietly.

final AppLocalizations en = AppLocalizationsEn();
final AppLocalizations fil = AppLocalizationsFil();

Map<String, dynamic> _evacJson({Map<String, dynamic>? mine, bool active = true, bool asks = true}) => {
  'id': 'ev1',
  'title': 'Forced evacuation: Atipolo',
  'body': 'Umalis na po. Tumataas ang tubig.',
  'category': 'evacuation',
  'target_type': 'resident',
  'created_at': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String(),
  'expires_at': null,
  'is_active': active,
  'is_open': active,
  'details': {
    'kind': 'forced',
    'centers': [
      {'name': 'Naval Central School', 'place': 'P. Inocentes St.'},
      {'name': '  '},
    ],
    'bring': 'Go-bag',
  },
  'target_municipalities': ['Naval'],
  'target_barangays': [
    {'id': 'b1', 'name': 'Atipolo', 'municipality': 'Naval'},
    {'id': 'b2', 'name': 'Caraycaray', 'municipality': 'Naval'},
  ],
  'asks_response': asks,
  'issuer_agency_type': 'MDRRMO',
  'my_response': mine,
};

class _FakeRepo extends AnnouncementRepository {
  _FakeRepo({this.items = const [], this.one, this.fail = false, this.ended = false});

  List<AnnouncementModel> items;
  AnnouncementModel? one;
  bool fail;
  bool ended;
  final calls = <Map<String, Object?>>[];

  @override
  Future<List<AnnouncementModel>> getAnnouncements() async => items;

  @override
  Future<AnnouncementModel?> getAnnouncement(String id) async => one;

  @override
  Future<AlertResponse> respond(String id, {required String status, String? note, double? latitude, double? longitude}) async {
    calls.add({'id': id, 'status': status, 'note': note, 'lat': latitude, 'lng': longitude});
    if (ended) throw const AlertEndedException('ended');
    if (fail) throw const NetworkFailure();
    return AlertResponse(status: status, note: note, respondedAt: DateTime.now());
  }
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('the model', () {
    test('reads the place, the facts and my answer', () {
      final a = AnnouncementModel.fromJson(_evacJson(mine: {'status': 'need_help', 'note': 'Roof', 'handled_at': null}));
      expect(a.placeLine(en), 'Naval · Atipolo, Caraycaray');
      expect(a.centers, [
        {'name': 'Naval Central School', 'place': 'P. Inocentes St.'},
      ]);
      expect(a.isUrgent, isTrue);
      expect(a.canAnswer, isTrue);
      expect(a.myResponse!.needsHelp, isTrue);
      expect(a.issuer, 'MDRRMO');
    });

    test('an announcement from before migration 043 still reads', () {
      final a = AnnouncementModel.fromJson({
        'id': 'm1', 'title': 'Maintenance', 'body': 'Down at 2am', 'category': 'maintenance',
        'created_at': '2026-09-30T18:00:00Z', 'expires_at': null,
      });
      expect(a.placeLine(en), 'Whole province');
      expect(a.placeLine(fil), 'Buong probinsya');
      expect(a.isSafety, isFalse);
      expect(a.canAnswer, isFalse);
    });

    test('an ended alert cannot be answered', () {
      expect(AnnouncementModel.fromJson(_evacJson(active: false)).canAnswer, isFalse);
    });

    test('each kind has its own words, and an unknown one reads as an announcement', () {
      expect(announcementKindLabel(en, 'evacuation'), 'Evacuation order');
      expect(announcementKindLabel(fil, 'evacuation'), 'Utos na paglikas');
      expect(announcementKindLabel(en, 'something_new'), en.announceCategoryGeneral);
    });

    test('the chips say the signal and the rainfall, in colour and in words', () {
      final w = AnnouncementModel.fromJson({
        ..._evacJson(), 'category': 'weather', 'details': {'signal': 3, 'rainfall': 'orange', 'storm_name': 'Ada'},
      });
      final chips = announcementChips(en, w).map((c) => c.label).toList();
      expect(chips, ['Signal No. 3', 'Orange rainfall warning', 'Ada']);
      expect(announcementChips(en, AnnouncementModel.fromJson(_evacJson())).first.label, 'Forced');
      expect(announcementFacts(en, AnnouncementModel.fromJson(_evacJson())).first.value, 'Naval Central School — P. Inocentes St.');
    });
  });

  group('the stored notice', () {
    Map<String, dynamic> row(String type, Map<String, dynamic> meta) => {
      'id': 'n-9', 'type': type, 'title': 'Evacuation order: Forced evacuation: Atipolo',
      'body': 'Umalis na po.', 'created_at': '2026-10-01T02:00:00Z', 'metadata': meta,
    };

    test('a safety alert becomes a notice that opens the alert', () {
      final n = NotificationProvider.fromStoredRow(row('announcement.published', {
        'announcement_id': 'ev1', 'category': 'evacuation', 'urgent': true, 'asks_response': true,
        'title': 'Forced evacuation: Atipolo',
      }))!;
      expect(n.kind, NotificationKind.announcement);
      expect(n.isAnnouncement, isTrue);
      expect(n.announcementId, 'ev1');
      expect(n.serverTitle, 'Forced evacuation: Atipolo');
      expect(n.eventKey, 'announcement:n-9');

      final view = noticeView(en, n);
      expect(view.primary, NoticeAction.openAnnouncement);
      expect(view.primaryLabel, en.annRespondNow);
      expect(view.title, 'Evacuation order');
      expect(view.body, 'Forced evacuation: Atipolo');
      expect(view.eyebrow, en.annNoticeEyebrow);
    });

    test('an ordinary announcement does not pop up (it stays in the list)', () {
      expect(
        NotificationProvider.fromStoredRow(row('announcement.published', {
          'announcement_id': 'r1', 'category': 'relief', 'urgent': false,
        })),
        isNull,
      );
    });

    test('a notice without an announcement id is dropped, not shown broken', () {
      expect(NotificationProvider.fromStoredRow(row('announcement.published', {'urgent': true})), isNull);
    });

    test('a station reaching you is told in words, with who it was', () {
      final n = NotificationProvider.fromStoredRow(row('announcement.help_acknowledged', {
        'announcement_id': 'ev1', 'station': 'Naval MDRRMO',
      }))!;
      expect(n.kind, NotificationKind.helpAcknowledged);
      final view = noticeView(fil, n);
      expect(view.title, fil.annHelpAckTitle);
      expect(view.body, contains('Naval MDRRMO'));
      expect(view.primary, NoticeAction.openAnnouncement);
    });
  });

  group('answering', () {
    testWidgets('"I am safe" is sent at once and the panel says so', (tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(_app(AlertResponsePanel(announcement: AnnouncementModel.fromJson(_evacJson()), repository: repo)));
      await tester.tap(find.byKey(const Key('alert-safe')));
      await tester.pumpAndSettle();
      expect(repo.calls.single['status'], 'safe');
      expect(repo.calls.single['lat'], isNull, reason: 'a safe answer does not send where the phone is');
      expect(find.byKey(const Key('alert-answered-safe')), findsOneWidget);
      expect(find.text(en.annYouSaidSafe), findsOneWidget);
    });

    testWidgets('"I need help" asks for a line and sends it with the position', (tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(_app(AlertResponsePanel(
        announcement: AnnouncementModel.fromJson(_evacJson()),
        repository: repo,
        positionReader: (_) => (latitude: 11.56, longitude: 124.39),
      )));
      await tester.tap(find.byKey(const Key('alert-need-help')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('alert-help-note')), 'Three of us on the roof');
      await tester.tap(find.text(en.annNeedHelpSend));
      await tester.pumpAndSettle();
      expect(repo.calls.single, {'id': 'ev1', 'status': 'need_help', 'note': 'Three of us on the roof', 'lat': 11.56, 'lng': 124.39});
      expect(find.byKey(const Key('alert-answered-help')), findsOneWidget);
    });

    testWidgets('backing out of "I need help" sends nothing', (tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(_app(AlertResponsePanel(announcement: AnnouncementModel.fromJson(_evacJson()), repository: repo)));
      await tester.tap(find.byKey(const Key('alert-need-help')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.annCancel));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.byKey(const Key('alert-need-help')), findsOneWidget);
    });

    testWidgets('when "I need help" cannot be sent, it offers the hotlines', (tester) async {
      final repo = _FakeRepo(fail: true);
      await tester.pumpWidget(_app(AlertResponsePanel(announcement: AnnouncementModel.fromJson(_evacJson()), repository: repo)));
      await tester.tap(find.byKey(const Key('alert-need-help')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.annNeedHelpSend));
      await tester.pumpAndSettle();
      expect(find.text(en.annNotSentTitle), findsOneWidget);
      expect(find.text(en.annNotSentHelpBody), findsOneWidget);
      expect(find.text(en.accountOpenHotlines), findsOneWidget);
    });

    testWidgets('an alert that ended while open says so', (tester) async {
      final repo = _FakeRepo(ended: true);
      await tester.pumpWidget(_app(AlertResponsePanel(announcement: AnnouncementModel.fromJson(_evacJson()), repository: repo)));
      await tester.tap(find.byKey(const Key('alert-safe')));
      await tester.pumpAndSettle();
      expect(find.text(en.annEndedTitle), findsOneWidget);
    });

    testWidgets('an answer given before shows, and can be changed', (tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(_app(AlertResponsePanel(
        announcement: AnnouncementModel.fromJson(_evacJson(mine: {'status': 'safe'})),
        repository: repo,
      )));
      expect(find.byKey(const Key('alert-answered-safe')), findsOneWidget);
      await tester.tap(find.byKey(const Key('alert-change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-need-help')), findsOneWidget);
    });
  });

  group('screens', () {
    testWidgets('the detail puts "are you safe?" before the message, and lists where to go', (tester) async {
      final repo = _FakeRepo(one: AnnouncementModel.fromJson(_evacJson()));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: AnnouncementDetailScreen(id: 'ev1', repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('announcement-title')), findsOneWidget);
      expect(find.byKey(const Key('alert-response-panel')), findsOneWidget);
      expect(find.textContaining('Naval Central School'), findsOneWidget);
      final panelY = tester.getTopLeft(find.byKey(const Key('alert-response-panel'))).dy;
      final bodyY = tester.getTopLeft(find.text('Umalis na po. Tumataas ang tubig.')).dy;
      expect(panelY, lessThan(bodyY));
    });

    testWidgets('an alert that is gone, or not for this area, says so', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: AnnouncementDetailScreen(id: 'gone', repository: _FakeRepo()),
      ));
      await tester.pumpAndSettle();
      expect(find.text(en.annNotFoundTitle), findsOneWidget);
    });

    testWidgets('an ended alert shows it ended and asks nothing', (tester) async {
      final repo = _FakeRepo(one: AnnouncementModel.fromJson({..._evacJson(active: false), 'ended_by': {'title': 'All clear: Atipolo'}}));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: AnnouncementDetailScreen(id: 'ev1', repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('announcement-ended')), findsOneWidget);
      expect(find.textContaining('All clear: Atipolo'), findsOneWidget);
      expect(find.byKey(const Key('alert-safe')), findsNothing);
    });

    testWidgets('Home shows the most dangerous alert, with the answer, and counts the rest', (tester) async {
      final weather = AnnouncementModel.fromJson({..._evacJson(asks: false), 'id': 'wx', 'category': 'weather', 'title': 'Signal 2', 'details': {'signal': 2}});
      final relief = AnnouncementModel.fromJson({..._evacJson(asks: false), 'id': 'rl', 'category': 'relief', 'title': 'Relief'});
      final evac = AnnouncementModel.fromJson(_evacJson());
      await tester.pumpWidget(_app(ActiveAlertsCard(repository: _FakeRepo(items: [weather, relief, evac]))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-active-alert')), findsOneWidget);
      expect(find.text('Forced evacuation: Atipolo'), findsOneWidget);
      expect(find.byKey(const Key('alert-safe')), findsOneWidget);
      // Weather is the other urgent one; relief is not urgent and not counted.
      expect(find.text(en.annHomeMore(1)), findsOneWidget);
    });

    testWidgets('Home draws nothing on an ordinary day', (tester) async {
      final relief = AnnouncementModel.fromJson({..._evacJson(asks: false), 'id': 'rl', 'category': 'relief'});
      await tester.pumpWidget(_app(ActiveAlertsCard(repository: _FakeRepo(items: [relief]))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-active-alert')), findsNothing);
    });
  });
}
