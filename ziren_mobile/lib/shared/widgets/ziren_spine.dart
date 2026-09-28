import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The Spine — Ziren's signature layout structure.
///
/// Every other emergency app lays its content out as a feed of cards. That
/// shape says "here are some things"; it cannot say "this happened, then this,
/// and you are here now". An emergency is a sequence — reported, dispatched,
/// en route, arrived, resolved — and the whole product is really about where
/// along that sequence you currently are.
///
/// So Ziren hangs its content off a vertical rail. The rail is filled behind
/// you and hollow ahead of you, which means a resident can read their position
/// in the response without reading a single word. It is used on Home (the live
/// incident), Reports (history), and Profile (verification progress), which is
/// what makes those screens look like one product rather than three.
///
/// Deliberately not decoration: if a surface has no sequence to express, it
/// should not use a spine.

/// State of a single node on the rail.
enum SpineState {
  /// Already happened.
  done,

  /// Happening now — the only node that animates.
  active,

  /// Not yet reached.
  pending,

  /// Reached, but the sequence stopped here (cancelled, rejected).
  halted,
}

class SpineNode {
  const SpineNode({
    required this.title,
    this.detail,
    this.timestamp,
    this.state = SpineState.pending,
    this.icon,
    this.trailing,
    this.onTap,
    this.accent,
  });

  final String title;
  final String? detail;
  final String? timestamp;
  final SpineState state;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Overrides the state colour. Used where the node carries agency or
  /// severity meaning that outranks its position in the sequence.
  final Color? accent;
}

/// Renders [nodes] against a continuous vertical rail.
class ZirenSpine extends StatelessWidget {
  const ZirenSpine({super.key, required this.nodes, this.compact = false});

  final List<SpineNode> nodes;

  /// Tighter vertical rhythm, for history lists rather than live status.
  final bool compact;

  static const double railX = 13; // centre of the rail from the left edge

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < nodes.length; i++)
          _SpineRow(
            node: nodes[i],
            isFirst: i == 0,
            isLast: i == nodes.length - 1,
            // The segment above a node belongs to the transition into it, so
            // it is filled once that node has been reached.
            incomingFilled: i > 0 && nodes[i].state != SpineState.pending,
            compact: compact,
          ),
      ],
    );
  }
}

class _SpineRow extends StatelessWidget {
  const _SpineRow({
    required this.node,
    required this.isFirst,
    required this.isLast,
    required this.incomingFilled,
    required this.compact,
  });

  final SpineNode node;
  final bool isFirst;
  final bool isLast;
  final bool incomingFilled;
  final bool compact;

  Color get _color {
    if (node.accent != null) return node.accent!;
    switch (node.state) {
      case SpineState.done:
        return ZirenTokens.systemSuccess;
      case SpineState.active:
        return ZirenTokens.brandOrange;
      case SpineState.halted:
        return ZirenTokens.textMuted;
      case SpineState.pending:
        return ZirenTokens.surfaceBorder;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = compact ? ZirenTokens.space16 : ZirenTokens.space20;

    final content = Padding(
      padding: EdgeInsets.only(
        left: ZirenTokens.space16,
        bottom: isLast ? 0 : gap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.title,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight:
                        node.state == SpineState.active
                            ? FontWeight.w700
                            : FontWeight.w600,
                    color:
                        node.state == SpineState.pending
                            ? ZirenTokens.textMuted
                            : ZirenTokens.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              if (node.timestamp != null)
                Text(
                  node.timestamp!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              if (node.trailing != null) ...[
                const SizedBox(width: ZirenTokens.space8),
                node.trailing!,
              ],
            ],
          ),
          if (node.detail != null) ...[
            const SizedBox(height: 3),
            Text(
              node.detail!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color:
                    node.state == SpineState.pending
                        ? ZirenTokens.textDisabled
                        : ZirenTokens.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: ZirenSpine.railX * 2,
            child: _Rail(
              color: _color,
              state: node.state,
              icon: node.icon,
              isFirst: isFirst,
              isLast: isLast,
              incomingFilled: incomingFilled,
            ),
          ),
          Expanded(
            child:
                node.onTap == null
                    ? content
                    : InkWell(
                      onTap: node.onTap,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                      child: content,
                    ),
          ),
        ],
      ),
    );
  }
}

/// The rail itself: a line above the marker, the marker, a line below.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.color,
    required this.state,
    required this.icon,
    required this.isFirst,
    required this.isLast,
    required this.incomingFilled,
  });

  final Color color;
  final SpineState state;
  final IconData? icon;
  final bool isFirst;
  final bool isLast;
  final bool incomingFilled;

  static const double _marker = 22;

  @override
  Widget build(BuildContext context) {
    final lineAbove =
        isFirst
            ? const SizedBox(height: 4)
            : Expanded(
              flex: 0,
              child: Container(
                width: 2,
                height: 4,
                color:
                    incomingFilled
                        ? color.withValues(alpha: 0.35)
                        : ZirenTokens.surfaceBorder,
              ),
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        lineAbove,
        _Marker(color: color, state: state, icon: icon, size: _marker),
        if (!isLast)
          Expanded(
            child: Container(
              width: 2,
              // Ahead of the active node the rail is hollow, so the boundary
              // between "done" and "still to come" is visible at a glance.
              color:
                  state == SpineState.done
                      ? color.withValues(alpha: 0.35)
                      : ZirenTokens.surfaceBorder,
            ),
          ),
      ],
    );
  }
}

class _Marker extends StatefulWidget {
  const _Marker({
    required this.color,
    required this.state,
    required this.icon,
    required this.size,
  });

  final Color color;
  final SpineState state;
  final IconData? icon;
  final double size;

  @override
  State<_Marker> createState() => _MarkerState();
}

class _MarkerState extends State<_Marker> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_Marker old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncAnimation();
  }

  /// Only the active node animates. Running a repeating controller for every
  /// node in a long history list would burn battery for no signal — and on an
  /// emergency app, battery is a feature.
  void _syncAnimation() {
    if (widget.state == SpineState.active) {
      _ctrl ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
    } else {
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A halted step is filled too: the report REACHED it and went no further.
    // Left hollow it was the same picture as a step still to come, so a
    // cancelled report showed a rail that looked as if nothing had happened.
    final halted = widget.state == SpineState.halted;
    final filled =
        widget.state == SpineState.done ||
        widget.state == SpineState.active ||
        halted;

    final core = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? widget.color : ZirenTokens.surfaceCard,
        border: Border.all(
          color: filled ? widget.color : ZirenTokens.surfaceBorder,
          width: 2,
        ),
      ),
      child:
          widget.icon != null
              ? Icon(
                widget.icon,
                size: 12,
                color: filled ? Colors.white : ZirenTokens.textMuted,
              )
              : widget.state == SpineState.done
              ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
              : halted
              ? const Icon(LucideIcons.x, size: 13, color: Colors.white)
              : null,
    );

    final ctrl = _ctrl;
    if (ctrl == null) return core;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = ctrl.value;
        return SizedBox(
          width: widget.size + 14,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding halo — the only motion on the screen, so it reads
              // as "this is happening now" without a label.
              Container(
                width: widget.size + 14 * t,
                height: widget.size + 14 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.22 * (1 - t)),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: core,
    );
  }
}

/// Section heading used above a spine. Quiet by design — the rail is the
/// structure, the heading only names it.
class SpineHeading extends StatelessWidget {
  const SpineHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZirenTokens.space12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textMuted,
                letterSpacing: 0.9,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
