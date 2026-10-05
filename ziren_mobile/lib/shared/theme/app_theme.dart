import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

// ============================================================
// Ziren Material 3 ThemeData — light + dark
//
// Font: Nunito (rounded geometric sans — warm, friendly,
//   readable at small sizes, supports Filipino/Bisaya strings
//   without layout breakage).
//
// Rules:
//   - Do not hardcode colours in widgets. Use ZirenTokens.
//   - AppBar is surfaceCard with a bottom border — keeps orange
//     reserved for actions, not chrome.
//   - ElevatedButton = brandOrange, primary actions only.
//   - SOS button uses severityCritical — approved exception.
//   - Card radius = radius20 (pillowy). Use radius24 for hero cards.
//   - Shadows via ZirenTokens.shadowSm/Md/Lg — no elevation tinting.
//
// One ThemeData builder, not two: `themeFor(brightness)` below reads
// ZirenTokens.* throughout, and those are brightness-aware getters — see
// app_tokens.dart. The caller (main.dart) sets ZirenTokens' mode via
// AccessibilityProvider *before* evaluating this, so brightness only needs
// stating explicitly here for the two things ThemeData itself requires it
// for (ColorScheme.brightness, and the status bar icon colour).
// ============================================================

abstract final class AppTheme {
  // ── Nunito text theme ────────────────────────────────────
  static TextTheme get _textTheme {
    // Build each style explicitly to preserve colors.
    // Calling GoogleFonts.nunitoTextTheme() can silently reset
    // color values via TextTheme.apply() — avoid it.
    final nunito = GoogleFonts.nunito();

    T applyNunito<T extends TextStyle>(T style) =>
        style.copyWith(fontFamily: nunito.fontFamily) as T;

    final base = TextTheme(
      // Display — hero greetings, key stats
      displayLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: ZirenTokens.textPrimary,
        height: 1.2,
        letterSpacing: -0.3,
      ),
      // Screen titles
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ZirenTokens.textPrimary,
        height: 1.3,
      ),
      // Section headers
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ZirenTokens.textPrimary,
        height: 1.3,
      ),
      // Card titles
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ZirenTokens.textPrimary,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ZirenTokens.textPrimary,
        height: 1.4,
      ),
      // Body copy
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: ZirenTokens.textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: ZirenTokens.textSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: ZirenTokens.textMuted,
        height: 1.5,
      ),
      // Buttons
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: ZirenTokens.textPrimary,
        letterSpacing: 0.1,
      ),
      // Section labels — UPPERCASE + letter-spacing use site
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: ZirenTokens.textMuted,
        letterSpacing: 0.8,
      ),
    );

    return base.copyWith(
      displayLarge: applyNunito(base.displayLarge!),
      headlineMedium: applyNunito(base.headlineMedium!),
      headlineSmall: applyNunito(base.headlineSmall!),
      titleMedium: applyNunito(base.titleMedium!),
      titleSmall: applyNunito(base.titleSmall!),
      bodyLarge: applyNunito(base.bodyLarge!),
      bodyMedium: applyNunito(base.bodyMedium!),
      bodySmall: applyNunito(base.bodySmall!),
      labelLarge: applyNunito(base.labelLarge!),
      labelSmall: applyNunito(base.labelSmall!),
    );
  }

  // ── Theme ──────────────────────────────────────────────────
  // `brightness` only decides ColorScheme.brightness and the status bar icon
  // colour below — every actual colour comes from ZirenTokens, which the
  // caller has already switched into the matching mode.
  static ThemeData themeFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,

      // Brand
      primary: ZirenTokens.brandOrange,
      onPrimary: ZirenTokens.textInverse,
      primaryContainer: ZirenTokens.brandContainer,
      onPrimaryContainer: ZirenTokens.brandOrange,

      // Secondary — processing indigo
      secondary: ZirenTokens.statusProcessing,
      onSecondary: ZirenTokens.textInverse,
      secondaryContainer: ZirenTokens.statusProcessingBg,
      onSecondaryContainer: ZirenTokens.statusProcessing,

      // Tertiary — MDRRMO emerald
      tertiary: ZirenTokens.agencyMDRRMO,
      onTertiary: ZirenTokens.textInverse,
      tertiaryContainer: ZirenTokens.agencyMDRRMOBg,
      onTertiaryContainer: ZirenTokens.agencyMDRRMO,

      // Error
      error: ZirenTokens.systemError,
      onError: ZirenTokens.textInverse,
      errorContainer: ZirenTokens.systemErrorBg,
      onErrorContainer: ZirenTokens.systemError,

      // Surfaces
      surface: ZirenTokens.surfaceCard,
      onSurface: ZirenTokens.textPrimary,
      onSurfaceVariant: ZirenTokens.textSecondary,
      outline: ZirenTokens.surfaceBorder,
      outlineVariant: ZirenTokens.surfaceRaised,
      surfaceContainerHighest: ZirenTokens.surfaceOverlay,
      surfaceContainerHigh: ZirenTokens.surfaceCard,
      surfaceContainer: ZirenTokens.surfaceRaised,
      surfaceContainerLow: ZirenTokens.surfaceRaised,
      surfaceContainerLowest: ZirenTokens.surfaceBase,
      inverseSurface: ZirenTokens.textPrimary,
      onInverseSurface: ZirenTokens.textInverse,
      inversePrimary: ZirenTokens.brandDim,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ZirenTokens.surfaceBase,
      textTheme: _textTheme,

      // ── AppBar ───────────────────────────────────────────
      // White background with subtle bottom border.
      // Orange stays reserved for actions, not chrome.
      appBarTheme: AppBarTheme(
        backgroundColor: ZirenTokens.surfaceCard,
        foregroundColor: ZirenTokens.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ZirenTokens.textPrimary,
        ),
        iconTheme: IconThemeData(color: ZirenTokens.textSecondary),
        actionsIconTheme: IconThemeData(color: ZirenTokens.textSecondary),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: ZirenTokens.surfaceBorder, width: 1),
        ),
        // The status bar sits over the AppBar's own background, so its icons
        // need the opposite brightness from the surface behind them — dark
        // icons read on the light AppBar, and would vanish on the dark one.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      ),

      // ── Elevated button — brand orange ───────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ZirenTokens.brandOrange,
          foregroundColor: ZirenTokens.textInverse,
          disabledBackgroundColor: ZirenTokens.surfaceRaised,
          disabledForegroundColor: ZirenTokens.textMuted,
          minimumSize: const Size.fromHeight(ZirenTokens.minTouchTarget + 4),
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space24,
            vertical: ZirenTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          ),
          elevation: 0,
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ── Outlined button ──────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ZirenTokens.brandOrange,
          disabledForegroundColor: ZirenTokens.textMuted,
          minimumSize: const Size.fromHeight(ZirenTokens.minTouchTarget + 4),
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space24,
            vertical: ZirenTokens.space12,
          ),
          side: const BorderSide(color: ZirenTokens.brandOrange, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ── Text button ──────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ZirenTokens.brandOrange,
          textStyle: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input decoration ─────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ZirenTokens.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          borderSide: const BorderSide(
            color: ZirenTokens.brandOrange,
            width: 2,
          ),
        ),
        // 2px to match the focus ring. At 1px an invalid field read as less
        // prominent than a merely-focused one, which inverts the priority.
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          borderSide: const BorderSide(
            color: ZirenTokens.systemError,
            width: 2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          borderSide: const BorderSide(
            color: ZirenTokens.systemError,
            width: 2,
          ),
        ),
        labelStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: ZirenTokens.textSecondary,
        ),
        hintStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: ZirenTokens.textMuted,
        ),
        // Error text is an instruction, not a footnote — it carries the fix.
        errorStyle: GoogleFonts.nunito(
          fontSize: 12.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: ZirenTokens.systemError,
        ),
        // Messages here name the specific fix, so they need room to wrap
        // rather than being truncated to a single line.
        errorMaxLines: 3,
        helperMaxLines: 2,
        floatingLabelStyle: GoogleFonts.nunito(
          fontSize: 12,
          color: ZirenTokens.brandOrange,
        ),
        prefixIconColor: ZirenTokens.textMuted,
        suffixIconColor: ZirenTokens.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space16,
          vertical: 14.0,
        ),
      ),

      // ── Text cursor ──────────────────────────────────────
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ZirenTokens.brandOrange,
        selectionColor: ZirenTokens.brandOrange.withValues(alpha: 0.2),
        selectionHandleColor: ZirenTokens.brandOrange,
      ),

      // ── Card ─────────────────────────────────────────────
      // radius20 default, flat elevation, subtle border.
      cardTheme: CardThemeData(
        color: ZirenTokens.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
          side: BorderSide(color: ZirenTokens.surfaceBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Divider ──────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: ZirenTokens.surfaceBorder,
        thickness: 1,
        space: 1,
      ),

      // ── Chip ─────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: ZirenTokens.surfaceRaised,
        selectedColor: ZirenTokens.brandContainer,
        labelStyle: GoogleFonts.nunito(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ZirenTokens.textSecondary,
        ),
        secondaryLabelStyle: GoogleFonts.nunito(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ZirenTokens.brandOrange,
        ),
        side: BorderSide(color: ZirenTokens.surfaceBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        ),
      ),

      // ── Switch ───────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ZirenTokens.textInverse;
          }
          return ZirenTokens.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ZirenTokens.brandOrange;
          }
          return ZirenTokens.surfaceRaised;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return ZirenTokens.surfaceBorder;
        }),
      ),

      // ── Checkbox ─────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ZirenTokens.brandOrange;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(ZirenTokens.textInverse),
        side: BorderSide(color: ZirenTokens.surfaceBorder, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius4),
        ),
      ),

      // ── SnackBar ─────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ZirenTokens.toastSurface,
        contentTextStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: ZirenTokens.toastText,
        ),
        actionTextColor: ZirenTokens.brandOrange,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          side: BorderSide(color: ZirenTokens.toastBorder),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── Bottom sheet ─────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: ZirenTokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZirenTokens.radius24),
          ),
        ),
      ),

      // ── Dialog ───────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: ZirenTokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius24),
        ),
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ZirenTokens.textPrimary,
        ),
        contentTextStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: ZirenTokens.textSecondary,
        ),
      ),

      // ── List tile ────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: ZirenTokens.textPrimary,
        iconColor: ZirenTokens.textMuted,
        subtitleTextStyle: GoogleFonts.nunito(
          fontSize: 12,
          color: ZirenTokens.textMuted,
        ),
      ),

      // ── Popup menu ───────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: ZirenTokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          side: BorderSide(color: ZirenTokens.surfaceBorder),
        ),
        elevation: 4,
        shadowColor: const Color(
          0xFF000000,
        ).withValues(alpha: dark ? 0.24 : 0.08),
        textStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: ZirenTokens.textPrimary,
        ),
      ),

      // ── Navigation bar (bottom shell) ────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ZirenTokens.surfaceCard,
        indicatorColor: ZirenTokens.brandSubtle,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: ZirenTokens.brandOrange,
              size: 22,
            );
          }
          return IconThemeData(color: ZirenTokens.textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.brandOrange,
            );
          }
          return GoogleFonts.nunito(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: ZirenTokens.textMuted,
          );
        }),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // ── Icon ─────────────────────────────────────────────
      iconTheme: IconThemeData(color: ZirenTokens.textSecondary, size: 24),

      // ── FloatingActionButton ─────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ZirenTokens.brandOrange,
        foregroundColor: ZirenTokens.textInverse,
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }
}
