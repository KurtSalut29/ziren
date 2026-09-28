import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Emergency Preparedness / Safety Guide — spec Section 22.
///
/// Static, offline-readable reference content: no backend call, so it works
/// exactly when it matters most — no signal, battery low, still useful.
/// Ziren's value should not stop at "report an emergency"; this is what
/// gives the app something to say before and during one too.
class SafetyGuideScreen extends StatelessWidget {
  const SafetyGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final guides = _buildGuides(t);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.safetyGuideTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.all(ZirenTokens.space16),
        itemCount: guides.length,
        separatorBuilder: (_, __) => const SizedBox(height: ZirenTokens.space10),
        itemBuilder: (_, i) => _GuideTile(guide: guides[i]),
      ),
    );
  }
}

class _Guide {
  const _Guide({
    required this.title,
    required this.icon,
    required this.color,
    required this.bg,
    required this.steps,
  });
  final String title;
  final IconData icon;
  final Color color;
  final Color bg;
  final List<String> steps;
}

List<_Guide> _buildGuides(AppLocalizations t) => [
  _Guide(
    title: t.safetyFireTitle,
    icon: LucideIcons.flame,
    color: ZirenTokens.agencyBFP,
    bg: ZirenTokens.agencyBFPBg,
    steps: [
      t.safetyFireStep1,
      t.safetyFireStep2,
      t.safetyFireStep3,
      t.safetyFireStep4,
      t.safetyFireStep5,
      t.safetyFireStep6,
    ],
  ),
  _Guide(
    title: t.safetyEarthquakeTitle,
    icon: LucideIcons.vibrate,
    color: ZirenTokens.severityHigh,
    bg: ZirenTokens.severityHighBg,
    steps: [
      t.safetyEarthquakeStep1,
      t.safetyEarthquakeStep2,
      t.safetyEarthquakeStep3,
      t.safetyEarthquakeStep4,
      t.safetyEarthquakeStep5,
      t.safetyEarthquakeStep6,
    ],
  ),
  _Guide(
    title: t.safetyFloodTitle,
    icon: LucideIcons.waves_horizontal,
    color: ZirenTokens.agencyMDRRMO,
    bg: ZirenTokens.agencyMDRRMOBg,
    steps: [
      t.safetyFloodStep1,
      t.safetyFloodStep2,
      t.safetyFloodStep3,
      t.safetyFloodStep4,
      t.safetyFloodStep5,
      t.safetyFloodStep6,
    ],
  ),
  _Guide(
    title: t.safetyTyphoonTitle,
    icon: LucideIcons.cloud_lightning,
    color: ZirenTokens.systemInfo,
    bg: ZirenTokens.systemInfoBg,
    steps: [
      t.safetyTyphoonStep1,
      t.safetyTyphoonStep2,
      t.safetyTyphoonStep3,
      t.safetyTyphoonStep4,
      t.safetyTyphoonStep5,
      t.safetyTyphoonStep6,
    ],
  ),
  _Guide(
    title: t.safetyRoadAccidentTitle,
    icon: LucideIcons.car,
    color: ZirenTokens.severityMedium,
    bg: ZirenTokens.severityMediumBg,
    steps: [
      t.safetyRoadAccidentStep1,
      t.safetyRoadAccidentStep2,
      t.safetyRoadAccidentStep3,
      t.safetyRoadAccidentStep4,
      t.safetyRoadAccidentStep5,
      t.safetyRoadAccidentStep6,
    ],
  ),
  _Guide(
    title: t.safetyMedicalTitle,
    icon: LucideIcons.stethoscope,
    color: ZirenTokens.severityHigh,
    bg: ZirenTokens.severityHighBg,
    steps: [
      t.safetyMedicalStep1,
      t.safetyMedicalStep2,
      t.safetyMedicalStep3,
      t.safetyMedicalStep4,
      t.safetyMedicalStep5,
      t.safetyMedicalStep6,
    ],
  ),
  _Guide(
    title: t.safetyCrimeTitle,
    icon: LucideIcons.gavel,
    color: ZirenTokens.agencyPNP,
    bg: ZirenTokens.agencyPNPBg,
    steps: [
      t.safetyCrimeStep1,
      t.safetyCrimeStep2,
      t.safetyCrimeStep3,
      t.safetyCrimeStep4,
      t.safetyCrimeStep5,
      t.safetyCrimeStep6,
    ],
  ),
];

class _GuideTile extends StatelessWidget {
  const _GuideTile({required this.guide});
  final _Guide guide;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          border: Border.all(color: ZirenTokens.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: guide.bg,
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            ),
            child: Icon(guide.icon, color: guide.color, size: 20),
          ),
          title: Text(
            guide.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            0,
            ZirenTokens.space16,
            ZirenTokens.space16,
          ),
          children: [
            for (var i = 0; i < guide.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: ZirenTokens.space10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: guide.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: guide.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: Text(
                        guide.steps[i],
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
