import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';
import '../domain/incident_model.dart';

/// All incident API calls are isolated here.
/// Talks to the FastAPI backend, not directly to Supabase.
class IncidentRepository {
  IncidentRepository({
    String? Function()? accessToken,
    this.submitTimeout = const Duration(seconds: 15),
  }) : _accessTokenOverride = accessToken;

  /// How long a report may be in flight before the phone stops waiting and
  /// tells the resident it could not be sent.
  ///
  /// Every other call in this file has a deadline; this one, the one that
  /// matters most, had none. With signal but no data — the state a prepaid SIM
  /// with no active promo is in — the connection is never refused and never
  /// answered, so the resident could be left watching a spinner until the OS
  /// gave up on its own. Same figure as the SOS request.
  final Duration submitTimeout;

  final String? Function()? _accessTokenOverride;

  /// Returns the current Supabase access token for API auth.
  String? get _accessToken =>
      _accessTokenOverride != null
          ? _accessTokenOverride()
          : Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  /// Submit a new incident report.
  ///
  /// [stationId] is optional: with coordinates the server picks the nearest
  /// station itself, which is also the only way a report can be routed when the
  /// phone has no internet to fetch the station list with.
  ///
  /// Returns null in the one case the server SAVED the report but its reply was
  /// unreadable — see the 201 branch.
  ///
  /// Throws [NetworkFailure] when nothing answered at all, and [ServerFailure]
  /// when our backend answered with a refusal — the two read very differently
  /// to a resident, and the caller needs to tell them apart.
  Future<IncidentModel?> submitIncident({
    required String reportText,
    String? stationId,
    double? latitude,
    double? longitude,
    String? locationAddress,
    List<String> mediaUrls = const [],
    String submittedVia = 'internet',
    // 5W1H wizard fields
    String? incidentCategory,
    Map<String, dynamic>? wizardAnswers,
    List<String>? overlapAgencies,
    String? landmarkNote,
    String? victimRelationship,
  }) async {
    final http.Response response;
    try {
      response = await withAuthRetry(
        () => http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/'),
              headers: _headers,
              body: jsonEncode({
                'report_text': reportText.trim(),
                if (stationId != null) 'station_id': stationId,
                if (latitude != null) 'latitude': latitude,
                if (longitude != null) 'longitude': longitude,
                if (locationAddress != null)
                  'location_address': locationAddress,
                if (mediaUrls.isNotEmpty) 'media_urls': mediaUrls,
                'submitted_via': submittedVia,
                // wizard fields — omit if null so legacy backend handles gracefully
                if (incidentCategory != null)
                  'incident_category': incidentCategory,
                if (wizardAnswers != null) 'wizard_answers': wizardAnswers,
                if (overlapAgencies != null)
                  'overlap_agencies': overlapAgencies,
                if (landmarkNote != null) 'landmark_note': landmarkNote,
                if (victimRelationship != null)
                  'victim_relationship': victimRelationship,
              }),
            )
            .timeout(submitTimeout),
      );
    } catch (_) {
      // Nothing came back: no route, no DNS, a dropped connection, or nobody
      // answered inside [submitTimeout].
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }

    if (response.statusCode == 201) {
      try {
        return IncidentModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } catch (e) {
        // The server SAVED this report; only its reply is unreadable. Calling
        // that a network failure would text the same report a second time.
        debugPrint('[submitIncident] saved, but the reply was unreadable: $e');
        return null;
      }
    }

    final detail = _errorDetail(response.body);
    if (detail == null) {
      // An error page that is not ours — a tunnel that is down or over its
      // quota (ngrok answers 403 HTML), a proxy, a captive portal. Whatever
      // it is, our backend did not answer.
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
    throw ServerFailure(detail);
  }

  /// The `detail` of a FastAPI error body as one readable sentence, or null if
  /// the body is not a FastAPI error at all.
  ///
  /// `detail` is a string for most refusals but a LIST of {loc, msg, type} for
  /// a 422. The list used to be handed straight to a String parameter, threw a
  /// TypeError, and was caught as "no connection" — so a report the server had
  /// refused for being invalid was texted as though the internet were down.
  @visibleForTesting
  static String? errorDetail(String body) => _errorDetail(body);

