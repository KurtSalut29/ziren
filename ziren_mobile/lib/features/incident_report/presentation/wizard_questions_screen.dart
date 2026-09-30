import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import 'wizard_shared.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 2 of the 5W1H wizard — category-specific questions.
///
/// Shows 3–5 quick-choice chip questions relevant to the selected category,
/// plus an optional free-text / voice catch-all field at the bottom.
class WizardQuestionsScreen extends StatefulWidget {
  const WizardQuestionsScreen({super.key});

  @override
  State<WizardQuestionsScreen> createState() => _WizardQuestionsScreenState();
}

class _WizardQuestionsScreenState extends State<WizardQuestionsScreen> {
  final _catchAllController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill catch-all from any previous visit to this step
    final existing =
        context.read<IncidentProvider>().wizardAnswers['catch_all'] as String?;
    if (existing != null) _catchAllController.text = existing;
  }

  @override
  void dispose() {
    _catchAllController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();
    final category = provider.incidentCategory;

    if (category == null || !provider.hasStation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/report/category'),
      );
      return const SizedBox.shrink();
    }

    final questions = _questionsFor(t, category);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(category.label),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WizardProgress(step: 2),
            WizardStationBanner(provider: provider),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Per-category questions
                    ...questions.map(
                      (q) => _QuestionBlock(
                        question: q,
                        answers: provider.wizardAnswers,
                        onAnswer:
                            (key, val) => provider.mergeWizardAnswer(key, val),
                      ),
                    ),

                    const SizedBox(height: ZirenTokens.space20),
                    WizardSectionLabel(t.qExtraDetails),
                    const SizedBox(height: ZirenTokens.space8),

                    // Free-text catch-all + voice
                    _CatchAllField(
                      controller: _catchAllController,
                      provider: provider,
                      onChanged:
                          (v) => provider.mergeWizardAnswer('catch_all', v),
                    ),

                    const SizedBox(height: ZirenTokens.space32),
                  ],
                ),
              ),
            ),

            // Next button
            WizardNavBar(
              onNext: () {
                // Persist catch-all text before leaving
                final text = _catchAllController.text.trim();
                if (text.isNotEmpty) {
                  provider.mergeWizardAnswer('catch_all', text);
                }
                context.push('/report/overlap');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Question definitions per category ────────────────────────

class _Question {
  const _Question({
    required this.key,
    required this.prompt,
    required this.options,
  });
  final String key;
  final String prompt;
  final List<String> options;
}

List<_Question> _questionsFor(AppLocalizations t, IncidentCategory category) {
  switch (category) {
    case IncidentCategory.fire:
      return [
        _Question(
          key: 'material',
          prompt: t.qFireMaterial,
          options: [
            t.ansHouse,
            t.ansVehicle,
            t.ansForestField,
            t.ansBuildingWarehouse,
            t.ansOther,
          ],
        ),
        _Question(
          key: 'spreading',
          prompt: t.qFireSpreading,
          options: [t.ansYesSpreading, t.ansNoControlled, t.ansDontKnow],
        ),
        _Question(
          key: 'injured',
          prompt: t.qFireInjured,
          options: [t.ansYes, t.ansNone, t.ansDontKnow],
        ),
        _Question(
          key: 'road_blocked',
          prompt: t.qFireRoadBlocked,
          options: [t.ansYes, t.ansNo],
        ),
      ];

    case IncidentCategory.medicalTrauma:
      return [
        _Question(
          key: 'type',
          prompt: t.qMedType,
          options: [
            t.ansAccident,
            t.ansHeartAttackStroke,
            t.ansSeizure,
            t.ansTroubleBreathing,
            t.ansOther,
          ],
        ),
        _Question(
          key: 'victim_count',
          prompt: t.qMedVictimCount,
          options: [t.ansOne, t.ansTwoToFive, t.ansMoreThanFive, t.ansDontKnow],
        ),
        _Question(
          key: 'bleeding',
          prompt: t.qMedBleeding,
          options: [t.ansYes, t.ansNone, t.ansDontKnow],
        ),
        _Question(
          key: 'conscious',
          prompt: t.qMedConscious,
          options: [t.ansYesConscious, t.ansNoUnconscious, t.ansDontKnow],
        ),
      ];

    case IncidentCategory.vehicular:
      return [
        _Question(
          key: 'vehicle_type',
          prompt: t.qVehType,
          options: [
            t.ansMotorcycle,
            t.ansCarSuv,
            t.ansBusTruck,
            t.ansTricycleEbike,
            t.ansOther,
          ],
        ),
        _Question(
          key: 'injured',
          prompt: t.qVehInjured,
          options: [t.ansYes, t.ansNone, t.ansDontKnow],
        ),
        _Question(
          key: 'road_blocked',
          prompt: t.qVehRoadBlocked,
          options: [t.ansYesBlocked, t.ansPartly, t.ansNo],
        ),
      ];

    case IncidentCategory.floodLandslideCalamity:
      return [
        _Question(
          key: 'type',
          prompt: t.qCalType,
          options: [
            t.ansFlood,
            t.ansLandslide,
            t.ansStorm,
            t.ansEarthquake,
            t.ansOther,
          ],
        ),
        _Question(
          key: 'affected',
          prompt: t.qCalAffected,
          options: [
            t.ansOneToFive,
            t.ansSixToTwenty,
            t.ansMoreThanTwenty,
            t.ansDontKnow,
          ],
        ),
        _Question(
          key: 'road_blocked',
          prompt: t.qCalRoadCut,
          options: [t.ansYes, t.ansNo, t.ansDontKnow],
        ),
        _Question(
          key: 'evacuation',
          prompt: t.qCalEvacuation,
          options: [t.ansYesUrgent, t.ansPossibly, t.ansNotYetNeeded],
        ),
      ];

    case IncidentCategory.domesticDisputeCrime:
      return [
        _Question(
          key: 'type',
          prompt: t.qCrimeType,
          options: [
            t.ansFightDisturbance,
            t.ansTheftHoldup,
            t.ansPhysicalAssault,
            t.ansArmed,
            t.ansOther,
          ],
        ),
        _Question(
          key: 'weapon',
          prompt: t.qCrimeWeapon,
          options: [t.ansYes, t.ansNone, t.ansDontKnow],
        ),
        _Question(
          key: 'ongoing',
          prompt: t.qCrimeOngoing,
          options: [t.ansYesOngoing, t.ansItIsOver, t.ansDontKnow],
        ),
      ];

    case IncidentCategory.other:
      return const []; // only the catch-all free-text is shown
  }
}

// ── Question block widget ─────────────────────────────────────

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({
    required this.question,
    required this.answers,
    required this.onAnswer,
  });
  final _Question question;
  final Map<String, dynamic> answers;
  final void Function(String key, String value) onAnswer;

  @override
  Widget build(BuildContext context) {
    final current = answers[question.key] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardSectionLabel(question.prompt),
        const SizedBox(height: ZirenTokens.space8),
        Wrap(
          spacing: ZirenTokens.space8,
          runSpacing: ZirenTokens.space8,
          children:
              question.options.map((opt) {
                final isSelected = current == opt;
                return GestureDetector(
                  onTap: () => onAnswer(question.key, opt),
                  child: AnimatedContainer(
                    duration: ZirenTokens.motionQuick,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZirenTokens.space12,
                      vertical: ZirenTokens.space8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? ZirenTokens.brandOrange
                              : ZirenTokens.surfaceCard,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                      border: Border.all(
                        color:
                            isSelected
                                ? ZirenTokens.brandOrange
                                : ZirenTokens.surfaceBorder,
                      ),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color:
                            isSelected ? Colors.white : ZirenTokens.textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: ZirenTokens.space20),
      ],
    );
  }
}

// ── Catch-all free-text + voice ───────────────────────────────

class _CatchAllField extends StatelessWidget {
  const _CatchAllField({
    required this.controller,
    required this.provider,
    required this.onChanged,
  });
  final TextEditingController controller;
  final IncidentProvider provider;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          maxLines: 4,
          maxLength: 500,
          onChanged: onChanged,
          style: TextStyle(fontSize: 14, color: ZirenTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Anumang dagdag na detalye na hindi nsaklaw sa itaas…',
            hintStyle: TextStyle(
              color: ZirenTokens.textMuted,
              fontSize: 13,
            ),
            filled: true,
            fillColor: ZirenTokens.surfaceCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
            ),
          ),
        ),
        if (provider.speechAvailable) ...[
          const SizedBox(height: ZirenTokens.space8),
          OutlinedButton.icon(
            icon: Icon(
              provider.isListening ? LucideIcons.mic : LucideIcons.mic,
              size: 18,
              color:
                  provider.isListening
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.textMuted,
            ),
            label: Text(
              provider.isListening
                  ? AppLocalizations.of(context).wizardListening
                  : AppLocalizations.of(context).wizardSpeakDetails,
              style: TextStyle(
                color:
                    provider.isListening
                        ? ZirenTokens.brandOrange
                        : ZirenTokens.textMuted,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color:
                    provider.isListening
                        ? ZirenTokens.brandOrange
                        : ZirenTokens.surfaceBorder,
              ),
            ),
            onPressed: () {
              if (provider.isListening) {
                provider.stopListening();
              } else {
                provider.startListening(
                  onResult: (text) {
                    controller.text = text;
                    onChanged(text);
                  },
                );
              }
            },
          ),
        ],
      ],
    );
  }
}
