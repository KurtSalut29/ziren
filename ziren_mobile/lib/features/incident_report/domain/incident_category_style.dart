import 'package:flutter/material.dart';

import '../../../shared/theme/app_tokens.dart';
import 'incident_provider.dart' show IncidentCategory;
import 'package:flutter_lucide/flutter_lucide.dart';

/// The colour a resident sees for each report category — Home's quick-action
/// ring and the wizard's category grid both read from this one place.
///
/// WHY THIS EXISTS
///
/// The two screens used to define this mapping independently, and they had
/// drifted: Home coloured Calamity with `ZirenTokens.systemInfo` while the
/// wizard coloured it `agencyMDRRMO`, and — the actual bug this fixes —
/// `systemInfo` (`0xFF0EA5E9`) and `agencyPNP` (`0xFF0EA5E9`) are the exact
/// same hex value. Calamity and Crime rendered as pixel-identical blue
/// circles on Home, so the one screen meant to make emergency category
/// selection instant under stress asked a resident to tell two categories
/// apart by icon alone. One canonical mapping, reused by both screens,
/// makes that collision structurally impossible to reintroduce.
///
/// The six colours below are deliberately not decorative choices: three are
/// the fixed agency hues (BFP/PNP/MDRRMO) for the categories that agency
/// visibly owns, and the remaining three are severity/neutral tones already
/// used nowhere else in this six-way set.
class IncidentCategoryStyle {
  const IncidentCategoryStyle._();

  static Color color(IncidentCategory category) => switch (category) {
    IncidentCategory.fire => ZirenTokens.agencyBFP,
    IncidentCategory.medicalTrauma => ZirenTokens.categoryMedical,
    IncidentCategory.vehicular => ZirenTokens.categoryAccident,
    IncidentCategory.floodLandslideCalamity => ZirenTokens.agencyMDRRMO,
    IncidentCategory.domesticDisputeCrime => ZirenTokens.agencyPNP,
    IncidentCategory.other => ZirenTokens.textSecondary,
  };

  static Color background(IncidentCategory category) => switch (category) {
    IncidentCategory.fire => ZirenTokens.agencyBFPBg,
    IncidentCategory.medicalTrauma => ZirenTokens.categoryMedicalBg,
    IncidentCategory.vehicular => ZirenTokens.categoryAccidentBg,
    IncidentCategory.floodLandslideCalamity => ZirenTokens.agencyMDRRMOBg,
    IncidentCategory.domesticDisputeCrime => ZirenTokens.agencyPNPBg,
    IncidentCategory.other => ZirenTokens.surfaceRaised,
  };

  static IconData icon(IncidentCategory category) => switch (category) {
    IncidentCategory.fire => LucideIcons.flame,
    IncidentCategory.medicalTrauma => LucideIcons.stethoscope,
    IncidentCategory.vehicular => LucideIcons.car,
    IncidentCategory.floodLandslideCalamity => LucideIcons.waves_horizontal,
    IncidentCategory.domesticDisputeCrime => LucideIcons.shield,
    IncidentCategory.other => LucideIcons.ellipsis,
  };
}
