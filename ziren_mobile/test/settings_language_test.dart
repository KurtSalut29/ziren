import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ziren/core/config/accessibility_provider.dart';
import 'package:ziren/core/config/locale_provider.dart';
import 'package:ziren/features/auth/domain/auth_provider.dart';
import 'package:ziren/features/settings/domain/profile_model.dart';
import 'package:ziren/features/settings/domain/profile_provider.dart';
import 'package:ziren/features/settings/presentation/settings_screen.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Tester's report, 2026-09-30: picked Filipino on the first screen, signed
/// in, opened Settings — and the language row said English. The account's
/// profile still held "English" from an earlier choice, Settings preferred
/// the profile, and opening Settings also switched the whole app to English.
/// The phone's own choice is the newest one; the profile only records it.

class _FakeProfile extends ProfileProvider {
  _FakeProfile(this._p);

  ProfileModel _p;
  final saved = <String?>[];

  @override
  ProfileModel? get profile => _p;

  @override
  bool get isLoading => false;

  @override
  Future<void> loadProfile({bool force = false}) async {}

  @override
  Future<bool> saveProfile({
    required String fullName,
    String? phoneNumber,
    String? barangay,
    String? municipalityAddress,
    String? preferredLanguage,
    required bool pushNotificationsEnabled,
    String? emergencyContactName,
    String? emergencyContactNumber,
  }) async {
    saved.add(preferredLanguage);
    _p = _p.copyWith(preferredLanguage: preferredLanguage);
    notifyListeners();
    return true;
  }
}

ProfileModel _profile(String? language) => ProfileModel(
  id: 'u1',
  email: 'resident@example.com',
  fullName: 'Juan Dela Cruz',
  role: 'resident',
  approvalStatus: 'not_required',
  isVerified: false,
  preferredLanguage: language,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
  });

  Future<(LocaleProvider, _FakeProfile)> pump(
    WidgetTester tester, {
    required String phone,
    required String? onProfile,
  }) async {
    tester.view.physicalSize = const Size(1100, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final locale = LocaleProvider();
    await locale.setLanguageName(phone);
    final profile = _FakeProfile(_profile(onProfile));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<ProfileProvider>.value(value: profile),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => AccessibilityProvider()),
        ],
        child: Consumer<LocaleProvider>(
          builder:
              (_, l, __) => MaterialApp(
                locale: l.locale,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                home: const SettingsScreen(),
              ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (locale, profile);
  }

  testWidgets('Settings shows the phone\'s language, not a stale profile one', (
    tester,
  ) async {
    final (locale, profile) = await pump(
      tester,
      phone: 'Filipino',
      onProfile: 'English',
    );

    // The app stays in Filipino — opening Settings used to flip it.
    expect(locale.locale.languageCode, 'fil');
    expect(find.text('Filipino'), findsOneWidget);
    expect(find.text('English'), findsNothing);
    // And the profile is corrected to match the phone.
    expect(profile.saved, ['Filipino']);
  });

  testWidgets('nothing is written when phone and profile already agree', (
    tester,
  ) async {
    final (locale, profile) = await pump(
      tester,
      phone: 'English',
      onProfile: 'English',
    );
    expect(locale.locale.languageCode, 'en');
    expect(find.text('English'), findsOneWidget);
    expect(profile.saved, isEmpty);
  });

  testWidgets('an account with no language on file gets the phone\'s', (
    tester,
  ) async {
    final (_, profile) = await pump(
      tester,
      phone: 'Filipino',
      onProfile: null,
    );
    expect(profile.saved, ['Filipino']);
  });
}
