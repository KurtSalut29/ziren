import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// ============================================================
// Ziren Design Tokens — Mobile (Flutter)
// Light theme. Single source of truth.
//
// RULES (hard — do not override silently):
//
// brandOrange (#FC5A05)
//   → CTAs, active nav, primary buttons, FAB, dispatched status.
//   → NEVER for severity or generic error states.
//   → Red is reserved for critical severity only — if you use
//     orange for errors, the severity signal loses meaning in
//     a dispatch context.
//
// Severity scale (4-tier)
//   → Always pair color with icon + label (accessibility).
//   → severity ≠ workflow status. Tokens are separate intentionally.
//   → Contrast ratios checked ≥4.5:1 on #FAFAFA.
//
// Workflow status
//   → Separate from severity. "dispatched" maps to brandOrange
//     (key action moment). "processing" uses indigo — distinct
//     from agencyPNP sky-blue to avoid ambiguity at a glance.
//
// Agency colors
//   → BFP / PNP / MDRRMO fixed hues. Do not repurpose.
//
// aiSuggested (purple)
//   → Machine output ONLY — never decorative.
//
// Typography note (web dashboard)
//   → Web dashboard uses Plus Jakarta Sans loaded via next/font/google
//     (switched from Nunito in Phase 1 design upgrade, 2026-08-02).
//   → Mobile uses the system font stack — no web font load on Flutter.
//   → Keep all color/spacing/radius tokens in sync between this file
//     and ziren_dashboard/app/globals.css.
//
// Keep in sync with ziren_dashboard/app/globals.css.
// ============================================================

abstract final class ZirenTokens {
  // ── Runtime appearance mode ───────────────────────────────
  //
  // Everything below this point was `static const` until Settings grew a
  // real dark mode. Flipping brightness here is what a resident's toggle
  // ultimately does — see AccessibilityProvider, the single writer of this
  // state. Reading it needs no BuildContext, which matters because these
  // fields are called from ~150 files as bare static access
  // (`ZirenTokens.textPrimary`), never `ZirenTokens.of(context).textPrimary`
  // — changing that call shape was not something a font/theme settings
  // screen justified touching.
  //
  // Spacing, radius, motion, agency/severity hues and icons stay `const`:
  // nothing below asks them to change, and leaving them alone kept this
  // change to the ~50 call sites that actually needed unconsting rather than
  // the ~3000 that reference this file at all.
  static Brightness _brightness = Brightness.light;
  static bool _highContrast = false;

  static bool get isDark => _brightness == Brightness.dark;

  /// Called by AccessibilityProvider whenever the resolved brightness or the
  /// high-contrast preference changes. Never called mid-frame — the provider
  /// sets this, then forces a full remount (see main.dart's KeyedSubtree) so
  /// every static getter below is re-read from scratch rather than leaving
  /// stale colors painted from the previous mode.
  static void setMode({required Brightness brightness, required bool highContrast}) {
    _brightness = brightness;
    _highContrast = highContrast;
  }

  // ── Brand / Primary ──────────────────────────────────────
  static const Color brandOrange = Color(0xFFFC5A05);
  static const Color brandDim = Color(0xFFE04E04); // hover / pressed
  static const Color brandActive = Color(
    0xFFC94600,
  ); // active nav / selected state

  // Tinted surfaces — a light orange wash in both themes, since a solid
  // pastel behind orange text goes muddy on a dark base. withValues keeps
  // the same brand hue doing the tinting either way.
  static Color get brandSubtle =>
      isDark ? brandOrange.withValues(alpha: 0.14) : const Color(0xFFFFF0E8);
  static Color get brandContainer =>
      isDark ? brandOrange.withValues(alpha: 0.22) : const Color(0xFFFFE4D0);

