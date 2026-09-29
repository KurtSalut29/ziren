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

/// The duty switch with its state said in words and colour.
///
/// On duty the whole card turns green and says what that means ("receiving
/// dispatches · BFP Naval Station"); off duty it goes quiet and says what the
/// crew is missing. The old version was a solid grey slab with a small switch,
/// and responders could not tell at a glance which state they were in - the
/// most consequential state in the app for them, since an off-duty responder
/// gets no assignments. Who is signed in rides underneath as one quiet line.
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
  final String displayName;
  final String? rank;
  final String? agencyLabel;
  final String? avatarUrl;

  /// Opens the profile (the identity line).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final green = ZirenTokens.systemSuccess;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      child: AnimatedContainer(
        duration: ZirenTokens.motionBase,
        decoration: BoxDecoration(
          color: onDuty ? ZirenTokens.systemSuccessBg : ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(
            color:
                onDuty
                    ? green.withValues(alpha: 0.45)
                    : ZirenTokens.surfaceBorder.withValues(alpha: 0.9),
            width: onDuty ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: ZirenTokens.motionBase,
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: onDuty ? green : ZirenTokens.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      onDuty ? LucideIcons.shield_check : LucideIcons.power_off,
                      size: 22,
                      color: onDuty ? Colors.white : ZirenTokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          busy
                              ? t.respDutyCardBusy
                              : onDuty
                              ? t.respDutyOnTitle
                              : t.respDutyOffTitle,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: onDuty ? green : ZirenTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          onDuty
                              ? (agencyLabel?.isNotEmpty == true
                                  ? t.respDutyOnBody(agencyLabel!)
                                  : t.respDutyOnBodyPlain)
                              : t.respDutyOffBody,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space8),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  else
                    Semantics(
                      toggled: onDuty,
                      label: onDuty ? t.respDutyToggleOff : t.respDutyToggleOn,
                      onTap: () => onChanged(!onDuty),
                      child: ExcludeSemantics(
                        child: Transform.scale(
                          scale: 1.15,
                          child: Switch.adaptive(
                            value: onDuty,
                            onChanged: onChanged,
                            activeTrackColor: green,
                            thumbColor: const WidgetStatePropertyAll(
                              Colors.white,
                            ),
                            trackOutlineColor: WidgetStatePropertyAll(
                              onDuty ? green : ZirenTokens.surfaceBorder,
                            ),
                            inactiveTrackColor: ZirenTokens.surfaceRaised,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color:
                  onDuty
                      ? green.withValues(alpha: 0.2)
                      : ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
            ),
            // ── Who ─────────────────────────────────────────
            InkWell(
              onTap: onTap,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(kCardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
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
                                width: 30,
                                height: 30,
                                // An expired signed URL must fall back to
                                // initials, same as the profile screen.
                                errorBuilder:
                                    (_, _, _) => _DutyAvatarInitial(
                                      displayName: displayName,
                                    ),
                              )
                              : _DutyAvatarInitial(displayName: displayName),
                    ),
                    const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                            if (rank != null)
                              TextSpan(
                                text: '  $rank',
                                style: TextStyle(color: ZirenTokens.textMuted),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Icon(
                      LucideIcons.chevron_right,
                      size: 18,
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

/// Fallback for [DutyStatusCard]'s avatar - no photo, or a network error.
class _DutyAvatarInitial extends StatelessWidget {
  const _DutyAvatarInitial({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Text(
      initialsOf(displayName),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    );
  }
}

// ── Figure band ─────────────────────────────────────────────────

/// One figure in the band.
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

  /// Null renders a plain figure; non-null makes the cell pressable.
  final VoidCallback? onTap;
}

/// The figures as one card split into equal columns, not three separate
/// boxes: they are one reading of one queue, and three bordered boxes with
/// chevron badges looked like three different buttons.
class ResponderStatBand extends StatelessWidget {
  const ResponderStatBand({super.key, required this.cells});

  final List<ResponderStat> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kHomeGutter, 12, kHomeGutter, 0),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(
            color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0)
                  VerticalDivider(
                    width: 1,
                    indent: 14,
                    endIndent: 14,
                    color: ZirenTokens.surfaceBorder,
                  ),
                Expanded(child: ResponderStatCell(stat: cells[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ResponderStatCell extends StatelessWidget {
  const ResponderStatCell({super.key, required this.stat});

  final ResponderStat stat;

  @override
  Widget build(BuildContext context) {
    // A zero recedes: on a quiet shift, a red "0" would be the loudest mark
    // on the screen while saying the least.
    final quiet = stat.value == '0' || stat.value == '—';
    final tone = quiet ? ZirenTokens.textMuted : stat.color;

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(stat.icon, size: 15, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    stat.value,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color:
                          quiet
                              ? ZirenTokens.textMuted
                              : ZirenTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ),
    );

    if (stat.onTap == null) return body;
    return Semantics(
      button: true,
      label: '${stat.label}: ${stat.value}',
      excludeSemantics: true,
      child: InkWell(onTap: stat.onTap, child: body),
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
