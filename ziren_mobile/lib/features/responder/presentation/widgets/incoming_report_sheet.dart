import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../domain/responder_incident_model.dart';
import '../../domain/responder_vocabulary.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// What the responder did with the dialog.
enum IncomingReportChoice {
  /// Opened the assignment. The alarm stops and the full alert takes over,
  /// where ACCEPT and CAN'T RESPOND live.
  view,

  /// Closed the dialog without opening it. The alarm stops; the assignment
  /// stays in the queue, unanswered.
  dismiss,
}

/// The centered dialog that announces a new assignment, ported from the
/// ResQLink prototype's incoming-report modal.
///
/// WHY A SMALL DIALOG AND NOT THE FULL-SCREEN ALERT
///
/// Both exist, and they answer different questions.
///
/// This is the DOORBELL. It arrives over whatever the responder is looking at,
/// says what came in and where, and asks only whether they want to look. It is
/// deliberately small: a responder mid-way through closing another incident
/// should not have their screen replaced to be told a second one landed.
///
/// [IncidentAlertScreen] is the ANSWER. It takes the whole screen, runs the
/// countdown the dispatcher's board is watching, and offers the two replies
/// that change what the board shows. That screen is reached from here, and
/// from the OS notification's full-screen intent when the phone is in a
/// pocket.
///
/// Keeping them separate is what lets the doorbell be gentle without making
/// the answer optional.
///
/// DISMISS IS NOT DECLINE, AND THE COPY SAYS SO
///
/// The prototype's "Dismiss" button sits beside "View & Respond" with nothing
/// to say which one the dispatcher hears about. Here, dismissing silences the
/// alarm and closes the dialog, and the assignment stays exactly where it was —
/// unanswered, still in the queue, still counting against the ack window. A
/// responder who thinks "Not now" told the dispatcher anything would be
/// leaving a call uncovered while believing they had handed it back, so the
/// line under the buttons states the truth plainly.
///
/// NO "AI 97%"
///
/// The prototype draws a confidence percentage on the bar. Ziren's rubric
/// returns a tier, not a confidence. See [ResponderVocabulary.fill].
class IncomingReportSheet extends StatefulWidget {
  const IncomingReportSheet({super.key, required this.incident});

  final ResponderIncidentModel incident;

  /// Raise the dialog. Resolves to what the responder chose — including
  /// [IncomingReportChoice.dismiss] when they tap the scrim or the back
  /// button, so the caller always gets an answer and can always stop the alarm.
  static Future<IncomingReportChoice> show(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final choice = await showDialog<IncomingReportChoice>(
      context: context,
      // Barrier taps are allowed: the alarm is loud and the escape has to be
      // as easy as the answer, or the habit this teaches is to silence the
      // phone before a shift.
      barrierDismissible: true,
      builder: (_) => IncomingReportSheet(incident: incident),
    );
    return choice ?? IncomingReportChoice.dismiss;
  }

  @override
  State<IncomingReportSheet> createState() => _IncomingReportSheetState();
}

class _IncomingReportSheetState extends State<IncomingReportSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incident;
    final tint = ResponderVocabulary.color(i.severity);

    // Respect the system "reduce motion" setting. A pulsing dot is decoration;
    // a responder who has asked their phone to stop animating things has
    // usually asked for a reason.
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space20,
        vertical: ZirenTokens.space24,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceOverlay,
          borderRadius: BorderRadius.all(Radius.circular(ZirenTokens.radius24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space20,
          ZirenTokens.space20,
          ZirenTokens.space20,
          ZirenTokens.space20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Label row ──────────────────────────────────────
            Row(
              children: [
                _PulsingDot(
                  controller: _pulse,
                  color: tint,
                  still: reduceMotion,
                ),
                const SizedBox(width: ZirenTokens.space8),
                Expanded(
                  child: Text(
                    'INCOMING REPORT',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
                _CloseButton(
                  onTap:
                      () => Navigator.of(
                        context,
                      ).pop(IncomingReportChoice.dismiss),
                ),
              ],
            ),
            const SizedBox(height: ZirenTokens.space12),

            // ── The report ─────────────────────────────────────
            _ReportCard(incident: i, tint: tint),
            const SizedBox(height: ZirenTokens.space12),

            // The sentence that keeps "Not now" from reading as a decline.
            Text(
              'Not now only silences this. The assignment stays in your list '
              'until you accept or send it back.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space16),

            // ── The two answers ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Not now',
                    filled: false,
                    onTap:
                        () => Navigator.of(
                          context,
                        ).pop(IncomingReportChoice.dismiss),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  flex: 2,
                  child: _SheetButton(
                    label: 'View & respond',
                    filled: true,
                    onTap:
                        () => Navigator.of(
                          context,
                        ).pop(IncomingReportChoice.view),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────

/// The prototype's blinking dot beside the label.
class _PulsingDot extends StatelessWidget {
  const _PulsingDot({
    required this.controller,
    required this.color,
    required this.still,
  });

  final AnimationController controller;
  final Color color;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (still) return dot;

    return FadeTransition(
      opacity: Tween<double>(
        begin: 1.0,
        end: 0.25,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut)),
      child: dot,
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      child: Container(
        // 32px of visible circle, but the InkWell + padding give it a touch
        // target at the 44px minimum. A close button that is hard to hit on a
        // sounding alarm is the definition of a hostile control.
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: Icon(
          LucideIcons.x,
          size: 18,
          color: ZirenTokens.textSecondary,
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.incident, required this.tint});

  final ResponderIncidentModel incident;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final where = i.locationAddress ?? i.stationName ?? 'Location unknown';

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ResponderVocabulary.background(i.severity),
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceCard,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                ),
                child: Icon(
                  ResponderVocabulary.icon(i.severity),
                  size: 19,
                  color: tint,
                ),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            i.categoryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space6),
                        Text(
                          ResponderVocabulary.label(i.severity),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            color: tint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      where,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),

          // ── Chips ──────────────────────────────────────────
          Wrap(
            spacing: ZirenTokens.space6,
            runSpacing: ZirenTokens.space6,
            children: [
              _Chip(text: i.shortId),
              if (i.reporterName != null && i.reporterName!.isNotEmpty)
                _Chip(text: 'From ${i.reporterName}'),
              _Chip(text: ResponderVocabulary.elapsed(i.createdAt)),
              if (i.sosFlag)
                _Chip(
                  text: 'SOS',
                  tint: ZirenTokens.severityCritical,
                  icon: LucideIcons.megaphone,
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),

          // ── Severity bar ───────────────────────────────────
          //
          // The prototype's bar, without the invented percentage. The tier is
          // written beside it so the bar never carries the meaning alone.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: ResponderVocabulary.fill(i.severity),
                    ),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder:
                        (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 5,
                          backgroundColor: ZirenTokens.surfaceCard,
                          valueColor: AlwaysStoppedAnimation<Color>(tint),
                        ),
                  ),
                ),
              ),
              const SizedBox(width: ZirenTokens.space8),
              Text(
                'Severity',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.tint, this.icon});

  final String text;
  final Color? tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? ZirenTokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Brand orange, not severity red, even on a critical call. Orange is this
    // product's action colour and red means "critical severity" everywhere
    // else in it; a red button here would be the only red in the app that is
    // not a severity, and the responder reading it fast has no way to know
    // which meaning applies. The severity keeps the card.
    return Material(
      color: filled ? ZirenTokens.brandOrange : ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            border:
                filled
                    ? null
                    : Border.all(color: ZirenTokens.surfaceBorder, width: 1.4),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color:
                  filled ? ZirenTokens.textInverse : ZirenTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
