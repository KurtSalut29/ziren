import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../domain/responder_trends.dart';
import '../../domain/responder_vocabulary.dart';

// The two charts on the responder's Home.
//
// WHY THEY ARE HAND-DRAWN AND NOT A CHARTING PACKAGE
//
// Two shapes are needed — seven bars and one ring — and both have to obey
// colour rules a general-purpose library knows nothing about: severity keeps
// its exact hue, brand orange never appears on anything that is not an action,
// and every tier is labelled with a word because colour alone is unreadable to
// a red-green deficient responder. Bending a package's theming to those
// constraints is more code than drawing the shapes, and it would add a
// dependency to a build that is already fighting for memory on this hardware.
//
// EVERY BAR IS A REAL CLOSURE
//
// See ResponderTrends — the series is derived from the same history rows the
// Reports tab lists, not from anything generated to make a chart look
// populated. Where the data could be incomplete, the chart says so.

// ── Closed per day ────────────────────────────────────────────

/// Seven days of closed work, as bars.
///
/// GREEN, NOT ORANGE
///
/// Brand orange marks actions and active navigation in this product and
/// nothing else; a bar the responder cannot press must not wear it. Green is
/// already this app's colour for a resolved incident, so the bars and the
/// "Closed today" figure above them agree without a legend.
class ClosedPerDayChart extends StatelessWidget {
  const ClosedPerDayChart({
    super.key,
    required this.days,
    this.truncated = false,
  });

  final List<DayCount> days;

  /// True when the 50-row history cap could be hiding closures inside this
  /// window. Drawn as a footnote rather than hidden.
  final bool truncated;

  static const List<String> _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (a, d) => a + d.count);
    // The tallest bar sets the scale, with a floor of 1 so an all-zero week
    // draws flat instead of dividing by zero.
    final peak = math.max(1, days.fold<int>(0, (a, d) => math.max(a, d.count)));
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final today = DateTime.now();

    return _ChartCard(
      title: 'Closed, last 7 days',
      trailing: '$total total',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 108,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
              duration: Duration(milliseconds: reduceMotion ? 0 : 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i > 0) const SizedBox(width: ZirenTokens.space6),
                      Expanded(
                        child: _Bar(
                          count: days[i].count,
                          fraction: days[i].count / peak,
                          // Staggered left to right, so the week reads as a
                          // sequence rather than everything arriving at once.
                          progress: _stagger(t, i, days.length),
                          label: _initials[days[i].day.weekday - 1],
                          isToday: _sameDay(days[i].day, today),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (truncated) ...[
            const SizedBox(height: ZirenTokens.space10),
            const _Footnote(
              'Your history is capped at 50 incidents, and this week reaches '
              'that cap — the earliest days here may be undercounted.',
            ),
          ],
        ],
      ),
    );
  }

  /// Bar [i] of [n] starts a little after bar i-1 and finishes with the rest.
  static double _stagger(double t, int i, int n) {
    const overlap = 2.0;
    final span = 1.0 / (n + overlap);
    final start = i * span;
    return ((t - start) / (span * (1 + overlap))).clamp(0.0, 1.0);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.fraction,
    required this.progress,
    required this.label,
    required this.isToday,
  });

  final int count;
  final double fraction;
  final double progress;
  final String label;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    // A zero day still draws a stub, so the axis stays legible and the day is
    // visibly present-and-empty rather than missing.
    final tint =
        count == 0 ? ZirenTokens.surfaceBorder : ZirenTokens.statusResolved;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          count == 0 ? '' : '$count',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: ZirenTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final full = box.maxHeight;
              final h = count == 0 ? 4.0 : math.max(4.0, full * fraction);
              return Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: h * progress,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(ZirenTokens.radius4),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: ZirenTokens.space6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
            color: isToday ? ZirenTokens.textPrimary : ZirenTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Severity mix ──────────────────────────────────────────────

/// The mix of severities in a set of incidents, as a ring with a written
/// legend.
///
/// The legend is not optional decoration. Critical is red and low is green in
/// this palette, which is the one pair a red-green deficient reader cannot
/// separate — so the ring carries the proportion and the words carry the
/// meaning.
class SeverityMixRing extends StatelessWidget {
  const SeverityMixRing({
    super.key,
    required this.mix,
    required this.title,
    required this.emptyNote,
    this.centerLabel = 'reports',
    this.trailingFormat,
  });

