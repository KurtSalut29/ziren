import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/features/incident_report/domain/incident_model.dart';
import 'package:ziren/features/incident_report/presentation/incident_labels.dart';
import 'package:ziren/features/notifications/domain/notification_provider.dart';
import 'package:ziren/features/notifications/presentation/notice_view.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/l10n/app_localizations_en.dart';
import 'package:ziren/l10n/app_localizations_fil.dart';

/// Every notice says the thing that actually happened, in the resident's language,
/// and offers the one thing worth doing about it.
///
/// The generic version - "Report update - (the status)" - said the same line for a
/// report the resident trashed, one the agency cancelled and one it rejected, and
/// printed the raw wire word `en_route` for a responder on the way.
AppNotification _n(
  String status, {
  NotificationKind kind = NotificationKind.status,
  String? detail,
  String? title,
  int? eta,
  String? agency,
}) => AppNotification(
  incidentId: 'inc-1',
  reportText: 'smoke',
  newStatus: status,
  receivedAt: DateTime.utc(2026, 9, 25),
  kind: kind,
  detail: detail,
  serverTitle: title,
  etaMinutes: eta,
  respondingAgency: agency,
);

final AppLocalizations en = AppLocalizationsEn();
final AppLocalizations fil = AppLocalizationsFil();

void main() {
  group('what happened, in its own words', () {
    test('the agency accepted the report', () {
      final v = noticeView(en, _n('accepted', kind: NotificationKind.accepted));
      expect(v.title, 'Report accepted');
      expect(v.body, contains('confirmed your report is real'));
      expect(v.primary, NoticeAction.dismiss);
    });

    test('a responder was sent, with how long it will take', () {
      final v = noticeView(en, _n('dispatched', eta: 7, agency: 'BFP Naval'));
      expect(v.title, 'Responder on the way');
      expect(v.body, 'A responder is on the way.');
      expect(v.etaLine, isNotNull);
      expect(v.etaLine, contains('BFP Naval'));
      expect(v.stage, 2);
    });

    test('en route is "on the way", not the raw wire word', () {
      final v = noticeView(en, _n('en_route'));
      expect(v.title, 'Responder on the way');
      expect(v.title, isNot(contains('en_route')));
      expect(v.body, contains('heading to your location'));
    });

    test('the responder has arrived', () {
      final v = noticeView(en, _n('arrived'));
      expect(v.title, 'Responder arrived');
      expect(v.body, contains('arrived at your location'));
      expect(v.stage, 2);
    });

    test('resolved offers to open the report', () {
      final v = noticeView(en, _n('resolved'));
      expect(v.title, 'Resolved');
      expect(v.stage, 3);
      expect(v.primary, NoticeAction.viewReport);
      expect(v.help, contains('rate'));
    });

    test('the agency cancelled it - and why', () {
      final v = noticeView(
        en,
        _n('cancelled', kind: NotificationKind.cancelled, detail: 'Duplicate of another report'),
      );
      expect(v.title, 'Report cancelled by the agency');
      expect(v.body, 'Reason: Duplicate of another report');
      expect(v.halted, isTrue);
      expect(v.help, contains('call the station'));
      expect(v.primary, NoticeAction.viewReport);
    });

    test('the agency cancelled it, no reason known yet', () {
      final v = noticeView(en, _n('cancelled', kind: NotificationKind.cancelled));
      expect(v.body, 'The agency cancelled your report.');
    });

    test('a rejection quotes the reason and points to what to do', () {
      final v = noticeView(
        en,
        _n('rejected', kind: NotificationKind.rejected, detail: 'Wrong agency'),
      );
      expect(v.title, 'Report not accepted');
      expect(v.quote, 'Wrong agency');
      expect(v.help, isNotNull);
    });

    test('a question offers to open the chat, not the report', () {
      final v = noticeView(
        en,
        _n('clarification_requested', kind: NotificationKind.clarification, detail: 'Which barangay?'),
      );
      expect(v.quote, 'Which barangay?');
      expect(v.primary, NoticeAction.openChat);
      expect(v.primaryLabel, 'Reply now');
    });

    test('a message quotes it and opens the chat', () {
      final v = noticeView(
        en,
        _n('message', kind: NotificationKind.message, detail: 'Please stay on the line.'),
      );
      expect(v.title, 'New message from the agency');
      expect(v.quote, 'Please stay on the line.');
      expect(v.primary, NoticeAction.openChat);
    });

    test('a message from the crew says it is from the crew', () {
      final v = noticeView(
        en,
        _n('message', kind: NotificationKind.message, detail: 'Two minutes away.', title: 'New message from the responder'),
      );
      expect(v.title, 'New message from the responder');
    });

    test('a status the app does not know yet is shown, not swallowed', () {
      final v = noticeView(en, _n('teleporting'));
      expect(v.title, 'teleporting');
    });
  });

  group('the same events in Filipino', () {
    test('every kind has words, and none is left in English by accident', () {
      final kinds = <AppNotification>[
        _n('accepted', kind: NotificationKind.accepted),
        _n('processing'),
        _n('dispatched', eta: 4),
        _n('en_route'),
        _n('arrived'),
        _n('resolved'),
        _n('cancelled', kind: NotificationKind.cancelled, detail: 'Duplicate'),
        _n('rejected', kind: NotificationKind.rejected, detail: 'Wrong agency'),
        _n('clarification_requested', kind: NotificationKind.clarification, detail: 'Saan?'),
        _n('message', kind: NotificationKind.message, detail: 'Hello'),
      ];
      for (final n in kinds) {
        final e = noticeView(en, n);
        final f = noticeView(fil, n);
        expect(f.title.trim(), isNotEmpty, reason: n.newStatus);
        expect(f.body.trim(), isNotEmpty, reason: n.newStatus);
        expect(f.title, isNot(e.title), reason: '${n.newStatus} title is untranslated');
      }
    });

    test('the reason is put into the Filipino sentence', () {
      final v = noticeView(
        fil,
        _n('cancelled', kind: NotificationKind.cancelled, detail: 'Doble ang ulat'),
      );
      expect(v.body, 'Dahilan: Doble ang ulat');
    });
  });

  group('the four-step rail', () {
    test('en route and arrived are part of "responder on the way"', () {
      expect(noticeStage('received'), 0);
      expect(noticeStage('processing'), 1);
      expect(noticeStage('dispatched'), 2);
      expect(noticeStage('en_route'), 2);
      expect(noticeStage('arrived'), 2);
      expect(noticeStage('resolved'), 3);
    });
  });

  group('the words for a status anywhere else in the app', () {
    test('en route and arrived have labels', () {
      expect(IncidentLabels.status(en, 'en_route'), 'Responder on the way');
      expect(IncidentLabels.status(en, 'arrived'), 'Responder arrived');
      expect(IncidentLabels.status(fil, 'arrived'), isNot('arrived'));
    });
  });

  group('who cancelled a report', () {
    IncidentModel report({String status = 'cancelled', DateTime? withdrawnAt, String? review}) =>
        IncidentModel(
          id: 'i',
          reportText: 't',
          status: status,
          submittedVia: 'internet',
          createdAt: DateTime.utc(2026, 9, 25),
          withdrawnAt: withdrawnAt,
          reviewStatus: review,
        );

    test('the resident trashing it is withdrawn, and only that goes in Trash', () {
      final r = report(withdrawnAt: DateTime.utc(2026, 9, 25));
      expect(r.isWithdrawn, isTrue);
      expect(r.isCancelledByAgency, isFalse);
    });

    test('the agency cancelling it is not in Trash', () {
      final r = report();
      expect(r.isWithdrawn, isFalse);
      expect(r.isCancelledByAgency, isTrue);
      expect(IncidentLabels.reportStatus(en, r), 'Cancelled by the agency');
    });

    test('a rejection is neither', () {
      final r = report(review: 'rejected');
      expect(r.isWithdrawn, isFalse);
      expect(r.isCancelledByAgency, isFalse);
      expect(r.isRejected, isTrue);
    });

    test('an open report is none of these', () {
      final r = report(status: 'dispatched');
      expect(r.isWithdrawn || r.isCancelledByAgency || r.isRejected, isFalse);
    });
  });
}
