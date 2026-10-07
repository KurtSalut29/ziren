import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/features/notifications/domain/notification_provider.dart';
import 'package:ziren/features/notifications/presentation/notice_view.dart';
import 'package:ziren/features/settings/domain/profile_model.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/l10n/app_localizations_en.dart';
import 'package:ziren/l10n/app_localizations_fil.dart';
import 'package:ziren/shared/widgets/suspension_banner.dart';

/// A resident is TOLD when an admin warns or suspends their account, and the app
/// knows a suspended account from one in good standing.
///
/// Before this there was no notice of any kind: a false-SOS flag changed the
/// account in silence and the resident found out when the SOS button stopped
/// working. The stored notifications for these (`account.warned`,
/// `account.suspended`, `account.reinstated`) carry no incident id, and the sync
/// used to throw away every row without one.
final AppLocalizations en = AppLocalizationsEn();
final AppLocalizations fil = AppLocalizationsFil();

Map<String, dynamic> _row(String type, Map<String, dynamic> meta, {String id = 'n-1'}) => {
  'id': id,
  'type': type,
  'title': 'server title',
  'body': 'server body',
  'created_at': '2026-10-01T02:00:00+00:00',
  'metadata': meta,
};

Map<String, dynamic> _profile(Map<String, dynamic> extra) => {
  'id': 'u-1',
  'email': 'resident@ziren.test',
  'full_name': 'Maria Santos',
  'role': 'resident',
  ...extra,
};