  static String? _errorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('detail')) {
        return null;
      }
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      if (detail is List) {
        final messages = [
          for (final item in detail)
            if (item is Map && item['msg'] is String)
              (item['msg'] as String).replaceFirst('Value error, ', ''),
        ];
        if (messages.isNotEmpty) return messages.join(' ');
      }
      return 'Submission failed.';
    } catch (_) {
      return null;
    }
  }

  /// Phase 9 — Check if GPS coordinates fall within a station's coverage area.
  /// Returns a map with keys: within_coverage (bool), distance_km (double?).
  /// Fails open — on any error returns {within_coverage: true}.
  Future<Map<String, dynamic>> checkStationCoverage({
    required String stationId,
    required double lat,
    required double lng,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/incidents/coverage-check',
      ).replace(
        queryParameters: {
          'station_id': stationId,
          'lat': lat.toString(),
          'lng': lng.toString(),
        },
      );
      final response = await withAuthRetry(
        () => http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 8)),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'within_coverage': true, 'distance_km': null};
  }

  /// Fetch all incidents submitted by the current user.
  Future<List<IncidentModel>> getMyIncidents() async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/my'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((e) => IncidentModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      throw const ServerFailure('Failed to load your reports.');
    } on ServerFailure {
      rethrow;
    } catch (e, st) {
      debugPrint('[getMyIncidents] raw error: $e');
      debugPrint('[getMyIncidents] stack: $st');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Take back a report the resident filed themselves.
  ///
  /// The row is not deleted. It moves to `cancelled`, which drops it out of
  /// the dispatcher's queue while leaving the record intact — an emergency
  /// report is an audit artefact, and the person who filed it should not be
  /// able to erase something responders may already have read.
  ///
  /// The backend refuses with 409 once an agency has been assigned or the
  /// status has moved past `received`. That is not a bug to retry around: a
  /// truck may already be moving, and the resident is told to call the station
  /// instead. The message from the server is surfaced verbatim for that reason.
  Future<void> withdrawIncident(String incidentId, {String? reason}) async {
    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/incidents/$incidentId/withdraw',
              ),
              headers: _headers,
              body: jsonEncode({
                if (reason != null && reason.trim().isNotEmpty)
                  'reason': reason.trim(),
              }),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) return;

      // 409 and 403 are decisions: the server is telling the resident WHY, and
      // that message ("call the station to stand it down") is the useful part.
      if (response.statusCode == 409 || response.statusCode == 403) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw ServerFailure(
          (body['detail'] as String?) ??
              'This report can no longer be withdrawn.',
        );
      }

      // Everything else is a fault, not a decision, and must not be dressed up
      // as one. A flat "could not withdraw" reads like a refusal the resident
      // should accept — it was shown once for a 404 from a server that had not
      // been restarted, and looked exactly like the feature working correctly.
      debugPrint(
        '[withdrawIncident] HTTP ${response.statusCode}: ${response.body}',
      );
      throw ServerFailure(
        'Something went wrong on our side (${response.statusCode}). '
        'Your report has NOT been withdrawn.',
      );
    } on ServerFailure {
      rethrow;
    } catch (e, st) {
      debugPrint('[withdrawIncident] raw error: $e');
      debugPrint('[withdrawIncident] stack: $st');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// One incident, freshly fetched. Used to wait for the transcript.
  ///
  /// Transcription runs after the report is saved, so the resident's copy is
  /// briefly older than the server's. This is how the confirm screen notices
  /// the words have arrived.
  Future<IncidentModel> getIncident(String incidentId) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/$incidentId'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        return IncidentModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      throw const ServerFailure('Could not load the report.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[getIncident] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Tell the backend whether we heard the resident correctly.
  ///
  /// [correctedText] null or empty means "you heard me right". Anything else
  /// replaces the transcript and re-ranks the report: the person at the scene
  /// outranks the recogniser, always.
  Future<IncidentModel> confirmTranscript(
    String incidentId, {
    String? correctedText,
  }) async {
    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/incidents/$incidentId/confirm',
              ),
              headers: _headers,
              body: jsonEncode({'corrected_text': correctedText}),
            )
            .timeout(const Duration(seconds: 15)),
      );

      if (response.statusCode == 200) {
        return IncidentModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      final error = jsonDecode(response.body);
      throw ServerFailure(error['detail'] ?? 'Could not save your correction.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[confirmTranscript] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// The full thread for one of the resident's own incidents — their own
  /// follow-ups plus whatever the agency/responder wrote back.
  Future<List<IncidentNote>> getIncidentNotes(String incidentId) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/$incidentId/notes'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((e) => IncidentNote.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      throw const ServerFailure('Could not load the thread.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[getIncidentNotes] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Post a follow-up on the resident's own incident — "Add Information to
  /// an Existing Report" and "Incident-Specific Communication" are the same
  /// action from this side (see IncidentNote's doc comment).
  Future<IncidentNote> addIncidentNote(String incidentId, String body) async {
    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/$incidentId/notes'),
              headers: _headers,
              body: jsonEncode({'body': body}),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 201) {
        return IncidentNote.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      final error = jsonDecode(response.body);
      throw ServerFailure(error['detail'] ?? 'Could not send your message.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[addIncidentNote] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Null means the resident has not rated this incident yet — never a 404.
  Future<IncidentFeedback?> getMyFeedback(String incidentId) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/incidents/$incidentId/feedback',
              ),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body == null) return null;
        return IncidentFeedback.fromJson(body as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[getMyFeedback] raw error: $e');
      return null;
    }
  }

  /// One-shot, post-resolution rating (Section 26). The backend refuses a
  /// second submission for the same incident with 409 — surfaced verbatim,
  /// since "you already rated this" is a fact the resident should see, not
  /// a generic failure.
  Future<void> submitFeedback({
    required String incidentId,
    required int rating,
    String? comment,
  }) async {
    try {
      final response = await withAuthRetry(
        () => http
            .post(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/incidents/$incidentId/feedback',
              ),
              headers: _headers,
              body: jsonEncode({
                'rating': rating,
                if (comment != null && comment.trim().isNotEmpty)
                  'comment': comment.trim(),
              }),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 201) return;
      final error = jsonDecode(response.body);
      throw ServerFailure(error['detail'] ?? 'Could not save your feedback.');
    } on ServerFailure {
      rethrow;
    } catch (e) {
      debugPrint('[submitFeedback] raw error: $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }
}
