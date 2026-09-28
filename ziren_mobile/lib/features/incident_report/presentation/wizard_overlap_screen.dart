import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import 'wizard_shared.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 3 of the 5W1H wizard — "may kasama pa bang..." overlap flags.
///
/// Multi-select secondary concerns that help the dispatcher identify
/// whether multiple agencies need to respond (e.g. fire + injuries).
/// Feeds Phase 6A multi-agency routing suggestion — not a new pipeline.
class WizardOverlapScreen extends StatelessWidget {
  const WizardOverlapScreen({super.key});

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

    // Filter out the flag that matches the primary category to avoid redundancy
    final primaryKey = provider.incidentCategory!.value;
    final flags =
        OverlapFlag.values.where((f) => f.value != primaryKey).toList();

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.overlapTitle),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WizardProgress(step: 3),
            WizardStationBanner(provider: provider),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.overlapHelp,
                      style: TextStyle(
                        fontSize: 14,
                        color: ZirenTokens.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space20),
                    Wrap(
                      spacing: ZirenTokens.space10,
                      runSpacing: ZirenTokens.space10,
                      children:
                          flags.map((flag) {
                            final isSelected = provider.overlapFlags.contains(
                              flag,
                            );
                            final isNone = flag == OverlapFlag.none;
                            final color =
                                isNone
                                    ? ZirenTokens.textMuted
                                    : ZirenTokens.brandOrange;

                            return GestureDetector(
                              onTap: () => provider.toggleOverlapFlag(flag),
                              child: AnimatedContainer(
                                duration: ZirenTokens.motionQuick,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ZirenTokens.space16,
                                  vertical: ZirenTokens.space10,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      isSelected
                                          ? color.withValues(alpha: 0.12)
                                          : ZirenTokens.surfaceCard,
                                  borderRadius: BorderRadius.circular(
                                    ZirenTokens.radius32,
                                  ),
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? color
                                            : ZirenTokens.surfaceBorder,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSelected)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: ZirenTokens.space6,
                                        ),
                                        child: Icon(
                                          LucideIcons.circle_check_big,
                                          size: 16,
                                          color: color,
                                        ),
                                      ),
                                    Text(
                                      flag.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            isSelected
                                                ? color
                                                : ZirenTokens.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            WizardNavBar(onNext: () => context.push('/report/who')),
          ],
        ),
      ),
    );
  }
}
