import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/ziren_logo.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Structural shell shared by every auth screen: a photographic brand hero,
/// a light card that rises over it, and the Ziren mark on a white disc
/// straddling the seam between the two.
///
/// Why this shape rather than a form on a plain scaffold — the auth screens
/// are the only part of Ziren a person meets before they have any context for
/// what the product is. A full-bleed brand panel does that introduction in one
/// glance, and the overlapping card gives the form a clear physical boundary
/// instead of leaving fields floating on an empty background. The disc on the
/// seam is what stitches the two halves into one object; without it the card
/// reads as a separate screen that happens to sit on top of an unrelated one.
///
/// The masthead — disc, title, subtitle — does not scroll. It names the card,
/// and a name that slides away under a two-field form looks like a bug. Only
/// [child] scrolls.
///
/// The hero carries the artwork in assets/images/auth_backdrop.jpg — PNP,
/// MDRRMO and BFP at work, which is the one thing that says what this app is
/// for before a person has read a word of it.
///
/// The ink behind and over it is a neutral near-black, deliberately not a
/// brand or severity colour: brand orange stays reserved for actions, and the
/// severity palette must keep meaning what it means in the dispatch UI. The
/// scrim is not decoration either — the artwork has a burning house in it, and
/// white text over open flame fails contrast outright.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.compact = false,
    this.onBack,
  });

  /// Card content, below the masthead. This is the part that scrolls.
  final Widget child;

  /// Large heading rendered under the disc, centred.
  final String? title;
  final String? subtitle;

  /// Shorter hero, for screens whose content is long (registration).
  final bool compact;

  final VoidCallback? onBack;

  // Neutral near-black. Sampled to sit alongside textPrimary (#1A1A1A)
  // without reading as pure black, which looks harsh at full-bleed size.
  // Also the colour the artwork's own darkest region settles to, so the
  // image and the surface behind it meet without a seam.
  static const Color _heroInk = Color(0xFF141419);

  /// Corner radius of the card. Larger than radius24 on purpose — at phone
  /// width this is the biggest rounded shape on screen, and matching it to a
  /// list card would make it read as one.
  static const double _cardRadius = 32;

  @override
  Widget build(BuildContext context) {
    // The hero gives up height to the keyboard. Without this the card keeps a
    // fixed top edge, and on a short phone the masthead plus one field is
    // already taller than what the keyboard leaves — the form would have
    // nowhere to go.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final heroHeight =
        keyboardOpen ? (compact ? 108.0 : 132.0) : (compact ? 190.0 : 268.0);
    // Raised from 62/78, and the padding inside it cut, because the mark was
    // too small to make out. Both were sized against an asset that turned out
    // to be 344x589 rather than square — BoxFit.contain then fitted it by
    // height and drew the monogram at 58% of the width it was given. The
    // asset is fixed (see make-logo-assets.mjs), and these are the numbers
    // that were only ever compensating for it.
    final discSize = compact ? 76.0 : 96.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The hero is dark, so the status bar icons must be light or they
      // disappear into it.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _heroInk,
        // SizedBox.expand is load-bearing. A Stack sizes itself to its largest
        // NON-positioned child, so with the hero left unpositioned the Stack
        // collapsed to the hero's height and `Positioned.fill(top: ...)` gave
        // the card 28px to render a whole form in. Every child below is
        // positioned, so the Stack now takes its size from these constraints
        // instead. Analyzer and runtime were both silent about it.
        body: SizedBox.expand(
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: ZirenTokens.motionBase,
                curve: ZirenTokens.curveStandard,
                top: 0,
                left: 0,
                right: 0,
                height: heroHeight,
                child: _Hero(compact: compact),
              ),

              if (onBack != null)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + ZirenTokens.space8,
                  left: ZirenTokens.space12,
                  child: _ScrimBackButton(onPressed: onBack!),
                ),

              // Card — its top edge is where the hero ends, with the disc
              // hanging above it.
              AnimatedPositioned(
                duration: ZirenTokens.motionBase,
                curve: ZirenTokens.curveStandard,
                top: heroHeight,
                left: 0,
                right: 0,
                bottom: 0,
                child: Stack(
                  // So the disc can paint outside this box, over the hero.
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: ZirenTokens.surfaceCard,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(_cardRadius),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Theme(
                          data: _cardTheme(context),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Room for the half of the disc that overhangs.
                              SizedBox(
                                height: discSize / 2 + ZirenTokens.space16,
                              ),

                              if (title != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    ZirenTokens.space24,
                                    0,
                                    ZirenTokens.space24,
                                    ZirenTokens.space24,
                                  ),
                                  child: _Masthead(
                                    title: title!,
                                    subtitle: subtitle,
                                    compact: compact,
                                  ),
                                ),

                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    ZirenTokens.space24,
                                    0,
                                    ZirenTokens.space24,
                                    ZirenTokens.space32,
                                  ),
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 480,
                                      ),
                                      child: child,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      top: -discSize / 2,
                      left: 0,
                      right: 0,
                      child: Center(child: _BrandDisc(size: discSize)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pill geometry, scoped to the auth card.
  ///
  /// Deliberately a local override rather than an edit to the app theme: the
  /// report wizard and the responder screens are dense, and 32px corners on
  /// every input there would cost horizontal room those fields actually need.
  /// Only the auth and registration flow gets the softer shape.
  ThemeData _cardTheme(BuildContext context) {
    final base = Theme.of(context);
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ZirenTokens.radius32),
    );

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      borderSide: BorderSide(color: color, width: width),
    );

    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: border(ZirenTokens.surfaceBorder, 1),
        enabledBorder: border(ZirenTokens.surfaceBorder, 1),
        focusedBorder: border(ZirenTokens.brandOrange, 2),
        errorBorder: border(ZirenTokens.systemError, 2),
        focusedErrorBorder: border(ZirenTokens.systemError, 2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space20,
          vertical: 17,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          shape: WidgetStatePropertyAll(pill),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          shape: WidgetStatePropertyAll(pill),
        ),
      ),
    );
  }
}

