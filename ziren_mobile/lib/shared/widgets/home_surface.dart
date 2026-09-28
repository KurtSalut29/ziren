import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'home_kit.dart' show kHomeGutter;
import 'ziren_logo.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// ════════════════════════════════════════════════════════════════
// Single-surface home
//
// Resident Home used to be four stacked rounded rectangles — a tinted
// hero box, two paired list cards, and a wide activity card — drawn at
// seven different corner radii, two of which both claimed to be "the
// card radius" (kCardRadius = 18 in home_kit, radius20 = 20 labelled
// "card default" in app_tokens). Nothing in that stack said what
// mattered most, because every container carried the same weight.
//
// These widgets replace it with one continuous ground. Regions are
// separated by a hairline and by space, never by a box. Hierarchy comes
// from type role and spacing, so nothing here hand-picks a font size —
// app_theme already defines a Material 3 text theme and the old home
// widgets were reaching past it to fontSize: 12.5.
//
// The radial dial stays. It was never the problem; the tinted box
// around it was.
// ════════════════════════════════════════════════════════════════

/// Top-of-screen identity banner: wordmark, notification bell, location and
/// connectivity pills.
///
/// The backdrop is the resident-facing community illustration
/// (`assets/images/resident_hero.jpg`) under a dark scrim — the scrim is
/// what keeps the white wordmark/bell/pills readable regardless of which
/// part of the image lands under them, since `BoxFit.cover` can crop to a
/// lighter or darker region depending on screen width.
class HomeHeroBanner extends StatelessWidget {
  const HomeHeroBanner({
    super.key,
    required this.hasUnread,
    required this.onBellTap,
    required this.bellLabel,
    required this.bellLabelUnread,
    required this.locationLabel,
    required this.connectivityLabel,
    required this.connectivityIcon,
    required this.connectivityColor,
  });

  final bool hasUnread;
  final VoidCallback onBellTap;
  final String bellLabel;
  final String bellLabelUnread;
  final String locationLabel;

  /// Short connectivity status shown beside the location pill — "Connected",
  /// "Offline", "Checking…". The full explanation sentence that used to sit
  /// in its own band lives in the Home screen's tooltip/semantics only; a
  /// hero pill has room for a word, not a sentence.
  final String connectivityLabel;
  final IconData connectivityIcon;
  final Color connectivityColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(ZirenTokens.radius24),
        bottomRight: Radius.circular(ZirenTokens.radius24),
      ),
      child: SizedBox(
        // Previously unset, so the banner was only ever as tall as its
        // content (logo row + pills row) needed — the photo behind it was
        // mostly cropped away. A fixed height gives the image real room to
        // read as a photo rather than a sliver behind the UI.
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
          // Image and scrim are both full-bleed layers of the same Stack —
          // deliberately NOT nested inside the padded content below. An
          // earlier version put the scrim inside the Container's own
          // padding, which only darkened the inset content area and left a
          // visible undarkened border of raw image around it.
          Positioned.fill(
            child: Image.asset(
              'assets/images/resident_hero.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Flat, not a top/bottom gradient: the source photo's own
          // brightness already varies a lot left-to-right (a dusk scene
          // panel next to a bright daylight one), so a gradient that only
          // varies vertically left that variance untouched and read as a
          // patchy shadow. One uniform alpha evens it out everywhere.
          const Positioned.fill(
            child: ColoredBox(color: Color(0x8A000000)), // 0.54 black
          ),
          // Full-bleed like the two layers above it, not just Padding —
          // that's what lets the Column inside stretch to the banner's
          // full fixed height and push the location/connectivity pills
          // down to the bottom edge instead of both rows huddling at the
          // top with empty photo below them.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                kHomeGutter,
                ZirenTokens.space16,
                kHomeGutter,
                ZirenTokens.space16,
              ),
              child: _HomeHeroBannerContent(
                hasUnread: hasUnread,
                onBellTap: onBellTap,
                bellLabel: bellLabel,
                bellLabelUnread: bellLabelUnread,
                locationLabel: locationLabel,
                connectivityLabel: connectivityLabel,
                connectivityIcon: connectivityIcon,
                connectivityColor: connectivityColor,
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroBannerContent extends StatelessWidget {
  const _HomeHeroBannerContent({
    required this.hasUnread,
    required this.onBellTap,
    required this.bellLabel,
    required this.bellLabelUnread,
    required this.locationLabel,
    required this.connectivityLabel,
    required this.connectivityIcon,
    required this.connectivityColor,
  });

  final bool hasUnread;
  final VoidCallback onBellTap;
  final String bellLabel;
  final String bellLabelUnread;
  final String locationLabel;
  final String connectivityLabel;
  final IconData connectivityIcon;
  final Color connectivityColor;

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const ZirenLogo.mark(size: 24, onDark: true),
              const SizedBox(width: ZirenTokens.space8),
              const Text(
                'Ziren',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: hasUnread ? bellLabelUnread : bellLabel,
                child: Material(
                  // A plain icon on a busy photo doesn't read as a button —
                  // the same translucent-white circle the location/
                  // connectivity pills already use below marks it as
                  // tappable regardless of what part of the image lands
                  // underneath.
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onBellTap,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(ZirenTokens.space8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            LucideIcons.bell,
                            color: Colors.white,
                            size: 22,
                          ),
                          if (hasUnread)
                            Positioned(
                              top: -1,
                              right: -1,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: ZirenTokens.severityCritical,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF7A3B2E),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: ZirenTokens.space8,
            runSpacing: ZirenTokens.space8,
            children: [
              _HeroPill(
                icon: LucideIcons.map_pin,
                iconColor: Colors.white,
                label: locationLabel,
              ),
              _HeroPill(
                icon: connectivityIcon,
                iconColor: connectivityColor,
                label: connectivityLabel,
              ),
            ],
          ),
        ],
      );
  }
}

/// A small translucent chip on the hero banner — location, connectivity.
/// Shares one look so the two read as a pair rather than two different
/// affordances.
class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 14),
          const SizedBox(width: ZirenTokens.space4),
          // The connectivity pill's label is always one short word, but the
          // location pill's is now a live reverse-geocoded address (see
          // ResidentHomeScreen) — much longer and unbounded, unlike the
          // static barangay name this replaced. Capped so it can never push
          // the pill wider than the banner or crowd the pill beside it.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one dominant, uncategorised emergency action on Home — the
