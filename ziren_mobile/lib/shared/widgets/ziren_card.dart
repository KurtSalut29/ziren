import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'ziren_logo.dart';

/// Surface primitives shared by the mobile app, matching the language the web
/// dashboard uses: large corner radii, a single hairline border instead of a
/// drop shadow, and generous internal padding.
///
/// Keeping these in one file is what stops the two products drifting apart —
/// app_tokens.dart already carries a note to keep radius/spacing in sync with
/// the dashboard, and these widgets are where that intent becomes enforceable.

/// A panel. The default surface for grouping related content.
class ZirenCard extends StatelessWidget {
  const ZirenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ZirenTokens.space20),
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Optional left accent bar. Used sparingly — it is how the app marks a
  /// card as belonging to a specific agency or severity, so applying it
  /// decoratively would dilute a signal the dispatcher relies on.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(ZirenTokens.radius20);

    Widget content = Padding(padding: padding, child: child);

    if (accent != null) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(child: content),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Material(
        color: ZirenTokens.surfaceCard,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: ZirenTokens.surfaceBorder),
              borderRadius: radius,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Small uppercase label that introduces a group of content.
///
/// The dashboard uses this to head its sidebar sections; on mobile it heads
/// form sections. Deliberately quiet — it orients without competing with the
/// content beneath it.
class ZirenSectionLabel extends StatelessWidget {
  const ZirenSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: ZirenTokens.space4,
        bottom: ZirenTokens.space8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              // Matches ProfileSection's title exactly (see profile_kit.dart)
              // — Contact and Assignment on the responder profile are the
              // reference for how bold a section header should read here.
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Several rows sharing one bordered container, separated by hairlines rather
/// than gaps — the mobile counterpart of the dashboard's seamless stat band.
///
/// Use when the rows are peers (a settings group, a summary block). Do not use
/// for unrelated items; the shared container implies they belong together.
class ZirenGroupedRows extends StatelessWidget {
  const ZirenGroupedRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            color: ZirenTokens.surfaceBorder,
          ),
        );
      }
      rows.add(children[i]);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(ZirenTokens.radius20),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          border: Border.all(color: ZirenTokens.surfaceBorder),
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// The Ziren logo + wordmark lockup.
///
/// Extracted so the splash, sign-in and register screens cannot drift into
/// three slightly different versions of the same mark.
class ZirenWordmark extends StatelessWidget {
  const ZirenWordmark({
    super.key,
    this.logoSize = 44,
    this.fontSize = 24,
    this.showTagline = false,
  });

  final double logoSize;
  final double fontSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Mark only: the "Ziren" wordmark is set in type right beside it.
            ZirenLogo.mark(size: logoSize),
            SizedBox(width: logoSize * 0.27),
            Text(
              'Ziren',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.brandOrange,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        if (showTagline) ...[
          const SizedBox(height: ZirenTokens.space4),
          Text(
            'Emergency Response, Simplified',
            style: TextStyle(fontSize: 13, color: ZirenTokens.textMuted),
          ),
        ],
      ],
    );
  }
}