void main() {
  // An administrator's decision on the resident's ID reaches the phone as a
  // notice of its own (user report 2026-10-08: an approval used to change
  // nothing until the app was reopened, and nothing said so).
  group('a verification decision', () {
    test('an approval is an account notice, so the profile is read again', () {
      final n = NotificationProvider.fromStoredRow(
        _row('account.verified', {'at': '2026-10-08T02:00:00+00:00'}),
      )!;
      expect(n.kind, NotificationKind.accountVerified);
      expect(n.isAccount, isTrue);
      expect(n.eventKey, 'account:n-1');
      final v = noticeView(en, n);
      expect(v.title, 'Your account is verified');
      expect(v.body, contains('send emergency reports'));
      expect(noticeView(fil, n).title, 'Verified na ang account mo');
    });

    test('a refusal says what to send and opens Verify', () {
      final n = NotificationProvider.fromStoredRow(
        _row('account.verification_rejected', {'at': '2026-10-08T02:00:00+00:00'}),
      )!;
      expect(n.kind, NotificationKind.accountVerificationRejected);
      expect(n.isAccount, isTrue);
      final v = noticeView(en, n);
      expect(v.title, 'Your ID could not be verified');
      expect(v.primary, NoticeAction.verifyAgain);
      expect(v.primaryLabel, 'Verify again');
    });
  });

  group('a stored account notice becomes a notification', () {
    test('a warning, with the rule, the note and how many are left', () {
      final n = NotificationProvider.fromStoredRow(_row('account.warned', {
        'at': '2026-10-01T02:00:00+00:00',
        'violation': 'false_report',
        'violation_label': 'Sending a false or prank report',
        'note': 'Reported a fire that did not exist.',
        'warning_count': 1,
        'warnings_left': 2,
      }))!;

      expect(n.kind, NotificationKind.accountWarning);
      expect(n.isAccount, isTrue);
      expect(n.incidentId, isEmpty, reason: 'there is no report behind it');
      expect(n.violation, 'false_report');
      expect(n.detail, 'Reported a fire that did not exist.');
      expect(n.warningsLeft, 2);
      expect(n.serverId, 'n-1');
      expect(n.eventKey, 'account:n-1');
    });

    test('a suspension carries its end date', () {
      final n = NotificationProvider.fromStoredRow(_row('account.suspended', {
        'violation': 'spam',
        'note': 'Third duplicate this week.',
        'suspended_until': '2026-10-08T02:00:00+00:00',
        'indefinite': false,
      }))!;
      expect(n.kind, NotificationKind.accountSuspended);
      expect(n.suspendedUntil, DateTime.utc(2026, 10, 8, 2));
      expect(n.indefinite, isFalse);
    });

    test('an open-ended suspension has no date', () {
      final n = NotificationProvider.fromStoredRow(_row('account.suspended', {
        'violation': 'fake_identity',
        'suspended_until': null,
        'indefinite': true,
      }))!;
      expect(n.suspendedUntil, isNull);
      expect(n.indefinite, isTrue);
    });

    test('two account notices are two events, not one', () {
      final a = NotificationProvider.fromStoredRow(_row('account.warned', {'violation': 'spam'}, id: 'n-1'))!;
      final b = NotificationProvider.fromStoredRow(_row('account.warned', {'violation': 'spam'}, id: 'n-2'))!;
      expect(a.eventKey, isNot(b.eventKey));
    });

    test('a report notice still needs its incident id', () {
      expect(NotificationProvider.fromStoredRow(_row('incident.accepted', {'at': 'x'})), isNull);
      final n = NotificationProvider.fromStoredRow(
        _row('incident.cancelled', {'incident_id': 'inc-1', 'at': '2026-10-01T02:00:00+00:00'}),
      )!;
      expect(n.incidentId, 'inc-1');
      expect(n.isAccount, isFalse);
    });

    test('a notice meant for somebody else is ignored', () {
      expect(NotificationProvider.fromStoredRow(_row('station.created', {'x': 1})), isNull);
    });
  });

  group('what the resident reads', () {
    AppNotification note(
      NotificationKind kind, {
      String? violation = 'false_report',
      String? label,
      String? detail,
      DateTime? until,
      bool indefinite = false,
      int? left,
      bool wasSuspended = false,
    }) => AppNotification(
      incidentId: '',
      reportText: '',
      newStatus: kind.name,
      receivedAt: DateTime.utc(2026, 10, 1),
      kind: kind,
      detail: detail,
      violation: violation,
      violationLabel: label,
      suspendedUntil: until,
      indefinite: indefinite,
      warningsLeft: left,
      wasSuspended: wasSuspended,
    );

    test('a warning names the rule, quotes the admin, and counts down', () {
      final v = noticeView(en, note(NotificationKind.accountWarning, detail: 'Reported a fire that did not exist.', left: 2));
      expect(v.eyebrow, 'Account notice');
      expect(v.title, 'You received a warning');
      expect(v.body, 'Reason: Sending a false or prank report.');
      expect(v.quote, 'Reported a fire that did not exist.');
      expect(v.help, contains('2 more warnings'));
      expect(v.primary, NoticeAction.dismiss);
      expect(v.hasRail, isFalse, reason: 'no report, so no progress rail');
    });

    test('one warning left is singular', () {
      final v = noticeView(en, note(NotificationKind.accountWarning, left: 1));
      expect(v.help, startsWith('One more warning'));
    });

    test('no countdown once the limit is reached', () {
      expect(noticeView(en, note(NotificationKind.accountWarning, left: 0)).help, isNull);
    });

    test('a suspension says until when and offers the hotlines', () {
      final v = noticeView(en, note(NotificationKind.accountSuspended, violation: 'spam', until: DateTime.utc(2026, 10, 8, 2)));
      expect(v.title, 'Reporting is suspended');
      expect(v.body, contains('Sending repeated or duplicate reports'));
      expect(v.body, contains('You cannot send reports until October 8, 2026.'));
      expect(v.help, contains('911'));
      expect(v.primary, NoticeAction.hotlines);
      expect(v.primaryLabel, 'Emergency hotlines');
    });

    test('an open-ended suspension never prints the year 9999', () {
      final v = noticeView(en, note(NotificationKind.accountSuspended, indefinite: true));
      expect(v.body, contains('until further notice'));
      expect(v.body, isNot(contains('9999')));
    });

    test('being let back in', () {
      final lifted = noticeView(en, note(NotificationKind.accountReinstated, wasSuspended: true, detail: 'Appeal accepted.'));
      expect(lifted.title, 'You can send reports again');
      expect(lifted.body, 'Your suspension was lifted.');
      expect(lifted.quote, 'Appeal accepted.');
      final cleared = noticeView(en, note(NotificationKind.accountReinstated));
      expect(cleared.body, 'Your warnings were cleared.');
    });

    test('every violation has its own words, in both languages', () {
      const keys = ['false_report', 'false_sos', 'spam', 'abusive_language', 'fake_identity', 'other'];
      final seenEn = <String>{}, seenFil = <String>{};
      for (final k in keys) {
        final n = note(NotificationKind.accountWarning, violation: k);
        seenEn.add(violationWords(en, n));
        seenFil.add(violationWords(fil, n));
      }
      expect(seenEn.length, keys.length);
      expect(seenFil.length, keys.length);
      expect(seenEn.intersection(seenFil), isEmpty, reason: 'Filipino is not English');
    });

    test('a violation this build has never heard of uses the server words', () {
      final n = note(NotificationKind.accountWarning, violation: 'new_rule', label: 'Something new');
      expect(violationWords(en, n), 'Something new');
      expect(violationWords(en, note(NotificationKind.accountWarning, violation: 'new_rule')), isNotEmpty);
    });

    test('Filipino says it in Filipino', () {
      final w = noticeView(fil, note(NotificationKind.accountWarning, left: 2));
      expect(w.title, 'Nakatanggap ka ng babala');
      expect(w.body, startsWith('Dahilan:'));
      final s = noticeView(fil, note(NotificationKind.accountSuspended, indefinite: true));
      expect(s.title, 'Suspendido ang pag-uulat');
      expect(s.help, contains('911'));
      expect(s.primaryLabel, 'Mga emergency hotline');
    });
  });

  group('the profile knows a suspension from good standing', () {
    test('good standing', () {
      final p = ProfileModel.fromJson(_profile({}));
      expect(p.isSuspended, isFalse);
      expect(p.warningCount, 0);
    });

    test('a date ahead is a suspension', () {
      final p = ProfileModel.fromJson(_profile({
        'sos_warning_count': 3,
        'sos_suspended_until': DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String(),
      }));
      expect(p.isSuspended, isTrue);
      expect(p.suspensionIndefinite, isFalse);
      expect(p.warningCount, 3);
    });

    test('a date already past is not', () {
      final p = ProfileModel.fromJson(_profile({
        'sos_suspended_until': DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
      }));
      expect(p.isSuspended, isFalse);
    });

    test('until further notice', () {
      final p = ProfileModel.fromJson(_profile({'sos_suspended_until': '9999-12-31T00:00:00+00:00'}));
      expect(p.isSuspended, isTrue);
      expect(p.suspensionIndefinite, isTrue);
      expect(suspensionSentence(en, until: p.suspendedUntil, indefinite: p.suspensionIndefinite), contains('until further notice'));
    });

    test('an edit to the profile keeps the standing', () {
      final p = ProfileModel.fromJson(_profile({
        'sos_warning_count': 2,
        'sos_suspended_until': '9999-12-31T00:00:00+00:00',
      })).copyWith(fullName: 'Maria S.');
      expect(p.warningCount, 2);
      expect(p.isSuspended, isTrue);
    });
  });
}
