import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/ziren_dialogs.dart';
import '../../domain/incident_provider.dart';

/// "Speaking: Bisaya" beside the microphone, and the choice behind it.
///
/// Evaluator finding #22 (2026-10-05): Bisaya speech was always heard by the
/// Filipino recogniser, because nothing told the phone otherwise. This is the
/// resident's spoken language — separate from the app's display language,
/// which offers only Filipino and English — and it is remembered on the phone.
///
/// When the phone has no recogniser for the language itself, the chip says so
/// and what it will use instead, and [SpokenLanguageCheckNote] asks the
/// resident to look over the words before sending.
class SpokenLanguageChip extends StatelessWidget {
  const SpokenLanguageChip({super.key, required this.provider});

  final IncidentProvider provider;

  static String nameOfCode(String code) => switch (code) {
    'ceb' => 'Bisaya (Cebuano)',
    'war' => 'Waray',
    'fil' => 'Filipino',
    'en' => 'English',
    _ => code,
  };

  Future<void> _choose(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final picked = await showZirenOptionSheet<String>(
      context,
      title: t.speakingLanguageTitle,
      message: t.speakingLanguageMessage,
      options: [
        for (final lang in IncidentProvider.spokenLanguages)
          ZirenSheetOption<String>(
            icon: lang == provider.spokenLanguage ? LucideIcons.circle_check : LucideIcons.mic,
            label: lang,
            value: lang,
            subtitle: _subtitleFor(t, lang),
          ),
      ],
    );
    if (picked != null) await provider.setSpokenLanguage(picked);
  }

  String? _subtitleFor(AppLocalizations t, String lang) {
    final used = provider.recogniserFor(lang);
    if (used == null) return provider.speechLocales.isEmpty ? null : t.speakingLanguageNone;
    final native = switch (lang) {
      'Bisaya' => 'ceb',
      'Waray' => 'war',
      'English' => 'en',
      _ => 'fil',
    };
    return used == native ? null : t.speakingLanguageFallback(lang, nameOfCode(used));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = provider.spokenLanguage;
    final warn = provider.speechLocales.isNotEmpty && !provider.spokenLanguageNative;
    return Semantics(
      button: true,
      label: t.speakingLanguageLabel(lang),
      child: InkWell(
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        onTap: () => _choose(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZirenTokens.radius32),
            border: Border.all(color: warn ? ZirenTokens.systemWarning : ZirenTokens.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                warn ? LucideIcons.triangle_alert : LucideIcons.languages,
                size: 14,
                color: warn ? ZirenTokens.systemWarning : ZirenTokens.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                t.speakingLanguageLabel(lang),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ZirenTokens.textPrimary),
              ),
              const SizedBox(width: 2),
              Icon(LucideIcons.chevron_down, size: 14, color: ZirenTokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown under the field once something has been dictated in a language the
/// phone cannot hear natively: the words are a best effort, so look them over.
class SpokenLanguageCheckNote extends StatelessWidget {
  const SpokenLanguageCheckNote({super.key, required this.provider, required this.hasText});

  final IncidentProvider provider;
  final bool hasText;

  @override
  Widget build(BuildContext context) {
    if (!hasText || provider.speechLocales.isEmpty || provider.spokenLanguageNative) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: ZirenTokens.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.pencil_line, size: 14, color: ZirenTokens.systemWarning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              t.speakingLanguageCheck(provider.spokenLanguage),
              style: TextStyle(fontSize: 12, color: ZirenTokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
