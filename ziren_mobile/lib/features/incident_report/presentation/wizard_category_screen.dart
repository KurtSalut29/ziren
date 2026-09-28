import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import 'wizard_shared.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 1 of the 5W1H wizard — WHAT happened?
///
/// Resident picks one of 8 incident categories.
/// Location capture is kicked off here (runs in background while user taps).
class WizardCategoryScreen extends StatefulWidget {
  const WizardCategoryScreen({super.key});

  @override
  State<WizardCategoryScreen> createState() => _WizardCategoryScreenState();
}

class _WizardCategoryScreenState extends State<WizardCategoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<IncidentProvider>();
      // Start GPS capture early so it's ready by the time we reach Step 4
      p.fetchLocation();
      p.initSpeech();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();

    if (!provider.hasStation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/select-station'),
      );
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.categoryQuestion),
        leading: BackButton(
          onPressed: () {
            provider.clearStation();
            context.go('/select-station');
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress bar — step 1 of 5
            const WizardProgress(step: 1),

            // Station banner
            WizardStationBanner(provider: provider),

            // Category grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.categoryHelp,
                      style: TextStyle(
                        fontSize: 14,
                        color: ZirenTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space16),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: ZirenTokens.space12,
                        crossAxisSpacing: ZirenTokens.space12,
                        childAspectRatio: 1.6,
                        children:
                            IncidentCategory.values
                                .map(
                                  (cat) => _CategoryCard(
                                    category: cat,
                                    selected: provider.incidentCategory == cat,
                                    onTap: () {
                                      provider.setCategory(cat);
                                      context.push('/report/questions');
                                    },
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category card ─────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final IncidentCategory category;
  final bool selected;
  final VoidCallback onTap;

  (Color, Color, IconData) get _style {
    switch (category) {
      case IncidentCategory.fire:
        return (
          ZirenTokens.agencyBFP,
          ZirenTokens.agencyBFPBg,
          LucideIcons.flame,
        );
      case IncidentCategory.medicalTrauma:
        return (
          ZirenTokens.severityHigh,
          ZirenTokens.severityHighBg,
          LucideIcons.stethoscope,
        );
      case IncidentCategory.vehicular:
        return (
          ZirenTokens.severityMedium,
          ZirenTokens.severityMediumBg,
          LucideIcons.car,
        );
      case IncidentCategory.floodLandslideCalamity:
        return (
          ZirenTokens.agencyMDRRMO,
          ZirenTokens.agencyMDRRMOBg,
          LucideIcons.waves_horizontal,
        );
      case IncidentCategory.domesticDisputeCrime:
        return (
          ZirenTokens.agencyPNP,
          ZirenTokens.agencyPNPBg,
          LucideIcons.gavel,
        );
      case IncidentCategory.other:
        return (
          ZirenTokens.textSecondary,
          ZirenTokens.surfaceRaised,
          LucideIcons.ellipsis,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, bg, icon) = _style;
    final isSelected = selected;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ZirenTokens.motionQuick,
        padding: const EdgeInsets.all(ZirenTokens.space12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : bg,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          border: Border.all(
            color: isSelected ? color : ZirenTokens.surfaceBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? ZirenTokens.shadowSm : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: ZirenTokens.space8),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : ZirenTokens.textPrimary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
