import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/responder_incident_model.dart';
import '../domain/responder_provider.dart';
import 'widgets/responder_action_sheets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The screen a dispatch assignment takes over the phone with.
///
/// WHY A WHOLE SCREEN AND NOT A BANNER
///
/// The previous design notified and hoped. A heads-up banner reaches a
/// responder who is already looking at their phone — which is precisely the
/// responder who did not need telling. Everyone else got a line of text that
/// slid past a dark screen in a pocket.
///
/// This is modelled on an incoming call, because that is what it is: a summons
/// that expects an answer within a known number of seconds, from someone who
/// is not currently holding the device. It shows only what a crew needs to
/// decide — how bad, what kind, where, how far into the window — and gives
/// them exactly two answers.
///
/// TWO BUTTONS, AND THE SECOND ONE MATTERS MOST
///
/// It would be easy to ship only ACCEPT. But a screen with one button trains
/// people to press it, and an acceptance pressed to make an alarm stop is
/// worse than no acceptance at all — the board now shows a crew committed to a
/// call nobody is driving to. CAN'T RESPOND has to be equally reachable, or
/// the data this whole feature produces is fiction.
///
/// THE COUNTDOWN IS NOT A THREAT
///
/// It shows the same window the dispatcher's board is watching, so a crew
/// knows when their silence is about to become somebody else's problem.
/// Nothing happens to them when it expires; the incident simply turns loud on
/// the board and a human reassigns it. Running out is a normal outcome, not a
/// failure, and the copy at the bottom says so.
class IncidentAlertScreen extends StatefulWidget {
  const IncidentAlertScreen({
    super.key,
    required this.incident,
    this.onDismissed,
  });

  final ResponderIncidentModel incident;

  /// Called after either answer, so the caller can cancel the OS notification
  /// — which is `ongoing` with FLAG_INSISTENT and will otherwise keep sounding
  /// after the crew has already answered.
  final VoidCallback? onDismissed;

  @override
  State<IncidentAlertScreen> createState() => _IncidentAlertScreenState();
}

class _IncidentAlertScreenState extends State<IncidentAlertScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  Timer? _tick;
  late int _secondsWaiting;
  bool _answering = false;

  @override
  void initState() {
    super.initState();
    _secondsWaiting = widget.incident.ack.secondsWaiting ?? 0;

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // One second, locally, anchored to the server's number rather than to a
    // deadline computed here. See ResponderAck: the phone and the dispatcher
    // board must never disagree about this clock.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsWaiting++);
    });

    // A repeating haptic for the case the handset is on silent AND the
    // full-screen intent was degraded to a banner by Android 14's grant. Belt
    // and braces on the one alert in this product that must not be missed.
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  int get _deadline => widget.incident.ack.deadlineSeconds;
  int get _remaining => (_deadline - _secondsWaiting).clamp(0, 9999);
  bool get _overdue => _remaining <= 0;

  Future<void> _accept() async {
    if (_answering) return;
    setState(() => _answering = true);
    final provider = context.read<ResponderProvider>();
    final ok = await provider.acceptIncident(widget.incident.id);
    if (!mounted) return;
    if (ok) {
      widget.onDismissed?.call();
      Navigator.of(context).pop(true);
    } else {
      setState(() => _answering = false);
      _showError(
        provider.answerError ??
            AppLocalizations.of(context).respAnswerSendFailed,
      );
    }
  }

  Future<void> _decline() async {
    if (_answering) return;
    final choice = await DeclineSheet.show(context);
    if (choice == null || !mounted) return;

    setState(() => _answering = true);
    final provider = context.read<ResponderProvider>();
    final ok = await provider.declineIncident(
      widget.incident.id,
      reason: choice.$1,
      note: choice.$2,
    );
    if (!mounted) return;
    if (ok) {
      widget.onDismissed?.call();
      Navigator.of(context).pop(false);
    } else {
      setState(() => _answering = false);
      _showError(
        provider.answerError ??
            AppLocalizations.of(context).respAnswerSendFailed,
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ZirenTokens.systemError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final incident = widget.incident;
    final severity = (incident.severity ?? '').toLowerCase();
    final accent = switch (severity) {
      'critical' => ZirenTokens.severityCritical,
      'high' => ZirenTokens.severityHigh,
      'medium' => ZirenTokens.severityMedium,
      'low' => ZirenTokens.severityLow,
      // Untriaged is not low priority — it is an incident the rubric could not
      // read, and it carries the strictest deadline. Brand orange rather than
      // a severity colour, because claiming a severity here would be a lie.
      _ => ZirenTokens.brandOrange,
    };

    // PopScope with canPop:false. The back gesture must not dismiss this —
    // swiping away a dispatch alert would leave the board showing an
    // unanswered assignment with no record that anyone ever saw it.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1016),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: ZirenTokens.space24),

              // ── The countdown ring ────────────────────────────
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final scale =
                          _overdue ? 1.0 : 1.0 + (_pulse.value * 0.04);
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 240,
                            height: 240,
                            child: CircularProgressIndicator(
                              value:
                                  _overdue
                                      ? 1.0
                                      : (_secondsWaiting / _deadline).clamp(
                                        0.0,
                                        1.0,
                                      ),
                              strokeWidth: 10,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.10,
                              ),
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                severity.isEmpty
                                    ? t.respUntriaged
                                    : severity.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: ZirenTokens.space8),
                              Text(
                                _overdue ? t.respOverdue : '$_remaining',
                                style: TextStyle(
                                  fontSize: _overdue ? 30 : 64,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                  color: Colors.white,
                                ),
                              ),
                              if (!_overdue)
                                Text(
                                  t.respSeconds,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
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

              // ── What and where ────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space24,
                ),
                child: Column(
                  children: [
                    if (incident.sosFlag)
                      Container(
                        margin: const EdgeInsets.only(
                          bottom: ZirenTokens.space12,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZirenTokens.space12,
                          vertical: ZirenTokens.space6,
                        ),
                        decoration: BoxDecoration(
                          color: ZirenTokens.severityCritical,
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius32,
                          ),
                        ),
                        child: const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    Text(
                      incident.categoryLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.map_pin,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: ZirenTokens.space4),
                        Flexible(
                          child: Text(
                            incident.locationAddress ??
                                incident.landmarkNote ??
                                'Walang address na naitala',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (incident.landmarkNote != null &&
                        incident.locationAddress != null) ...[
                      const SizedBox(height: ZirenTokens.space4),
                      Text(
                        t.respLandmarkPrefix(incident.landmarkNote!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: ZirenTokens.space24),

              // ── The two answers ───────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZirenTokens.space24,
                  0,
                  ZirenTokens.space24,
                  ZirenTokens.space16,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 68,
                      child: ElevatedButton.icon(
                        onPressed: _answering ? null : _accept,
                        icon:
                            _answering
                                ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                : const Icon(LucideIcons.check, size: 28),
                        label: Text(
                          _answering ? '...' : t.respAccept,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZirenTokens.systemSuccess,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ZirenTokens.radius16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _answering ? null : _decline,
                        icon: const Icon(LucideIcons.x, size: 22),
                        label: Text(
                          t.respDeclineLong,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ZirenTokens.radius16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space12),
                    Text(
                      _overdue
                          ? 'Nakikita na ito ng dispatcher bilang walang sagot. '
                              'Puwede mo pa ring tanggapin.'
                          : 'Kapag walang sagot, babalik ito sa dispatcher '
                              'para may maipadala silang iba.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
