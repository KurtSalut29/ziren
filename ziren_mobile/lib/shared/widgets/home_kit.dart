import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// ============================================================
// Home kit — the shared building blocks of the Resident and
// Responder home screens.
//
// Both roles get the same shapes so the app reads as one product:
// an identity header, one dominant action card, a grid of quick
// actions, paired list cards, and a recent-activity card. What
// changes between them is the content, not the structure — a
// responder's dominant action is going on duty, a resident's is
// calling for help.
//
// Colour comes from app_tokens only. The severity, agency and
// aiSuggested rules in that file are operational, not stylistic,
// and they survive this layout unchanged.
// ============================================================

/// Page background. Slightly cooler and darker than surfaceBase so the
/// cards read as raised without needing shadows on every one.
Color get kHomeCanvas => ZirenTokens.isDark
    ? const Color(0xFF0C0C0E)
    : const Color(0xFFF4F4F7);

const double kHomeGutter = ZirenTokens.space16;
const double kCardRadius = 18.0;

// ── Identity header ─────────────────────────────────────────────

/// Avatar, name, a one-line state, and the notification bell.
///
/// The state line is the honest version of a greeting: it says whether
/// the app can reach the server and how a report would travel if it
/// cannot. On a phone in a storm that is the single most useful thing
/// the top of the screen can tell someone.
class HomeIdentityHeader extends StatelessWidget {
  const HomeIdentityHeader({
    super.key,
    required this.name,
    this.stateLabel,
    this.stateColor,
    this.stateDetail,
    required this.hasUnread,
    required this.onBellTap,
    required this.bellLabel,
    required this.bellLabelUnread,
    this.avatarColor = ZirenTokens.brandOrange,
  });

  final String name;

  /// The one-line state under the name. Optional: on the single-surface
  /// Resident home the delivery band above already says whether the app
  /// can reach the server, and repeating it here was the same fact twice
  /// on one screen.
  final String? stateLabel;
  final Color? stateColor;
  final String? stateDetail;
  final bool hasUnread;
  final VoidCallback onBellTap;

  /// Spoken name for the bell. The unread state is carried by a coloured
  /// dot, which a screen reader cannot see — so it has to be in the label,
  /// and the label has to come from the caller's locale.
  final String bellLabel;
  final String bellLabelUnread;
  final Color avatarColor;

