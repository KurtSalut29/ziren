import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/home_kit.dart' show kCardRadius, kHomeGutter;
import '../../../../shared/widgets/profile_kit.dart' show initialsOf;
import 'package:flutter_lucide/flutter_lucide.dart';

/// Shared building blocks for the Responder Home screen — the duty card,
/// figure cells, the quick-action tile, and a section heading matching the
/// resident side's `HomeSectionHeading`. Extracted out of
/// responder_home_screen.dart so they're no longer private to that one
/// screen.
///
/// This is a first step toward the fix for "the pages are not consistent
/// because we have other design in each page" — see
/// docs/specs/2026-09-11-responder-redesign-design.md §2 and §8. Reports and
/// Profile do not yet draw from this file; adopting these widgets there is
/// tracked as follow-up work, not done by this extraction. Nothing here is
/// new design work: every widget was lifted, unchanged in behavior, from
/// responder_home_screen.dart.

// ── Section heading ─────────────────────────────────────────────

/// A titled section with an optional trailing action — matches
/// HomeSectionHeading's look exactly, so the resident and responder sides
/// read as the same product even though the pages around this heading
/// differ. Kept as a separate widget rather than importing
/// HomeSectionHeading directly so the responder side does not depend on a
/// resident-named type; the two are visually identical on purpose.
class ResponderSectionHeading extends StatelessWidget {
  const ResponderSectionHeading(
    this.title, {
    super.key,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space24,
        kHomeGutter,
        ZirenTokens.space12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.brandOrange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Duty status ─────────────────────────────────────────────────

/// The duty switch, as a row rather than a dial.
///
/// From the prototype. It states the state in words — "Aktibo — handa
/// tumugon" — beside the switch, because a switch alone is a shape a tired
/// person reads wrong: on and off look alike at a glance, and the cost of
/// misreading it is an assignment that never arrives.
class DutyStatusCard extends StatelessWidget {
  const DutyStatusCard({
    super.key,
    required this.onDuty,
    required this.busy,
    required this.onChanged,
    required this.displayName,
    required this.onTap,
    this.rank,
    this.agencyLabel,
    this.avatarUrl,
  });

  final bool onDuty;
  final bool busy;
  final ValueChanged<bool> onChanged;

  /// The responder's own name, shown under the duty banner — the reference
  /// design puts "who" directly beneath "what state", since both answer the
  /// same question a dispatcher radioing this phone would ask first.
  final String displayName;
  final String? rank;
  final String? agencyLabel;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final tone = onDuty ? ZirenTokens.systemSuccess : ZirenTokens.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(
            color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          children: [
            // ── The state, stated plainly ──────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ZirenTokens.space16),
              decoration: BoxDecoration(
                color: tone,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(kCardRadius),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          busy
                              ? t.respDutyCardBusy
                              : onDuty
                              ? t.respDutyCardOn
                              : t.respDutyCardOff,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (agencyLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            t.respDutyCardStation(agencyLabel!),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  else
                    Semantics(
                      toggled: onDuty,
                      label: onDuty ? t.respDutyToggleOff : t.respDutyToggleOn,
                      onTap: () => onChanged(!onDuty),
                      child: ExcludeSemantics(
                        child: Switch.adaptive(
                          value: onDuty,
                          onChanged: onChanged,
                          activeTrackColor: Colors.white.withValues(
                            alpha: 0.35,
                          ),
                          activeColor: Colors.white,
                          thumbColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Who ─────────────────────────────────────────
            InkWell(
              onTap: onTap,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(kCardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(
                        color: ZirenTokens.brandOrange,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child:
                          avatarUrl != null
                              ? Image.network(
                                avatarUrl!,
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40,
                                // An expired signed URL or a network hiccup
                                // must fall back to initials, same as the
                                // profile screen's avatar — see EditableAvatar.
                                errorBuilder:
                                    (_, __, ___) => _DutyAvatarInitial(
                                      displayName: displayName,
                                    ),
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return _DutyAvatarInitial(
                                    displayName: displayName,
                                  );
                                },
                              )
                              : _DutyAvatarInitial(displayName: displayName),
                    ),
                    const SizedBox(width: ZirenTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                          if (rank != null)
                            Text(
                              rank!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }
}

/// Fallback for [DutyStatusCard]'s avatar slot — no photo, a network error,
/// or still loading. Kept private since only the duty card needs this exact
/// 40px/orange-background variant.
class _DutyAvatarInitial extends StatelessWidget {
  const _DutyAvatarInitial({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Text(
      initialsOf(displayName),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }
}

// ── Figure band ─────────────────────────────────────────────────

/// One figure in the band. Public so the design-preview test can render the
/// band without a Supabase session — see test/home_design_preview_test.dart.
class ResponderStat {
  const ResponderStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  /// Null renders the cell as a plain, unpressable figure — the caller's
  /// call, e.g. when the count behind it is zero and there is nothing to
  /// reveal. Non-null gets a ripple, a tap target, and a small affordance
  /// glyph so the cell reads as a control rather than a decoration.
  final VoidCallback? onTap;
}

/// Figures in a row, equal-width.
///
/// Equal-width cells rather than a scrolling strip: three or four is few
/// enough to fit any phone this app targets, and a figure that has to be
/// scrolled to is a figure nobody reads.
class ResponderStatBand extends StatelessWidget {
  const ResponderStatBand({super.key, required this.cells});

  final List<ResponderStat> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space10,
        kHomeGutter,
        0,
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: ZirenTokens.space8),
            Expanded(child: ResponderStatCell(stat: cells[i])),
          ],
        ],
      ),
    );
  }
}

class ResponderStatCell extends StatelessWidget {
  const ResponderStatCell({super.key, required this.stat});

  final ResponderStat stat;

  @override
  Widget build(BuildContext context) {
    // A zero recedes. On a quiet shift most cells read "0", and rendered in
    // severity red at figure size those zeros become the loudest marks on the
    // screen while carrying the least information - the eye pulled to the
    // absence of an emergency. Same rule the dispatcher console's tiles use.
    final quiet = stat.value == '0' || stat.value == '—';
    final tone = quiet ? ZirenTokens.textMuted : stat.color;
    final interactive = stat.onTap != null;

    // Ink, not Container, for the decorated box: an InkWell's splash paints
    // into the nearest Material ancestor, and a plain Container's own
    // BoxDecoration would sit on top of that ripple instead of showing it.
    // Faint colour wash and border only when live and interactive — a quiet
    // zero cell stays visually inert, matching its own "nothing to act on"
    // meaning instead of inviting a tap that does nothing.
    final card = Ink(
      padding: const EdgeInsets.symmetric(
        vertical: ZirenTokens.space12,
        horizontal: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color:
            interactive
                ? Color.alphaBlend(
                  stat.color.withValues(alpha: 0.06),
                  ZirenTokens.surfaceCard,
                )
                : ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(
          color:
              interactive
                  ? stat.color.withValues(alpha: 0.28)
                  : ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        children: [
          // Icon-in-a-tinted-circle, the same treatment HomeRow and the
          // queue card's type tile use elsewhere in this app — a bare glyph
          // read as a smaller, plainer version of everything around it. A
          // small chevron badge is the only extra mark for "this taps to
          // something" — no separate label, so the card stays as compact
          // as its non-interactive sibling.
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color:
                      quiet
                          ? ZirenTokens.surfaceRaised
                          : tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(stat.icon, size: 16, color: tone),
              ),
              if (interactive)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: ZirenTokens.surfaceCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: tone.withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.chevron_right,
                      size: 10,
                      color: tone,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          FittedBox(
            child: Text(
              stat.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1,
                color: tone,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: ZirenTokens.textMuted,
            ),
          ),
        ],
      ),
    );

    final content = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child:
          interactive
              ? InkWell(
                onTap: stat.onTap,
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                splashColor: stat.color.withValues(alpha: 0.16),
                highlightColor: stat.color.withValues(alpha: 0.08),
                child: card,
              )
              : card,
    );

    if (!interactive) return content;

    return Semantics(
      button: true,
      label: '${stat.label}: ${stat.value}',
      child: content,
    );
  }
}

// ── Quick action tile ───────────────────────────────────────────
//
// One shortcut into the app's real "what's most urgent" feature — see
// responder_home_screen.dart's call site for why the reference design's
// other two tiles were dropped. Public (renamed from the former private
// `_QuickActionTile`) so Reports/Profile can reuse the same shape for any
// future single-shortcut affordance without re-implementing it.
class ResponderQuickActionTile extends StatelessWidget {
  const ResponderQuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Material(
      color: disabled ? color.withValues(alpha: 0.4) : color,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space12,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  if (badgeCount != null && badgeCount! > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(
                LucideIcons.chevron_right,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
