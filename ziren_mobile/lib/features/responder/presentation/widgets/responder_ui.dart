import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../domain/responder_incident_model.dart';
import '../../domain/responder_vocabulary.dart';

/// Button text in the app's own typeface. A ButtonStyle's `textStyle`
/// replaces the theme's rather than merging with it, so a bare
/// `TextStyle(fontSize: …)` there silently drops Nunito for the platform
/// default. Start from the theme's label style instead.
TextStyle responderButtonText(
  BuildContext context,
  double size,
  FontWeight weight,
) => (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(
  fontSize: size,
  fontWeight: weight,
);

// The small pieces every responder screen shares: the severity and status
// chips, the category tile, and the assignment's progress track. One copy
// each, so Home, Reports and the detail screen describe an incident with the
// same words, icons and colours - responders said the old screens were hard to
// read partly because the same call looked different on each.

/// Severity as icon + WORD + colour, never colour alone (red-green deficient
/// readers cannot separate critical from low by hue).
class SeverityChip extends StatelessWidget {
  const SeverityChip({super.key, required this.severity, this.muted = false});

  final String? severity;

  /// Greyed for work already done, so a list of closed calls does not read as
  /// a wall of emergencies. The word stays.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color =
        muted ? ZirenTokens.textMuted : ResponderVocabulary.color(severity);
    return _Chip(
      icon: ResponderVocabulary.icon(severity),
      label: ResponderVocabulary.label(severity),
      color: color,
      background:
          muted
              ? ZirenTokens.surfaceRaised
              : ResponderVocabulary.background(severity),
    );
  }
}

/// Where the assignment stands: New, Accepted, En route, On scene, Resolved.
class PhaseChip extends StatelessWidget {
  const PhaseChip({super.key, required this.incident});

  final ResponderIncidentModel incident;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = ResponderVocabulary.phase(incident);
    return _Chip(
      icon: ResponderVocabulary.phaseIcon(p),
      label: ResponderVocabulary.phaseLabel(p, t),
      color: ResponderVocabulary.phaseColor(p),
      background: ResponderVocabulary.phaseBackground(p),
    );
  }
}

/// A plain SOS marker.
class SosChip extends StatelessWidget {
  const SosChip({super.key});

  @override
  Widget build(BuildContext context) => _Chip(
    icon: LucideIcons.megaphone,
    label: 'SOS',
    color: ZirenTokens.severityCritical,
    background: ZirenTokens.severityCriticalBg,
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    // On the dark canvas the saturated tones (indigo especially) sink into
    // their own tinted background; lift the text toward white a little.
    final color = ZirenTokens.isDark
        ? Color.lerp(this.color, Colors.white, 0.3)!
        : this.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The incident's KIND as an icon in a tinted square. Tinted by severity
/// while open, neutral once closed.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    required this.severity,
    this.closed = false,
    this.size = 42,
  });

  final String? category;
  final String? severity;
  final bool closed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint =
        closed ? ZirenTokens.textMuted : ResponderVocabulary.color(severity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            closed
                ? ZirenTokens.surfaceRaised
                : ResponderVocabulary.background(severity),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(
        ResponderVocabulary.categoryIcon(category),
        size: size * 0.46,
        color: tint,
      ),
    );
  }
}

/// The five steps of an assignment with the current one marked:
/// Assigned → Accepted → En route → On scene → Resolved.
///
/// Answers "where am I in this call" at a glance, which the old screen only
/// said in one small coloured word.
class AssignmentProgress extends StatelessWidget {
  const AssignmentProgress({
    super.key,
    required this.incident,
    this.compact = false,
  });

  final ResponderIncidentModel incident;

  /// Dots only, no labels (for cards).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final current = ResponderVocabulary.stepIndex(
      ResponderVocabulary.phase(incident),
    );
    if (current == null) return const SizedBox.shrink();
    final labels = [
      t.respStepAssigned,
      t.respStatusAccepted,
      t.respStatusEnRoute,
      t.respStatusOnScene,
      t.respStatusResolved,
    ];
    final done = ZirenTokens.statusResolved;
    final now = ResponderVocabulary.phaseColor(
      ResponderVocabulary.phase(incident),
    );

    Widget dot(int i) {
      final isDone = i < current || current == 4;
      final isNow = i == current && current != 4;
      final size = compact ? 10.0 : 22.0;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDone ? done : (isNow ? now : ZirenTokens.surfaceCard),
          border: Border.all(
            color: isDone ? done : (isNow ? now : ZirenTokens.surfaceBorder),
            width: compact ? 1.5 : 2,
          ),
          boxShadow:
              isNow && !compact
                  ? [
                    BoxShadow(
                      color: now.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ]
                  : null,
        ),
        alignment: Alignment.center,
        child:
            compact
                ? null
                : isDone
                ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
                : isNow
                ? Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                )
                : null,
      );
    }

    Widget line(int i) => Expanded(
      child: Container(
        height: compact ? 2 : 3,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: i < current || current == 4 ? done : ZirenTokens.surfaceBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    final track = Row(
      children: [
        for (var i = 0; i < 5; i++) ...[dot(i), if (i < 4) line(i)],
      ],
    );
    if (compact) {
      return Semantics(
        label: labels[current],
        excludeSemantics: true,
        child: track,
      );
    }

    return Semantics(
      label: '${t.respStepsTitle}: ${labels[current]}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          track,
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Text(
                    labels[i],
                    textAlign:
                        i == 0
                            ? TextAlign.left
                            : i == 4
                            ? TextAlign.right
                            : TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.2,
                      fontWeight:
                          i == current ? FontWeight.w800 : FontWeight.w600,
                      color:
                          i == current
                              ? ZirenTokens.textPrimary
                              : i < current
                              ? ZirenTokens.textSecondary
                              : ZirenTokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The standard responder card: white, rounded, hairline border, with an
/// optional severity stripe down the left edge for open calls.
class ResponderCard extends StatelessWidget {
  const ResponderCard({
    super.key,
    required this.child,
    this.stripe,
    this.onTap,
    this.padding = const EdgeInsets.all(ZirenTokens.space16),
    this.highlighted = false,
  });

  final Widget child;
  final Color? stripe;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool highlighted;

  static const double radius = 18;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return AnimatedContainer(
      duration: ZirenTokens.motionBase,
      decoration: BoxDecoration(
        color:
            highlighted && stripe != null
                ? Color.alphaBlend(
                  stripe!.withValues(alpha: 0.07),
                  ZirenTokens.surfaceCard,
                )
                : ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              highlighted && stripe != null
                  ? stripe!
                  : ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: ZirenTokens.isDark ? 0 : 0.03,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          child:
              stripe == null
                  ? body
                  : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 5, color: stripe),
                        Expanded(child: body),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }
}

/// A small uppercase label above a group, e.g. "DO THIS FIRST".
class ResponderEyebrow extends StatelessWidget {
  const ResponderEyebrow(this.text, {super.key, this.color, this.trailing});

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: color ?? ZirenTokens.textSecondary,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
