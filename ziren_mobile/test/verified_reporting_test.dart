// A resident reports only once an administrator has verified the account, and
// registration cannot finish without the ID and selfie (user request
// 2026-10-07). The server enforces it too (incident_standing.py).

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

ProfileModel _resident({int level = 0, String? idType, String role = 'resident'}) => ProfileModel(
  id: 'u1',
  email: 'resident@example.com',
  fullName: 'Juan Dela Cruz',
  role: role,
  approvalStatus: 'not_required',
  isVerified: false,
  verificationLevel: level,
  validIdType: idType,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('registration cannot finish without its evidence', () {
    test('a resident needs the ID type, a photo whose name matches, and a selfie', () {
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
      expect(d.missingEvidence, isNull);
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
    });

    test('a draft an older build saved as "skipped" is not let through', () async {
      SharedPreferences.setMockInitialValues({
        'registration_draft_v1':
            '{"role":"resident","firstName":"Juan","lastName":"Cruz","skippedVerification":true}',
      });
      final d = RegistrationDraft();
      expect(await d.restore(), isTrue);
      expect(d.missingEvidence, RegStep.idType);
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

    testWidgets('a verified resident goes straight on', (tester) async {
      final p = _FakeProfile(_resident(level: 2));
      expect(await start(tester, p), isFalse);
      expect(find.text('Verify your account to send reports'), findsNothing);
    });

    testWidgets('an unverified resident is told why, with a hotline and Verify', (tester) async {
      final p = _FakeProfile(_resident());
      await start(tester, p);
      expect(find.text('Verify your account to send reports'), findsOneWidget);
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
      expect(find.text('Verify your account to send reports'), findsOneWidget);
      expect(p.reloads, 1); // the fresh look is still under way
      p.answer(_resident());
      await tester.pumpAndSettle();
      expect(find.text('Verify your account to send reports'), findsOneWidget);
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
