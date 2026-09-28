import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The looping alarm that sounds while an assignment is waiting to be answered.
///
/// WHY THE APP MAKES A SOUND AT ALL WHEN THE OS ALREADY DOES
///
/// [ResponderAlertService] raises an OS notification with an alarm-usage
/// channel, and that covers the responder whose phone is in a pocket. It does
/// NOT cover the one holding the phone with the app open — Android suppresses
/// the heads-up notification for the app that is currently in the foreground,
/// which is exactly the responder the dispatcher most expects to reach. Before
/// this, an assignment arriving while the app was on screen was silent.
///
/// So the division is: OS notification when backgrounded, this when in front.
/// The shell stops this the moment the app is paused, so the two never sound
/// at once and neither one outlives the answer.
///
/// WHY IT LOOPS
///
/// The dispatcher console does the same thing, and for the same reason: a
/// single chime is a sound a busy person hears and forgets before their hands
/// are free. It keeps going until somebody answers the alert — and the alert
/// always has a reachable dismiss, which is what makes an endless loop
/// acceptable rather than hostile.
///
/// EVERY FAILURE IS SWALLOWED, DELIBERATELY
///
/// An assignment must never fail to appear because audio would not start. A
/// device with the media stack in a bad state, an emulator with no audio, a
/// codec that refuses the file — all of them produce a silent alert here, and
/// a silent alert is enormously better than none. Failures are reported to the
/// debug console and nowhere else.
class IncidentAlarm {
  IncidentAlarm();

  /// audioplayers resolves [AssetSource] against `assets/`, so this is
  /// `assets/sounds/dispatch_alarm.wav` on disk. Registered in pubspec.yaml
  /// under `assets/sounds/`.
  ///
  /// Three short beeps and a rest, built to loop without a click. It is the
  /// phone's own sound: the dashboard's alert file is for a dispatcher's desk,
  /// and a crew member's phone should not sound like someone else's console.
  static const String _asset = 'sounds/dispatch_alarm.wav';

  final AudioPlayer _player = AudioPlayer(playerId: 'ziren_dispatch_alarm');

  bool _configured = false;
  bool _playing = false;

  /// Bumped by every [stop], so a [start] still working through its awaits can
  /// tell that it has been cancelled.
  ///
  /// THE BUG THIS EXISTS TO PREVENT
  ///
  /// Starting the alarm is several awaits long — configure the audio context,
  /// stop whatever was there, then play. A responder who dismisses the sheet
  /// inside that window used to leave the alarm unstoppable: `stop()` ran
  /// first and found nothing playing, then `play()` resolved a moment later
  /// and began looping with the "am I playing" flag already false, so every
  /// subsequent `stop()` returned early and the phone sounded until the app
  /// was killed. Rare on a warm audio stack and entirely reachable on a cold
  /// one — which is exactly the state a phone is in when it has been sitting
  /// in a pocket waiting for a call.
  int _generation = 0;

  /// True while the loop is sounding. The shell reads this so a rebuild does
  /// not restart a loop that is already running.
  bool get isPlaying => _playing;

  Future<void> _configure() async {
    if (_configured) return;

    // Alarm usage, not media. Two consequences, both wanted: Android routes it
    // to the alarm stream, which sounds through a ringer the responder has
    // silenced, and it ducks rather than stops whatever else is playing —
    // navigation voice guidance, most often, which a crew driving to a scene
    // needs to keep hearing.
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.duckOthers},
        ),
      ),
    );

    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    _configured = true;
  }

  /// Start looping. Calling it again while already sounding does nothing, so
  /// a poll that re-reports the same unanswered assignment cannot restart the
  /// file from the top every few seconds.
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    final token = ++_generation;

    try {
      await _configure();
      if (token != _generation) return;

      await _player.stop();
      if (token != _generation) return;

      await _player.play(AssetSource(_asset));

      // A stop() that arrived while play() was in flight could not silence a
      // player that had not started yet. Now that it has, honour it.
      if (token != _generation) await _player.stop();
    } catch (e) {
      _playing = false;
      debugPrint('[IncidentAlarm] could not start: $e');
    }
  }

  Future<void> stop() async {
    // Bumped before the early return, so a start() mid-flight is cancelled
    // even when nothing is audibly playing yet.
    _generation++;
    if (!_playing) return;
    _playing = false;

    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[IncidentAlarm] could not stop: $e');
    }
  }

  Future<void> dispose() async {
    _generation++;
    _playing = false;
    try {
      await _player.dispose();
    } catch (_) {
      // Disposing a player that never initialised throws on some platforms.
    }
  }
}
