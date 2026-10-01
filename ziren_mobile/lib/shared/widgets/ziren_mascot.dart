import 'dart:async';

import 'package:flutter/material.dart';

/// The two loops Ziren plays on Home, both cut from the branding sheets
/// (Wave_Mascot.png, No_Internet_Mascot.png) into ten frames each, on one
/// canvas registered by the feet: every frame of both sets stands on the same
/// spot at the same size, so frames cross-fade in place and the two sets swap
/// without the figure jumping.
enum ZirenMascotMood {
  /// Waving hello: Start, Move 1-8, End, and straight back to Start.
  wave(prefix: 'wave', frameTime: Duration(milliseconds: 150), blend: 0.6),

  /// No internet: not connected, looks around, thinks, ... turns away (End),
  /// then from the top again. Each pose is a feeling, so each is held long
  /// enough to read.
  offline(
    prefix: 'offline',
    frameTime: Duration(milliseconds: 560),
    // Short: these poses differ a lot (the badge and head move), and a long
    // overlap showed both for a moment.
    blend: 0.28,
  );

  const ZirenMascotMood({
    required this.prefix,
    required this.frameTime,
    required this.blend,
  });

  final String prefix;

  /// How long each frame lasts, cross-fade included.
  final Duration frameTime;

  /// The share of [frameTime] spent fading into the next frame.
  final double blend;

  static const int frameCount = 10;

  List<String> get frames => [
    for (var i = 1; i <= frameCount; i++)
      'assets/images/mascot/${prefix}_${i.toString().padLeft(2, '0')}.webp',
  ];
}

/// Ziren on Home: waving, or — while [offline] — the no-internet loop. The
/// change between the two fades through, with a small grow, never a cut.
///
/// Nothing is shown until all 20 frames are decoded (it then fades in), so no
/// frame ever flashes in blank. With "Remove animations" on in the phone's
/// settings, Ziren stands still on the first frame of the loop.
class ZirenMascot extends StatefulWidget {
  const ZirenMascot({super.key, required this.offline});

  final bool offline;

  /// The canvas every frame is drawn on, in pixels, and the feet's place on
  /// it (see scratchpad anim/register.py).
  static const Size canvas = Size(345, 398);

  @override
  State<ZirenMascot> createState() => _ZirenMascotState();
}

class _ZirenMascotState extends State<ZirenMascot> {
  bool _ready = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    final all = [
      for (final mood in ZirenMascotMood.values)
        for (final path in mood.frames)
          precacheImage(AssetImage(path), context),
    ];
    Future.wait(all).whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mood =
        widget.offline ? ZirenMascotMood.offline : ZirenMascotMood.wave;
    // Decoration: the card beside it says what Ziren has to say.
    return ExcludeSemantics(
      child: AnimatedOpacity(
        opacity: _ready ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          child: SizedBox.fromSize(
            size: ZirenMascot.canvas,
            child:
                !_ready
                    ? null
                    : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 520),
                      // Each side fades over 60% of the change, overlapping in
                      // the middle: the figure never goes see-through, which
                      // two plain 50/50 fades of the same body would do.
                      // Fade-through: the old loop fades and settles out in
                      // the first half, the new one grows in during the
                      // second. Never both at once — the two sets hold their
                      // heads in different places, and overlapping them
                      // showed two pins for a moment.
                      transitionBuilder: (child, animation) {
                        final fade = CurvedAnimation(
                          parent: animation,
                          curve: const Interval(0.5, 1, curve: Curves.easeOut),
                        );
                        final grow = Tween<double>(begin: 0.95, end: 1).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: const Interval(
                              0.5,
                              1,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                        );
                        return FadeTransition(
                          opacity: fade,
                          child: ScaleTransition(
                            scale: grow,
                            alignment: Alignment.bottomCenter,
                            child: child,
                          ),
                        );
                      },
                      layoutBuilder:
                          (current, previous) => Stack(
                            fit: StackFit.expand,
                            children: [
                              ...previous,
                              if (current != null) current,
                            ],
                          ),
                      child: ZirenFrameLoop(
                        key: ValueKey(mood),
                        mood: mood,
                        // Until the fade-through has brought it in.
                        startDelay: const Duration(milliseconds: 520),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}

/// One mood's ten frames, played Start to End and round again, each frame
/// cross-fading into the next. Draw it at [ZirenMascot.canvas] size.
class ZirenFrameLoop extends StatefulWidget {
  const ZirenFrameLoop({
    super.key,
    required this.mood,
    this.startDelay = Duration.zero,
  });

  final ZirenMascotMood mood;

  /// How long the first frame waits before the loop starts: a loop that is
  /// fading in holds still until it is showing, so its first change of pose
  /// is not half-seen through the fade.
  final Duration startDelay;

  @override
  State<ZirenFrameLoop> createState() => _ZirenFrameLoopState();
}

class _ZirenFrameLoopState extends State<ZirenFrameLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: widget.mood.frameTime * ZirenMascotMood.frameCount,
  );

  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _start?.cancel();
      _loop
        ..stop()
        ..value = 0;
    } else if (!_loop.isAnimating && !(_start?.isActive ?? false)) {
      if (widget.startDelay == Duration.zero) {
        _loop.repeat();
      } else {
        _start = Timer(widget.startDelay, () {
          if (mounted) _loop.repeat();
        });
      }
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.mood.frames;
    const n = ZirenMascotMood.frameCount;
    final blend = widget.mood.blend;
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final pos = _loop.value * n;
        final i = pos.floor() % n;
        final next = (i + 1) % n;
        // Held for the first part of the frame, then faded into the next.
        final b = Curves.easeInOut.transform(
          ((pos - pos.floor() - (1 - blend)) / blend).clamp(0.0, 1.0),
        );
        // The next frame comes in a little ahead of this one going out, so
        // where the two overlap (the body) it stays solid all the way.
        final over = (b / 0.6).clamp(0.0, 1.0);
        final under = 1 - ((b - 0.4) / 0.6).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            _frame(frames[i], under, i),
            if (b > 0) _frame(frames[next], over, next),
          ],
        );
      },
    );
  }

  /// Keyed by frame, so a frame moving from "next" to "current" keeps its
  /// element (and its decoded image) instead of being rebuilt.
  Widget _frame(String path, double opacity, int index) {
    return Image.asset(
      path,
      key: ValueKey(index),
      opacity: AlwaysStoppedAnimation(opacity),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}
