import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/locale_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'widgets/onboarding_kit.dart';

/// First screen a new user ever sees. Pick the language the app speaks.
///
/// Why this comes BEFORE the privacy notice
/// ----------------------------------------
/// The original plan had consent first. That order cannot work: agreeing to a
/// data-privacy notice you cannot read is not consent, and RA 10173 treats it
/// as no consent at all. The language choice is what makes the next screen
/// meaningful, so it has to lead.
///
/// The choice applies the moment it is tapped
/// ------------------------------------------
/// This screen used to be written in both languages at once and to stay that
/// way whatever was picked; the choice only took effect on Continue. Testers
/// tapped English, saw nothing change, and read it as broken. Now a tap
/// switches the app's locale on the spot, so this screen turns into the chosen
/// language as the proof that it worked. Each option still names itself in
/// its own language, with a sample line, so it can be recognised before
/// anything has been chosen, and the title keeps a small line in the other
/// language for someone who landed on the wrong one.
///
/// Ziren's help mascot asks the question — the one friendly face in a setup
/// that is otherwise forms and legal text.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    // Whatever the app is already speaking — Filipino by default, which is
    // what most of Biliran reads most comfortably, so the hurried user can
    // simply press Continue.
    _selected = context.read<LocaleProvider>().languageName;
  }

  Future<void> _choose(String name) async {
    setState(() => _selected = name);
    await context.read<LocaleProvider>().setLanguageName(name);
  }

  Future<void> _continue() async {
    await context.read<LocaleProvider>().setLanguageName(_selected);
    if (!mounted) return;
    context.go('/onboarding/consent');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final english = _selected == LocaleProvider.languageEnglish;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                ZirenTokens.space24,
                ZirenTokens.space16,
                ZirenTokens.space24,
                0,
              ),
              child: OnboardingSteps(step: 1),
            ),
            // The screen is FILLED, not centred and not top-packed: whatever
            // height the phone has left over is shared out evenly between
            // the groups (mascot, heading, choices, button), and the mascot
            // itself grows with the screen. Pinning the button to the bottom
            // left one wide empty band above it on a tall phone; centring
            // the block just split that band into two, above and below.
            // Scrolls instead when the text is too large to fit.
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  const vPad = ZirenTokens.space16;
                  final mascot = (box.maxHeight * 0.21).clamp(92.0, 170.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZirenTokens.space24,
                      vertical: vPad,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, box.maxHeight - vPad * 2),
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OnboardingMascot(
                              text: t.onbLangGreeting,
                              size: mascot,
                            ),
                            const Spacer(),
                            const SizedBox(height: ZirenTokens.space16),
                            Text(
                              t.onbLangTitle,
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: -0.5,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // The same heading in the other language, for
                            // someone who reads that one instead.
                            Text(
                              english
                                  ? 'Piliin ang inyong wika'
                                  : 'Choose your language',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ZirenTokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: ZirenTokens.space8),
                            Text(
                              t.onbLangSubtitle,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: ZirenTokens.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: ZirenTokens.space16),
                            _LanguageCard(
                              key: const Key('lang-fil'),
                              badge: 'FIL',
                              title: 'Tagalog',
                              sample: 'Mag-ulat ng emerhensiya',
                              selectedLabel: t.onbLangSelected,
                              selected: !english,
                              onTap:
                                  () =>
                                      _choose(LocaleProvider.languageFilipino),
                            ),
                            const SizedBox(height: ZirenTokens.space12),
                            _LanguageCard(
                              key: const Key('lang-en'),
                              badge: 'EN',
                              title: 'English',
                              sample: 'Report an emergency',
                              selectedLabel: t.onbLangSelected,
                              selected: english,
                              onTap:
                                  () => _choose(LocaleProvider.languageEnglish),
                            ),
                            const SizedBox(height: ZirenTokens.space16),
                            // Waray is the language of Biliran and its absence
                            // here is deliberate, not an oversight. See
                            // l10n.yaml: machine-drafted Waray in an emergency
                            // app is not safe to ship, and saying so is better
                            // than quietly offering two languages and hoping
                            // nobody notices which one is missing.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  LucideIcons.languages,
                                  size: 15,
                                  color: ZirenTokens.textMuted,
                                ),
                                const SizedBox(width: ZirenTokens.space8),
                                Expanded(
                                  child: Text(
                                    t.onbLangMoreSoon,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.4,
                                      color: ZirenTokens.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const SizedBox(height: ZirenTokens.space20),
                            ZirenButton(
                              key: const Key('lang-continue'),
                              label: t.onbLangContinue,
                              icon: LucideIcons.arrow_right,
                              onPressed: _continue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    super.key,
    required this.badge,
    required this.title,
    required this.sample,
    required this.selectedLabel,
    required this.selected,
    required this.onTap,
  });

  final String badge;
  final String title;
  final String sample;
  final String selectedLabel;
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
            child: AnimatedContainer(
              duration: ZirenTokens.motionQuick,
              padding: const EdgeInsets.all(ZirenTokens.space16),
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
                  AnimatedContainer(
                    duration: ZirenTokens.motionQuick,
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? ZirenTokens.brandOrange
                              : ZirenTokens.surfaceRaised,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color:
                            selected ? Colors.white : ZirenTokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space12 + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color:
                                selected
                                    ? ZirenTokens.brandActive
                                    : ZirenTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '“$sample”',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: ZirenTokens.motionQuick,
                    child:
                        selected
                            ? Icon(
                              LucideIcons.circle_check,
                              key: const ValueKey('on'),
                              color: ZirenTokens.brandOrange,
                              size: 26,
                              semanticLabel: selectedLabel,
                            )
                            : Icon(
                              LucideIcons.circle,
                              key: const ValueKey('off'),
                              color: ZirenTokens.textMuted,
                              size: 26,
                            ),
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
