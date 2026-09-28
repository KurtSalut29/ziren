import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';

/// One action under a [ReviewNotice].
class ReviewAction {
  const ReviewAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The one action worth doing first. Only one per notice should be filled.
  final bool filled;
}

/// A decision from the agency, said plainly on the resident's own report.
///
/// Used for both things an agency can tell a resident about a report that is
/// not a status change: that it was REJECTED (with the reason), and that it
/// needs more information (with the question). Neither had a place in the app
/// before - a rejection surfaced as a bare "Cancelled" in Trash, and a
/// question never surfaced at all - so this is deliberately loud without being
/// alarming: amber, an icon and a title, never red. Red means critical
/// severity here and nothing else.
///
/// Built from theme tokens only (no hard-coded white or black), so it reads in
/// dark mode as well as light.
class ReviewNotice extends StatelessWidget {
  const ReviewNotice({
    super.key,
    required this.icon,
    required this.title,
    this.label,
    this.body,
    this.footnote,
    this.cue,
    this.actions = const [],
  });

  final IconData icon;
  final String title;

  /// A small lead-in above [body], e.g. "They asked:".
  final String? label;
  final String? body;

  /// A plainer line under the body: what to do next.
  final String? footnote;

  /// A short verb shown at the trailing edge of a compact notice on a list
  /// card, where the whole card is the tap target and there is no room for
  /// buttons.
  final String? cue;

  final List<ReviewAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: ZirenTokens.systemWarning),
              const SizedBox(width: ZirenTokens.space8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              if (cue != null) ...[
                const SizedBox(width: ZirenTokens.space8),
                Text(
                  cue!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.brandOrange,
                  ),
                ),
              ],
            ],
          ),
          if ((body ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: ZirenTokens.space6),
            if (label != null)
              Text(
                label!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textMuted,
                ),
              ),
            Text(
              body!.trim(),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: ZirenTokens.space8),
            Text(
              footnote!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: ZirenTokens.space12),
            Wrap(
              spacing: ZirenTokens.space8,
              runSpacing: ZirenTokens.space8,
              children: [for (final a in actions) _ActionButton(action: a)],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});
  final ReviewAction action;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(action.icon, size: 16);
    final label = Text(action.label);
    return action.filled
        ? FilledButton.icon(
          onPressed: action.onTap,
          icon: icon,
          label: label,
          style: FilledButton.styleFrom(
            backgroundColor: ZirenTokens.brandOrange,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, ZirenTokens.minTouchTarget),
          ),
        )
        : OutlinedButton.icon(
          onPressed: action.onTap,
          icon: icon,
          label: label,
          style: OutlinedButton.styleFrom(
            foregroundColor: ZirenTokens.textPrimary,
            side: BorderSide(color: ZirenTokens.surfaceBorder),
            minimumSize: const Size(0, ZirenTokens.minTouchTarget),
          ),
        );
  }
}
