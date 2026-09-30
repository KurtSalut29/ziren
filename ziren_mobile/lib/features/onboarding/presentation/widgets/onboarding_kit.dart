import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';

/// Where the three first-run screens sit: Language → Privacy → Get started.
/// Dots plus "Step 2 of 3", so a new user can see the setup is short.
class OnboardingSteps extends StatelessWidget {
  const OnboardingSteps({super.key, required this.step, this.total = 3});

  /// 1-based.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          AnimatedContainer(
            duration: ZirenTokens.motionQuick,
            width: i == step ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color:
                  i <= step
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.surfaceBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
        const SizedBox(width: ZirenTokens.space10),
        Text(
          t.onbStep('$step', '$total'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

/// The help mascot with a speech bubble asking the question. It bobs gently,
/// unless the phone asks for reduced motion.
class OnboardingMascot extends StatefulWidget {
  const OnboardingMascot({
    super.key,
    required this.text,
    this.size = 92,
    this.onBrand = false,
  });

  final String text;

  /// Drawn on the orange brand hero: a white glow instead of an orange one,
  /// which would vanish into it.
  final bool onBrand;

  /// The mascot's own size; its glow is a little larger.
  final double size;

  @override
  State<OnboardingMascot> createState() => _OnboardingMascotState();
}

class _OnboardingMascotState extends State<OnboardingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bob.stop();
      _bob.value = 0;
    } else if (!_bob.isAnimating) {
      _bob.repeat();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedBuilder(
          animation: _bob,
          builder:
              (context, child) => Transform.translate(
                offset: Offset(0, -4 * math.sin(_bob.value * 2 * math.pi)),
                child: child,
              ),
          child: Container(
            width: widget.size + 12,
            height: widget.size + 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors:
                    widget.onBrand
                        ? [
                          Colors.white.withValues(alpha: 0.45),
                          Colors.white.withValues(alpha: 0.0),
                        ]
                        : [
                          ZirenTokens.brandOrange.withValues(alpha: 0.22),
                          ZirenTokens.brandOrange.withValues(alpha: 0.0),
                        ],
              ),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              'assets/images/mascot_help.png',
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              semanticLabel: 'Ziren',
            ),
          ),
        ),
        const SizedBox(width: ZirenTokens.space4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: ZirenTokens.space16),
            child: CustomPaint(
              painter: _BubbleTail(
                color: ZirenTokens.surfaceCard,
                border: ZirenTokens.surfaceBorder,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceCard,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                    bottomLeft: Radius.circular(6),
                  ),
                  border: Border.all(color: ZirenTokens.surfaceBorder),
                  boxShadow: ZirenTokens.shadowSm,
                ),
                child: AnimatedSwitcher(
                  duration: ZirenTokens.motionQuick,
                  child: Text(
                    widget.text,
                    key: ValueKey(widget.text),
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The little tail on the bubble's lower-left corner, pointing at the mascot.
class _BubbleTail extends CustomPainter {
  _BubbleTail({required this.color, required this.border});

  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 14;
    final path =
        Path()
          ..moveTo(1, y)
          ..lineTo(-9, y + 10)
          ..lineTo(1, y + 8)
          ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      Path()
        ..moveTo(0.5, y)
        ..lineTo(-9, y + 10)
        ..lineTo(0.5, y + 8),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BubbleTail old) =>
      old.color != color || old.border != border;
}
