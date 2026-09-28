import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';

/// The status band — three live readings in one seamless container.
///
/// This replaces the row of three icon tiles that used to sit here. Those
/// tiles were decoration: an icon, a two-word label, and no information. A
/// resident looking at them learned nothing they did not already know, so the
/// only thing distinguishing the three was their colour — which is why
/// removing the colour left nothing behind.
///
/// The band inverts the hierarchy. The live value is the largest thing in
/// each cell and the destination name is the caption under it, so the block
/// answers "is anything waiting for me?" at a glance instead of asking the
/// resident to go and find out. It is the same seamless-band structure the
/// web dashboard uses for its stats — one bordered container divided by
/// hairlines rather than three floating cards — which is what makes the two
/// products read as one system.
///
/// Colour returns here, but earned: a cell tints only when its value is
/// non-zero and therefore worth looking at.
class StatusBand extends StatelessWidget {
  const StatusBand({super.key, required this.cells});

  final List<StatusCell> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: ZirenTokens.surfaceBorder,
                ),
              Expanded(child: _Cell(cell: cells[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class StatusCell {
  const StatusCell({
    required this.value,
    required this.label,
    required this.caption,
    required this.onTap,
    this.icon,
    this.highlight = false,
  });

  /// The reading. Kept short — a number, or a word like "Bukas".
  final String value;

  /// What the reading is about, in caption case beneath the value.
  final String label;

  /// Secondary line, e.g. the unit or the nearest distance.
  final String caption;

  final VoidCallback onTap;
  final IconData? icon;

  /// True when the value is worth attention. Drives the tint.
  final bool highlight;
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell});
  final StatusCell cell;

  @override
  Widget build(BuildContext context) {
    final accent =
        cell.highlight ? ZirenTokens.brandOrange : ZirenTokens.textPrimary;

    return Semantics(
      button: true,
      label: '${cell.label}. ${cell.value} ${cell.caption}',
      child: ExcludeSemantics(
        child: Material(
          color:
              cell.highlight
                  ? ZirenTokens.brandSubtle
                  : ZirenTokens.surfaceCard,
          child: InkWell(
            onTap: cell.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZirenTokens.space12,
                vertical: ZirenTokens.space16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(child: Text(
                        cell.value,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -0.8,
                          color: accent,
                        ),
                      )),
                      if (cell.icon != null) ...[
                        const SizedBox(width: 5),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            cell.icon,
                            size: 15,
                            color:
                                cell.highlight
                                    ? ZirenTokens.brandOrange
                                    : ZirenTokens.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  Text(
                    cell.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cell.caption,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
