import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';

/// The calm-state hero — what Home is when nothing is happening.
///
/// The counterpart to LiveIncidentPanel. Almost every session opens here, so
/// it is deliberately quiet: one dominant control, one line of reassurance,
/// and nothing competing for attention. The old home stacked a readiness
/// strip, an SOS card, a report button, a quick-action grid, an active strip
/// and a report list on one screen — six blocks all asking to be read, which
/// is exactly the "same as every other app" shape.
///
/// The SOS ring is drawn rather than boxed. A rectangle with a label reads as
/// a form control; a large physical target reads as a thing you hit without
/// looking, which is what it is for.
class ReadyPanel extends StatelessWidget {
  const ReadyPanel({
    super.key,
    required this.message,
    required this.pulse,
    required this.isBusy,
    required this.onSos,
    required this.coverageLine,
    required this.isOffline,
  });

  final String message;
  final Animation<double> pulse;
  final bool isBusy;
  final VoidCallback onSos;

  /// One line naming who is actually covering this resident right now.
  final String coverageLine;

  /// The dot beside [coverageLine] used to be hardcoded green, so the pill
  /// read a success-coloured dot even while offline. On a screen whose whole
  /// job is telling someone whether help can reach them, a status light that
  /// always says "fine" is worse than none.
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: ZirenTokens.textSecondary,
          ),
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── SOS ─────────────────────────────────────────
        Semantics(
          button: true,
          label: 'SOS. Emergency. Double tap to send an immediate alert.',
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: isBusy ? null : onSos,
              child: AnimatedBuilder(
                animation: pulse,
                builder: (_, child) {
                  final t = pulse.value;
                  return SizedBox(
                    width: 250,
                    height: 250,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Two offset halos rather than one, so the pulse reads
                        // as a heartbeat instead of a loading spinner.
                        _Halo(scale: 0.72 + 0.28 * t, opacity: 0.16 * (1 - t)),
                        _Halo(
                          scale: 0.72 + 0.28 * ((t + 0.5) % 1.0),
                          opacity: 0.10 * (1 - ((t + 0.5) % 1.0)),
                        ),
                        child!,
                      ],
                    ),
                  );
                },
                child: Container(
                  width: 178,
                  height: 178,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // severityCritical, not brand orange: this button means
                    // "critical emergency", and that is precisely the token
                    // reserved for it.
                    color:
                        isBusy
                            ? ZirenTokens.severityCritical.withValues(
                              alpha: 0.55,
                            )
                            : ZirenTokens.severityCritical,
                    boxShadow: [
                      BoxShadow(
                        color: ZirenTokens.severityCritical.withValues(
                          alpha: 0.32,
                        ),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isBusy)
                        const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      else ...[
                        const Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'EMERGENCY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85),
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: ZirenTokens.space20),

        // ── Coverage ────────────────────────────────────
        //
        // Naming the station that covers you is the reassurance. "You are
        // protected" is marketing; "MDRRMO Naval, 2.1 km away" is a fact.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space10,
          ),
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceCard,
            borderRadius: BorderRadius.circular(ZirenTokens.radius32),
            border: Border.all(color: ZirenTokens.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isOffline
                          ? ZirenTokens.systemWarning
                          : ZirenTokens.systemSuccess,
                ),
              ),
              const SizedBox(width: ZirenTokens.space8),
              Flexible(
                child: Text(
                  coverageLine,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: ZirenTokens.space12),
        Text(
          AppLocalizations.of(context).readyPanelFalseReportWarning,
          style: TextStyle(fontSize: 11.5, color: ZirenTokens.textMuted),
        ),
      ],
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.scale, required this.opacity});
  final double scale;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250 * scale,
      height: 250 * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ZirenTokens.severityCritical.withValues(alpha: opacity),
      ),
    );
  }
}
