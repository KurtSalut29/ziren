import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:intl/intl.dart';

import '../theme/app_tokens.dart';
import 'home_kit.dart' show kHomeGutter;

/// Top of Home, resident and responder alike: the tagline with the
/// bell and profile buttons, today's date, a large greeting, and the mascot
/// speaking to the user in a tinted card.
///
/// The mascot card is where the status the old photo banner carried now
/// lives - location and connection ride under the mascot's message as two
/// small chips, so nothing a resident used to glance at up top is lost.
class MascotHomeHeader extends StatelessWidget {
  const MascotHomeHeader({
    super.key,
    required this.tagline,
    required this.hasUnread,
    required this.onBellTap,
    required this.bellLabel,
    required this.bellLabelUnread,
    required this.displayName,
    required this.onProfileTap,
    required this.profileLabel,
    this.avatarUrl,
    required this.greeting,
    required this.greetingName,
    required this.mascot,
    required this.mascotName,
    required this.message,
    required this.locationLabel,
    required this.connectivityLabel,
    required this.connectivityIcon,
    required this.connectivityColor,
  });

  final String tagline;
  final bool hasUnread;
  final VoidCallback onBellTap;
  final String bellLabel;
  final String bellLabelUnread;

  /// Full name, for the profile button's initials.
  final String displayName;
  final VoidCallback onProfileTap;
  final String profileLabel;
  final String? avatarUrl;

  /// The whole greeting ("Good morning, Kurt!") and the part of it drawn in
  /// the brand colour ("Kurt").
  final String greeting;
  final String greetingName;

  /// The mascot, drawn waving; [MascotArt.resident] or [MascotArt.responder].
  final MascotArt mascot;
  final String mascotName;
  final String message;
  final String locationLabel;
  final String connectivityLabel;
  final IconData connectivityIcon;
  final Color connectivityColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space12,
        kHomeGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // No "Ziren" wordmark here (the user took it out): the mascot
              // card already says "Hi! I'm Ziren", so the top row carries
              // only the tagline beside the bell and profile buttons.
              Expanded(
                child: Text(
                  tagline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: ZirenTokens.space12),
              _BellButton(
                hasUnread: hasUnread,
                onTap: onBellTap,
                label: hasUnread ? bellLabelUnread : bellLabel,
              ),
              const SizedBox(width: ZirenTokens.space10),
              _ProfileButton(
                displayName: displayName,
                avatarUrl: avatarUrl,
                onTap: onProfileTap,
                label: profileLabel,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space20),
          Text(
            _today(context),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: ZirenTokens.brandOrange,
            ),
          ),
          const SizedBox(height: ZirenTokens.space6),
          Text.rich(
            _greetingSpans(),
            style: TextStyle(
              fontSize: 30,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.9,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space16),
          _MascotCard(
            mascot: mascot,
            mascotName: mascotName,
            message: message,
            chips: [
              _StatusChip(
                icon: LucideIcons.map_pin,
                iconColor: ZirenTokens.brandOrange,
                label: locationLabel,
              ),
              _StatusChip(
                icon: connectivityIcon,
                iconColor: connectivityColor,
                label: connectivityLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "WEDNESDAY, SEPTEMBER 30" in the app's language.
  String _today(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toLanguageTag();
    try {
      return DateFormat.MMMMEEEEd(locale).format(now).toUpperCase();
    } catch (_) {
      // Date names not loaded for this locale (tests, an unusual system
      // locale): the Material date is always there.
      return MaterialLocalizations.of(
        context,
      ).formatFullDate(now).toUpperCase();
    }
  }

  TextSpan _greetingSpans() {
    final at = greetingName.isEmpty ? -1 : greeting.indexOf(greetingName);
    if (at < 0) return TextSpan(text: greeting);
    return TextSpan(
      children: [
        TextSpan(text: greeting.substring(0, at)),
        TextSpan(
          text: greetingName,
          style: const TextStyle(color: ZirenTokens.brandOrange),
        ),
        TextSpan(text: greeting.substring(at + greetingName.length)),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.hasUnread,
    required this.onTap,
    required this.label,
  });

  final bool hasUnread;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: ZirenTokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          side: BorderSide(color: ZirenTokens.surfaceBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  LucideIcons.bell,
                  size: 22,
                  color: ZirenTokens.textPrimary,
                ),
                if (hasUnread)
                  Positioned(
                    top: 11,
                    right: 12,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        // Orange, not red: an unread notice is not an alarm,
                        // and red is kept for critical severity.
                        color: ZirenTokens.brandOrange,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ZirenTokens.surfaceCard,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.displayName,
    required this.avatarUrl,
    required this.onTap,
    required this.label,
  });

  final String displayName;
  final String? avatarUrl;
  final VoidCallback onTap;
  final String label;

  String get _initials {
    final words =
        displayName
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final last = words.length > 1 ? words.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = Center(
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color:
              ZirenTokens.isDark
                  ? ZirenTokens.brandOrange
                  : ZirenTokens.brandActive,
        ),
      ),
    );
    final url = avatarUrl;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: ZirenTokens.brandSubtle,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 50,
            height: 50,
            child:
                url == null || url.isEmpty
                    ? initials
                    : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => initials,
                    ),
          ),
        ),
      ),
    );
  }
}

