import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ziren/core/errors/failures.dart';
import 'package:ziren/core/utils/validators.dart';
import 'package:ziren/features/hotlines/presentation/hotlines_view.dart';
import 'package:ziren/features/safety/presentation/safety_guide_screen.dart';
import 'package:ziren/features/settings/domain/profile_model.dart';
import 'package:ziren/features/settings/presentation/change_password_screen.dart';
import 'package:ziren/features/settings/presentation/help_faq_screen.dart';
import 'package:ziren/features/settings/presentation/settings_screen.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// The redesigned Settings screens do what they say: the password is really
/// changed (and refused for the right reasons), the editor validates and
/// saves its own fields, and the help, FAQ, safety and hotline screens open
/// and switch the way they look like they should.

/// A home screen with one button that pushes [screen] and records what it
/// popped with, so "saves and goes back" can be asserted.
class _Launcher extends StatefulWidget {
  const _Launcher(this.screen);
  final Widget screen;
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  Object? popped = 'not yet';
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          final r = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => widget.screen),
          );
          setState(() => popped = r);
        },
        child: Text('open · $popped'),
      ),
    ),
  );
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<AppLocalizations> _open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(_Launcher(screen)));
  await tester.tap(find.textContaining('open'));
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(Scaffold).last));
}

const _profile = ProfileModel(
  id: 'u1',
  email: 'kurt@example.com',
  fullName: 'Kurt Salut',
  role: 'resident',
  approvalStatus: 'not_required',
  isVerified: false,
  phoneNumber: '09171234567',
  barangay: 'Larrazabal',
  municipalityAddress: 'Naval',
  emergencyContactName: 'Ana Salut',
  emergencyContactNumber: '09181234567',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the same mobile number is recognised however it is written', () {
    expect(Validators.sameMobile('0917 123 4567', '+63 917-123-4567'), isTrue);
    expect(Validators.sameMobile('09171234567', '09181234567'), isFalse);
    expect(Validators.sameMobile('', ''), isFalse);
  });

  group('Change password', () {
    Future<void> fill(WidgetTester tester, String current, String next, String confirm) async {
      await tester.enterText(find.byKey(const Key('cp-current')), current);
      await tester.enterText(find.byKey(const Key('cp-new')), next);
      await tester.enterText(find.byKey(const Key('cp-confirm')), confirm);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is sent until the form is right', (tester) async {
      var calls = 0;
      final t = await _open(
        tester,
        ChangePasswordScreen(onSubmit: ({required currentPassword, required newPassword}) async => calls++),
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.text(t.cpEnterCurrent), findsOneWidget);
      expect(find.text('Enter a password.'), findsOneWidget);

      await fill(tester, 'OldPass123', 'NewPass123', 'NewPass124');
      expect(find.text(t.cpMismatch), findsOneWidget);

      await fill(tester, 'OldPass123', 'OldPass123', 'OldPass123');
      expect(find.text(t.cpSameAsOld), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('a wrong current password is said under that field', (tester) async {
      final t = await _open(
        tester,
        ChangePasswordScreen(
          onSubmit: ({required currentPassword, required newPassword}) async =>
              throw const WrongPasswordFailure(),
        ),
      );
      await fill(tester, 'Wrong1234', 'NewPass123', 'NewPass123');
      expect(find.text(t.cpWrongCurrent), findsOneWidget);
      // Typing again clears it rather than leaving a stale error.
      await tester.enterText(find.byKey(const Key('cp-current')), 'Wrong12345');
      await tester.pump();
      expect(find.text(t.cpWrongCurrent), findsNothing);
    });

    testWidgets('a good change sends both passwords and goes back', (tester) async {
      String? sentCurrent;
      String? sentNew;
      await _open(
        tester,
        ChangePasswordScreen(
          onSubmit: ({required currentPassword, required newPassword}) async {
            sentCurrent = currentPassword;
            sentNew = newPassword;
          },
        ),
      );
      await fill(tester, 'OldPass123', 'NewPass123', 'NewPass123');
      expect(sentCurrent, 'OldPass123');
      expect(sentNew, 'NewPass123');
      expect(find.text('open · true'), findsOneWidget);
    });
  });

  group('Edit personal information', () {
    testWidgets('its own number as the emergency contact is refused', (tester) async {
      var saved = 0;
      final t = await _open(
        tester,
        PersonalInfoEditorScreen(
          profile: _profile,
          preferredLanguage: 'English',
          pushNotificationsEnabled: true,
          onSave: (_) async {
            saved++;
            return true;
          },
        ),
      );
      await tester.enterText(find.byKey(const Key('edit-ec-number')), '+63 917 123 4567');
      await tester.tap(find.text(t.settingsSaveChanges));
      await tester.pumpAndSettle();
      expect(find.text(t.regEmergencySameAsYours), findsOneWidget);

      await tester.enterText(find.byKey(const Key('edit-name')), '  ');
      await tester.tap(find.text(t.settingsSaveChanges));
      await tester.pumpAndSettle();
      expect(find.text(t.respProfileNameRequired), findsOneWidget);
      expect(saved, 0);
    });

    testWidgets('saves exactly what was typed, then goes back', (tester) async {
      Map<String, String>? fields;
      final t = await _open(
        tester,
        PersonalInfoEditorScreen(
          profile: _profile,
          preferredLanguage: 'English',
          pushNotificationsEnabled: true,
          onSave: (f) async {
            fields = f;
            return true;
          },
        ),
      );
      await tester.enterText(find.byKey(const Key('edit-name')), 'Kurt Michael Salut');
      await tester.tap(find.text(t.settingsSaveChanges));
      await tester.pumpAndSettle();
      expect(fields?['full_name'], 'Kurt Michael Salut');
      expect(fields?['emergency_contact_number'], '09181234567');
      expect(find.text('open · true'), findsOneWidget);
    });

    testWidgets('leaving with unsaved edits asks first', (tester) async {
      final t = await _open(
        tester,
        PersonalInfoEditorScreen(
          profile: _profile,
          preferredLanguage: 'English',
          pushNotificationsEnabled: true,
          onSave: (_) async => true,
        ),
      );
      await tester.enterText(find.byKey(const Key('edit-name')), 'Someone Else');
      await tester.pump(); // a person cannot press Back in the same frame
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(t.settingsDiscardTitle), findsOneWidget);

      await tester.tap(find.text(t.settingsKeepEditing));
      await tester.pumpAndSettle();
      expect(find.text(t.settingsEditPersonalInfo), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settingsDiscard));
      await tester.pumpAndSettle();
      expect(find.text('open · false'), findsOneWidget);
    });
  });

  testWidgets('Help & FAQ opens one answer at a time', (tester) async {
    final t = await _open(tester, const HelpFaqScreen());
    expect(find.text(t.settingsFaqReportA), findsOneWidget);
    await tester.tap(find.text(t.settingsFaqOfflineQ));
    await tester.pumpAndSettle();
    expect(find.text(t.settingsFaqOfflineA), findsOneWidget);
    expect(find.text(t.settingsFaqReportA), findsNothing);
    // The old sheet told people a report was impossible offline; the answer
    // now points at the hotlines.
    expect(t.settingsFaqOfflineA, contains('hotlines'));
  });

  testWidgets('Safety Guide opens an emergency on its own page', (tester) async {
    final t = await _open(tester, const SafetyGuideScreen());
    expect(find.text(t.safetyFireTitle), findsOneWidget);
    expect(find.text(t.safetyCrimeTitle), findsOneWidget);
    await tester.tap(find.text(t.safetyFireTitle));
    await tester.pumpAndSettle();
    expect(find.byType(SafetyGuideDetailScreen), findsOneWidget);
    expect(find.text(t.safetyFireStep1), findsOneWidget);
    expect(find.text(t.safetyFireStep6), findsOneWidget);
    expect(find.text(t.safetyGuideCallHotline), findsOneWidget);
  });

  testWidgets('Hotlines: 911 first, and the agency filter filters', (tester) async {
    final t = await _open(tester, const HotlinesScreen());
    final national = tester.getTopLeft(find.text(t.hotlinesNational)).dy;
    final intro = tester.getTopLeft(find.text(t.hotlinesScreenIntro)).dy;
    expect(national, lessThan(intro));

    // Station names read "BFP Almeria Station"; the pills are bare "BFP".
    expect(find.textContaining('BFP '), findsWidgets);
    await tester.tap(find.text('PNP'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BFP '), findsNothing);
    expect(find.textContaining('PNP '), findsWidgets);
  });
}
