import 'package:flutter/services.dart' show rootBundle;

/// Which legal document to show.
enum LegalDoc { privacy, terms }

/// The Terms of Use and Data Privacy Notice, and the versions of each that
/// this build ships.
///
/// Why the text is a bundled asset rather than a database row
/// ----------------------------------------------------------
/// The consent screen is shown before the user has an account, and often
/// before they have a usable connection — a resident standing in their yard in
/// Culaba with one bar is exactly the person this app exists for. A notice
/// fetched over the network would fail there, and "could not load the privacy
/// policy, tap to retry" is not an acceptable thing to put between someone and
/// an emergency app. Bundling it means it always renders.
///
/// The trade is that changing the text needs an app release. That is the right
/// trade: the version constants below are what a consent record points at, so
/// text and version can never drift apart if they ship together.
///
/// Bumping a version
/// -----------------
/// Change the text, bump the matching constant, and every existing user is
/// asked to read and accept again on next launch. Do not bump for a typo fix —
/// re-prompting the whole province is a cost, and a consent record that says
/// "1.1" should mean something changed that was worth re-reading.
abstract final class LegalDocuments {
  /// Bumping either of these re-prompts every existing account.
  static const String privacyVersion = '1.0';
  // 1.1 (2026-09-24): the connectivity section no longer describes an SMS
  // delivery path — the app now sends reports over the internet only.
  static const String termsVersion = '1.1';

  /// Filipino is the app's default and the language most of Biliran reads
  /// most comfortably; English is the fallback for anything not translated.
  static String assetPath(LegalDoc doc, String languageCode) {
    final lang = languageCode == 'en' ? 'en' : 'fil';
    final name = doc == LegalDoc.privacy ? 'privacy' : 'terms';
    return 'assets/legal/${name}_$lang.md';
  }

  static String versionOf(LegalDoc doc) =>
      doc == LegalDoc.privacy ? privacyVersion : termsVersion;

  /// Load a document's text. Falls back to English if the localised file is
  /// missing, rather than showing an empty sheet.
  static Future<String> load(LegalDoc doc, String languageCode) async {
    try {
      return await rootBundle.loadString(assetPath(doc, languageCode));
    } catch (_) {
      return rootBundle.loadString(assetPath(doc, 'en'));
    }
  }
}
