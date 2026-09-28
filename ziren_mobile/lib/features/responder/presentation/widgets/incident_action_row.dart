import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/home_kit.dart' show kCardRadius;
import 'package:flutter_lucide/flutter_lucide.dart';

/// One tappable action on the incident detail screen — request backup,
/// escalate, take a scene photo.
///
/// WHY THIS REPLACED THREE STACKED OUTLINE BUTTONS
///
/// Each of those was a full-width `OutlinedButton` in its own semantic
/// colour (info blue, high-severity amber, brand orange), which is the
/// right colour for each action individually but reads as a loose stack of
/// unrelated widgets when three sit on top of each other — nothing this app
/// does elsewhere. Every other place a responder or resident sees several
/// actions together (Settings, a profile section) groups them as rows in
/// one card: icon in a tinted circle, label, a clear affordance on the
/// right. This is that pattern, not a new one.
///
/// The colour still carries the meaning — the icon and its circle keep the
/// action's semantic tone — it is just no longer also the shape of a
/// separate button floating on the page.
class IncidentActionRow extends StatelessWidget {
  const IncidentActionRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onTap,
    this.busy = false,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  /// Shows a small spinner in the icon circle instead of the icon.
  final bool busy;

  /// Overrides the trailing chevron — used for a short note ("N added")
  /// instead of "go here" when the row does not navigate anywhere.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final tone = disabled ? ZirenTokens.textMuted : iconColor;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space16,
          vertical: ZirenTokens.space12,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child:
                  busy
                      ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(tone),
                        ),
                      )
                      : Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: ZirenTokens.space12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color:
                      disabled
                          ? ZirenTokens.textMuted
                          : ZirenTokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: ZirenTokens.space8),
            trailing ??
                Icon(
                  LucideIcons.chevron_right,
                  color: ZirenTokens.textMuted,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }
}

/// The card these rows live inside — one border, one radius, a hairline
/// between each row instead of a gap between separate buttons.
class IncidentActionCard extends StatelessWidget {
  const IncidentActionCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: ZirenTokens.space16,
                endIndent: ZirenTokens.space16,
                color: ZirenTokens.surfaceBorder,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
