import 'package:flutter/material.dart';

/// The Ziren mark, in the variant that suits the ground it sits on.
///
/// The authored artwork is a two-colour logo — a near-black monogram with one
/// shape in brand orange — on an opaque white field. Neither of those survives
/// contact with a real surface: the white field draws a card around the mark
/// wherever it is placed, and the near-black ink is invisible on anything dark.
///
/// So the per-ground artwork is generated at build time rather than tinted at
/// runtime. `ziren_dashboard/scripts/make-logo-assets.mjs` knocks the white out
/// to alpha and recolours only the NEUTRAL ink, leaving the orange as authored
/// because it clears the 3:1 contrast bar for graphical objects on both light
/// and dark grounds. A ColorFiltered wrapper could not do that — it would have
/// to repaint the orange too.
///
/// Which leaves this widget one decision: mark or lockup, light ground or dark.
///
///   [ZirenLogo.mark]   the ZR monogram alone. Correct anywhere the word
///                      "ZIREN" is already on screen beside it, and correct at
///                      any size under about 96px, where the bundled wordmark
///                      renders as a grey smear and costs the monogram half its
///                      height.
///   [ZirenLogo.lockup] monogram plus wordmark, for a logo standing alone.
///
/// The app is themeMode.light today, so [onDark] is not read from the theme —
/// it names the surface the caller is painting on. Pass true on a dark scrim,
/// the SOS screen, or a brand gradient.
class ZirenLogo extends StatelessWidget {
  const ZirenLogo.mark({super.key, this.size = 40, this.onDark = false})
    : _lockup = false;

  const ZirenLogo.lockup({super.key, this.size = 120, this.onDark = false})
    : _lockup = true;

  /// Box the mark is drawn into. Both assets are square with even padding, so
  /// this is the rendered size, not a bounding hint.
  final double size;

  /// True when the surface behind the logo is dark, whatever the app theme is.
  final bool onDark;

  final bool _lockup;

  String get _asset {
    if (_lockup) {
      return onDark
          ? 'assets/images/ziren_logo_on_dark.png'
          : 'assets/images/ziren_logo.png';
    }
    return onDark
        ? 'assets/images/ziren_mark_on_dark.png'
        : 'assets/images/ziren_mark.png';
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      width: size,
      height: size,
      // contain, not the default. The mark is wider than it is tall inside its
      // square canvas; letting a non-square box crop it squashes the monogram.
      fit: BoxFit.contain,
    );
  }
}
