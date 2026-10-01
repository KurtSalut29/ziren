import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_tokens.dart';
import '../domain/demo_models.dart';
import 'demo_anchor.dart';

/// Runs [script] over whatever screen is showing: the screen dims, the part
/// being explained is lit, and the mascot, from a speech bubble above or below
/// it, points at it and says what it is for.
///
/// A see-through route on the root navigator, so the screen underneath cannot
/// be tapped while the mascot is talking (nothing is ever sent by a demo), and
/// the phone's back button ends it like any other screen.
Future<void> showDemoTour(BuildContext context, DemoScript script) async {
  final lang = Localizations.localeOf(context).languageCode;
  final navigator = Navigator.of(context, rootNavigator: true);
  await navigator.push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => DemoTourView(script: script, lang: lang),
      transitionsBuilder:
          (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
    ),
  );
  // Only once the tour's own route is gone: run earlier (while it was still
  // popping), "leave the form" popped the tour a second time instead of the
  // form, and the resident was left on a half-filled report.
  if (!navigator.mounted) return;
  final ctx = navigator.context;
  if (!ctx.mounted) return;
  script.close?.call(ctx);
  // Done, Skip or the back button: back to the Home the demo was started
  // from, with whatever it opened closed - a report it showed was pushed as
  // a plain page, which go() alone would leave on top.
  navigator.popUntil((route) => route.isFirst);
  GoRouter.maybeOf(ctx)?.go(script.homeRoute);
}

/// The words around the steps, which are not part of any one script.
abstract final class DemoChrome {
  static String skip(String l) => l == 'en' ? 'Skip' : 'Laktawan';
  static String back(String l) => l == 'en' ? 'Back' : 'Bumalik';
  static String next(String l) => l == 'en' ? 'Next' : 'Susunod';
  static String done(String l) => l == 'en' ? 'Done' : 'Tapos na';
  static String badge(String l) => 'DEMO';
  static String counter(int i, int n) => '$i / $n';
}

class DemoTourView extends StatefulWidget {
  const DemoTourView({super.key, required this.script, required this.lang});

  final DemoScript script;
  final String lang;

  @override
  State<DemoTourView> createState() => _DemoTourViewState();
}

