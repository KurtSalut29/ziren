import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import 'wizard_shared.dart';

import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 4 of the 5W1H wizard — WHO + WHERE detail.
///
/// Captures:
///   - Resident's relationship to the victim (WHO)
///   - Optional landmark note to supplement GPS (WHERE)
///
/// GPS has been running in the background since Step 1.
class WizardWhoScreen extends StatefulWidget {
  const WizardWhoScreen({super.key});

  @override
  State<WizardWhoScreen> createState() => _WizardWhoScreenState();
}

class _WizardWhoScreenState extends State<WizardWhoScreen> {
  final _landmarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final note = context.read<IncidentProvider>().landmarkNote;
    if (note != null) _landmarkController.text = note;
  }

  @override
  void dispose() {
    _landmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();

    if (provider.incidentCategory == null || !provider.hasStation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/report/category'),
      );
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.whoTitle),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WizardProgress(step: 4),
            WizardStationBanner(provider: provider),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── WHO: relationship ─────────────────────
                    WizardSectionLabel(t.whoRelationship),
                    const SizedBox(height: ZirenTokens.space12),
                    ...VictimRelationship.values.map((rel) {
                      final isSelected = provider.victimRelationship == rel;
                      return GestureDetector(
                        onTap: () => provider.setVictimRelationship(rel),
                        child: AnimatedContainer(
                          duration: ZirenTokens.motionQuick,
                          margin: const EdgeInsets.only(
                            bottom: ZirenTokens.space8,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZirenTokens.space16,
                            vertical: ZirenTokens.space12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? ZirenTokens.brandOrange.withValues(
                                      alpha: 0.08,
                                    )
                                    : ZirenTokens.surfaceCard,
                            borderRadius: BorderRadius.circular(
                              ZirenTokens.radius12,
                            ),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? ZirenTokens.brandOrange
                                      : ZirenTokens.surfaceBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: ZirenTokens.motionQuick,
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? ZirenTokens.brandOrange
                                            : ZirenTokens.textMuted,
                                    width: isSelected ? 6 : 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: ZirenTokens.space12),
                              Flexible(child: Text(
                                rel.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                  color:
                                      isSelected
                                          ? ZirenTokens.brandOrange
                                          : ZirenTokens.textPrimary,
                                ),
                              )),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: ZirenTokens.space24),

                    // ── WHERE: GPS status ─────────────────────
                    WizardSectionLabel(t.whoLocation),
                    const SizedBox(height: ZirenTokens.space8),
                    _LocationChip(provider: provider),
                    const SizedBox(height: ZirenTokens.space16),

                    // ── WHERE: landmark note ──────────────────
                    WizardSectionLabel(t.whoLandmark),
                    const SizedBox(height: ZirenTokens.space8),
                    TextFormField(
                      controller: _landmarkController,
                      maxLength: 300,
                      onChanged: (v) => provider.setLandmarkNote(v),
                      style: TextStyle(
                        fontSize: 14,
                        color: ZirenTokens.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: t.whoLandmarkHint,
                        hintStyle: TextStyle(
                          color: ZirenTokens.textMuted,
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          LucideIcons.map_pin,
                          color: ZirenTokens.textMuted,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: ZirenTokens.surfaceCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius12,
                          ),
                          borderSide: BorderSide(
                            color: ZirenTokens.surfaceBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius12,
                          ),
                          borderSide: BorderSide(
                            color: ZirenTokens.surfaceBorder,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: ZirenTokens.space16),
                  ],
                ),
              ),
            ),

            WizardNavBar(
              onNext: () {
                provider.setLandmarkNote(_landmarkController.text);
                context.push('/report/review');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── GPS status chip ───────────────────────────────────────────

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.provider});
  final IncidentProvider provider;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (icon, label, color) =
        provider.locationDenied
            ? (
              LucideIcons.map_pin_off,
              t.reportNoGps,
              ZirenTokens.systemWarning,
            )
            : provider.currentPosition == null
            ? (
              LucideIcons.locate,
              t.reportFindingLocation,
              ZirenTokens.textMuted,
            )
            : (
              LucideIcons.map_pin,
              t.reportGpsAcquired,
              ZirenTokens.systemSuccess,
            );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: ZirenTokens.space8),
          Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}