  // ── Surfaces ───────────────────────────────────────────────
  // Dark values avoid pure black — a slightly warm near-black reads as a
  // deliberate palette rather than "brightness inverted", and each step
  // (base → card → raised) still reads as an elevation ladder the way the
  // light theme's white/near-white/pale-grey does.
  static Color get surfaceBase =>
      isDark ? const Color(0xFF121214) : const Color(0xFFFAFAFA);
  static Color get surfaceCard =>
      isDark ? const Color(0xFF1C1C1F) : const Color(0xFFFFFFFF);
  static Color get surfaceRaised =>
      isDark ? const Color(0xFF252528) : const Color(0xFFF4F4F5);
  static Color get surfaceOverlay =>
      isDark ? const Color(0xFF232326) : const Color(0xFFFFFFFF);
  static Color get surfaceBorder {
    if (isDark) return _highContrast ? const Color(0xFF57575F) : const Color(0xFF333338);
    return _highContrast ? const Color(0xFFB0B0B8) : const Color(0xFFE4E4E7);
  }

  // ── Text ───────────────────────────────────────────────────
  // Contrast ratios vs the matching surfaceBase:
  //   textPrimary    ~16:1 both themes   headings, key values
  //   textSecondary  ~7:1 both themes    labels, secondary info
  //   textMuted      3.5:1 light / ~6:1 dark, boosted further under
  //                  high contrast — this was the one token the original
  //                  light-only doc comment flagged as "large text only".
  //   textDisabled   —   non-interactive, not contrast-checked
  static Color get textPrimary =>
      isDark ? const Color(0xFFF5F5F6) : const Color(0xFF1A1A1A);
  static Color get textSecondary =>
      isDark ? const Color(0xFFB4B4BC) : const Color(0xFF52525B);
  static Color get textMuted {
    if (_highContrast) return textSecondary;
    return isDark ? const Color(0xFF8B8B95) : const Color(0xFFA1A1AA);
  }
  static Color get textDisabled =>
      isDark ? const Color(0xFF4B4B52) : const Color(0xFFD4D4D8);
  static const Color textInverse = Color(0xFFFFFFFF); // text on brand bg

  // ── Severity (4-tier — contrast-checked ≥4.5:1 on #FAFAFA) ──
  // RULE: always pair with icon + label. Never color alone.
  // RULE: severity ≠ brandOrange. Red/amber/green = risk signal.

  // Base hues are the safety constraint — fixed across both themes so "red
  // means critical" never depends on which mode is active. Only the pastel
  // *Bg fills adapt: a low-alpha wash of the same hue on the dark surface,
  // rather than the light theme's near-white tint, which would render as a
  // glaring pale card on a near-black scaffold.
  /// Critical — fire, mass casualty. Contrast 5.9:1 (light)
  static const Color severityCritical = Color(0xFFDC2626);
  static Color get severityCriticalBg => isDark
      ? severityCritical.withValues(alpha: 0.16)
      : const Color(0xFFFEF2F2);
  static const Color severityCriticalBorder = Color(0xFFFECACA);
  static const IconData severityCriticalIcon = LucideIcons.triangle_alert;

  /// High — injury, armed incident. Contrast 4.7:1 (light)
  static const Color severityHigh = Color(0xFFD97706);
  static Color get severityHighBg =>
      isDark ? severityHigh.withValues(alpha: 0.16) : const Color(0xFFFFFBEB);
  static const Color severityHighBorder = Color(0xFFFDE68A);
  static const IconData severityHighIcon = LucideIcons.octagon_alert;

  /// Medium — property damage, minor. Contrast 4.6:1 (light)
  static const Color severityMedium = Color(0xFFCA8A04);
  static Color get severityMediumBg => isDark
      ? severityMedium.withValues(alpha: 0.16)
      : const Color(0xFFFEFCE8);
  static const Color severityMediumBorder = Color(0xFFFEF08A);
  static const IconData severityMediumIcon = LucideIcons.info;

