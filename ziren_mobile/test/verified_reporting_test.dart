// A new resident reports for their first 7 days; after that only once an
// administrator has verified the account (user request 2026-10-08, softening
// 2026-10-07's verified-only rule). Registration sends all of the evidence -
// ID, selfie, 2x2 ID photo - or, with "Verify later", none of it. The server
// enforces the same rule (incident_standing.py, resident_trust.py).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ziren/features/registration/domain/registration_draft.dart';
import 'package:ziren/features/settings/domain/profile_model.dart';
import 'package:ziren/features/settings/domain/profile_provider.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/widgets/report_gate.dart';

class _FakeProfile extends ProfileProvider {
  _FakeProfile(this._p, {this.onReload});

  ProfileModel _p;
  final ProfileModel Function()? onReload;
  int reloads = 0;

  @override
  ProfileModel? get profile => _p;

  @override
  Future<void> loadProfile({bool force = false}) async {
    reloads++;
    if (onReload != null) _p = onReload!();
  }
}

/// A server that has not answered yet: [answer] is the reply arriving.
class _SlowProfile extends ProfileProvider {
  _SlowProfile(this._p);

  ProfileModel _p;
  final _reply = Completer<void>();
  int reloads = 0;

  @override
  ProfileModel? get profile => _p;

  @override
  Future<void> loadProfile({bool force = false}) {
    reloads++;
    return _reply.future;
  }

  void answer(ProfileModel fresh) {
    _p = fresh;
    _reply.complete();
  }
}

/// By default the first week is over (yesterday), so the rule bites.
ProfileModel _resident({
  int level = 0,
  String? idType,
  String role = 'resident',
  DateTime? graceEnds,
  bool? pending,
}) => ProfileModel(
  id: 'u1',
  email: 'resident@example.com',
  fullName: 'Juan Dela Cruz',
  role: role,
  approvalStatus: 'not_required',
  isVerified: false,
  verificationLevel: level,
  validIdType: idType,
  reportingGraceEndsAt:
      level >= 2 || role != 'resident'
          ? null
          : (graceEnds ?? DateTime.now().subtract(const Duration(days: 1))),
  verificationPending: pending,
);

