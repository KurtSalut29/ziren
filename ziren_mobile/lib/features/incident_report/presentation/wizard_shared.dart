/// Shared widgets used across all 5W1H wizard steps.
/// Import this file instead of importing private classes from sibling screens.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/incident_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// ── Progress bar ──────────────────────────────────────────────

/// Thin progress bar. [step] is 1-indexed, [totalSteps] defaults to 5
/// (legacy wizard) but can be set to 2 for the new 2-screen flow.
class WizardProgress extends StatelessWidget {
  const WizardProgress({super.key, required this.step, this.totalSteps = 5});
  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space12,
        ZirenTokens.space16,
        0,
      ),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final filled = i < step;
          return Expanded(
            child: AnimatedContainer(
              duration: ZirenTokens.motionBase,
              height: 3,
              margin: EdgeInsets.only(
                right: i < totalSteps - 1 ? ZirenTokens.space4 : 0,
              ),
              decoration: BoxDecoration(
                color:
                    filled
                        ? ZirenTokens.brandOrange
                        : ZirenTokens.surfaceBorder,
                borderRadius: BorderRadius.circular(ZirenTokens.radius4),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Station banner ────────────────────────────────────────────

/// Compact selected-station pill shown at the top of every wizard step.
class WizardStationBanner extends StatelessWidget {
  const WizardStationBanner({super.key, required this.provider});
  final IncidentProvider provider;

  @override
  Widget build(BuildContext context) {
    final station = provider.selectedStation;
    if (station == null) return const SizedBox.shrink();

    final color = switch (station.agencyType) {
      'BFP' => ZirenTokens.agencyBFP,
      'PNP' => ZirenTokens.agencyPNP,
      'MDRRMO' => ZirenTokens.agencyMDRRMO,
      _ => ZirenTokens.brandOrange,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space10,
        ZirenTokens.space16,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.building, size: 14, color: color),
          const SizedBox(width: ZirenTokens.space8),
          Flexible(child: Text(
            '${station.agencyType} · ${station.name}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          )),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────

class WizardSectionLabel extends StatelessWidget {
  const WizardSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ZirenTokens.textSecondary,
        height: 1.4,
      ),
    );
  }
}

// ── Bottom nav bar ────────────────────────────────────────────

class WizardNavBar extends StatelessWidget {
  const WizardNavBar({
    super.key,
    required this.onNext,
    this.label,
  });
  final VoidCallback onNext;

  /// Defaults to the localised "Next →". It used to default to a hard-coded
  /// "Susunod →", which English readers saw too.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? AppLocalizations.of(context).wizardNext;
    return Container(
      padding: EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: ZirenTokens.brandOrange,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          ),
        ),
        onPressed: onNext,
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
