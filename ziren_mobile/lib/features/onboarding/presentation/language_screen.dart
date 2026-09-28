import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/locale_provider.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_logo.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// First screen a new user ever sees. Pick the language the app speaks.
///
/// Why this comes BEFORE the privacy notice
/// ----------------------------------------
/// The original plan had consent first. That order cannot work: agreeing to a
/// data-privacy notice you cannot read is not consent, and RA 10173 treats it
/// as no consent at all. The language choice is what makes the next screen
/// meaningful, so it has to lead.
///
/// Why nothing on this screen is localised
/// ---------------------------------------
/// It is the one screen in the app that must be readable by someone who has
/// not yet told us what they read. Each option is written in its own language,
/// with a sample line underneath, so the choice can be made by recognition
/// rather than by translation. Localising it would mean guessing — and a
/// wrong guess here makes every screen after it unreadable.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  /// Filipino leads, and is preselected. It is what most of Biliran reads
  /// most comfortably, and a preselected sensible default means the hurried
  /// user can simply press Continue.
  String _selected = LocaleProvider.languageFilipino;

  Future<void> _continue() async {
    await context.read<LocaleProvider>().setLanguageName(_selected);
    if (!mounted) return;
    context.go('/onboarding/consent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space24,
            ZirenTokens.space32,
            ZirenTokens.space24,
            ZirenTokens.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZirenLogo.mark(size: 56, onDark: ZirenTokens.isDark),
              const SizedBox(height: ZirenTokens.space24),

              // Bilingual heading — the one place both languages sit together,
              // because the reader has not chosen yet.
              Text(
                'Choose your language',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.5,
                  color: ZirenTokens.textPrimary,
                ),
              ),
              const SizedBox(height: ZirenTokens.space4),
              Text(
                'Piliin ang inyong wika',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.5,
                  color: ZirenTokens.textMuted,
                ),
              ),
              const SizedBox(height: ZirenTokens.space8),
              Text(
                'You can change this later in Settings.\n'
                'Maaari ninyo itong palitan sa Settings.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: ZirenTokens.textSecondary,
                ),
              ),

              const SizedBox(height: ZirenTokens.space32),

              _LanguageCard(
                title: 'Tagalog',
                sample: 'Mag-ulat ng emerhensiya',
                selected: _selected == LocaleProvider.languageFilipino,
                onTap:
                    () => setState(
                      () => _selected = LocaleProvider.languageFilipino,
                    ),
              ),
              const SizedBox(height: ZirenTokens.space12),
              _LanguageCard(
                title: 'English',
                sample: 'Report an emergency',
                selected: _selected == LocaleProvider.languageEnglish,
                onTap:
                    () => setState(
                      () => _selected = LocaleProvider.languageEnglish,
                    ),
              ),

              const Spacer(),

              // Waray is the language of Biliran and its absence here is
              // deliberate, not an oversight. See l10n.yaml: machine-drafted
              // Waray in an emergency app is not safe to ship, and saying so
              // is better than quietly offering two languages and hoping
              // nobody notices which one is missing.
              Text(
                'Waray and Bisaya are coming once a native speaker has '
                'reviewed them.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
              ),
              const SizedBox(height: ZirenTokens.space16),

              ZirenButton(
                label: 'Continue  ·  Magpatuloy',
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.title,
    required this.sample,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sample;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$title. $sample',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? ZirenTokens.brandSubtle : ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZirenTokens.radius20),
            child: Container(
              padding: const EdgeInsets.all(ZirenTokens.space20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZirenTokens.radius20),
                border: Border.all(
                  color:
                      selected
                          ? ZirenTokens.brandOrange
                          : ZirenTokens.surfaceBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color:
                                selected
                                    ? ZirenTokens.brandActive
                                    : ZirenTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: ZirenTokens.space4),
                        Text(
                          sample,
                          style: TextStyle(
                            fontSize: 14,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? LucideIcons.circle_dot
                        : LucideIcons.circle,
                    color:
                        selected
                            ? ZirenTokens.brandOrange
                            : ZirenTokens.textMuted,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