  /// Low — informational. Contrast 5.2:1 (light)
  static const Color severityLow = Color(0xFF16A34A);
  static Color get severityLowBg =>
      isDark ? severityLow.withValues(alpha: 0.16) : const Color(0xFFF0FDF4);
  static const Color severityLowBorder = Color(0xFFBBF7D0);
  static const IconData severityLowIcon = LucideIcons.circle_check_big;

  // ── Workflow status (incident lifecycle — NOT severity) ──
  // received    — neutral, pending dispatcher review
  static const Color statusReceived = Color(0xFF6B7280);
  static Color get statusReceivedBg => isDark
      ? statusReceived.withValues(alpha: 0.16)
      : const Color(0xFFF9FAFB);

  // processing  — indigo, distinct from agencyPNP sky-blue
  static const Color statusProcessing = Color(0xFF4F46E5);
  static Color get statusProcessingBg => isDark
      ? statusProcessing.withValues(alpha: 0.18)
      : const Color(0xFFEEF2FF);

  // dispatched  — brand orange, the key action moment
  static const Color statusDispatched = Color(0xFFFC5A05);
  static Color get statusDispatchedBg => brandSubtle;

  // resolved    — green, terminal success
  static const Color statusResolved = Color(0xFF16A34A);
  static Color get statusResolvedBg => isDark
      ? statusResolved.withValues(alpha: 0.16)
      : const Color(0xFFF0FDF4);

  // cancelled   — muted, terminal
  static const Color statusCancelled = Color(0xFF9CA3AF);
  static Color get statusCancelledBg => isDark
      ? statusCancelled.withValues(alpha: 0.16)
      : const Color(0xFFF3F4F6);

  // ── System / validation ───────────────────────────────────
  static const Color systemSuccess = Color(0xFF16A34A);
  static Color get systemSuccessBg => isDark
      ? systemSuccess.withValues(alpha: 0.16)
      : const Color(0xFFF0FDF4);
  static const Color systemWarning = Color(0xFFD97706);
  static Color get systemWarningBg => isDark
      ? systemWarning.withValues(alpha: 0.16)
      : const Color(0xFFFFFBEB);
  static const Color systemError = Color(0xFFDC2626);
  static Color get systemErrorBg =>
      isDark ? systemError.withValues(alpha: 0.16) : const Color(0xFFFEF2F2);
  static const Color systemInfo = Color(0xFF0EA5E9);
  static Color get systemInfoBg =>
      isDark ? systemInfo.withValues(alpha: 0.16) : const Color(0xFFF0F9FF);

  // ── Connectivity mode ─────────────────────────────────────
  static const Color connectivityOnline = Color(0xFF16A34A);
  static const Color connectivityOffline = Color(0xFF9CA3AF);

  // ── AI-suggested vs human-confirmed ──────────────────────
  // RULE: purple = machine output ONLY. Never decorative.
  static const Color aiSuggested = Color(0xFF7C3AED);
  static Color get aiSuggestedBg =>
      isDark ? aiSuggested.withValues(alpha: 0.18) : const Color(0xFFF5F3FF);
  static const Color confirmed = Color(0xFFFC5A05);
  static Color get confirmedBg => brandSubtle;

  // ── Agency identity ───────────────────────────────────────
  // RULE: do NOT repurpose for severity or workflow status.
  static const Color agencyBFP = Color(0xFFEF4444); // fire/rescue
  static Color get agencyBFPBg =>
      isDark ? agencyBFP.withValues(alpha: 0.16) : const Color(0xFFFEF2F2);
  static const Color agencyPNP = Color(0xFF0EA5E9); // police
  static Color get agencyPNPBg =>
      isDark ? agencyPNP.withValues(alpha: 0.16) : const Color(0xFFF0F9FF);
  static const Color agencyMDRRMO = Color(0xFF10B981); // disaster
  static Color get agencyMDRRMOBg => isDark
      ? agencyMDRRMO.withValues(alpha: 0.16)
      : const Color(0xFFECFDF5);

