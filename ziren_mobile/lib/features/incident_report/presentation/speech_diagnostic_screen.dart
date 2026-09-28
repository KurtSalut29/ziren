import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' show LocaleName;

import '../../../shared/theme/app_tokens.dart';
import '../data/transcript_eval_repository.dart';
import '../domain/incident_provider.dart';
import '../domain/speech_locale_resolver.dart';
import '../domain/speech_test_sentences.dart';
import '../domain/transcript_accuracy.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Speech diagnostic — which recogniser actually reads Waray and Bisaya.
///
/// Why this exists
/// ---------------
/// The app listened in `en_PH` while residents here report mostly in Waray and
/// Bisaya, so every transcript was English phonetics applied to Visayan
/// speech. Fixing the locale raises an immediate question the code cannot
/// answer on its own: **which** locale, given that no handset is likely to
/// ship a Waray recogniser.
///
/// SpeechLocaleResolver's answer is a hypothesis — that Cebuano, as the
/// nearest Visayan relative, reads Waray better than Filipino does. This
/// screen is how that gets tested instead of assumed: say one sentence, run it
/// through each available candidate, read the transcripts side by side.
///
/// It is a measuring instrument, not a resident-facing feature. The numbers it
/// produces are the kind that belong in a Results chapter.
class SpeechDiagnosticScreen extends StatefulWidget {
  const SpeechDiagnosticScreen({super.key});

  @override
  State<SpeechDiagnosticScreen> createState() => _SpeechDiagnosticScreenState();
}

class _SpeechDiagnosticScreenState extends State<SpeechDiagnosticScreen> {
  static const _spokenLanguages = ['Waray', 'Bisaya', 'Filipino', 'English'];

  String _language = 'Waray';
  String? _recordingLocale;
  bool _showAllLocales = false;

  /// Ground truth — what the tester actually said. Without it every row is an
  /// opinion; with it each row is a measurement.
  final _saidCtrl = TextEditingController(
    text: SpeechTestSentences.defaultFor('Waray'),
  );

  /// localeId → what came back for it.
  final Map<String, _Attempt> _attempts = {};

  /// localeId → backend scoring, when the backend was reachable.
  final Map<String, TranscriptEvaluation> _evals = {};

