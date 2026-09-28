import 'package:speech_to_text/speech_to_text.dart' show LocaleName;

import '../../../core/config/locale_provider.dart';

/// Picks which speech-recognition locale to listen in.
///
/// The problem
/// -----------
/// Residents here report mostly in Waray and Bisaya. The app was hardcoded to
/// `en_PH`, so every one of those was being matched against English vocabulary
/// and phonetics — the recogniser was not failing, it was doing exactly what it
/// was told.
///
/// Fixing that is not simply "use the resident's language", because the device
/// may not have a recogniser for it. Waray in particular is very unlikely to be
/// installed on any handset.
///
/// The fallback order, and why
/// ---------------------------
/// When Waray is unavailable the obvious guess is Filipino — it is the national
/// language and certainly present. That is probably the wrong guess. Waray and
/// Cebuano are both Visayan languages and share far more phonology and
/// vocabulary with each other than either shares with Tagalog. A Cebuano
/// recogniser fed Waray speech should land closer than a Filipino one.
///
/// That is a hypothesis, not a fact, which is why [candidatesFor] is ordered
/// and public and the diagnostic screen can walk it: record one sentence, run
/// it through each candidate, compare. Measure before believing.
///
/// Nothing here decides severity. A bad transcript costs detail, never
/// urgency — the wizard chips carry the signals that set severity, and
/// triage_service treats them as overriding anything read from text.
class SpeechLocaleResolver {
  const SpeechLocaleResolver._();

  /// Ordered preference of language codes per spoken language.
  ///
  /// First match against what the device actually has wins. The list is a
  /// ranking, not a set: order carries the linguistic argument above.
  static List<String> candidatesFor(String languageName) {
    switch (languageName) {
      case 'Waray':
        // war: the real thing, if a device ever ships it.
        // ceb: nearest living relative — both Visayan.
        // fil: national language, distant but always installed.
        return const ['war', 'ceb', 'fil', 'en'];
      case 'Bisaya':
        return const ['ceb', 'fil', 'en'];
      case LocaleProvider.languageEnglish:
        return const ['en', 'fil'];
      case LocaleProvider.languageFilipino:
      default:
        return const ['fil', 'en'];
    }
  }

  /// Resolve to a locale id the device will accept, or null to let the
  /// platform use its own default.
  ///
  /// [available] is what `SpeechToText.locales()` returned. Ids come back in
  /// both `en_PH` and `en-PH` shapes depending on platform, and sometimes as a
  /// bare `en`, so matching is on the language subtag only.
  static String? resolve({
    required String languageName,
    required List<LocaleName> available,
  }) {
    if (available.isEmpty) return null;

    for (final code in candidatesFor(languageName)) {
      final match = _firstWithLanguage(available, code);
      if (match != null) return match.localeId;
    }
    return null;
  }

  /// Every device locale whose language subtag is [languageCode].
  static List<LocaleName> allWithLanguage(
    List<LocaleName> available,
    String languageCode,
  ) => available.where((l) => _languageOf(l.localeId) == languageCode).toList();

  static LocaleName? _firstWithLanguage(
    List<LocaleName> available,
    String languageCode,
  ) {
    for (final l in available) {
      if (_languageOf(l.localeId) == languageCode) return l;
    }
    return null;
  }

  /// `en_PH` / `en-PH` / `en` → `en`
  static String _languageOf(String localeId) =>
      localeId.replaceAll('-', '_').split('_').first.toLowerCase();

  /// Which of the candidates the device can actually serve, in preference
  /// order. Used by the diagnostic screen to build its comparison run, and to
  /// tell the resident plainly when their language is not supported at all.
  static List<String> availableCandidates({
    required String languageName,
    required List<LocaleName> available,
  }) {
    return candidatesFor(
      languageName,
    ).where((code) => _firstWithLanguage(available, code) != null).toList();
  }

  /// True when the device has a recogniser for the language itself, rather
  /// than only for one of its fallbacks. When this is false the transcript is
  /// a best-effort artefact and the attached audio is the real record.
  static bool hasNativeSupport({
    required String languageName,
    required List<LocaleName> available,
  }) {
    final wanted = candidatesFor(languageName).first;
    return _firstWithLanguage(available, wanted) != null;
  }
}
