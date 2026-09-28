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
