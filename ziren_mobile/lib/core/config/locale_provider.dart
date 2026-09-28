import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's active locale and keeps it in step with the resident's
/// `preferred_language` profile field.
///
/// Why this needs local storage as well as the profile
/// ---------------------------------------------------
/// The profile is fetched over the network after sign-in. A resident opening
/// the app on a bad connection, or before logging in, would otherwise get the
/// default language until the request lands — and in this app the first screen
/// someone sees may be the one they are trying to report an emergency from.
/// The choice is therefore mirrored into SharedPreferences and read
/// synchronously at startup; the profile stays the source of truth and
/// overwrites it whenever it loads.
///
/// Supported locales
/// -----------------
/// `en` and `fil` only. The Settings picker used to offer Bisaya and Waray as
/// well, and none of the four did anything: the value was validated by the
/// backend, written to the database, and never read by a single line of UI
/// code. Rather than keep three dead options, the picker now offers what the
/// app can actually speak. Waray is the language of Biliran and belongs here —
/// it returns when a native speaker has reviewed the strings, because
/// machine-drafted Waray in an emergency app is not a safe thing to ship.
class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'preferred_language';

  /// Display names, as stored in `users.preferred_language` by the backend.
  /// These are the values the Settings picker writes, and the backend's
  /// validator accepts. Keep both sides in step.
  static const languageFilipino = 'Filipino';
  static const languageEnglish = 'English';

  /// What the picker offers today.
  static const supportedLanguageNames = <String>[
    languageFilipino,
    languageEnglish,
  ];

  /// Accepted by the backend but not yet translated. A profile carrying one of
  /// these — set before the picker was narrowed — falls back to Filipino
  /// rather than silently showing English to a Waray speaker.
  static const _unshippedLanguageNames = <String>['Bisaya', 'Waray'];

  static const supportedLocales = <Locale>[Locale('en'), Locale('fil')];

  Locale _locale = const Locale('fil');
  Locale get locale => _locale;

  /// The display name for the active locale, for the Settings picker.
  String get languageName =>
      _locale.languageCode == 'en' ? languageEnglish : languageFilipino;

  /// Read the stored choice. Call once at startup, before `runApp`, so the
  /// first frame is already in the right language.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored != null) {
        _locale = localeForLanguageName(stored);
        notifyListeners();
      }
    } catch (_) {
      // A failed preferences read must not stop the app from starting.
      // The default locale stands.
    }
  }

  /// Apply the language held on the resident's profile. Called when the
  /// profile loads, so a resident who set their language on another device
  /// gets it here too.
  Future<void> syncFromProfile(String? preferredLanguage) async {
    if (preferredLanguage == null) return;
    await setLanguageName(preferredLanguage);
  }

  /// Change the language and remember it. `name` is a display name
  /// ('Filipino', 'English'), matching what the backend stores.
  Future<void> setLanguageName(String name) async {
    final next = localeForLanguageName(name);
    if (next == _locale) return;
    _locale = next;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, name);
    } catch (_) {
      // The in-memory change already took effect; losing the persisted copy
      // only means the choice is re-read from the profile next launch.
    }
  }

  /// The language name persisted on this device, for code with no
  /// BuildContext to reach the provider through — chiefly registration, which
  /// must record the choice made during onboarding onto the new account.
  static Future<String> storedLanguageName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored != null && supportedLanguageNames.contains(stored)) {
        return stored;
      }
    } catch (_) {}
    return languageFilipino;
  }

  /// Maps a stored display name onto a locale.
  ///
  /// Anything unrecognised — including the not-yet-translated Bisaya and
  /// Waray — resolves to Filipino, which is closer for a Biliran resident
  /// than English is.
  static Locale localeForLanguageName(String name) {
    if (name == languageEnglish) return const Locale('en');
    if (_unshippedLanguageNames.contains(name)) return const Locale('fil');
    return const Locale('fil');
  }
}