  String get _initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space12,
        ZirenTokens.space8,
        ZirenTokens.space16,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarColor,
            ),
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                    height: 1.15,
                  ),
                ),
                if (stateLabel != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: stateColor ?? ZirenTokens.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space6),
                      Flexible(
                        child: Text(
                          stateLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ),
                      if (stateDetail != null) ...[
                        const SizedBox(width: ZirenTokens.space8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: ZirenTokens.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space8),
                        Flexible(
                          child: Text(
                            stateDetail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          _BellButton(
            hasUnread: hasUnread,
            onTap: onBellTap,
            label: bellLabel,
            labelUnread: bellLabelUnread,
          ),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.hasUnread,
    required this.onTap,
    required this.label,
    required this.labelUnread,
  });
  final bool hasUnread;
  final VoidCallback onTap;
  final String label;
  final String labelUnread;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: hasUnread ? labelUnread : label,
      iconSize: 28,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            LucideIcons.bell,
            size: 28,
            color: ZirenTokens.textPrimary,
          ),
          if (hasUnread)
            Positioned(
              top: -1,
              right: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: ZirenTokens.severityCritical,
                  shape: BoxShape.circle,
                  border: Border.all(color: kHomeCanvas, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Hero action card ────────────────────────────────────────────

/// The one dominant control on a home screen, plus a three-cell strip
/// of the facts that decide whether pressing it will work.
///
/// The strip is not decoration: location, clock and dispatch mode are
/// exactly what determines whether help can be routed, and showing
/// "Unavailable" there is more useful than discovering it after the
/// press.
class HeroActionCard extends StatelessWidget {
  const HeroActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.caption,
    required this.onTap,
    required this.facts,
    this.accent = ZirenTokens.severityCritical,
    this.tint,
    this.pulse,
    this.busy = false,
  });

  final String title;
  final String subtitle;
  final String caption;
  final VoidCallback onTap;
  final List<HeroFact> facts;
  final Color accent;

  /// Defaults to [ZirenTokens.severityCriticalBg] — resolved in [build],
  /// not as a constructor default, because that token now varies with
  /// light/dark mode and a constructor default must be a compile-time
  /// constant.
  final Color? tint;

  /// Repeating 0→1 animation driving the outer ring. Optional; without it
  /// the rings are static.
  final Animation<double>? pulse;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // Same gate as RadialActionDial: the ring here repeats for as long as the
    // responder is on duty, so it is the animation most worth silencing when
    // the OS has been told to stop them.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      decoration: BoxDecoration(
        color: tint ?? ZirenTokens.severityCriticalBg,
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space24),
            child: _HeroButton(
              title: title,
              subtitle: subtitle,
              caption: caption,
              accent: accent,
              onTap: onTap,
              pulse: reduceMotion ? null : pulse,
              busy: busy,
            ),
          ),
          if (facts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space8,
                0,
                ZirenTokens.space8,
                ZirenTokens.space16,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 34,
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    Expanded(child: _FactCell(fact: facts[i])),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class HeroFact {
  const HeroFact({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _FactCell extends StatelessWidget {
  const _FactCell({required this.fact});
  final HeroFact fact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(fact.icon, size: 15, color: fact.color),
            const SizedBox(width: ZirenTokens.space6),
            Flexible(
              child: Text(
                fact.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          fact.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
        ),
      ],
    );
  }
}

class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.title,
    required this.subtitle,
    required this.caption,
    required this.accent,
    required this.onTap,
    required this.pulse,
    required this.busy,
  });

  final String title;
  final String subtitle;
  final String caption;
  final Color accent;
  final VoidCallback onTap;
  final Animation<double>? pulse;
  final bool busy;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const size = 210.0;

    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.subtitle}. ${widget.caption}',
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Two rings breathing outward. One animation drives both at
              // different phases — an emergency control should look alive
              // without turning the screen into a light show.
              if (widget.pulse != null)
                AnimatedBuilder(
                  animation: widget.pulse!,
                  builder: (_, __) {
                    final t = widget.pulse!.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        _ring(
                          size * (0.78 + 0.22 * t),
                          widget.accent.withValues(alpha: 0.10 * (1 - t)),
                        ),
                        _ring(
                          size * (0.72 + 0.14 * t),
                          widget.accent.withValues(alpha: 0.16 * (1 - t)),
                        ),
                      ],
                    );
                  },
                ),
              _ring(size * 0.86, widget.accent.withValues(alpha: 0.10)),

              AnimatedScale(
                scale: _down ? 0.96 : 1.0,
                duration: ZirenTokens.motionPress,
                child: Container(
                  width: size * 0.70,
                  height: size * 0.70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.25, -0.35),
                      radius: 1.0,
                      colors: [
                        Color.lerp(widget.accent, Colors.white, 0.18)!,
                        widget.accent,
                        Color.lerp(widget.accent, Colors.black, 0.18)!,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.38),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child:
                      widget.busy
                          ? const SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                          : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.0,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Width-capped and wrappable. The caption sits
                              // inside a 147px circle, so an unconstrained
                              // single line spills past the edge as soon as the
                              // text is longer than the English placeholder —
                              // which Tagalog generally is.
                              SizedBox(
                                width: size * 0.54,
                                child: Text(
                                  widget.caption,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.25,
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                            ],
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double d, Color c) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
  );
}

// ── Radial action dial ──────────────────────────────────────────

/// SOS at the centre, the report categories in a ring around it.
///
/// The arrangement is the argument. The centre is the path for someone who
/// cannot classify what is happening — a person hiding from an intruder, a
/// bystander at a collapse, anyone whose hands are shaking. It carries no
/// category on purpose, so a dispatcher calls back and asks rather than
/// acting on a guess the app pressured out of them.
///
/// The ring is for the other case, where you already know: one tap goes
/// straight to a confirm screen with the category set, not into a wizard.
/// Both paths keep a confirm step — an accidental send commits a crew and a
/// vehicle, and that cost does not go away because the tap was quick.
///
/// Replaces a separate hero card plus a six-tile grid. Same two jobs, one
/// object, and the hierarchy between them is now visible instead of implied
/// by which section came first.
class RadialActionDial extends StatefulWidget {
  const RadialActionDial({
    super.key,
    required this.centerTitle,
    required this.centerSubtitle,
    required this.centerCaption,
    required this.onCenterTap,
    required this.actions,
    required this.facts,
    this.accent = ZirenTokens.severityCritical,
    this.tint,
    this.pulse,
    this.busy = false,
    this.replayToken = 0,
  });