/// restyled successor to the old radial SOS dial's centre button. Still
/// goes straight to the SOS confirm screen: this card exists for the
/// resident who cannot classify what is happening, same as before, only
/// no longer shaped like a pulsing dial. The category grid beneath it is
/// for the resident who already knows.
///
/// Uses `ZirenTokens.brandGradient` deliberately — the token's own comment
/// reserves it for "the single most-important hero card per screen", and
/// this is that card.
class EmergencyCtaCard extends StatelessWidget {
  const EmergencyCtaCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Short uppercase word ("FASTEST") shown beside the title. Optional and
  /// off by default — only the resident-flow SOS card asserts a speed claim
  /// against a specific alternative (the category-tile flow's extra review
  /// step); a generic reuse of this card elsewhere has no such comparison to
  /// make.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
          child: Ink(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            decoration: BoxDecoration(
              gradient: ZirenTokens.brandGradient,
              borderRadius: BorderRadius.circular(ZirenTokens.radius20),
              boxShadow: ZirenTokens.shadowMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  // Lightning, not the alert triangle this used to carry —
                  // "emergency" is already said by the title and the card's
                  // own colour; the one thing the icon can add on top of that
                  // is the claim this card actually makes, which is speed.
                  child: const Icon(
                    LucideIcons.zap,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: ZirenTokens.space8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.chevron_right,
                  color: Colors.white,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline between regions of the single surface.
///
/// Full-bleed on purpose. An inset rule reads as the edge of a card that
/// is not there, which is the habit this file exists to break.
class HomeRule extends StatelessWidget {
  const HomeRule({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: ZirenTokens.surfaceBorder);
}

/// How the next report will leave the phone, stated before it is sent.
///
/// This sits at the top of the screen rather than as an 8dp dot beside
/// the resident's name because "it still works when the network does
/// not" is the claim this product actually has to land, and someone
/// deciding whether to trust the app in a storm is asking exactly this.
///
/// Takes its colour from the connectivity tokens rather than severity red,
/// even when reporting that the phone is offline — this is a plain status,
/// not an incident, and severity red would say otherwise.
class DeliveryBand extends StatelessWidget {
  const DeliveryBand({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: tone.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(
        horizontal: kHomeGutter,
        vertical: ZirenTokens.space10,
      ),
      child: Row(
        children: [
          // A 3dp bar, not a coloured left border on a card: it marks the
          // band as a band rather than as one more container.
          Container(width: 3, height: 34, color: tone),
          const SizedBox(width: ZirenTokens.space12),
          Icon(icon, size: 20, color: tone),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(
                    color: ZirenTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled region of the single surface. No box, no border, no radius.
///
/// [emptyText] is required rather than optional: these regions are driven
/// by live data that is often genuinely empty, and a silent gap reads as
/// a failed load.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.title,
    required this.children,
    required this.emptyText,
    this.action,
    this.onAction,
    this.trailingCount,
  });

  final String title;
  final List<Widget> children;
  final String emptyText;
  final String? action;
  final VoidCallback? onAction;
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // More space above the heading than below it — the heading
          // belongs to what follows, not to what it was separated from.
          padding: const EdgeInsets.fromLTRB(
            kHomeGutter,
            ZirenTokens.space20,
            ZirenTokens.space8,
            ZirenTokens.space4,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: text.labelMedium?.copyWith(
                  color: ZirenTokens.textSecondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              if (trailingCount != null && trailingCount! > 0) ...[
                const SizedBox(width: ZirenTokens.space6),
                Text(
                  '$trailingCount',
                  style: text.labelMedium?.copyWith(
                    color: ZirenTokens.brandOrange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const Spacer(),
              if (action != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, ZirenTokens.minTouchTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZirenTokens.space8,
                    ),
                    foregroundColor: ZirenTokens.brandOrange,
                  ),
                  child: Text(action!),
                ),
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kHomeGutter,
              0,
              kHomeGutter,
              ZirenTokens.space16,
            ),
            child: Text(
              emptyText,
              style: text.bodyMedium?.copyWith(color: ZirenTokens.textMuted),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// One row on the single surface.
///
/// A full-bleed tap target with the icon carrying the colour, so the row
/// is scannable without a container of its own. [trailingNote] keeps its
/// colour because workflow status is meaning, not decoration.
class HomeRow extends StatelessWidget {
  const HomeRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailingNote,
    this.trailingColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? trailingNote;
  final Color? trailingColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kHomeGutter,
          vertical: ZirenTokens.space10,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: ZirenTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingNote != null) ...[
              const SizedBox(width: ZirenTokens.space8),
              Text(
                trailingNote!,
                style: text.labelSmall?.copyWith(
                  color: trailingColor ?? ZirenTokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