const _locked = 'Your 7 days to verify are over';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('registration cannot finish without its evidence', () {
    test('a resident needs the ID type, a matching photo, a selfie and a 2x2 photo', () {
      final d = RegistrationDraft();
      expect(d.missingEvidence, RegStep.idType);
      d.validIdType = 'philsys';
      expect(d.missingEvidence, RegStep.idCapture);
      d.idImagePath = '/tmp/id.jpg';
      d.ocrNameMatched = false; // the name on the card is someone else's
      expect(d.missingEvidence, RegStep.idCapture);
      d.ocrNameMatched = true;
      expect(d.missingEvidence, RegStep.selfie);
      d.selfiePath = '/tmp/me.jpg';
      expect(d.missingEvidence, RegStep.portrait);
      d.portraitPath = '/tmp/2x2.jpg'; // picked, but refused or not checked yet
      expect(d.missingEvidence, RegStep.portrait);
      d.portraitChecks = {'verdict': 'match', 'score': 0.71};
      expect(d.missingEvidence, isNull);
      expect(d.steps, contains(RegStep.portrait));
      expect(d.next(RegStep.selfie), RegStep.portrait);
      expect(d.next(RegStep.portrait), RegStep.review);
    });

    test('a responder needs the agency ID with a matching name, and a selfie', () {
      final d = RegistrationDraft()..role = 'responder';
      expect(d.missingEvidence, RegStep.responderDetails);
      d.agencyIdImagePath = '/tmp/agency.jpg';
      expect(d.missingEvidence, RegStep.responderDetails);
      d.agencyIdNameMatched = true;
      expect(d.missingEvidence, RegStep.selfie);
      d.selfiePath = '/tmp/me.jpg';
      expect(d.missingEvidence, isNull);
      expect(d.steps, isNot(contains(RegStep.portrait))); // residents only
    });

    test('"Verify later": nothing is missing, and nothing is sent', () {
      final d = RegistrationDraft()
        ..validIdType = 'philsys'
        ..idImagePath = '/tmp/id.jpg'; // half-collected before choosing
      expect(d.missingEvidence, RegStep.idCapture);
      d.skippedVerification = true;
      expect(d.missingEvidence, isNull);
      expect(d.sendsIdentityEvidence, isFalse);
      // A responder cannot leave their agency ID for later.
      final r = RegistrationDraft()
        ..role = 'responder'
        ..skippedVerification = true;
      expect(r.missingEvidence, RegStep.responderDetails);
      expect(r.sendsIdentityEvidence, isTrue);
    });

    test('Back from the review after "Verify later" passes the identity steps', () {
      final d = RegistrationDraft();
      expect(d.previous(RegStep.review), RegStep.portrait);
      d.skippedVerification = true;
      expect(d.previous(RegStep.review), RegStep.contact);
      expect(d.previous(RegStep.contact), RegStep.address);
    });

    test('"Verify later" and the 2x2 photo survive a restart', () async {
      final d = RegistrationDraft()
        ..skippedVerification = true
        ..portraitPath = '/tmp/2x2.jpg'
        ..portraitChecks = {'verdict': 'uncertain', 'score': 0.3};
      d.commit();
      await Future<void>.delayed(Duration.zero);
      final back = RegistrationDraft();
      expect(await back.restore(), isTrue);
      expect(back.skippedVerification, isTrue);
      expect(back.portraitPath, '/tmp/2x2.jpg');
      expect(back.portraitChecks, {'verdict': 'uncertain', 'score': 0.3});
    });
  });

  group('starting a report', () {
    Future<Completer<bool>> tapReport(WidgetTester tester, ProfileProvider profile) async {
      final refused = Completer<bool>();
      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileProvider>.value(
          value: profile,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: TextButton(
                      onPressed: () async => refused.complete(await refuseReport(context)),
                      child: const Text('Report'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Report'));
      return refused;
    }

    Future<bool?> start(WidgetTester tester, ProfileProvider profile) async {
      final refused = await tapReport(tester, profile);
      await tester.pumpAndSettle();
      return refused.isCompleted ? refused.future : null;
    }

    testWidgets('in the first week an unverified resident goes straight on', (tester) async {
      final p = _FakeProfile(
        _resident(graceEnds: DateTime.now().add(const Duration(days: 3))),
      );
      expect(await start(tester, p), isFalse);
      expect(find.text(_locked), findsNothing);
      expect(p.reloads, 0); // nothing to look up: the server takes the report
    });

    testWidgets('the week ends while the profile is on screen: refused by the clock', (tester) async {
      // Loaded with a deadline that has since passed; the server said "not
      // locked" when it was read.
      final p = _FakeProfile(
        _resident(graceEnds: DateTime.now().subtract(const Duration(minutes: 1))),
      );
      expect(p.profile!.reportingLockedByServer, isFalse);
      await start(tester, p);
      expect(find.text(_locked), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('rejected (nothing pending any more): asked to verify again', (tester) async {
      // valid_id_type survives a rejection; the server's "pending" does not.
      final p = _FakeProfile(_resident(idType: 'philsys', pending: false));
      await start(tester, p);
      expect(find.text(_locked), findsOneWidget);
      expect(find.text('Verify my account'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('a verified resident goes straight on', (tester) async {
      final p = _FakeProfile(_resident(level: 2));
      expect(await start(tester, p), isFalse);
      expect(find.text(_locked), findsNothing);
    });

    testWidgets('an unverified resident is told why, with a hotline and Verify', (tester) async {
      final p = _FakeProfile(_resident());
      await start(tester, p);
      expect(find.text(_locked), findsOneWidget);
      expect(find.text('Emergency hotlines'), findsOneWidget);
      expect(find.text('Verify my account'), findsOneWidget);
      // It still looks again, beside the dialog: an approval may have landed.
      expect(p.reloads, 1);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('the answer is on screen at once, not after the server replies', (tester) async {
      final p = _SlowProfile(_resident());
      final done = await tapReport(tester, p);
      await tester.pump(); // the tap
      await tester.pump(const Duration(milliseconds: 400)); // the dialog's fade
      expect(find.text(_locked), findsOneWidget);
      expect(p.reloads, 1); // the fresh look is still under way
      p.answer(_resident());
      await tester.pumpAndSettle();
      expect(find.text(_locked), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(await done.future, isTrue);
    });

    testWidgets('approved while the dialog is open: it closes and the report goes on', (tester) async {
      final p = _SlowProfile(_resident(idType: 'philsys'));
      final done = await tapReport(tester, p);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Waiting for an administrator'), findsOneWidget);
      p.answer(_resident(level: 2));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for an administrator'), findsNothing);
      expect(await done.future, isFalse);
    });

    testWidgets('one waiting for an administrator is told so, no Verify button', (tester) async {
      final p = _FakeProfile(_resident(level: 1, idType: 'philsys'));
      await start(tester, p);
      expect(find.text('Waiting for an administrator'), findsOneWidget);
      expect(find.text('Verify my account'), findsNothing);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('approved since the app loaded: the fresh profile lets them on', (tester) async {
      final p = _FakeProfile(_resident(idType: 'philsys'), onReload: () => _resident(level: 2));
      expect(await start(tester, p), isFalse);
      expect(find.text('Waiting for an administrator'), findsNothing);
    });

    testWidgets('a responder is not a resident and is not asked', (tester) async {
      final p = _FakeProfile(_resident(role: 'responder'));
      expect(await start(tester, p), isFalse);
    });
  });
}
