/// App-wide configuration loaded from environment variables.
///
/// Secrets (Supabase URL/key, API base URL) must be supplied via
/// --dart-define-from-file=dart_defines.json at build time.
/// NEVER hardcode values here.
class AppConfig {
  // Populated via --dart-define-from-file=dart_defines.json
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Firebase Cloud Messaging (push notifications with the app closed;
  // evaluator findings #11 / #12). From the Firebase console: Project
  // settings -> General -> Your apps (Android). All four optional: without
  // them push stays off and notices arrive in the app as before.
  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
  static const String firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '');
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');

  static bool get pushConfigured =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;

  /// Sanity-check at startup — call this in main() before runApp().
  /// Prints a masked diagnostic so you can confirm keys are loaded.
  static void validate() {
    // ignore: avoid_print
    print(
      '[AppConfig] SUPABASE_URL   : ${supabaseUrl.isEmpty ? "EMPTY ❌" : "${supabaseUrl.substring(0, supabaseUrl.length.clamp(0, 35))}... ✅"}',
    );
    // ignore: avoid_print
    print(
      '[AppConfig] SUPABASE_ANON_KEY: ${supabaseAnonKey.isEmpty ? "EMPTY ❌" : "${supabaseAnonKey.substring(0, 10)}... ✅"}',
    );
    // ignore: avoid_print
    print(
      '[AppConfig] API_BASE_URL   : ${apiBaseUrl.isEmpty ? "EMPTY ❌" : "$apiBaseUrl ✅"}',
    );

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception(
        'Supabase config is missing. '
        'Run with: flutter run --dart-define-from-file=dart_defines.json',
      );
    }
  }
}
