import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Captures the resident's own voice as a file the dispatcher can play back.
///
/// This exists alongside `speech_to_text`, not instead of it, and the division
/// of labour is deliberate:
///
///   * the RECORDING is the truth. A Naval dispatcher who speaks Waray
///     understands it perfectly, with none of the word error rate that makes
///     Waray and Bisaya transcription the weakest part of the pipeline.
///   * the TRANSCRIPT is the sorter. It only has to be good enough to rank the
///     queue by severity, which is a far lower bar than being good enough to
///     act on — and the dispatcher always has the audio to check it against.
///
/// `speech_to_text` cannot do this job. It wraps the platform recogniser, which
/// returns words and never hands back the audio, so the file has to come from
/// a real recorder.
class VoiceNoteService {
  VoiceNoteService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// Hard ceiling on a single voice note.
  ///
  /// Not an arbitrary round number: this is an emergency report from a phone
  /// that may be on one bar, and at the encoding below sixty seconds is roughly
  /// 240 KB. Long enough to say what is happening and where; short enough to
  /// finish uploading before the caller moves.
  static const Duration maxDuration = Duration(seconds: 60);

  /// Below this a file is a container, not a report. See [stop].
  static const int _minBytes = 8000; // ~2 seconds at 32 kbps

  File? _file;

  /// The recording captured by the last completed [stop], if any.
  File? get file => _file;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> get isRecording => _recorder.isRecording();

  /// Begin recording. Returns false when the microphone was refused.
  ///
  /// Encoded as 16 kHz mono AAC. Speech carries almost nothing above 8 kHz, so
  /// a higher sample rate would cost bandwidth on a bad connection and buy the
  /// dispatcher no intelligibility. Mono for the same reason.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ziren_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 32000,
      ),
      path: path,
    );
    return true;
  }

  /// Stop and return the finished recording, or null if nothing was captured.
  Future<File?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;

    final captured = File(path);
    // Zero bytes is not the failure to watch for. A recorder that loses the
    // microphone still closes a valid MP4 container, so the file exists, has a
    // header, and plays for a fraction of a second — which reads to the
    // resident as a working recording the station will hear.
    //
    // At the 32 kbps above, audio costs 4,000 bytes per second, so anything
    // under _minBytes cannot hold enough speech to be worth sending. Measured
    // case: 4,257 bytes, about one second, produced when the platform
    // recogniser was started alongside the encoder.
    if (!captured.existsSync() || captured.lengthSync() < _minBytes) {
      await _safeDelete(captured);
      return null;
    }
    _file = captured;
    return captured;
  }

  /// Abandon an in-progress recording without keeping the file.
  Future<void> cancel() async {
    final path = await _recorder.stop();
    if (path != null) await _safeDelete(File(path));
    _file = null;
  }

  /// Forget and delete the captured recording.
  Future<void> discard() async {
    final held = _file;
    _file = null;
    if (held != null) await _safeDelete(held);
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  Future<void> _safeDelete(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // A leftover file in the OS temp directory is not worth failing a report
      // over; the platform reclaims it.
    }
  }
}
