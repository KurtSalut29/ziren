import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/profile_kit.dart';

/// Emergency Preparedness / Safety Guide — spec Section 22.
///
/// Static, offline-readable reference content: no backend call, so it works
/// exactly when it matters most — no signal, battery low, still useful.
///
/// A grid of the seven emergencies, each opening its own page of numbered
/// steps with a call button at the bottom. It used to be seven collapsed rows
/// that opened in place, so reading one meant scrolling past the others with
/// your thumb, mid-emergency.
class SafetyGuideScreen extends StatelessWidget {
  const SafetyGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final guides = _buildGuides(t);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(t.safetyGuideTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space16,
          ZirenTokens.space4,
          ZirenTokens.space16,
          ZirenTokens.space32,
        ),
        children: [
          _OfflineBanner(text: t.safetyGuideIntro),
          const SizedBox(height: ZirenTokens.space16),
          // Two per row, each row as tall as its taller card, so a two-line
          // title does not leave its neighbour short.
          for (var i = 0; i < guides.length; i += 2) ...[
            if (i > 0) const SizedBox(height: ZirenTokens.space10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in guides.skip(i).take(2)) ...[
                    if (g != guides[i]) const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: _GuideCard(
                        guide: g,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SafetyGuideDetailScreen(guide: g)),
                        ),
                      ),
                    ),
                  ],
                  if (i + 1 >= guides.length) ...[
                    const SizedBox(width: ZirenTokens.space10),
                    const Expanded(child: SizedBox()),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemSuccessBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.systemSuccess.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ZirenTokens.systemSuccess.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(LucideIcons.book_open_check, size: 18, color: ZirenTokens.systemSuccess),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: ZirenTokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.guide, required this.onTap});

  final SafetyGuide guide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(ZirenTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: guide.bg,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Icon(guide.icon, color: guide.color, size: 22),
                    ),
                    const Spacer(),
                    Icon(LucideIcons.arrow_up_right, size: 18, color: ZirenTokens.textMuted),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space12),
                Text(
                  guide.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  t.safetyGuideSteps('${guide.steps.length}'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ZirenTokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One emergency's steps, full screen, with the hotlines one press away.
class SafetyGuideDetailScreen extends StatelessWidget {
  const SafetyGuideDetailScreen({super.key, required this.guide});

  final SafetyGuide guide;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(guide.title),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space12,
              ZirenTokens.space16,
              ZirenTokens.space12,
            ),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.push('/hotlines'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZirenTokens.systemSuccess,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.phone_call, size: 18),
                    const SizedBox(width: ZirenTokens.space8),
                    Text(
                      t.safetyGuideCallHotline,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space16,
          ZirenTokens.space4,
          ZirenTokens.space16,
          ZirenTokens.space24,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            decoration: BoxDecoration(
              color: guide.bg,
              borderRadius: BorderRadius.circular(ZirenTokens.radius20),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceCard,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: Icon(guide.icon, color: guide.color, size: 26),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guide.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.safetyGuideSteps('${guide.steps.length}'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: guide.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZirenTokens.space16),
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            decoration: profileCardDecoration(),
            child: Column(
              children: [
                for (var i = 0; i < guide.steps.length; i++)
                  _GuideStep(
                    number: i + 1,
                    text: guide.steps[i],
                    color: guide.color,
                    bg: guide.bg,
                    last: i == guide.steps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.text,
    required this.color,
    required this.bg,
    required this.last,
  });

  final int number;
  final String text;
  final Color color;
  final Color bg;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    '$number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: color.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: last ? 0 : ZirenTokens.space20),
              child: Text(
                text,
                style: TextStyle(fontSize: 14.5, height: 1.5, color: ZirenTokens.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One emergency and what to do in it.
class SafetyGuide {
  const SafetyGuide({
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

List<SafetyGuide> _buildGuides(AppLocalizations t) => [
  SafetyGuide(
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
  SafetyGuide(
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
  SafetyGuide(
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
  SafetyGuide(
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
  SafetyGuide(
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
  SafetyGuide(
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
  SafetyGuide(
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
