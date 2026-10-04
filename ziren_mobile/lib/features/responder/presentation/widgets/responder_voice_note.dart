import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  const ResponderVoiceNote({super.key, required this.incidentId, this.repository});

  final String incidentId;

  /// For tests; the app uses the real repository.
  final ResponderRepository? repository;

  @override
  State<ResponderVoiceNote> createState() => _ResponderVoiceNoteState();
}

class _ResponderVoiceNoteState extends State<ResponderVoiceNote> {
  late final ResponderRepository _repo = widget.repository ?? ResponderRepository();
  final _player = AudioPlayer();

  List<Map<String, dynamic>> _media = const [];
  bool _loading = true;
  bool _failed = false;
  String? _playingUrl;

  /// Signed links last five minutes. A photo that fails to load after that
  /// fetches fresh links once; never a loop.
  bool _refreshedLinks = false;

  void _onLinkExpired() {
    if (_refreshedLinks || !mounted) return;
    _refreshedLinks = true;
    _load();
  }

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

    final t = AppLocalizations.of(context);
    if (_failed) {
      return _Note(
        icon: LucideIcons.cloud_off,
        tint: ZirenTokens.systemWarning,
        text: t.respAttachmentsLoadFailed,
      );
    }

    final audio = _media.where((m) => m['kind'] == 'audio').toList();
    // Photos and videos. These used to be counted and answered with "view it
    // in the dashboard": a crew on the road has no dashboard, and the
    // dashboard did not show them either (evaluator findings #1 and #3).
    final visual = _media.where((m) => m['kind'] != 'audio').toList();

    // Nothing recorded — a typed report. No empty player, no placeholder.
    if (audio.isEmpty && visual.isEmpty) return const SizedBox.shrink();

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
        if (visual.isNotEmpty) ...[
          const SizedBox(height: ZirenTokens.space12),
          _AttachmentGrid(items: visual, onLinkExpired: _onLinkExpired),
        ],
      ],
    );
  }
}

/// The caller's photos and videos as thumbnails. A photo opens full screen
/// with pinch-to-zoom; a video opens in the phone's own player.
class _AttachmentGrid extends StatelessWidget {
  const _AttachmentGrid({required this.items, required this.onLinkExpired});

  final List<Map<String, dynamic>> items;
  final VoidCallback onLinkExpired;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.images, size: 15, color: ZirenTokens.textSecondary),
            const SizedBox(width: ZirenTokens.space8),
            Expanded(
              child: Text(
                t.respAttachmentsTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space8),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: ZirenTokens.space8,
          crossAxisSpacing: ZirenTokens.space8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final m in items)
              _AttachmentTile(
                url: m['url'] as String?,
                isVideo: m['kind'] == 'video',
                onLinkExpired: onLinkExpired,
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.url,
    required this.isVideo,
    required this.onLinkExpired,
  });

  final String? url;
  final bool isVideo;
  final VoidCallback onLinkExpired;

  Future<void> _openVideo(BuildContext context, String url) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(t.respAttachmentVideoFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final radius = BorderRadius.circular(ZirenTokens.radius12);
    final link = url;

    if (link == null) {
      return Semantics(
        label: t.respAttachmentUnavailable,
        child: Container(
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceRaised,
            borderRadius: radius,
            border: Border.all(color: ZirenTokens.surfaceBorder),
          ),
          alignment: Alignment.center,
          child: Icon(LucideIcons.image_off, size: 22, color: ZirenTokens.textMuted),
        ),
      );
    }

    if (isVideo) {
      return Semantics(
        button: true,
        label: t.respAttachmentPlayVideo,
        child: Material(
          color: Colors.black,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openVideo(context, link),
            child: const Center(
              child: Icon(LucideIcons.circle_play, size: 34, color: Colors.white),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      image: true,
      child: Material(
        color: ZirenTokens.surfaceRaised,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => _PhotoViewer(url: link),
            ),
          ),
          child: Image.network(
            link,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
            errorBuilder: (context, error, stack) {
              // Most likely the five-minute link lapsed while the screen was
              // open: fetch fresh ones (once) after this frame.
              WidgetsBinding.instance.addPostFrameCallback((_) => onLinkExpired());
              return Center(
                child: Icon(LucideIcons.image_off, size: 22, color: ZirenTokens.textMuted),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Full-screen photo with pinch-to-zoom: a thumbnail is too small to read a
/// house number or a plate from.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: t.respPhotoViewerClose,
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => Padding(
              padding: const EdgeInsets.all(ZirenTokens.space24),
              child: Text(
                t.respAttachmentUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
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