  final _evalRepo = TranscriptEvalRepository();
  bool _backendReachable = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IncidentProvider>().initSpeech();
    });
  }

  @override
  void dispose() {
    _saidCtrl.dispose();
    super.dispose();
  }

  /// Everything gathered so far, as plain text to paste into a report.
  /// Retyping results by hand is where transcription studies lose their data.
  Future<void> _copyResults() async {
    final said = _saidCtrl.text.trim();
    final b =
        StringBuffer()
          ..writeln('Ziren speech check')
          ..writeln('spoken language: $_language')
          ..writeln('said: $said')
          ..writeln('');

    for (final entry in _attempts.entries) {
      final a = entry.value;
      final wer = TranscriptAccuracy.compare(said: said, heard: a.transcript);
      final confidence =
          a.confidence > 0
              ? '${(a.confidence * 100).round()}%'
              : 'not reported';
      b
        ..writeln('[${entry.key}]')
        ..writeln('  heard: ${a.transcript}')
        ..writeln('  ${wer.summary}')
        ..writeln('  confidence: $confidence');

      final e = _evals[entry.key];
      if (e != null) {
        b.writeln(
          '  critical: ${e.raw.criticalRecognised}/${e.raw.criticalTotal}'
          '${e.raw.missed.isEmpty ? '' : '  lost: ${e.raw.missed.join(', ')}'}',
        );
        final c = e.corrected;
        if (c != null) {
          b.writeln('  corrected: ${c.text}');
          b.writeln(
            '  critical after correction: '
            '${c.criticalRecognised}/${c.criticalTotal}'
            '${e.recovered.isEmpty ? '' : '  recovered: ${e.recovered.join(', ')}'}',
          );
        }
      }
      if (a.error != null) b.writeln('  error: ${a.error}');
    }

    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Results copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Switching language swaps in that language's first preset and drops the
  /// recorded rows. Keeping them would leave transcripts of one sentence
  /// scored against a different one — a table that looks valid and is not.
  void _switchLanguage(String language) {
    setState(() {
      _language = language;
      _saidCtrl.text = SpeechTestSentences.defaultFor(language);
      _attempts.clear();
      _evals.clear();
    });
  }

  /// Choosing a different preset invalidates the rows for the same reason.
  void _useSentence(String sentence) {
    setState(() {
      _saidCtrl.text = sentence;
      _attempts.clear();
      _evals.clear();
    });
  }

  Future<void> _record(String localeId) async {
    final p = context.read<IncidentProvider>();
    setState(() {
      _recordingLocale = localeId;
      _attempts[localeId] = const _Attempt(transcript: '', confidence: 0);
    });

    await p.startListeningIn(
      localeId: localeId,
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          _attempts[localeId] = _Attempt(
            transcript: text,
            confidence: p.speechConfidence,
          );
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _recordingLocale = null;
      _attempts[localeId] = _Attempt(
        transcript: p.spokenText,
        confidence: p.speechConfidence,
        error: p.speechError,
      );
    });

    await _scoreAgainstBackend(localeId, p.spokenText);
  }

  /// Ask the backend for critical-word accuracy. WER is already computed
  /// on-device, so a failure here costs the run one column, not the run.
  Future<void> _scoreAgainstBackend(String localeId, String heard) async {
    final said = _saidCtrl.text.trim();
    if (said.isEmpty || heard.isEmpty) return;

    final evaluation = await _evalRepo.evaluate(
      said: said,
      heard: heard,
      locale: localeId,
    );
    if (!mounted) return;
    setState(() {
      _backendReachable = evaluation != null;
      if (evaluation != null) _evals[localeId] = evaluation;
    });
  }

  Future<void> _stop() async {
    await context.read<IncidentProvider>().stopListening();
    if (mounted) setState(() => _recordingLocale = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<IncidentProvider>();
    final locales = p.speechLocales;
    final candidates = SpeechLocaleResolver.availableCandidates(
      languageName: _language,
      available: locales,
    );
    final native = SpeechLocaleResolver.hasNativeSupport(
      languageName: _language,
      available: locales,
    );

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: const Text('Speech diagnostic'),
        actions: [
          IconButton(
            tooltip: 'Copy results',
            icon: const Icon(LucideIcons.copy),
            onPressed: _attempts.isEmpty ? null : _copyResults,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZirenTokens.space16),
        children: [
          _Card(
            title: 'DEVICE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Recogniser available', p.speechAvailable ? 'yes' : 'NO'),
                _kv('Locales installed', '${locales.length}'),
                if (p.speechError != null) _kv('Last error', p.speechError!),
              ],
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),

          _Card(
            title: 'SPOKEN LANGUAGE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: ZirenTokens.space8,
                  children: [
                    for (final l in _spokenLanguages)
                      ChoiceChip(
                        label: Text(l),
                        selected: _language == l,
                        onSelected: (_) => _switchLanguage(l),
                      ),
                  ],
                ),
                const SizedBox(height: ZirenTokens.space12),
                if (!native)
                  _Banner(
                    icon: LucideIcons.info,
                    color: ZirenTokens.systemWarning,
                    text:
                        'No $_language recogniser on this device. The '
                        'candidates below are fallbacks — this is exactly the '
                        'case the attached audio recording is for.',
                  )
                else
                  _Banner(
                    icon: LucideIcons.circle_check,
                    color: ZirenTokens.systemSuccess,
                    text: 'This device has a $_language recogniser.',
                  ),
                const SizedBox(height: ZirenTokens.space8),
                Text(
                  'Fallback order: ${SpeechLocaleResolver.candidatesFor(_language).join(' → ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),

          _Card(
            title: 'SAY THE SAME SENTENCE IN EACH',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Use one emergency sentence for every row, spoken the same '
                  'way, so the only thing that changes is the recogniser.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ZirenTokens.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space12),
                for (final sentence in SpeechTestSentences.forLanguage(
                  _language,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => _useSentence(sentence),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _saidCtrl.text == sentence
                                ? LucideIcons.circle_dot
                                : LucideIcons.circle,
                            size: 16,
                            color:
                                _saidCtrl.text == sentence
                                    ? ZirenTokens.brandOrange
                                    : ZirenTokens.textMuted,
                          ),
                          const SizedBox(width: ZirenTokens.space8),
                          Expanded(
                            child: Text(
                              sentence,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: ZirenTokens.space12),
                TextField(
                  controller: _saidCtrl,
                  onChanged: (_) => setState(() {}),
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'What you actually said',
                    labelStyle: TextStyle(fontSize: 13),
                    helperText:
                        'Edit freely — the Waray and Bisaya presets are '
                        'drafts built from the dataset vocabulary, not text '
                        'written by a native speaker.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: ZirenTokens.space16),
                if (!_backendReachable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ZirenTokens.space12),
                    child: _Banner(
                      icon: LucideIcons.cloud_off,
                      color: ZirenTokens.systemWarning,
                      text:
                          'Backend unreachable — showing word error rate only. '
                          'Critical-word accuracy is scored server-side, '
                          'against the same vocabulary the triage model uses.',
                    ),
                  ),
                if (candidates.isEmpty)
                  Text(
                    'None of the candidate locales are installed.',
                    style: TextStyle(color: ZirenTokens.textMuted),
                  ),
                for (final code in candidates) ..._rowsForCode(code, locales),
              ],
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),

          _Card(
            title: 'ALL INSTALLED LOCALES',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed:
                      () => setState(() => _showAllLocales = !_showAllLocales),
                  child: Text(_showAllLocales ? 'Hide' : 'Show all'),
                ),
                if (_showAllLocales)
                  for (final l in locales)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${l.localeId}  —  ${l.name}',
                        style: TextStyle(
                          fontSize: 12,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rowsForCode(String code, List<LocaleName> locales) {
    return [
      for (final l in SpeechLocaleResolver.allWithLanguage(locales, code))
        Padding(
          padding: const EdgeInsets.only(bottom: ZirenTokens.space12),
          child: _AttemptRow(
            locale: l,
            said: _saidCtrl.text.trim(),
            attempt: _attempts[l.localeId],
            evaluation: _evals[l.localeId],
            recording: _recordingLocale == l.localeId,
            busy: _recordingLocale != null && _recordingLocale != l.localeId,
            onRecord: () => _record(l.localeId),
            onStop: _stop,
          ),
        ),
    ];
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(
          '$k: ',
          style: TextStyle(fontSize: 12.5, color: ZirenTokens.textMuted),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ZirenTokens.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Attempt {
  const _Attempt({
    required this.transcript,
    required this.confidence,
    this.error,
  });

  final String transcript;
  final double confidence;
  final String? error;
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({
    required this.locale,
    required this.said,
    required this.attempt,
    required this.evaluation,
    required this.recording,
    required this.busy,
    required this.onRecord,
    required this.onStop,
  });

  final LocaleName locale;
  final String said;
  final _Attempt? attempt;
  final TranscriptEvaluation? evaluation;
  final bool recording;
  final bool busy;
  final VoidCallback onRecord;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locale.localeId,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    Text(
                      locale.name,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (recording)
                TextButton.icon(
                  onPressed: onStop,
                  icon: const Icon(LucideIcons.square, size: 18),
                  label: const Text('Stop'),
                  style: TextButton.styleFrom(
                    foregroundColor: ZirenTokens.severityCritical,
                  ),
                )
              else
                TextButton.icon(
                  onPressed: busy ? null : onRecord,
                  icon: const Icon(LucideIcons.mic, size: 18),
                  label: const Text('Record'),
                ),
            ],
          ),
          if (attempt != null) ...[
            const SizedBox(height: ZirenTokens.space8),
            Text(
              attempt!.transcript.isEmpty
                  ? (recording ? 'listening…' : '(nothing recognised)')
                  : attempt!.transcript,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontStyle:
                    attempt!.transcript.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                color:
                    attempt!.transcript.isEmpty
                        ? ZirenTokens.textMuted
                        : ZirenTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // Android frequently returns 0 here; that means "no rating
              // given", not "no confidence". Saying so avoids reading an
              // absent number as a bad score.
              attempt!.confidence > 0
                  ? 'confidence ${(attempt!.confidence * 100).round()}%'
                  : 'confidence not reported by this platform',
              style: TextStyle(
                fontSize: 11.5,
                color: ZirenTokens.textMuted,
              ),
            ),
            if (said.isNotEmpty && attempt!.transcript.isNotEmpty) ...[
              const SizedBox(height: ZirenTokens.space8),
              Text(
                TranscriptAccuracy.compare(
                  said: said,
                  heard: attempt!.transcript,
                ).summary,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              // Which words survived, not just how many. In the recorded
              // sample `sunog` came through and `Caibiran` did not — and that
              // distinction is the entire finding, invisible in a single
              // score.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final o in TranscriptAccuracy.wordOutcomes(
                    said: said,
                    heard: attempt!.transcript,
                  ))
                    Text(
                      o.word,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            o.heard
                                ? ZirenTokens.systemSuccess
                                : ZirenTokens.severityCritical,
                        decoration: o.heard ? null : TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ],
            if (evaluation != null) ...[
              const SizedBox(height: ZirenTokens.space12),
              const Divider(height: 1),
              const SizedBox(height: ZirenTokens.space8),
              // The number that matters more than WER. A transcript can score
              // badly and still carry every word a dispatcher acts on — the
              // recorded Waray sample did exactly that.
              _CriticalRow(label: 'Critical words', score: evaluation!.raw),
              if (evaluation!.corrected != null) ...[
                const SizedBox(height: 4),
                _CriticalRow(
                  label: 'After correction',
                  score: evaluation!.corrected!,
                  recovered: evaluation!.recovered,
                ),
              ],
            ],
            if (attempt!.error != null)
              Text(
                'error: ${attempt!.error}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: ZirenTokens.systemError,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: ZirenTokens.textMuted,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          child,
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: ZirenTokens.space8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of critical-word scoring, with the words that were lost named.
///
/// The count alone would answer "how bad", which is the less useful question.
/// Naming the missed words answers "which", and `sunog` being lost is a
/// different problem from `Caibiran` being lost — the first breaks triage, the
/// second is a place the app already has from GPS.
class _CriticalRow extends StatelessWidget {
  const _CriticalRow({
    required this.label,
    required this.score,
    this.recovered = const [],
  });

  final String label;
  final TranscriptScores score;
  final List<String> recovered;

  @override
  Widget build(BuildContext context) {
    final pct = (score.criticalAccuracy * 100).round();
    final colour =
        score.criticalTotal == 0
            ? ZirenTokens.textMuted
            : pct == 100
            ? ZirenTokens.systemSuccess
            : pct >= 50
            ? ZirenTokens.systemWarning
            : ZirenTokens.severityCritical;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ),
            Text(
              score.criticalTotal == 0
                  ? 'none in this sentence'
                  : '${score.criticalRecognised}/${score.criticalTotal}  ·  $pct%',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
          ],
        ),
        if (score.byKind.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              score.byKind.entries
                  .map(
                    (e) =>
                        '${e.key} ${e.value['recognised']}/${e.value['total']}',
                  )
                  .join('  ·  '),
              style: TextStyle(
                fontSize: 11.5,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
        if (score.missed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'lost: ${score.missed.join(', ')}',
              style: const TextStyle(
                fontSize: 11.5,
                color: ZirenTokens.severityCritical,
              ),
            ),
          ),
        if (recovered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'recovered by correction: ${recovered.join(', ')}',
              style: const TextStyle(
                fontSize: 11.5,
                color: ZirenTokens.systemSuccess,
              ),
            ),
          ),
      ],
    );
  }
}
