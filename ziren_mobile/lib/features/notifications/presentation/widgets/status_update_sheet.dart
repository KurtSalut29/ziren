import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/ziren_dialogs.dart';
import '../../../../shared/widgets/ziren_spine.dart';
import '../../../incident_report/presentation/incident_labels.dart';
import '../../domain/notification_provider.dart' show AppNotification;
import '../notice_view.dart';

/// A gentle chime, once, for a notice.
///
/// Its own sound (`notify_chime.wav`: two soft rising bell notes), not the
/// dispatcher console's alert file. That file is a loud attention-getter made for
/// a room full of dispatchers; a resident being told "a responder is on the way"
/// needs to be reassured, not startled, and a sound that means "new emergency" on
/// the dashboard should not mean "your report was updated" on a phone.
///
/// Not [IncidentAlarm] (the responder's looping alarm) - a resident is being
/// told, not asked to decide anything, so this plays once and stops. A
/// second notification arriving while the first chime is still playing
/// restarts it rather than layering two chimes on top of each other.
///
/// Every failure is swallowed, same reasoning as the responder alarm: a
/// silent notification is far better than a status update that never shows
/// because audio was unavailable.
class _StatusChime {
  _StatusChime._();
  static final AudioPlayer _player = AudioPlayer(
    playerId: 'ziren_status_chime',
  );
  static bool _configured = false;

  static Future<void> play() async {
    try {
      if (!_configured) {
        await _player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notification,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            // `ambient` already mixes with whatever else is playing. Asking it
            // to duck others as well is not a valid pairing - the audio
            // package asserts on it - so the whole context was refused, the
            // error was swallowed below, and the chime never played at all.
            iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
          ),
        );
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setVolume(1.0);
        _configured = true;
      }
      await _player.stop();
      await _player.play(AssetSource('sounds/notify_chime.wav'));
    } catch (e) {
      debugPrint('[StatusChime] could not play: $e');
    }
  }
}

/// The dialog that tells a resident what just happened to their report -
/// "a responder is on the way", "the agency cancelled it, and why", "you have a
/// new message".
///
/// WHY THIS IS NOT THE RESPONDER'S DOORBELL
///
/// [IncomingReportSheet] asks a responder to decide something and stays on
/// screen, alarming, until they do. A resident reading an update is not deciding
/// anything - they are being told - so this asks nothing back. Where there is
/// something worth doing about it (open the report, reply in the chat) that is
/// one clearly-drawn button, and "Got it" is always there. One chime, not a
/// loop, for the same reason: nagging a resident who has already been told once
/// would teach them to dismiss it unread.
///
/// All the words come from [noticeView], so this and the notifications list say
/// the same thing.
class StatusUpdateSheet {
  const StatusUpdateSheet._();

  /// Shows the notice and resolves to what the resident chose to do about it.
  static Future<NoticeAction> show(
    BuildContext context,
    AppNotification notification,
  ) async {
    unawaited(_StatusChime.play());
    final t = AppLocalizations.of(context);
    final view = noticeView(t, notification);

    final chosen = await showZirenDialog<NoticeAction>(
      context,
      leading: _Leading(view: view, eyebrow: view.eyebrow ?? t.notifStatusTitle),
      accent: view.color,
      title: view.title,
      message: view.body,
      body: _hasBody(view) ? _Body(view: view) : null,
      actions: [
        if (view.primary != NoticeAction.dismiss)
          ZirenDialogAction(
            label: view.primaryLabel,
            value: view.primary,
            kind: ZirenActionKind.primary,
          ),
        ZirenDialogAction(
          label: t.notifStatusOk,
          value: NoticeAction.dismiss,
          // With nothing else to do about it, "Got it" is the one button and
          // carries the notice's own colour.
          kind:
              view.primary == NoticeAction.dismiss
                  ? ZirenActionKind.primary
                  : ZirenActionKind.secondary,
        ),
      ],
    );
    return chosen ?? NoticeAction.dismiss;
  }

  static bool _hasBody(NoticeView v) =>
      v.hasRail || v.quote != null || v.help != null || v.etaLine != null;
}

class _Leading extends StatelessWidget {
  const _Leading({required this.view, required this.eyebrow});

  final NoticeView view;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: view.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(view.icon, color: view.color, size: 28),
        ),
        const SizedBox(height: ZirenTokens.space12),
        Text(
          eyebrow,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: ZirenTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});

  final NoticeView view;

  /// Same four wire values, same order, as the rail on the My Reports card -
  /// one canonical pipeline shown two places, so a resident who checks both
  /// never sees them disagree.
  static const _sequence = ['received', 'processing', 'dispatched', 'resolved'];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final stage = view.stage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.hasRail)
          ZirenSpine(
            compact: true,
            nodes: [
              for (var s = 0; s < _sequence.length; s++)
                SpineNode(
                  title: IncidentLabels.status(t, _sequence[s]),
                  state:
                      view.halted
                          ? (s == 0 ? SpineState.halted : SpineState.pending)
                          : s < (stage ?? 0)
                          ? SpineState.done
                          : s == (stage ?? 0)
                          ? (s == _sequence.length - 1
                              ? SpineState.done
                              : SpineState.active)
                          : SpineState.pending,
                ),
            ],
          ),
        if (view.quote != null) ...[
          if (view.hasRail) const SizedBox(height: ZirenTokens.space12),
          // A quote: the agency's own words, with a bar of the notice's colour
          // down its side. Drawn as a clipped row, not a border - a rounded box
          // cannot have a border on one side only.
          ClipRRect(
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: view.color),
                  Expanded(
                    child: Container(
                      color: ZirenTokens.surfaceRaised,
                      padding: const EdgeInsets.all(ZirenTokens.space12),
                      child: Text(
                        view.quote!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (view.etaLine != null) ...[
          const SizedBox(height: ZirenTokens.space12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.truck, size: 15, color: view.color),
              const SizedBox(width: ZirenTokens.space6),
              Flexible(
                child: Text(
                  view.etaLine!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: view.color,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (view.help != null) ...[
          const SizedBox(height: ZirenTokens.space12),
          Text(
            view.help!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
