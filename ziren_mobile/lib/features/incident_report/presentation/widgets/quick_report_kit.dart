import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';

/// Shared building blocks for the quick-report confirm and review screens.

/// A bold section caption above a field or block.
class QuickReportSectionLabel extends StatelessWidget {
  const QuickReportSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: ZirenTokens.textPrimary,
      ),
    );
  }
}

/// A bordered, rounded surface used for the read-only info rows on these
/// two screens (location, receiving station).
class QuickReportCard extends StatelessWidget {
  const QuickReportCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: child,
    );
  }
}

/// Four dots marking where this screen sits in the report → review flow.
/// Purely decorative orientation, not a literal step count of the whole app.
class QuickReportStepDots extends StatelessWidget {
  const QuickReportStepDots({super.key, required this.step, this.total = 4});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  i < step
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.surfaceBorder,
            ),
          ),
      ],
    );
  }
}