class _DemoTourViewState extends State<DemoTourView>
    with TickerProviderStateMixin {
  int _index = 0;

  /// The lit part of the screen, in global coordinates; null when the step has
  /// no anchor on screen (the mascot then talks from the middle).
  Rect? _target;

  /// Where the light last was, so it slides from there to the next part (a
  /// tween needs an end even while there is nothing to light).
  Rect _lastLit = Rect.zero;

  /// True while scrolling to the next step's anchor.
  bool _moving = true;

  /// Bumped on every step change, so a slow reveal for a step the user has
  /// already left is dropped.
  int _generation = 0;

  Timer? _remeasure;

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  List<DemoStep> get _steps => widget.script.steps;
  DemoStep get _step => _steps[_index];
  bool get _last => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(0));
    // Content under the tour can still be arriving (a list loading, a map
    // tile): keep the light on the anchor where it is now.
    _remeasure = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_moving || !mounted) return;
      final id = _step.anchor;
      if (id == null) return;
      final rect = _measure(id);
      if (rect != _target) setState(() => _target = rect);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bob
        ..stop()
        ..value = 0;
      _pulse
        ..stop()
        ..value = 0;
    } else {
      if (!_bob.isAnimating) _bob.repeat();
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _remeasure?.cancel();
    _bob.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _show(int index) async {
    final generation = ++_generation;
    setState(() {
      _index = index;
      _moving = true;
    });
    final id = _steps[index].anchor;
    Rect? rect;
    if (id != null) {
      await _reveal(id);
      // One frame for the scroll to land before measuring.
      await WidgetsBinding.instance.endOfFrame;
      rect = _measure(id);
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _target = rect;
      _moving = false;
    });
  }

  /// Scrolls [id] into view. When it is not built yet (a long list only builds
  /// what is near the screen), scrolls the screen down until it is.
  Future<void> _reveal(String id) async {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 320);
    for (var attempt = 0; attempt < 8; attempt++) {
      final ctx = DemoAnchors.contextOf(id);
      if (ctx != null) {
        if (!ctx.mounted) return;
        if (Scrollable.maybeOf(ctx) != null) {
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.3,
            duration: duration,
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      final position = _anyScrollPosition();
      if (position == null || position.extentAfter <= 0) return;
      final to = math.min(
        position.pixels + position.viewportDimension * 0.7,
        position.maxScrollExtent,
      );
      if (reduce) {
        position.jumpTo(to);
      } else {
        await position.animateTo(
          to,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// The scroll view that holds this script's other anchors.
  ScrollPosition? _anyScrollPosition() {
    for (final step in _steps) {
      final id = step.anchor;
      if (id == null) continue;
      final ctx = DemoAnchors.contextOf(id);
      if (ctx == null) continue;
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable != null) return scrollable.position;
    }
    return null;
  }

  Rect? _measure(String id) {
    final ctx = DemoAnchors.contextOf(id);
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    // A part that draws nothing today (no alert to show) is not there.
    if (box.size.width < 8 || box.size.height < 8) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    if (!rect.overlaps(screen)) return null;
    return rect.intersect(screen);
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop();
    } else {
      _show(_index + 1);
    }
  }

  void _back() {
    if (_index > 0) _show(_index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final target = _moving ? null : _target;
    if (target != null) _lastLit = target;

    // The bubble goes where there is more room: below a target in the top half
    // of the screen, above one in the bottom half, and in the middle when the
    // mascot has nothing to point at.
    final placement =
        target == null
            ? _Placement.middle
            : (target.center.dy < size.height * 0.5
                ? _Placement.below
                : _Placement.above);

    final pose =
        _step.pose ??
        switch (placement) {
          _Placement.below => DemoPose.pointUp,
          _Placement.above => DemoPose.pointDown,
          _Placement.middle => DemoPose.pointYou,
        };

    final card = _TourCard(
      key: ValueKey(_index),
      title: widget.script.title(widget.lang),
      text: _step.text(widget.lang),
      pose: pose,
      lang: widget.lang,
      index: _index,
      count: _steps.length,
      last: _last,
      bob: _bob,
      onSkip: () => Navigator.of(context).pop(),
      onBack: _index > 0 ? _back : null,
      onNext: _next,
    );

    const gap = 14.0;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Taps on the dimmed screen go nowhere: a demo never presses
          // anything for real.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: AnimatedBuilder(
                animation: _pulse,
                builder:
                    (_, __) => TweenAnimationBuilder<Rect?>(
                      tween: RectTween(end: target ?? _lastLit),
                      duration:
                          MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      builder:
                          (_, rect, __) => CustomPaint(
                            painter: _ScrimPainter(
                              hole: target == null ? null : rect,
                              pulse: _pulse.value,
                            ),
                          ),
                    ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: ZirenTokens.space12,
            right: ZirenTokens.space12,
            top: switch (placement) {
              _Placement.below => math.min(
                target!.bottom + gap,
                size.height - padding.bottom - _TourCard.minHeight,
              ),
              _Placement.middle => size.height * 0.30,
              _Placement.above => null,
            },
            bottom:
                placement == _Placement.above
                    ? math.min(
                      size.height - target!.top + gap,
                      size.height - padding.top - _TourCard.minHeight,
                    )
                    : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Placement { above, below, middle }

/// Dims everything except the lit part, which gets a brand-orange ring that
/// breathes outwards so the eye finds it.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.pulse});

  final Rect? hole;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xB3000000);
    final screen = Offset.zero & size;
    if (hole == null) {
      canvas.drawRect(screen, scrim);
      return;
    }
    final lit = RRect.fromRectAndRadius(
      hole!.inflate(6),
      const Radius.circular(ZirenTokens.radius16),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(screen),
        Path()..addRRect(lit),
      ),
      scrim,
    );
    canvas.drawRRect(
      lit,
      Paint()
        ..color = ZirenTokens.brandOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final spread = 4 + 10 * pulse;
    canvas.drawRRect(
      lit.inflate(spread),
      Paint()
        ..color = ZirenTokens.brandOrange.withValues(alpha: 0.55 * (1 - pulse))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.pulse != pulse;
}

/// The mascot and its speech bubble, in the onboarding's style: the figure in
/// a soft orange glow, the bubble's tail pointing at it.
class _TourCard extends StatelessWidget {
  const _TourCard({
    super.key,
    required this.title,
    required this.text,
    required this.pose,
    required this.lang,
    required this.index,
    required this.count,
    required this.last,
    required this.bob,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  /// Room the card needs, so it is never pushed off the screen's edge.
  static const minHeight = 210.0;
  static const mascotHeight = 128.0;

  final String title;
  final String text;
  final DemoPose pose;
  final String lang;
  final int index;
  final int count;
  final bool last;
  final Animation<double> bob;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedBuilder(
          animation: bob,
          builder:
              (_, child) => Transform.translate(
                offset: Offset(0, -4 * math.sin(bob.value * 2 * math.pi)),
                child: child,
              ),
          child: Container(
            width: 104,
            height: mascotHeight + 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.55),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              pose.asset,
              key: ValueKey(pose),
              height: mascotHeight,
              fit: BoxFit.contain,
              semanticLabel: 'Ziren',
            ),
          ),
        ),
        const SizedBox(width: ZirenTokens.space4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: ZirenTokens.space8),
            child: CustomPaint(
              painter: _BubbleTail(
                color: ZirenTokens.surfaceCard,
                border: ZirenTokens.brandOrange,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceCard,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                    bottomLeft: Radius.circular(6),
                  ),
                  border: Border.all(
                    color: ZirenTokens.brandOrange.withValues(alpha: 0.6),
                  ),
                  boxShadow: ZirenTokens.shadowSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ZirenTokens.brandOrange,
                            borderRadius: BorderRadius.circular(
                              ZirenTokens.radius4,
                            ),
                          ),
                          child: Text(
                            DemoChrome.badge(lang),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: ZirenTokens.brandOrange,
                            ),
                          ),
                        ),
                        Text(
                          DemoChrome.counter(index + 1, count),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    _Progress(index: index, count: count),
                    Row(
                      children: [
                        if (!last)
                          TextButton(
                            onPressed: onSkip,
                            style: TextButton.styleFrom(
                              foregroundColor: ZirenTokens.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              minimumSize: const Size(0, 40),
                            ),
                            child: Text(DemoChrome.skip(lang)),
                          ),
                        const Spacer(),
                        if (onBack != null)
                          IconButton(
                            tooltip: DemoChrome.back(lang),
                            onPressed: onBack,
                            icon: Icon(
                              LucideIcons.arrow_left,
                              size: 20,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                        const SizedBox(width: ZirenTokens.space4),
                        FilledButton.icon(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(
                            backgroundColor: ZirenTokens.brandOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          iconAlignment: IconAlignment.end,
                          icon: Icon(
                            last ? LucideIcons.check : LucideIcons.arrow_right,
                            size: 17,
                          ),
                          label: Text(
                            last
                                ? DemoChrome.done(lang)
                                : DemoChrome.next(lang),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color:
                    i <= index
                        ? ZirenTokens.brandOrange
                        : ZirenTokens.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

/// The bubble's tail on its lower-left corner, pointing at the mascot.
class _BubbleTail extends CustomPainter {
  _BubbleTail({required this.color, required this.border});

  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 16;
    canvas.drawPath(
      Path()
        ..moveTo(1, y)
        ..lineTo(-10, y + 11)
        ..lineTo(1, y + 9)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0.5, y)
        ..lineTo(-10, y + 11)
        ..lineTo(0.5, y + 9),
      Paint()
        ..color = border.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BubbleTail old) =>
      old.color != color || old.border != border;
}
