import 'dart:async';

import 'package:flutter/material.dart';

/// The two clips Ziren plays on Home, made from the branding videos
/// (ZIREN_Mascot_Wave_Transparent.webm, ZIREN_Mascot_No_Internet.webm) as
/// animated WebP with transparency — Flutter plays and loops those itself, no
/// video player needed. Both are on one canvas, registered by the feet, so
/// they stand on the same spot at the same size and swap without a jump
/// (scratchpad anim/videos.py).
enum ZirenMascotMood {
  /// Waving hello, 10 s at 30 fps, looping.
  wave,

  /// No internet: not connected, looks around, thinks, ... turns away, and
  /// round again, 10 s at 30 fps.
  offline;

  /// The clip.
  String get clip => 'assets/images/mascot/$name.webp';

  /// The clip's first frame: shown while it fades in, and for "Remove
  /// animations".
  String get still => 'assets/images/mascot/${name}_still.webp';
}

/// Ziren on Home: waving, or — while [offline] — the no-internet clip. The
/// change between the two fades through, with a small grow, never a cut.
///
/// Nothing is shown until both clips have their first frame decoded (it then
/// fades in), so Ziren never flashes in blank. With "Remove animations" on in
/// the phone's settings, Ziren stands still on the clip's first frame.
class ZirenMascot extends StatefulWidget {
  const ZirenMascot({super.key, required this.offline});

  final bool offline;

  /// The canvas both clips are drawn on, in pixels.
  static const Size canvas = Size(408, 464);

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
      for (final mood in ZirenMascotMood.values) ...[
        precacheImage(AssetImage(mood.clip), context),
        precacheImage(AssetImage(mood.still), context),
      ],
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
                      // Fade-through: the old clip fades and settles out in
                      // the first half, the new one grows in during the
                      // second. Never both at once — the two hold their heads
                      // in different places, and overlapping them showed two
                      // pins for a moment.
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
                      child: ZirenMascotClip(
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

/// One mood's clip, playing and looping. Draw it at [ZirenMascot.canvas]
/// size. An offstage tab pauses it: [Image] stops an animation while its
/// TickerMode is off.
///
/// For [startDelay] it shows the clip's first frame ([ZirenMascotMood.still]
/// is that frame) and only then starts playing: a clip fading in would
/// otherwise run on unseen and appear mid-move.
class ZirenMascotClip extends StatefulWidget {
  const ZirenMascotClip({
    super.key,
    required this.mood,
    this.startDelay = Duration.zero,
  });

  final ZirenMascotMood mood;
  final Duration startDelay;

  @override
  State<ZirenMascotClip> createState() => _ZirenMascotClipState();
}

class _ZirenMascotClipState extends State<ZirenMascotClip> {
  late bool _playing = widget.startDelay == Duration.zero;
  Timer? _start;

  @override
  void initState() {
    super.initState();
    if (!_playing) {
      _start = Timer(widget.startDelay, () {
        if (mounted) setState(() => _playing = true);
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final play = _playing && !MediaQuery.disableAnimationsOf(context);
    return Image.asset(
      play ? widget.mood.clip : widget.mood.still,
      fit: BoxFit.contain,
      // The clip's first frame replaces the identical still: no blank, no jump.
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}