  // ── Incident category (selection UI only) ─────────────────
  // RULE: for the category grid/tiles only — never severity, never a
  // second name for an agency hue. Fire, Flood and Crime already have an
  // owning agency and use that hue directly (see IncidentCategoryStyle);
  // Medical and Accident do not map to one Ziren agency, so they get their
  // own identity here instead of borrowing a severity tone that would
  // imply an unscored incident already carries a severity tier.
  static const Color categoryMedical = Color(0xFF0D9488); // teal
  static Color get categoryMedicalBg => isDark
      ? categoryMedical.withValues(alpha: 0.16)
      : const Color(0xFFF0FDFA);
  static const Color categoryAccident = Color(0xFF6366F1); // indigo
  static Color get categoryAccidentBg => isDark
      ? categoryAccident.withValues(alpha: 0.18)
      : const Color(0xFFEEF2FF);

  // ── Spacing scale ─────────────────────────────────────────
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // ── Border radius ─────────────────────────────────────────
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;
  static const double radius12 = 12.0;
  static const double radius16 = 16.0;
  static const double radius20 = 20.0; // card default
  static const double radius24 = 24.0; // nav rows, pillowy cards
  static const double radius32 = 32.0; // FAB, large pill buttons

  // ── Touch targets ─────────────────────────────────────────
  static const double minTouchTarget = 48.0;

  // ── Motion ────────────────────────────────────────────────
  //
  // Before these existed the app carried thirteen different duration
  // literals — 110, 120, 140, 150, 160, 180, 200, 220, 240ms — for the
  // same three or four kinds of transition. The values were individually
  // reasonable and collectively arbitrary: nothing said which to reach
  // for, so each screen picked again.
  //
  // Bands, not a smooth scale. Each one names a job:
  //
  //   press     a control acknowledging a finger. Must beat the eye.
  //   quick     chips, toggles, small tint and border changes.
  //   base      the default. Sheets, expansions, list rows settling.
  //   entrance  a whole surface arriving. The ceiling for ordinary UI.
  //
  // The two long ones are deliberate exceptions and stay named as such,
  // so they read as decisions rather than as outliers.
  static const Duration motionPress = Duration(milliseconds: 120);
  static const Duration motionQuick = Duration(milliseconds: 160);
  static const Duration motionBase = Duration(milliseconds: 220);
  static const Duration motionEntrance = Duration(milliseconds: 320);

  /// The category ring deploying out of the SOS. Long on purpose: it is the
  /// one moment on Home that explains the layout, and it plays once.
  static const Duration motionDial = Duration(milliseconds: 820);

  /// The SOS breathing. A slow cycle reads as "live", a fast one as "alarm",
  /// and the button is not the alarm — the emergency is.
  static const Duration motionPulse = Duration(milliseconds: 2200);

  /// Entrances and exits both. Ease-out means the motion arrives fast and
  /// settles, which is what makes a UI feel responsive rather than eager;
  /// ease-in on an entrance is the single most common way to make a screen
  /// feel slow. There is deliberately no ease-in-out token — it belongs to
  /// things that loop, and nothing here loops except the pulse.
  static const Curve curveStandard = Curves.easeOutCubic;

  /// Slight overshoot. Reserved for the dial chips, where the overshoot is
  /// what sells them as having been thrown outward. Not a default.
  static const Curve curveOvershoot = Curves.easeOutBack;

  // ── Brand gradient ────────────────────────────────────────
  // Reserved for the single most-important hero card per screen
  // (SOS button, main status hero). Not for decorative use.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFC5A05), Color(0xFFFF8C42)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows ───────────────────────────────────────────────
  // Use sparingly — light theme uses elevation via shadow, not bg change.
  // Dark surfaces already separate visually by tone (surfaceCard sits
  // lighter than surfaceBase), so a light-theme-strength shadow just reads
  // as a muddy halo — halved alpha keeps the same cards feeling "lifted"
  // instead.
  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: isDark ? 0.03 : 0.06),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMd => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: isDark ? 0.04 : 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLg => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: isDark ? 0.05 : 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
