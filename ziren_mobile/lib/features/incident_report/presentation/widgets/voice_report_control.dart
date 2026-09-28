import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../data/voice_note_service.dart';
import '../../domain/incident_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The resident says what happened, and the station hears it.
///
/// The recording is sent as-is. A dispatcher in Naval who speaks Waray
/// understands it perfectly, which no transcription of Waray currently manages
/// — that is the whole point of carrying the audio.
///
/// This deliberately does NOT transcribe at the same time. Starting the
/// platform recogniser alongside the encoder was measured on a real handset and
/// produced a 4,257-byte file: about one second, then the recogniser took the
/// microphone. The card appeared, the resident believed the station could hear
/// them, and playback lasted 60 ms. One or the other, not both — and between a
/// recording that is true and a transcript that might not be, the recording
/// wins. The typed field above still ranks the queue.
class VoiceReportControl extends StatefulWidget {
  const VoiceReportControl({super.key});

  @override
  State<VoiceReportControl> createState() => _VoiceReportControlState();
}

class _VoiceReportControlState extends State<VoiceReportControl>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _playing = false;

  // Rings breathe outward for as long as the mic is actually capturing —
  // same language as the SOS button's on-duty pulse on Home (see
  // home_kit.dart's RadialActionDial), reused here rather than invented
  // fresh so "this control is live right now" means the same thing
  // everywhere in the app. Runs only while recording; idle stays still.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start(IncidentProvider p) async {
    await _player.stop();
    setState(() {
      _elapsed = Duration.zero;
      _playing = false;
    });
    await p.startVoiceNote();
    if (mounted && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _pulse.repeat();
    }

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= VoiceNoteService.maxDuration) _stop(p);
    });
  }

  Future<void> _stop(IncidentProvider p) async {
    _ticker?.cancel();
    _ticker = null;
    _pulse.stop();
    _pulse.reset();
    // The length is handed to the provider rather than kept here. This widget
    // is rebuilt whenever the screen is, and a recording that outlives one
    // build was rendering as "0:00" while a real file sat behind it.
    await p.stopVoiceNote(length: _elapsed);
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback(String path) async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(DeviceFileSource(path));
    if (mounted) setState(() => _playing = true);
  }

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _ring(double diameter, Color color) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = context.watch<IncidentProvider>();
    final recording = p.isRecordingVoice;
    final note = p.voiceNote;
    final maxMinutes = VoiceNoteService.maxDuration.inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Circular record button ────────────────────────────
        // Centred, not a full-width bar: this is the one control the
        // resident is most likely to reach for one-handed, and a big
        // circular target reads as "the microphone" the way a bar with an
        // icon on it does not. Bigger than the old 96px/36px pairing — this
        // is the primary way of telling a station what happened, and it
        // should read as the most important control on the screen, not one
        // among equals with the typed field below it.
        Center(
          child: GestureDetector(
            onTap: () => recording ? _stop(p) : _start(p),
            child: Column(
              children: [
                SizedBox(
                  // Room for the outermost ring at its largest extent
                  // (button * 1.5) so the animation never clips against
                  // neighbouring content.
                  width: 132,
                  height: 132,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (recording)
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) {
                            final v = _pulse.value;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                _ring(
                                  108 * (0.85 + 0.65 * v),
                                  ZirenTokens.severityCritical.withValues(
                                    alpha: 0.16 * (1 - v),
                                  ),
                                ),
                                _ring(
                                  108 * (0.85 + 0.35 * v),
                                  ZirenTokens.severityCritical.withValues(
                                    alpha: 0.22 * (1 - v),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      AnimatedContainer(
                        duration: ZirenTokens.motionPress,
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              recording
                                  ? ZirenTokens.severityCritical
                                  : ZirenTokens.brandOrange,
                          boxShadow: ZirenTokens.shadowMd,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          recording ? LucideIcons.square : LucideIcons.mic,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZirenTokens.space10),
                Text(
                  recording ? _clock(_elapsed) : t.voiceTapToRecord,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recording
                      ? t.voiceTapToStop
                      : t.voiceUpToMinutes(maxMinutes),
                  style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
                ),
              ],
            ),
          ),
        ),

        if (!recording && note == null && !p.voiceCaptureFailed)
          Padding(
            padding: const EdgeInsets.only(top: ZirenTokens.space10),
            child: Text(
              t.voiceRecordingHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
            ),
          ),

        if (!recording && note != null) ...[
          const SizedBox(height: ZirenTokens.space12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ZirenTokens.space8,
              vertical: ZirenTokens.space8,
            ),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceCard,
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              border: Border.all(color: ZirenTokens.surfaceBorder),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _playing ? LucideIcons.pause : LucideIcons.play,
                    color: ZirenTokens.brandOrange,
                  ),
                  tooltip: _playing ? t.voicePause : t.voicePlay,
                  onPressed: () => _togglePlayback(note.path),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.voiceRecorded(_clock(p.voiceNoteLength)),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      Text(
                        t.voiceWillSend,
                        style: TextStyle(
                          fontSize: 12,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash),
                  color: ZirenTokens.textMuted,
                  tooltip: t.voiceDeleteTooltip,
                  onPressed: () async {
                    await _player.stop();
                    await p.discardVoiceNote();
                    if (mounted) {
                      setState(() {
                        _playing = false;
                        _elapsed = Duration.zero;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],

        // Two different failures, two different instructions, and never both
        // at once. Showing "hindi na-record" beside a playable recording —
        // which is what a leftover note from the previous report produced —
        // tells the resident to redo something that already worked.
        if (!recording && note == null && p.voiceCaptureFailed) ...[
          const SizedBox(height: ZirenTokens.space8),
          Text(
            t.voiceCaptureFailedMsg,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: ZirenTokens.severityCritical),
          ),
        ],

        if (!recording && p.voiceUploadFailed) ...[
          const SizedBox(height: ZirenTokens.space8),
          Text(
            t.voiceUploadFailedMsg,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: ZirenTokens.severityCritical),
          ),
        ],
      ],
    );
  }
}