  /// The word under the total in the ring's centre.
  final String centerLabel;

  /// Formats the header's total ("31 total"); defaults to English.
  final String Function(int total)? trailingFormat;

  /// Tier → count, from [ResponderTrends.severityMix].
  final Map<String, int> mix;
  final String title;

  /// Shown instead of the ring when nothing has been counted.
  final String emptyNote;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final tier in ResponderVocabulary.tiers)
        if ((mix[tier] ?? 0) > 0)
          _Slice(
            label: ResponderVocabulary.label(tier),
            count: mix[tier]!,
            color: ResponderVocabulary.color(tier),
          ),
      if ((mix['unscored'] ?? 0) > 0)
        _Slice(
          label: ResponderVocabulary.label(null),
          count: mix['unscored']!,
          color: ZirenTokens.textMuted,
        ),
    ];
    final total = entries.fold<int>(0, (a, e) => a + e.count);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return _ChartCard(
      title: title,
      trailing:
          total == 0 ? null : (trailingFormat?.call(total) ?? '$total total'),
      child:
          total == 0
              ? _Footnote(emptyNote)
              : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 104,
                    height: 104,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
                      duration: Duration(milliseconds: reduceMotion ? 0 : 750),
                      curve: Curves.easeOutCubic,
                      builder:
                          (context, t, _) => CustomPaint(
                            painter: _RingPainter(
                              slices: entries,
                              total: total,
                              progress: t,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$total',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                      color: ZirenTokens.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    centerLabel,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: ZirenTokens.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in entries) ...[
                          _LegendRow(slice: e, total: total),
                          if (e != entries.last)
                            const SizedBox(height: ZirenTokens.space8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
    );
  }
}

class _Slice {
  const _Slice({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.slices,
    required this.total,
    required this.progress,
  });

  final List<_Slice> slices;
  final int total;
  final double progress;

  static const double _stroke = 15.0;

  /// A hairline of background between slices, so two adjacent tiers do not
  /// read as one arc. Skipped when there is only one slice — a full ring with
  /// a gap in it looks like missing data.
  static const double _gap = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _stroke / 2,
      _stroke / 2,
      size.width - _stroke,
      size.height - _stroke,
    );

    final track =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = ZirenTokens.surfaceRaised;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    // Start at 12 o'clock and run clockwise, worst tier first — the same order
    // the legend lists and the queue is worked in.
    var start = -math.pi / 2;
    final gap = slices.length > 1 ? _gap : 0.0;

    for (final slice in slices) {
      final sweep = (math.pi * 2) * (slice.count / total) * progress;
      if (sweep <= gap) {
        start += sweep;
        continue;
      }
      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke
            ..strokeCap = StrokeCap.butt
            ..color = slice.color;
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.total != total || old.slices != slices;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.total});

  final _Slice slice;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = (slice.count / total * 100).round();
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: slice.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: ZirenTokens.space8),
        Expanded(
          child: Text(
            slice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: ZirenTokens.space6),
        // The count first and the share second. A percentage on its own hides
        // the sample size, and "100%" of one incident is not a trend.
        Text(
          '${slice.count} · $pct%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Shared chrome ─────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.trailing,
    this.trailingWidget,
  });

  final String title;
  final String? trailing;
  final Widget? trailingWidget;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              if (trailingWidget != null) trailingWidget!,
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          child,
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, height: 1.4, color: ZirenTokens.textMuted),
    );
  }
}

// ── Closed over time, with a range switch ─────────────────────

/// Closed calls as bars, over 7 days or 8 weeks.
///
/// Responders close a few calls a week, so the 7-day view is often all empty
/// stubs ("0 total", which read as broken). The 8-week view shows the real
/// pattern, and when a range IS empty the card says so in words, with when
/// the last call was closed, instead of only drawing flat bars.
class ClosedTrendCard extends StatefulWidget {
  const ClosedTrendCard({
    super.key,
    required this.title,
    required this.weekBars,
    required this.dayBars,
    required this.labels,
    required this.emptyNote,
    required this.totalLabel,
    this.truncatedNote,
  });