/// A mascot drawn as two layers so its raised hand can wave: the body, and
/// the hand with its wrist cuff (both full-canvas, so they stack exactly).
/// Made from the single mascot image by scratchpad split_hand.py; [pivot] is
/// the centre of the cuff, where the hand turns.
class MascotArt {
  const MascotArt({
    required this.body,
    required this.hand,
    required this.pivot,
    required this.size,
  });

  final String body;
  final String hand;
  final Alignment pivot;
  final Size size;

  static const resident = MascotArt(
    body: 'assets/images/mascot_resident_body.png',
    hand: 'assets/images/mascot_resident_hand.png',
    pivot: Alignment(0.7382, -0.2259),
    size: Size(359, 540),
  );

  static const responder = MascotArt(
    body: 'assets/images/mascot_responder_body.png',
    hand: 'assets/images/mascot_responder_hand.png',
    pivot: Alignment(-0.6287, -0.1630),
    size: Size(334, 540),
  );
}

/// The mascot waving: a few back-and-forth turns of the hand at the start of
/// every [kMascotLoop] (while "Hi! I'm Ziren" is being typed), then still.
class _WavingMascot extends StatefulWidget {
  const _WavingMascot({required this.art});

  final MascotArt art;

  @override
  State<_WavingMascot> createState() => _WavingMascotState();
}

class _WavingMascotState extends State<_WavingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: kMascotLoop,
  );

  /// The wave lasts the first 2 s of the loop: 2.5 swings, ±16° (the widest the wrist join stays hidden).
  static const double _waveEnd = 0.4;
  static const double _swings = 2.5;
  static const double _maxAngle = 16 * math.pi / 180;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop
        ..stop()
        ..value = 0.5; // hand at rest
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  double _angle(double t) {
    if (t >= _waveEnd) return 0;
    final p = t / _waveEnd;
    // Grows in and dies away (the sine envelope), so the hand never jumps.
    return _maxAngle *
        math.sin(2 * math.pi * _swings * p) *
        math.sin(math.pi * p);
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    // Both layers at the art's own size inside one FittedBox, so the pivot
    // (a fraction of the art) lands on the cuff whatever size the card is.
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      child: SizedBox.fromSize(
        size: art.size,
        child: Stack(
          // The turning hand may reach past the art's edge.
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.asset(art.body, excludeFromSemantics: true),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _loop,
                builder:
                    (context, hand) => Transform.rotate(
                      angle: _angle(_loop.value),
                      alignment: art.pivot,
                      child: hand,
                    ),
                child: Image.asset(art.hand, excludeFromSemantics: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MascotCard extends StatelessWidget {
  const _MascotCard({
    required this.mascot,
    required this.mascotName,
    required this.message,
    required this.chips,
  });

  final MascotArt mascot;
  final String mascotName;
  final String message;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space8,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space12,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.brandSubtle,
        borderRadius: BorderRadius.circular(ZirenTokens.radius24),
      ),
      child: Row(
        children: [
          SizedBox(width: 108, height: 150, child: _WavingMascot(art: mascot)),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypewriterText(
                  text: mascotName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color:
                        ZirenTokens.isDark
                            ? ZirenTokens.brandOrange
                            : ZirenTokens.brandActive,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space12),
                Wrap(
                  spacing: ZirenTokens.space6,
                  runSpacing: ZirenTokens.space6,
                  children: chips,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How often the mascot's greeting is typed out again, and how often the help
/// label pops in and out. One period for both, so Home moves in one rhythm.
const Duration kMascotLoop = Duration(seconds: 5);

/// The mascot's "Hi! I'm Ziren", typed out letter by letter with a cursor,
/// held, then erased, every [kMascotLoop].
///
/// A screen reader hears the whole line once; with "Remove animations" on
/// in the phone's settings, the line simply stands still.
class _TypewriterText extends StatefulWidget {
  const _TypewriterText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: kMascotLoop,
  );

  // Fractions of one loop: type, hold (cursor blinking), erase.
  static const double _typeEnd = 0.30;
  static const double _eraseStart = 0.88;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop
        ..stop()
        ..value = 0.5; // fully written
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters;
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _loop,
          builder: (context, _) {
            final t = _loop.value;
            final int shown;
            final bool cursor;
            if (!_loop.isAnimating) {
              shown = chars.length;
              cursor = false;
            } else if (t < _typeEnd) {
              shown = (t / _typeEnd * chars.length).ceil();
              cursor = true;
            } else if (t < _eraseStart) {
              shown = chars.length;
              // Blinks about twice a second while the line is held.
              cursor =
                  ((t - _typeEnd) * kMascotLoop.inMilliseconds ~/ 500).isEven;
            } else {
              final left = 1 - (t - _eraseStart) / (1 - _eraseStart);
              shown = (left * chars.length).floor();
              cursor = true;
            }
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: chars.take(shown).toString()),
                  // Always laid out, only its colour changes, so the line
                  // never jumps as the cursor blinks.
                  TextSpan(
                    text: '|',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color:
                          cursor ? widget.style.color : const Color(0x00000000),
                    ),
                  ),
                ],
              ),
              style: widget.style,
              maxLines: 1,
            );
          },
        ),
      ),
    );
  }
}

