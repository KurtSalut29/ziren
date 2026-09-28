import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/authorized_http.dart';

/// Scores a spoken-vs-transcribed pair against the backend's critical
/// vocabulary.
///
/// The scoring lives on the server on purpose. The authoritative word lists —
/// `06_DICTIONARY/emergency_terms.csv` and predict.py's BARANGAYS — are what
/// the triage model itself uses, and a copy of them shipped in the app would
/// be a second list free to drift out of step with the first. Sending two
/// short strings and reading back a score keeps one source of truth.
///
/// Word Error Rate is computed on-device as well (see TranscriptAccuracy), so
/// a diagnostic run still produces something useful with no network. Only the
/// critical-word half needs the backend.
class TranscriptEvalRepository {
  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns the evaluation, or null when the backend cannot be reached or
  /// refuses. Null is a normal outcome here, not an error worth interrupting a
  /// test run for — the tester is holding a phone in a place where the network
  /// may be exactly what is not working.
  Future<TranscriptEvaluation?> evaluate({
    required String said,
    required String heard,
    String? locale,
  }) async {
    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/triage/evaluate-transcript'),
              headers: _headers,
              body: jsonEncode({
                'said': said,
                'heard': heard,
                if (locale != null) 'locale': locale,
              }),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode != 200) return null;
      return TranscriptEvaluation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One side of the evaluation — raw, or after correction.
class TranscriptScores {
  const TranscriptScores({
    required this.text,
    required this.wer,
    required this.criticalTotal,
    required this.criticalRecognised,
    required this.hit,
    required this.missed,
    required this.byKind,
    required this.corrections,
  });

  final String text;
  final double wer;
  final int criticalTotal;
  final int criticalRecognised;
  final List<String> hit;
  final List<String> missed;

  /// kind ('emergency' | 'place' | 'agency') → {total, recognised}
  final Map<String, Map<String, int>> byKind;
  final List<String> corrections;

  /// 1.0 when nothing critical was lost. Also 1.0 when the sentence held
  /// nothing critical at all, so read [criticalTotal] with it.
  double get criticalAccuracy =>
      criticalTotal == 0 ? 1.0 : criticalRecognised / criticalTotal;

  static TranscriptScores fromJson(Map<String, dynamic> j) {
    final critical = (j['critical_words'] as Map?) ?? const {};
    final werBlock = (j['word_error_rate'] as Map?) ?? const {};
    return TranscriptScores(
      text: j['text'] as String? ?? '',
      wer: (werBlock['wer'] as num?)?.toDouble() ?? 0,
      criticalTotal: (critical['total'] as num?)?.toInt() ?? 0,
      criticalRecognised: (critical['recognised'] as num?)?.toInt() ?? 0,
      hit: List<String>.from(critical['hit'] as List? ?? const []),
      missed: List<String>.from(critical['missed'] as List? ?? const []),
      byKind: {
        for (final e in ((critical['by_kind'] as Map?) ?? const {}).entries)
          e.key as String: {
            for (final k in (e.value as Map).entries)
              k.key as String: (k.value as num).toInt(),
          },
      },
      corrections: List<String>.from(j['corrections'] as List? ?? const []),
    );
  }
}

class TranscriptEvaluation {
  const TranscriptEvaluation({
    required this.raw,
    required this.corrected,
    required this.recovered,
  });

  final TranscriptScores raw;

  /// Null when the backend has no model loaded and could not run corrections.
  final TranscriptScores? corrected;

  /// Critical words the correction layer got back that the raw transcript
  /// had lost. This is the measured justification for that layer existing.
  final List<String> recovered;

  static TranscriptEvaluation fromJson(Map<String, dynamic> j) {
    return TranscriptEvaluation(
      raw: TranscriptScores.fromJson((j['raw'] as Map).cast<String, dynamic>()),
      corrected:
          j['corrected'] == null
              ? null
              : TranscriptScores.fromJson(
                (j['corrected'] as Map).cast<String, dynamic>(),
              ),
      recovered: List<String>.from(
        j['critical_words_recovered'] as List? ?? const [],
      ),
    );
  }
}
