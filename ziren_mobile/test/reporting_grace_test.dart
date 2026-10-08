// A new resident reports for their first 7 days, then only once verified
// (user request 2026-10-08; backend app/core/resident_trust.py). The app reads
// the deadline from /users/me, counts it down on Home, and gates the report
// buttons by the same rule.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ziren/features/settings/domain/profile_model.dart';
import 'package:ziren/features/settings/domain/profile_provider.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/widgets/verification_banner.dart';

class _FakeProfile extends ProfileProvider {
  _FakeProfile(this._p);
  final ProfileModel _p;

  @override
  ProfileModel? get profile => _p;
}

Map<String, dynamic> _json({
  int level = 0,
  String role = 'resident',
  DateTime? ends,
  bool locked = false,
  bool? pending,
  String? idType,
}) => {
  'id': 'u1',
  'email': 'a@b.c',
  'full_name': 'Maria Santos',
  'role': role,
  'approval_status': 'not_required',
  'is_verified': true,
  'verification_level': level,
  'reporting_grace_ends_at': ends?.toUtc().toIso8601String(),
  'reporting_locked': locked,
  'verification_pending': pending,
  'valid_id_type': idType,
};

ProfileModel _p({
  int level = 0,
  String role = 'resident',
  Duration? left,
  bool locked = false,
  bool? pending,
  String? idType,
}) => ProfileModel.fromJson(
  _json(
    level: level,
    role: role,
    ends: left == null ? null : DateTime.now().add(left),
    locked: locked,
    pending: pending,
    idType: idType,
  ),
);

void main() {
  group('the profile', () {
    test('reads the deadline, the server\'s verdict and "pending" from /users/me', () {
      final p = _p(left: const Duration(days: 3), pending: true);
      expect(p.reportingGraceEndsAt, isNotNull);
      expect(p.inReportingGrace, isTrue);
      expect(p.reportingLocked, isFalse);
      expect(p.hasSubmittedEvidence, isTrue);
    });

    test('days left count today: the last hours are "1", never "0 days left"', () {
      expect(_p(left: const Duration(days: 6, hours: 23)).graceDaysLeft, 7);
      expect(_p(left: const Duration(days: 2, hours: 23)).graceDaysLeft, 3);
      expect(_p(left: const Duration(hours: 5)).graceDaysLeft, 1);
      expect(_p(left: const Duration(minutes: 1)).graceDaysLeft, 1);
    });

    test('locked by the server, or by the clock once the deadline passes', () {
      expect(_p(locked: true).reportingLocked, isTrue);
      final passed = _p(left: const Duration(seconds: -1));
      expect(passed.reportingLockedByServer, isFalse);
      expect(passed.reportingLocked, isTrue);
      expect(passed.inReportingGrace, isFalse);
    });

    test('never locked: a verified resident, or staff', () {
      expect(_p(level: 2, locked: true).reportingLocked, isFalse);
      expect(_p(role: 'responder', locked: true).reportingLocked, isFalse);
    });

    test('a rejected resident is not "pending", whatever valid_id_type says', () {
      expect(_p(idType: 'philsys', pending: false).hasSubmittedEvidence, isFalse);
      // An older server sends no "pending": the old reading stands.
      expect(_p(idType: 'philsys').hasSubmittedEvidence, isTrue);
    });
  });

  group('the Home banner', () {
    Future<void> show(WidgetTester tester, ProfileModel p) => tester.pumpWidget(
      ChangeNotifierProvider<ProfileProvider>.value(
        value: _FakeProfile(p),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: VerificationBanner()),
        ),
      ),
    );

    String title(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('verification-banner-title'))).data!;

    testWidgets('counts the days down', (tester) async {
      await show(tester, _p(left: const Duration(days: 2, hours: 20)));
      expect(title(tester), '3 days left to verify your account');
      expect(find.textContaining('You can send reports until'), findsOneWidget);
      expect(find.text('Verify now'), findsOneWidget);
    });

    testWidgets('says when it is the last day', (tester) async {
      await show(tester, _p(left: const Duration(hours: 3)));
      expect(title(tester), 'Last day to verify your account');
    });

    testWidgets('in review during the week: reports still go through until the date', (tester) async {
      await show(tester, _p(left: const Duration(days: 4), pending: true));
      expect(title(tester), 'Verification in review');
      expect(find.textContaining('You can send reports until'), findsOneWidget);
      expect(find.text('Verify now'), findsNothing);
    });

    testWidgets('after the week: reports are paused, and how to start again', (tester) async {
      await show(tester, _p(left: const Duration(days: -1), pending: false));
      expect(title(tester), 'Reports paused until you are verified');
      expect(find.textContaining('2x2 ID photo'), findsOneWidget);
      expect(find.text('Verify now'), findsOneWidget);
    });

    testWidgets('a verified resident sees nothing', (tester) async {
      await show(tester, _p(level: 2));
      expect(find.byKey(const ValueKey('verification-banner-title')), findsNothing);
    });
  });
}