// ── Masthead ──────────────────────────────────────────────────

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final String title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 23 : 27,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.6,
            color: ZirenTokens.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: ZirenTokens.space8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// The mark on a white disc, straddling the hero/card seam.
class _BrandDisc extends StatelessWidget {
  const _BrandDisc({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // 0.16, not 0.22. The disc is a frame for the mark, and a fifth of it
      // spent on inner margin was most of why the logo read as small.
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        shape: BoxShape.circle,
        boxShadow: ZirenTokens.shadowMd,
      ),
      // Decorative here: the wordmark in the hero already names the product,
      // and a screen reader announcing it twice adds nothing.
      // The monogram, not the lockup: this badge is at most 64px across and
      // the bundled wordmark inside it would render about 6px tall.
      child: ExcludeSemantics(
        child: ZirenLogo.mark(size: double.infinity, onDark: ZirenTokens.isDark),
      ),
    );
  }
}

/// Back affordance over the hero art. A bare white arrow on a gradient loses
/// contrast wherever the glow sits behind it, so it rides its own scrim.
class _ScrimBackButton extends StatelessWidget {
  const _ScrimBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const SizedBox(
          width: ZirenTokens.minTouchTarget,
          height: ZirenTokens.minTouchTarget,
          child: Icon(
            LucideIcons.chevron_left,
            size: 18,
            color: Colors.white,
            semanticLabel: 'Back',
          ),
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    // ClipRect keeps the artwork inside the hero while it animates down to
    // keyboard height; without it the image spills onto the card.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // COVER, ALIGNED TOP, over a matching base colour.
          //
          // The hero is a wide, short band and the artwork is 16:9, so cover
          // crops the sides rather than letterboxing — and aligning to the top
          // keeps the three agencies in frame, which is the half of the
          // picture worth showing. The base colour underneath matches the
          // artwork's own darkest region, so there is no seam if a device ever
          // gives the box an aspect the image cannot fill.
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AuthShell._heroInk,
              image: DecorationImage(
                image: AssetImage('assets/images/auth_backdrop.jpg'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),

          // Scrim. Load-bearing, not styling: the artwork contains a burning
          // house and police lights, and the wordmark below is white. Darkest
          // at the two edges — under the status bar, where the back button
          // sits, and at the bottom, where the hero meets the card.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3000000),
                  Color(0x59000000),
                  Color(0xD9141419),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
            ),
          ),