  final String title;
  final List<DayCount> weekBars;
  final List<DayCount> dayBars;

  /// "7 days", "8 weeks".
  final (String, String) labels;

  /// Shown under the bars when the chosen range has no closures.
  final String emptyNote;
  final String Function(int total) totalLabel;
  final String? truncatedNote;

  @override
  State<ClosedTrendCard> createState() => _ClosedTrendCardState();
}

class _ClosedTrendCardState extends State<ClosedTrendCard> {
  bool _weeks = true;

  static const List<String> _dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final bars = _weeks ? widget.weekBars : widget.dayBars;
    final total = bars.fold<int>(0, (a, d) => a + d.count);
    final peak = math.max(1, bars.fold<int>(0, (a, d) => math.max(a, d.count)));
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final today = DateTime.now();

    String label(int i) =>
        _weeks
            ? '${_months[bars[i].day.month - 1]} ${bars[i].day.day}'
            : _dayInitials[bars[i].day.weekday - 1];
    bool isCurrent(int i) =>
        _weeks
            ? i == bars.length - 1
            : ClosedPerDayChart._sameDay(bars[i].day, today);

    return _ChartCard(
      title: widget.title,
      trailingWidget: _RangeSwitch(
        labels: widget.labels,
        weeks: _weeks,
        onChanged: (w) => setState(() => _weeks = w),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.totalLabel(total),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          SizedBox(
            height: 112,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_weeks),
              tween: Tween(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
              duration: Duration(milliseconds: reduceMotion ? 0 : 600),
              curve: Curves.easeOutCubic,
              builder:
                  (context, t, _) => Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < bars.length; i++) ...[
                        if (i > 0) const SizedBox(width: ZirenTokens.space6),
                        Expanded(
                          child: _Bar(
                            count: bars[i].count,
                            fraction: bars[i].count / peak,
                            progress: ClosedPerDayChart._stagger(
                              t,
                              i,
                              bars.length,
                            ),
                            label: label(i),
                            isToday: isCurrent(i),
                          ),
                        ),
                      ],
                    ],
                  ),
            ),
          ),
          if (total == 0) ...[
            const SizedBox(height: ZirenTokens.space12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.info,
                  size: 15,
                  color: ZirenTokens.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(child: _Footnote(widget.emptyNote)),
              ],
            ),
          ],
          if (widget.truncatedNote != null) ...[
            const SizedBox(height: ZirenTokens.space10),
            _Footnote(widget.truncatedNote!),
          ],
        ],
      ),
    );
  }
}

class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({
    required this.labels,
    required this.weeks,
    required this.onChanged,
  });

  final (String, String) labels;
  final bool weeks;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String text, bool selected, bool value) => GestureDetector(
      onTap: () => onChanged(value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: ZirenTokens.motionBase,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? ZirenTokens.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected ? ZirenTokens.shadowSm : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: selected ? ZirenTokens.textPrimary : ZirenTokens.textMuted,
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(labels.$1, !weeks, false), seg(labels.$2, weeks, true)],
      ),
    );
  }
}

// ── What kinds of call ────────────────────────────────────────

/// Closed calls by type, as labelled horizontal bars with the type's icon.
/// Neutral colour: the type is not a severity, and painting fires in
/// critical red would say they were all critical.
class CategoryMixBars extends StatelessWidget {
  const CategoryMixBars({
    super.key,
    required this.title,
    required this.entries,
    required this.labelOf,
    required this.iconOf,
  });

  final String title;
  final List<MapEntry<String, int>> entries;
  final String Function(String category) labelOf;
  final IconData Function(String category) iconOf;

  @override
  Widget build(BuildContext context) {
    final peak = entries.isEmpty ? 1 : entries.first.value;
    return _ChartCard(
      title: title,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    iconOf(entries[i].key),
                    size: 15,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              labelOf(entries[i].key),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${entries[i].value}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: entries[i].value / peak,
                          minHeight: 6,
                          backgroundColor: ZirenTokens.surfaceRaised,
                          valueColor: AlwaysStoppedAnimation(
                            ZirenTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (i < entries.length - 1)
              const SizedBox(height: ZirenTokens.space12),
          ],
        ],
      ),
    );
  }
}
