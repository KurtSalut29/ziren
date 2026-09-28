import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';

/// Step indicator for the registration flow.
///
/// Registration asks for a lot — identity, address, credentials, and two
/// optional blocks. Presented as one scroll it reads as an undifferentiated
/// wall of fields with no sense of how much is left. Splitting it into named
/// steps gives the form an order and turns "how long is this?" into a visible
/// answer.
class AuthProgress extends StatelessWidget {
  const AuthProgress({super.key, required this.labels, required this.current});

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of ${labels.length}: ${labels[current]}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            i <= current
                                ? ZirenTokens.brandOrange
                                : ZirenTokens.surfaceBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: ZirenTokens.space10),
            Text(
              'Step ${current + 1} of ${labels.length} · ${labels[current]}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ZirenTokens.textMuted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optional-content block used for the ID and accessibility steps.
///
/// Replaces the bordered "boxes" those sections used to sit in. The old
/// treatment was inconsistent — most fields were bare while these two were
/// framed, which made them read as foreign objects dropped into the form
/// rather than parts of it.
class AuthOptionalBlock extends StatelessWidget {
  const AuthOptionalBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.blurb,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // Top-aligned: the icon used to centre itself against a two-line
          // heading, which read as a misalignment.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: ZirenTokens.textSecondary),
            ),
            const SizedBox(width: ZirenTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    blurb,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space20),
        child,
      ],
    );
  }
}

/// "Optional — you can skip this" chip.
class AuthOptionalTag extends StatelessWidget {
  const AuthOptionalTag({super.key, this.text = 'Optional'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: ZirenTokens.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