          // The wordmark, centred above the disc. The mark itself lives on the
          // disc at the seam, so the hero carries the name and the promise —
          // the two things a first-time user needs before they meet a form.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'ZIREN',
                    style: TextStyle(
                      fontSize: compact ? 24 : 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: compact ? 3 : 4,
                      shadows: const [
                        Shadow(blurRadius: 12, color: Color(0x99000000)),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: ZirenTokens.space8),
                    Text(
                      'Emergency response for Biliran Province',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.82),
                        shadows: const [
                          Shadow(blurRadius: 10, color: Color(0x99000000)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Field with caption ────────────────────────────────────────
//
// A small caption above the control rather than a floating Material label —
// the label stays put while the field fills, which is what makes a stack of
// them scannable.

class AuthField extends StatefulWidget {
  const AuthField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Once the caption moved above the control, the input's own focus ring
    // became the only focus signal — and a coloured border alone is a
    // colour-only cue, which fails for anyone who cannot distinguish it.
    // Driving the caption from focus too means the active field is marked by
    // position, weight and colour together, not colour by itself.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // hasFocus is true when any descendant holds focus, so this reports the
      // wrapped input without owning focus itself.
      onFocusChange: (has) {
        if (has != _focused) setState(() => _focused = has);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // The pill inputs are inset 20px from their own edge, so a caption
            // hard against the card padding looked detached from its field.
            padding: const EdgeInsets.only(left: ZirenTokens.space4),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: ZirenTokens.motionQuick,
                  width: _focused ? 3 : 0,
                  height: 12,
                  margin: EdgeInsets.only(right: _focused ? 6 : 0),
                  decoration: BoxDecoration(
                    color: ZirenTokens.brandOrange,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Flexible(child: AuthFieldLabel(widget.label, active: _focused)),
              ],
            ),
          ),
          const SizedBox(height: ZirenTokens.space8),
          widget.child,
        ],
      ),
    );
  }
}

/// The caption on its own, for controls that are not a single field —
/// a chip group or a pair of role cards.
class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.text, {super.key, this.active = false});

  final String text;

  /// Highlights the caption while its field holds focus.
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Sentence case in near-black, not an uppercase tracked-out micro-caption.
    // Uppercase labels read as metadata about the field; these are the
    // questions being asked, so they carry the same weight as the answer.
    return AnimatedDefaultTextStyle(
      duration: ZirenTokens.motionQuick,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: active ? ZirenTokens.brandOrange : ZirenTokens.textPrimary,
        letterSpacing: -0.1,
      ),
      child: Text(text),
    );
  }
}

/// The "already have an account / don't have one" line that closes an auth
/// card: muted question, then the action in ink.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            question,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 14, color: ZirenTokens.textMuted),
          ),
        ),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: ZirenTokens.textPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: ZirenTokens.space8,
              vertical: ZirenTokens.space8,
            ),
            minimumSize: const Size(0, ZirenTokens.minTouchTarget),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Text(action),
        ),
      ],
    );
  }
}

/// Seamless action rows — one bordered container, hairline separators.
class AuthActionRows extends StatelessWidget {
  const AuthActionRows({super.key, required this.rows});

  final List<AuthActionRow> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            thickness: 1,
            color: ZirenTokens.surfaceBorder,
          ),
        );
      }
      children.add(rows[i]);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(ZirenTokens.radius20),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          border: Border.all(color: ZirenTokens.surfaceBorder),
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class AuthActionRow extends StatelessWidget {
  const AuthActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.iconColor,
    this.iconBg,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? iconBg;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space12,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg ?? ZirenTokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? ZirenTokens.textSecondary,
                ),
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevron_right,
                color: ZirenTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