/// Location or connection, under the mascot's message.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space10,
        vertical: ZirenTokens.space4 + 1,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: ZirenTokens.space4),
          // A live address can be long; the chip never grows past the card.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Ziren mascot's head in a round button with its label ("Ask Ziren for
/// help") beside it, bottom-right of Home above the navigation bar: opens
/// "How to use Ziren". Label and head are one button.
///
/// The label pops out of the head, stays, and pops back in, every
/// [kMascotLoop]; the head itself never moves, so there is always something
/// to tap. With "Remove animations" on, the label just stays.
class ZirenHelpButton extends StatefulWidget {
  const ZirenHelpButton({
    super.key,
    required this.onPressed,
    required this.label,
  });

  final VoidCallback onPressed;
  final String label;

  static const double size = 66;

  @override
  State<ZirenHelpButton> createState() => _ZirenHelpButtonState();
}

class _ZirenHelpButtonState extends State<ZirenHelpButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: kMascotLoop,
  );

  // Fractions of one loop: pop out of the head, stay, pop back in, rest.
  // Out over 0.9 s, back in over 0.8 s: slow enough to read as a bubble
  // growing, not a flicker (0.45 s each felt too quick on the phone).
  static const double _popInEnd = 0.18;
  static const double _popOutStart = 0.72;
  static const double _popOutEnd = 0.88;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop
        ..stop()
        ..value = 0.5; // label showing
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  double _scale(double t) {
    if (t < _popInEnd) return Curves.easeOutBack.transform(t / _popInEnd);
    if (t < _popOutStart) return 1;
    if (t < _popOutEnd) {
      final out = Curves.easeInBack.transform(
        (t - _popOutStart) / (_popOutEnd - _popOutStart),
      );
      return (1 - out).clamp(0.0, 1.2);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    final label = widget.label;
    return Semantics(
      button: true,
      label: label,
      // The children's own tap actions are excluded with them, so the
      // screen reader's double-tap needs this one.
      onTap: onPressed,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The label, tucked under the head's halo so the two read as one
          // speech bubble: says what the mascot is for before anyone taps.
          // It grows from the head's edge (centerRight), like a bubble.
          AnimatedBuilder(
            animation: _loop,
            builder: (context, bubble) {
              final scale = _scale(_loop.value);
              return IgnorePointer(
                // Not tappable while it is (nearly) gone.
                ignoring: scale < 0.5,
                child: Opacity(
                  opacity: scale.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.centerRight,
                    child: bubble,
                  ),
                ),
              );
            },
            child: Transform.translate(
              offset: const Offset(14, 0),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: ZirenTokens.surfaceCard,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: ZirenTokens.brandOrange.withValues(alpha: 0.35),
                    ),
                  ),
                  // A soft lift, not a Material elevation: that draws a hard
                  // grey rim around a white pill on the light canvas.
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPressed,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ZirenTokens.space16,
                        ZirenTokens.space10,
                        ZirenTokens.space16 + 14,
                        ZirenTokens.space10,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _head(onPressed),
        ],
      ),
    );
  }

  Widget _head(VoidCallback onPressed) {
    return Container(
      width: ZirenHelpButton.size,
      height: ZirenHelpButton.size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        // A soft brand halo, so the button reads as floating above the page.
        color: ZirenTokens.brandOrange.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ZirenTokens.brandOrange.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: ZirenTokens.surfaceCard,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Image.asset(
              'assets/images/mascot_help.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
