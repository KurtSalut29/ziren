import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../data/responder_repository.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// The resident's own recording, playable by the crew going to the scene.
///
/// WHY THE CREW NEEDS THIS AND NOT JUST THE TRANSCRIPT
///
/// The report text on this screen is, for a voice report, machine
/// transcription of Waray or Cebuano — languages the recogniser was not
/// trained on and gets wrong in ways that change meaning. The whole reason
/// dispatchers can correct transcripts is that the words on screen are not
/// reliably the words that were said.
///
/// The dispatcher console has been able to play this recording since Phase 6.
/// The responder could not, which is backwards: the dispatcher is reading a
/// screen, and the responder is about to walk into whatever the caller was
/// describing. Anyone who can hear the difference between "duha ka motor" and
/// what the transcript made of it should be able to hear it, and the person
/// closest to the emergency should be first in that queue, not last.
///
/// The links are signed and expire in five minutes, so they are fetched when
/// this widget is built rather than cached with the incident.
class ResponderVoiceNote extends StatefulWidget {
  const ResponderVoiceNote({super.key, required this.incidentId});

  final String incidentId;

  @override
  State<ResponderVoiceNote> createState() => _ResponderVoiceNoteState();
}

class _ResponderVoiceNoteState extends State<ResponderVoiceNote> {
  final _repo = ResponderRepository();
  final _player = AudioPlayer();

  List<Map<String, dynamic>> _media = const [];
  bool _loading = true;
  bool _failed = false;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.getIncidentMedia(widget.incidentId);
      if (!mounted) return;
      setState(() {
        _media = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A failure here is reported, not hidden. An absent player and a broken
      // player look identical on screen, and the difference matters: one means
      // the resident typed their report, the other means there is a recording
      // this crew is not hearing.
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String url) async {
    if (_playingUrl == url) {
      await _player.stop();
      if (mounted) setState(() => _playingUrl = null);
      return;
    }
    await _player.stop();
    await _player.play(UrlSource(url));
    if (mounted) setState(() => _playingUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    if (_failed) {
      return _Note(
        icon: LucideIcons.cloud_off,
        tint: ZirenTokens.systemWarning,
        text: 'Could not load the attachments. Pull down to try again.',
      );
    }

    final audio = _media.where((m) => m['kind'] == 'audio').toList();
    final others = _media.where((m) => m['kind'] != 'audio').length;

    // Nothing recorded — a typed report. No empty player, no placeholder.
    if (audio.isEmpty && others == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in audio)
          _AudioRow(
            url: m['url'] as String?,
            playing: _playingUrl != null && _playingUrl == m['url'],
            onTap: () {
              final url = m['url'] as String?;
              if (url != null) _toggle(url);
            },
          ),
        if (others > 0) ...[
          if (audio.isNotEmpty) const SizedBox(height: ZirenTokens.space8),
          _Note(
            icon: LucideIcons.images,
            tint: ZirenTokens.textSecondary,
            text:
                others == 1
                    ? '1 photo or video attached — view it in the dashboard.'
                    : '$others photos or videos attached — view them in the dashboard.',
          ),
        ],
      ],
    );
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.url,
    required this.playing,
    required this.onTap,
  });

  final String? url;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A null url means the object failed to sign. Say so rather than offering
    // a play button that does nothing.
    if (url == null) {
      return const _Note(
        icon: LucideIcons.mic_off,
        tint: ZirenTokens.systemWarning,
        text: 'A recording exists but could not be opened.',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: ZirenTokens.space8),
      child: Material(
        color: ZirenTokens.brandSubtle,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        child: InkWell(
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(ZirenTokens.space12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: ZirenTokens.brandOrange,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? LucideIcons.square : LucideIcons.play,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Play the caller's recording",
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Says why it is worth playing rather than trusting the
                      // text above it. A responder who does not know the
                      // transcript can be wrong has no reason to press this.
                      Text(
                        AppLocalizations.of(context).respTranscriptWarning,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ],
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.tint, required this.text});

  final IconData icon;
  final Color tint;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ZirenTokens.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: tint)),
          ),
        ],
      ),
    );
  }
}
