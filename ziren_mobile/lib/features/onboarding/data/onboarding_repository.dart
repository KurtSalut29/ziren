import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/locale_provider.dart';
import '../domain/legal_documents.dart';

/// Remembers that a person has chosen a language and agreed to the notices.
///
/// Two places, on purpose
/// ----------------------
/// **SharedPreferences** gates the pre-login screens. It has to be local: the
/// consent screen runs before there is an account to attach anything to, and
/// it has to work with no connection. This is what makes the "only once"
/// behaviour instant.
///
/// **`public.users`** carries the real record — who agreed, to which version,
/// in which language, and when. Under RA 10173 consent has to be
/// demonstrable, and a boolean in a phone's preferences file demonstrates
/// nothing. It also makes the answer correct when the same handset is shared:
/// the device flag stops the screens reappearing for the person who already
/// agreed, and the per-account check catches a second person signing in on
/// the same phone, who has agreed to nothing.
///
/// The device flag is therefore an optimisation, and the row is the truth. If
/// the two disagree, the row wins.
class OnboardingRepository {
  OnboardingRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _kCompleted = 'onboarding_completed';
  static const _kTermsVersion = 'onboarding_terms_version';
  static const _kPrivacyVersion = 'onboarding_privacy_version';

  /// Has this device finished the language + consent screens, against the
  /// versions this build ships?
  ///
  /// A version bump makes this false again, which is the whole point of
  /// storing the versions rather than a bare boolean.
  Future<bool> isDeviceOnboarded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_kCompleted) ?? false)) return false;
      return prefs.getString(_kTermsVersion) == LegalDocuments.termsVersion &&
          prefs.getString(_kPrivacyVersion) == LegalDocuments.privacyVersion;
    } catch (_) {
      // A preferences read that throws must not strand someone on a blank
      // screen. Showing onboarding again is a mild annoyance; failing to
      // start is not survivable for an emergency app.
      return false;
    }
  }

  Future<void> markDeviceOnboarded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCompleted, true);
      await prefs.setString(_kTermsVersion, LegalDocuments.termsVersion);
      await prefs.setString(_kPrivacyVersion, LegalDocuments.privacyVersion);
    } catch (_) {
      // Worst case the screens show once more next launch.
    }
  }

  /// Clears the device flag. Wired to a long-press on the splash wordmark so
  /// the flow can be demonstrated without reinstalling the app.
  Future<void> resetDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCompleted);
      await prefs.remove(_kTermsVersion);
      await prefs.remove(_kPrivacyVersion);
    } catch (_) {}
  }

  /// Write the consent record onto the signed-in user's profile.
  ///
  /// Safe to call more than once — re-accepting after a version bump simply
  /// overwrites with the newer version and a fresh timestamp.
  ///
  /// Failure is swallowed deliberately. This runs immediately after sign-up,
  /// on the same rural connection that may already be struggling with the ID
  /// upload. Losing an account because the consent write timed out would be a
  /// far worse outcome than a row that needs backfilling — the device flag
  /// still holds, and [hasAccountConsented] will ask again on next launch if
  /// it genuinely did not land.
  ///
  /// [locale] defaults to whatever language the app is currently set to,
  /// read from the same preferences key LocaleProvider writes. Callers deep in
  /// the auth layer have no BuildContext to reach the provider through, and
  /// threading one down just to record consent would be worse.
  Future<void> recordConsentForCurrentUser({String? locale}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final resolved = locale ?? await _storedLanguageCode();
    try {
      await _client
          .from('users')
          .update({
            'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
            'terms_version': LegalDocuments.termsVersion,
            'privacy_version': LegalDocuments.privacyVersion,
            'consent_locale': resolved == 'en' ? 'en' : 'fil',
          })
          .eq('id', user.id);
    } catch (_) {}
  }

  Future<String> _storedLanguageCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('preferred_language');
      if (name == null) return 'fil';
      return LocaleProvider.localeForLanguageName(name).languageCode;
    } catch (_) {
      return 'fil';
    }
  }

  /// Has the signed-in account agreed to the versions this build ships?
  ///
  /// Returns true on any failure. A network hiccup must not push a resident
  /// who has already consented back through the consent screen on the way to
  /// reporting an emergency; the device flag has already gated the common
  /// case, and this check exists for the shared-handset case, not as a
  /// security control.
  Future<bool> hasAccountConsented() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final row =
          await _client
              .from('users')
              .select('terms_accepted_at, terms_version, privacy_version')
              .eq('id', user.id)
              .maybeSingle();
      if (row == null) return true;
      if (row['terms_accepted_at'] == null) return false;
      return row['terms_version'] == LegalDocuments.termsVersion &&
          row['privacy_version'] == LegalDocuments.privacyVersion;
    } catch (_) {
      return true;
    }
  }
}
