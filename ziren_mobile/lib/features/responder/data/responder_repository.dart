import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/authorized_http.dart';
import '../../incident_report/domain/incident_model.dart' show IncidentNote;
import '../domain/nearby_incident.dart';
import '../domain/responder_ack.dart';
import '../domain/responder_incident_model.dart';

/// All Responder-facing API calls isolated here.
/// Talks to the FastAPI /responder/* endpoints.
class ResponderRepository {
  ResponderRepository();

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  /// Fetch active assigned incidents (dispatched/en_route/arrived).
  Future<List<ResponderIncidentModel>> getMyQueue() async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/responder/queue'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map(
              (e) => ResponderIncidentModel.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      }
      final err = jsonDecode(response.body);
      throw ServerFailure(err['detail'] ?? 'Failed to load queue.');
    } on ServerFailure {
      rethrow;
    } catch (e, st) {
      debugPrint('[ResponderRepository.getMyQueue] $e\n$st');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Fetch full detail for one assigned incident.
  Future<ResponderIncidentModel> getIncidentDetail(String incidentId) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/responder/queue/$incidentId'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        return ResponderIncidentModel.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      final err = jsonDecode(response.body);
      throw ServerFailure(err['detail'] ?? 'Failed to load incident.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// Advance incident status through the FSM:
  ///   dispatched → en_route → arrived → resolved
  Future<void> updateStatus(String incidentId, String newStatus) async {
    try {
      final response = await withAuthRetry(
        () => http
            .patch(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/responder/queue/$incidentId/status',
              ),
              headers: _headers,
              body: jsonEncode({'status': newStatus}),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) return;
      final err = jsonDecode(response.body);
      throw ServerFailure(err['detail'] ?? 'Status update failed.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// Toggle Responder availability: on_duty / off_duty.
  Future<void> setAvailability(String availability) async {
    try {
      final response = await withAuthRetry(
        () => http
            .patch(
              Uri.parse('${AppConfig.apiBaseUrl}/responder/availability'),
              headers: _headers,
              body: jsonEncode({'availability': availability}),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) return;
      final err = jsonDecode(response.body);
      throw ServerFailure(err['detail'] ?? 'Availability update failed.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// The responder's own dashboard figures.
  ///
  /// Returns the raw map rather than a model: every field is a scalar the
  /// dashboard renders directly, and a model class here would be four lines of
  /// boilerplate per number with nothing to enforce.
  Future<Map<String, dynamic>> getDashboard() async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/responder/dashboard'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw const ServerFailure('Failed to load your figures.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// Signed links to the resident's attachments for one assigned incident.
  ///
  /// Each entry is {path, url, kind} where kind is audio / video / image, and
  /// `url` may be null for an object that failed to sign — the caller renders
  /// that as unavailable rather than dropping the row, so a missing recording
  /// is visible instead of silent.
  Future<List<Map<String, dynamic>>> getIncidentMedia(String incidentId) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/responder/queue/$incidentId/media',
              ),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 12)),
      );

      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }
      throw const ServerFailure('Could not load the attachments.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// Report the responder's current position.
  ///
  /// Returns false instead of throwing. This runs on a timer while the
  /// responder is on duty and driving; a failed ping is not something to
  /// interrupt them about, and the next tick will try again. The one thing it
  /// must never do is surface an error over a live incident screen.
  Future<bool> updateLocation(double lat, double lng) async {
    try {
      final response = await withAuthRetry(
        () => http
            .patch(
              Uri.parse('${AppConfig.apiBaseUrl}/responder/location'),
              headers: _headers,
              body: jsonEncode({'latitude': lat, 'longitude': lng}),
            )
            .timeout(const Duration(seconds: 8)),
      );
      if (response.statusCode == 200) return true;
      debugPrint(
        '[ResponderRepository.updateLocation] HTTP ${response.statusCode}: ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[ResponderRepository.updateLocation] $e');
      return false;
    }
  }

  /// Fetch resolved/cancelled incident history (last 50).
  Future<List<ResponderIncidentModel>> getHistory() async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/responder/history'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map(
              (e) => ResponderIncidentModel.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      }
      throw const ServerFailure('Failed to load history.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  // ── Phase 6D — the write verbs ──────────────────────────────
  //
  // Every one of these posts. They are grouped here rather than folded in
  // above because they share one property the read methods do not: each is an
  // action a responder took at a specific moment, and each can therefore be
  // replayed later by ResponderActionQueue with its original timestamp. That
  // is what `occurredAt` is for, and why it is threaded through all of them
  // rather than left to the server's clock.

  /// Confirm this crew is taking the call.
  ///
  /// The request that makes 'dispatched' mean something. Idempotent on the
  /// server: pressing twice returns the same success with the ORIGINAL
  /// timestamp, which matters because a responder on a bad connection will
  /// press it twice.
  Future<void> acceptIncident(String incidentId, {DateTime? occurredAt}) async {
    await _post(
      '/responder/queue/$incidentId/accept',
      body: {
        if (occurredAt != null)
          'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      failure: 'Could not confirm. Try again or call your dispatcher.',
    );
  }

  /// Hand the incident back, with a reason.
  ///
  /// `reason` MUST be one of DeclineReason.all's keys — the server validates
  /// against the same six strings the database CHECK constraint holds, and a
  /// translated key would fail with a 422 the responder cannot act on.
  Future<void> declineIncident(
    String incidentId, {
    required String reason,
    String? note,
    DateTime? occurredAt,
  }) async {
    await _post(
      '/responder/queue/$incidentId/decline',
      body: {
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (occurredAt != null)
          'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      failure: 'Could not send your reason. Call your dispatcher.',
    );
  }

  /// Close the incident WITH what the crew actually found.
  ///
  /// Replaces the bare resolve for the final step. `outcome` is required and
  /// must be one of IncidentOutcome.all's keys — this is the field that makes
  /// the severity rubric checkable against reality for the first time.
  Future<void> closeIncident(
    String incidentId, {
    required String outcome,
    String? notes,
    int? injured,
    int? fatal,
    int? transported,
    DateTime? occurredAt,
  }) async {
    await _post(
      '/responder/queue/$incidentId/close',
      body: {
        'outcome': outcome,
        if (notes != null && notes.trim().isNotEmpty)
          'outcome_notes': notes.trim(),
        // Sent even when zero. NULL is "not recorded" and 0 is "we counted,
        // nobody was hurt", and collapsing them turns every unfilled form
        // into a clean scene.
        if (injured != null) 'casualties_injured': injured,
        if (fatal != null) 'casualties_fatal': fatal,
        if (transported != null) 'casualties_transported': transported,
        if (occurredAt != null)
          'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      failure: 'Could not close the incident.',
    );
  }

  /// Attach photos taken on scene.
  ///
  /// `paths` are storage paths already uploaded to the incident-media bucket,
  /// not local files — the upload happens first, exactly as the resident's
  /// report media does, so a large photo never travels through the API.
  Future<void> attachSceneMedia(String incidentId, List<String> paths) async {
    await _post(
      '/responder/queue/$incidentId/scene-media',
      body: {'paths': paths},
      failure: 'Could not attach the photos.',
    );
  }

  /// The incident's own thread — Sections 11 and 12: field response updates
  /// and incident-specific communication are the same act from this side,
  /// same as the resident's. The backend has had this endpoint since
  /// migration 030; this was the "no mobile screen calls this yet" half.
  Future<List<IncidentNote>> getIncidentNotes(String incidentId) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/responder/queue/$incidentId/notes',
              ),
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
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// Post a field update / message on the incident's thread.
  Future<void> addIncidentNote(String incidentId, String body) async {
    await _post(
      '/responder/queue/$incidentId/notes',
      body: {'body': body},
      failure: 'Could not send your update.',
    );
  }

  /// "The situation is worse than assessed" — Section 14. Notifies the
  /// Agency Admin; never changes the incident's own severity (see the
  /// backend docstring this mirrors).
  Future<void> escalateIncident(String incidentId, String reason) async {
    await _post(
      '/responder/queue/$incidentId/escalate',
      body: {'reason': reason},
      failure: 'Could not send the escalation. Use the radio.',
    );
  }

  /// Ask a second agency to attend the same emergency.
  ///
  /// Returns the created child incident's summary. It is a real incident with
  /// its own dispatcher and its own crew — the ambulance needs something to be
  /// dispatched TO, which a flag on this incident would not give them.
  Future<Map<String, dynamic>> requestBackup(
    String incidentId, {
    required String agencyType,
    required String reason,
  }) async {
    return await _post(
      '/responder/queue/$incidentId/backup',
      body: {'agency_type': agencyType, 'reason': reason},
      failure: 'Could not raise the request. Use the radio.',
    );
  }

  /// Undispatched incidents near this responder, right now.
  ///
  /// Pass the phone's OWN live [lat]/[lng] when one is in hand — measured from
  /// where the crew actually is, not from the last two-minute ping — and omit
  /// both to fall back to the last reported position. Never throws for "nobody
  /// is near": an empty list is a normal, common answer.
  Future<NearbyResult> getNearby({double? lat, double? lng}) async {
    try {
      final params = <String, String>{
        if (lat != null) 'latitude': '$lat',
        if (lng != null) 'longitude': '$lng',
      };
      final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/responder/nearby',
      ).replace(queryParameters: params.isEmpty ? null : params);
      final response = await withAuthRetry(
        () => http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode == 200) {
        return NearbyResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      throw const ServerFailure('Could not check nearby incidents.');
    } on ServerFailure {
      rethrow;
    } catch (_) {
      throw const NetworkFailure('Could not reach the server.');
    }
  }

  /// Reply to a nearby-incident alert: "I can respond" or "not available".
  ///
  /// NEVER assigns anything — the dispatcher still decides and dispatches.
  /// `answer` must be 'can_respond' or 'unavailable'.
  Future<void> answerNearby(
    String incidentId,
    String answer, {
    double? lat,
    double? lng,
  }) async {
    await _post(
      '/responder/nearby/$incidentId/answer',
      body: {
        'answer': answer,
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      },
      failure: 'Could not send your answer. Try again.',
    );
  }

  /// Standing local knowledge near a point.
  /// Standing local knowledge near a point.
  Future<List<ApproachHazard>> getHazards(double lat, double lng) async {
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse(
                '${AppConfig.apiBaseUrl}/responder/hazards'
                '?latitude=$lat&longitude=$lng',
              ),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 8)),
      );
      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(ApproachHazard.fromJson)
            .toList();
      }
      return const [];
    } catch (e) {
      // Never throws. Hazards are additional context on a screen a crew is
      // reading while driving; failing to load them must not take the
      // incident down with them.
      debugPrint('[ResponderRepository.getHazards] $e');
      return const [];
    }
  }

  /// Record a hazard for the crews who come after.
  Future<void> createHazard({
    required double latitude,
    required double longitude,
    required String hazardType,
    required String note,
    int radiusM = 300,
  }) async {
    await _post(
      '/responder/hazards',
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'hazard_type': hazardType,
        'note': note,
        'radius_m': radiusM,
      },
      failure: 'Could not save the hazard.',
    );
  }

  /// The responder's own panic button.
  ///
  /// Longer timeout than anything else here, and that is deliberate: this is
  /// the one request worth waiting on. Everything else can be retried from a
  /// queue; a distress signal that arrives in twenty minutes is not a distress
  /// signal.
  Future<void> raiseDistress({
    double? latitude,
    double? longitude,
    String? incidentId,
    String? note,
  }) async {
    await _post(
      '/responder/distress',
      body: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (incidentId != null) 'incident_id': incidentId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      failure: 'Could not raise the alert. Call your station on the radio now.',
      timeout: const Duration(seconds: 20),
    );
  }

  /// One POST, one error contract.
  ///
  /// Written once because the six methods above were otherwise the same
  /// twenty lines with a different path. Preserves the distinction the rest of
  /// this class makes and the UI depends on: ServerFailure carries the
  /// server's own `detail` — which is the sentence explaining WHY, and is
  /// usually actionable — while NetworkFailure means the phone never reached
  /// it, which is the case the offline queue exists to absorb.
  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    required String failure,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    late final http.Response response;
    try {
      response = await withAuthRetry(
        () => http
            .post(
              Uri.parse('${AppConfig.apiBaseUrl}$path'),
              headers: _headers,
              body: jsonEncode(body),
            )
            .timeout(timeout),
      );
    } catch (e) {
      debugPrint('[ResponderRepository._post] $path $e');
      throw const NetworkFailure(
        'Could not reach the server. Check your connection.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const {};
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    }

    // Surface the server's reason when it gave one. "You have already started
    // responding — contact your dispatcher" tells a crew what to do next;
    // "Something went wrong" does not.
    String? detail;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] is String) {
        detail = (decoded['detail'] as String).trim();
      }
    } catch (_) {}
    throw ServerFailure(detail != null && detail.isNotEmpty ? detail : failure);
  }
}