  final String centerTitle;
  final String centerSubtitle;
  final String centerCaption;
  final VoidCallback onCenterTap;
  final List<QuickAction> actions;
  final List<HeroFact> facts;
  final Color accent;

  /// Unused by this widget's own build — see the "No tinted box" note
  /// below — kept only so callers that still pass it don't need editing.
  /// Nullable (rather than defaulting to [ZirenTokens.severityCriticalBg])
  /// because that token now varies with light/dark mode and a constructor
  /// default must be a compile-time constant.
  final Color? tint;
  final Animation<double>? pulse;
  final bool busy;

  /// Bump this to play the entrance again — e.g. after a pull-to-refresh.
  final int replayToken;

  @override
  State<RadialActionDial> createState() => _RadialActionDialState();
}

class _RadialActionDialState extends State<RadialActionDial>
    with SingleTickerProviderStateMixin {
  static const double _chipD = 54;
  static const double _colW = 78;
  static const double _labelBlock = 20;

  /// The entrance: the categories deploy outward from under the SOS into
  /// their ring positions, clockwise from the top.
  ///
  /// It plays on arrival and then the dial is still, except for the SOS
  /// breathing. That restraint is the point — on this screen movement means
  /// "look here", so a ring of permanently animating chips would compete
  /// with the one control that has earned the right to move.
  ///
  /// "On arrival" is the hard part, and the first version got it wrong. It
  /// fired once from initState, but Home lives in a StatefulShellRoute
  /// indexedStack: the branch is kept alive, so switching tabs and coming
  /// back does not remount the screen and never replayed it. Hot reload
  /// preserves State too, so it did not replay in development either. The
  /// animation ran exactly once per app launch, on a screen nobody was
  /// looking at yet.
  ///
  /// go_router mutes the tickers of inactive branches, so TickerMode is the
  /// honest signal for "this screen is now the one on screen". Watching it
  /// replays the entrance on every return to the tab.
  late final AnimationController _entrance;
  bool _wasVisible = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: ZirenTokens.motionDial,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_wasVisible) _replay();
    _wasVisible = visible;
  }

  @override
  void didUpdateWidget(covariant RadialActionDial old) {
    super.didUpdateWidget(old);
    if (old.replayToken != widget.replayToken) _replay();
  }

  void _replay() {
    // from: 0 rather than forward(), so a return to the tab restarts the
    // deployment instead of finding the controller already at 1.0.
    _entrance.forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Someone who has asked the OS to reduce motion should not have to watch
    // six chips fly across an emergency screen to reach the report button.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // No tinted box. The dial is the one dominant thing on this screen,
    // and wrapping it in a card put it on the same footing as the three
    // list cards that used to sit under it — four containers, one
    // hierarchy, no answer to "what matters here". On the open ground it
    // is simply the largest thing, which is the whole claim.
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space12,
        ZirenTokens.space8,
        ZirenTokens.space12,
        ZirenTokens.space16,
      ),
      child: Column(
        children: [
          // Capped and centred. The ring radius is derived from the available
          // width, so without a ceiling the dial grows without limit — on a
          // tablet or in landscape it became taller than the viewport and
          // overflowed. A dial wider than a thumb's reach is also the wrong
          // shape for a control meant to be worked one-handed.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final centerD = math.min(148.0, w * 0.44);
                  // Ring radius: as far out as fits, but never so close that a
                  // chip overlaps the centre button.
                  final maxR = w / 2 - _chipD / 2 - 4;
                  final minR = centerD / 2 + _chipD / 2 + 10;
                  final r = math.max(minR, maxR);
                  final h = 2 * r + _chipD + _labelBlock + 10;
                  final cx = w / 2;
                  final cy = h / 2;

                  return SizedBox(
                    width: w,
                    height: h,
                    child: AnimatedBuilder(
                      animation: _entrance,
                      builder: (context, _) {
                        final n = widget.actions.length;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < n; i++)
                              _satellite(
                                widget.actions[i],
                                i,
                                n,
                                cx,
                                cy,
                                r,
                                reduceMotion ? 1.0 : _chipProgress(i, n),
                              ),
                            Positioned(
                              left: cx - centerD / 2,
                              top: cy - centerD / 2,
                              child: Transform.scale(
                                scale: reduceMotion ? 1.0 : _centerProgress(),
                                child: _CenterButton(
                                  diameter: centerD,
                                  title: widget.centerTitle,
                                  subtitle: widget.centerSubtitle,
                                  caption: widget.centerCaption,
                                  accent: widget.accent,
                                  onTap: widget.onCenterTap,
                                  // The entrance was gated below but the pulse
                                  // was not, so "remove animations" still left
                                  // a red ring breathing on this screen for as
                                  // long as it was open — the one animation
                                  // here that never stops on its own.
                                  pulse: reduceMotion ? null : widget.pulse,
                                  busy: widget.busy,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          if (widget.facts.isNotEmpty) ...[
            const SizedBox(height: ZirenTokens.space12),
            Row(
              children: [
                for (var i = 0; i < widget.facts.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 34,
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  Expanded(child: _FactCell(fact: widget.facts[i])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The centre settles first and slightly overshoots, so the SOS is already
  /// standing before anything deploys around it.
  double _centerProgress() {
    final t =
        CurvedAnimation(
          parent: _entrance,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
        ).value;
    return 0.88 + 0.12 * t;
  }

  /// Each chip gets its own slice of the timeline, offset clockwise, so the
  /// ring unrolls rather than appearing all at once.
  double _chipProgress(int i, int count) {
    final start = 0.10 + i * 0.075;
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        start,
        math.min(1.0, start + 0.55),
        curve: Curves.easeOutCubic,
      ),
    ).value;
  }

  Widget _satellite(
    QuickAction a,
    int i,
    int count,
    double cx,
    double cy,
    double r,
    double t,
  ) {
    // Start at the top and go clockwise, so the first category listed is the
    // one at 12 o'clock rather than wherever the loop happened to begin.
    final angle = (-math.pi / 2) + (2 * math.pi * i / count);

    // Chips travel out from under the SOS to their ring position. They come
    // from the centre because that is what they are — the categorised paths
    // branching off the uncategorised one. Starting well inside the centre
    // button makes the travel long enough to actually read as movement.
    final travelled = r * (0.14 + 0.86 * t);
    final x = cx + travelled * math.cos(angle);
    final y = cy + travelled * math.sin(angle);

    return Positioned(
      left: x - _colW / 2,
      top: y - _chipD / 2,
      width: _colW,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.45 + 0.55 * t,
          child: Semantics(
            button: true,
            label: a.semanticLabel ?? a.label,
            child: _ChipButton(action: a, diameter: _chipD),
          ),
        ),
      ),
    );
  }
}

/// A ring chip. Presses down and lights its own colour while held, so a tap
/// registers on a phone held at arm's length in the rain.
class _ChipButton extends StatefulWidget {
  const _ChipButton({required this.action, required this.diameter});

  final QuickAction action;
  final double diameter;

  @override
  State<_ChipButton> createState() => _ChipButtonState();
}

class _ChipButtonState extends State<_ChipButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.action;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        // Confirms the press without asking the user to look at the screen.
        HapticFeedback.selectionClick();
        a.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _down ? 0.90 : 1.0,
            duration: ZirenTokens.motionPress,
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: ZirenTokens.motionPress,
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                color:
                    _down
                        ? a.color.withValues(alpha: 0.14)
                        : ZirenTokens.surfaceCard,
                shape: BoxShape.circle,
                border: Border.all(
                  color: a.color.withValues(alpha: _down ? 0.9 : 0.35),
                  width: _down ? 2 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _down ? 0.02 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(a.icon, size: 26, color: a.color),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            a.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterButton extends StatefulWidget {
  const _CenterButton({
    required this.diameter,
    required this.title,
    required this.subtitle,
    required this.caption,
    required this.accent,
    required this.onTap,
    required this.pulse,
    required this.busy,
  });

  final double diameter;
  final String title;
  final String subtitle;
  final String caption;
  final Color accent;
  final VoidCallback onTap;
  final Animation<double>? pulse;
  final bool busy;

  @override
  State<_CenterButton> createState() => _CenterButtonState();
}

class _CenterButtonState extends State<_CenterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;

    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.subtitle}. ${widget.caption}',
      child: GestureDetector(
        onTap:
            widget.busy
                ? null
                : () {
                  // Heavier than the ring chips. This is the control you press
                  // without looking, and the thump is the only confirmation
                  // available to someone who cannot watch the screen.
                  HapticFeedback.mediumImpact();
                  widget.onTap();
                },
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulse != null)
                AnimatedBuilder(
                  animation: widget.pulse!,
                  builder: (_, __) {
                    final t = widget.pulse!.value;
                    return Container(
                      width: d * (0.92 + 0.30 * t),
                      height: d * (0.92 + 0.30 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accent.withValues(alpha: 0.16 * (1 - t)),
                      ),
                    );
                  },
                ),
              AnimatedScale(
                scale: _down ? 0.95 : 1.0,
                duration: ZirenTokens.motionPress,
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.25, -0.35),
                      radius: 1.0,
                      colors: [
                        Color.lerp(widget.accent, Colors.white, 0.18)!,
                        widget.accent,
                        Color.lerp(widget.accent, Colors.black, 0.18)!,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.38),
                        blurRadius: 20,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child:
                      widget.busy
                          ? const SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                          : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  fontSize: d * 0.27,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.0,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.subtitle,
                                style: TextStyle(
                                  fontSize: d * 0.085,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: d * 0.74,
                                child: Text(
                                  widget.caption,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: d * 0.075,
                                    height: 1.2,
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                            ],
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section heading ─────────────────────────────────────────────

class HomeSectionHeading extends StatelessWidget {
  const HomeSectionHeading(this.text, {super.key, this.action, this.onAction});

  final String text;
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
              text,
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

// ── Quick action grid ───────────────────────────────────────────

class QuickAction {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// What a screen reader says instead of [label]. The visible label is a
  /// bare noun ("Sunog") because the chip has no room for more; spoken on
  /// its own that is a category, not a control, so the caller supplies the
  /// verb form here in the user's language. Falls back to [label].
  final String? semanticLabel;
}

/// Three across, wrapping. Each tile is a single tap into a pre-filled
/// report, so the label is the incident type and nothing else.
class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({super.key, required this.actions});
  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = ZirenTokens.space10;
          final w = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final a in actions)
                SizedBox(width: w, child: _QuickTile(action: a)),
            ],
          );
        },
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.action});
  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 104,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, size: 34, color: action.color),
              const SizedBox(height: ZirenTokens.space10),
              // One line. A wrapping label pushes its icon up and breaks the
              // baseline the six tiles share, which is the thing that makes
              // the grid read as a grid.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── List card ───────────────────────────────────────────────────

class ListCardRow {
  const ListCardRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailingNote,
    this.trailingColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? trailingNote;
  final Color? trailingColor;
  final VoidCallback? onTap;
}

/// A titled card holding a short list. Used in pairs side by side.
///
/// `emptyText` is required rather than optional: these cards are driven
/// by live data that is often genuinely empty, and an empty card with no
/// words in it looks like a failed load.
class HomeListCard extends StatelessWidget {
  const HomeListCard({
    super.key,
    required this.title,
    required this.titleColor,
    required this.rows,
    required this.emptyText,
    this.action,
    this.onAction,
  });

  final String title;
  final Color titleColor;
  final List<ListCardRow> rows;
  final String emptyText;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space12,
        ZirenTokens.space12,
        ZirenTokens.space8,
        ZirenTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
              if (action != null)
                GestureDetector(
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Text(
                      action!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ZirenTokens.space16,
                horizontal: 2,
              ),
              child: Text(
                emptyText,
                style: TextStyle(
                  fontSize: 12.5,
                  color: ZirenTokens.textMuted,
                  height: 1.4,
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
                ),
              _ListRow(row: rows[i]),
            ],
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.row});
  final ListCardRow row;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: row.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ZirenTokens.space10,
          horizontal: 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(row.icon, size: 22, color: row.iconColor),
            const SizedBox(width: ZirenTokens.space10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    row.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                  if (row.trailingNote != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      row.trailingNote!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: row.trailingColor ?? ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (row.onTap != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  LucideIcons.chevron_right,
                  size: 20,
                  color: ZirenTokens.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Recent activity card ────────────────────────────────────────

/// Wide card closing the page. Holds either a short list or an empty
/// state that says what will appear here and what puts it there.
class HomeActivityCard extends StatelessWidget {
  const HomeActivityCard({
    super.key,
    required this.title,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyIcon,
    this.rows = const [],
    this.action,
    this.onAction,
  });

  final String title;
  final String emptyTitle;
  final String emptyBody;
  final IconData emptyIcon;
  final List<ListCardRow> rows;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              if (action != null && rows.isNotEmpty)
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
          const SizedBox(height: ZirenTokens.space12),
          if (rows.isEmpty)
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    emptyIcon,
                    size: 26,
                    color: ZirenTokens.textMuted,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        emptyTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        emptyBody,
                        style: TextStyle(
                          fontSize: 13,
                          color: ZirenTokens.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
                ),
              _ListRow(row: rows[i]),
            ],
        ],
      ),
    );
  }
}
