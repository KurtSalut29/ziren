import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/errors/failures.dart';
import '../../incident_report/domain/incident_model.dart' show IncidentNote;
import '../data/responder_action_queue.dart';
import '../data/responder_repository.dart';
import 'nearby_incident.dart';
import 'responder_incident_model.dart';

/// State management for the Responder role.
///
/// Manages:
///  - Active incident queue (assigned incidents)
///  - Status update FSM (dispatched → en_route → arrived → resolved)
///  - Availability toggle (on_duty / off_duty)
///  - History (resolved/cancelled incidents)
///  - Dashboard figures (this responder's own, never the agency's)
///  - Location reporting while on duty
///
/// Phase 6D adds the write verbs the role never had: accepting a call,
/// refusing one with a reason, closing with what was actually found,
/// asking a second agency for help, and the responder's own panic button.
/// All of them go through the offline queue, because the responder is the
/// one person in this system guaranteed to lose signal.
class ResponderProvider extends ChangeNotifier {
  ResponderProvider({
    ResponderRepository? repository,
    ResponderActionQueue? actionQueue,
  }) : _repo = repository ?? ResponderRepository(),
       _actions = actionQueue ?? ResponderActionQueue() {
    _actions.sender = _send;
    _actions.onChanged = _refreshPendingCount;
  }

  final ResponderRepository _repo;
  final ResponderActionQueue _actions;

  /// Called after every queue load with the incident ids now in hand.
  ///
  /// ResponderNotificationProvider uses it to tell a genuinely new assignment
  /// from an update to one already held. Injected as a callback rather than
  /// held as a reference so the two providers do not depend on each other —
  /// main.dart is the only place that knows about both.
  void Function(Iterable<String>)? onQueueLoaded;

  /// Called with the ids of nearby incidents this session has not shown before,
  /// so the caller (main.dart) can raise a quiet OS notification for each - see
  /// ResponderAlertService.notifyNearby. Never the ones this session already
  /// announced; a poll that returns the same incident again must stay silent.
  void Function(List<NearbyIncident> freshlySeen)? onNearbyArrived;

  /// Called with the ids of a previous poll's nearby incidents that are no
  /// longer in this one - answered, dispatched to someone, or aged out - so
  /// the caller can withdraw any OS notification raised for them.
  void Function(List<String> incidentIds)? onNearbyResolved;

  /// Called with an incident id once the responder has answered its alert.
  ///
  /// Wired in main.dart to ResponderAlertService.dismiss. It is a callback
  /// rather than a direct reference for the same reason onQueueLoaded is: the
  /// provider must not depend on the notification layer, and main.dart stays
  /// the only place that knows about both.
  ///
  /// Load-bearing. The dispatch notification is `ongoing` with FLAG_INSISTENT,
  /// so it repeats until something cancels it.
  void Function(String incidentId)? onAlertAnswered;

  // ── Availability ─────────────────────────────────────────
  String _availability = 'off_duty';
  bool _togglingAvailability = false;
  String? _availabilityError;

  String get availability => _availability;
  bool get isOnDuty => _availability == 'on_duty';
  bool get togglingAvailability => _togglingAvailability;
  String? get availabilityError => _availabilityError;

  // ── Queue ─────────────────────────────────────────────────
  List<ResponderIncidentModel> _queue = [];
  bool _loadingQueue = false;
  String? _queueError;

  List<ResponderIncidentModel> get queue => _queue;
  bool get loadingQueue => _loadingQueue;
  String? get queueError => _queueError;
  int get activeCount => _queue.length;

  // ── Acceptance, refusal, closing ──────────────────────────
  bool _answering = false;
  String? _answerError;

  /// True while an accept / decline / close is in flight. Distinct from
  /// `updatingStatus` so the two cannot disable each other's buttons.
  bool get answering => _answering;
  String? get answerError => _answerError;

  // ── Offline queue ─────────────────────────────────────────
  int _pendingSyncCount = 0;

  /// How many actions are waiting for a network. Shown in the shell so a
  /// crew who acted in a dead zone can see that their taps were kept, and
  /// are not silently gone.
  int get pendingSyncCount => _pendingSyncCount;
  bool get hasPendingSync => _pendingSyncCount > 0;

  // ── Distress ──────────────────────────────────────────────
  bool _raisingDistress = false;
  bool get raisingDistress => _raisingDistress;

  // ── Detail / status update ────────────────────────────────
  ResponderIncidentModel? _detailIncident;
  bool _loadingDetail = false;
  String? _detailError;
  bool _updatingStatus = false;
  String? _statusUpdateError;

  ResponderIncidentModel? get detailIncident => _detailIncident;
  bool get loadingDetail => _loadingDetail;
  String? get detailError => _detailError;
  bool get updatingStatus => _updatingStatus;
  String? get statusUpdateError => _statusUpdateError;

  // ── Dashboard ─────────────────────────────────────────────
  Map<String, dynamic>? _dashboard;
  bool _loadingDashboard = false;
  String? _dashboardError;

  Map<String, dynamic>? get dashboard => _dashboard;
  bool get loadingDashboard => _loadingDashboard;
  String? get dashboardError => _dashboardError;

  int _statInt(String key) => (_dashboard?[key] as num?)?.toInt() ?? 0;
  int? _statIntOrNull(String key) => (_dashboard?[key] as num?)?.toInt();
  double? _statDoubleOrNull(String key) =>
      (_dashboard?[key] as num?)?.toDouble();

  int get activeCritical => _statInt('active_critical');
  int get enRouteCount => _statInt('en_route_count');
  int get onSceneCount => _statInt('on_scene_count');
  int get resolvedToday => _statInt('resolved_today');
  int get resolvedPeriod => _statInt('resolved_period');
  int get statsPeriodDays => _dashboard == null ? 30 : _statInt('period_days');

  /// Minutes the oldest open assignment has been waiting, or null when the
  /// queue is empty. Null and zero mean different things here — zero means a
  /// call came in this minute — so this is deliberately nullable.
  int? get oldestWaitingMinutes => _statIntOrNull('oldest_waiting_minutes');

  /// Median dispatch-to-resolved time. Null until there is one closed
  /// incident to compute it from; rendering "0m" for "no data" would be a
  /// flattering lie on a brand-new account.
  double? get medianResponseMinutes =>
      _statDoubleOrNull('median_response_minutes');

  // ── Nearby (undispatched incidents near me) ────────────────
  //
  // A responder is now told about an incident near them the moment it lands,
  // without waiting to be dispatched to it (see app.services.proximity). This
  // is deliberately separate state from the queue: these are NOT assigned to
  // this responder, nothing here is a command, and answering "I can respond"
  // tells the dispatcher a fact rather than taking the call.

  List<NearbyIncident> _nearby = [];
  bool _loadingNearby = false;
  String? _nearbyError;

  /// Incident ids already shown this session, so a repeated poll does not
  /// re-announce the same incident as if it had just arrived.
  final Set<String> _seenNearby = <String>{};

  /// Incident ids this responder has answered, kept locally so the button
  /// reflects the answer immediately rather than waiting for the next poll.
  final Map<String, String> _nearbyAnswers = <String, String>{};

  List<NearbyIncident> get nearby => _nearby;
  bool get loadingNearby => _loadingNearby;
  String? get nearbyError => _nearbyError;

  /// Undispatched incidents near me, right now. Pass the phone's own live fix
  /// when one is in hand; omitted, the server falls back to the last reported
  /// position. Silent on failure - see the field's own doc comment for why a
  /// missed poll must never interrupt whatever the responder is doing.
  Future<void> loadNearby({double? lat, double? lng}) async {
    if (_loadingNearby) return;
    _loadingNearby = true;
    notifyListeners();
    try {
      final result = await _repo.getNearby(lat: lat, lng: lng);
      final items =
          result.items
              .map(
                (i) =>
                    _nearbyAnswers.containsKey(i.incidentId) && !i.hasAnswered
                        ? _withAnswer(i, _nearbyAnswers[i.incidentId]!)
                        : i,
              )
              .toList();
      final fresh = items.where((i) => _seenNearby.add(i.incidentId)).toList();
      // Anything this session announced before that is not in THIS reading any
      // more - answered, dispatched to someone, or aged out. Forgotten here
      // (not just reported) so if it ever reappears - handed back, re-opened -
      // it is announced again rather than staying "already seen" forever.
      final stillPresent = items.map((i) => i.incidentId).toSet();
      final resolved = _seenNearby.difference(stillPresent).toList();
      for (final id in resolved) {
        _seenNearby.remove(id);
        _nearbyAnswers.remove(id);
      }
      _nearby = items;
      _nearbyError = null;
      if (fresh.isNotEmpty) onNearbyArrived?.call(fresh);
      if (resolved.isNotEmpty) onNearbyResolved?.call(resolved);
    } on NetworkFailure {
      // Quiet. This runs on a background poll; a connectivity blip must not
      // clear a list a responder may already be reading.
    } on ServerFailure catch (e) {
      _nearbyError = e.message;
    } catch (_) {
      _nearbyError = 'Could not check nearby incidents.';
    } finally {
      _loadingNearby = false;
      notifyListeners();
    }
  }

  NearbyIncident _withAnswer(NearbyIncident i, String answer) => NearbyIncident(
    incidentId: i.incidentId,
    recordNumber: i.recordNumber,
    severity: i.severity,
    category: i.category,
    reportText: i.reportText,
    locationAddress: i.locationAddress,
    latitude: i.latitude,
    longitude: i.longitude,
    createdAt: i.createdAt,
    sosFlagged: i.sosFlagged,
    distanceKm: i.distanceKm,
    etaMinutes: i.etaMinutes,
    direction: i.direction,
    level: i.level,
    reason: i.reason,
    rank: i.rank,
    unitsFreeInRange: i.unitsFreeInRange,
    you: i.you,
    answered: answer,
  );

  /// "I can respond" or "not available" - tells the dispatcher a fact. Never
  /// assigns anything; the dispatcher still chooses and dispatches. Applied
  /// optimistically so the button reflects the answer at once.
  Future<bool> answerNearby(
    String incidentId,
    String answer, {
    double? lat,
    double? lng,
  }) async {
    _nearbyAnswers[incidentId] = answer;
    _nearby =
        _nearby
            .map((i) => i.incidentId == incidentId ? _withAnswer(i, answer) : i)
            .toList();
    notifyListeners();
    try {
      await _repo.answerNearby(incidentId, answer, lat: lat, lng: lng);
      return true;
    } on ServerFailure {
      // The dispatcher already sent someone, or duty/agency no longer match -
      // both mean this alert is stale. Drop it rather than leave a button the
      // next tap will only fail again.
      _nearby = _nearby.where((i) => i.incidentId != incidentId).toList();
      _nearbyAnswers.remove(incidentId);
      notifyListeners();
      return false;
    } on NetworkFailure {
      // Kept as answered locally; the next successful poll reconciles it.
      return true;
    }
  }

  /// Clear nearby state on sign-out - the same reasoning as
  /// ResponderNotificationProvider.unsubscribe: the next responder on this
  /// handset must not inherit what a previous one saw or answered.
  void clearNearby() {
    _nearby = [];
    _seenNearby.clear();
    _nearbyAnswers.clear();
    notifyListeners();
  }

  // ── History ───────────────────────────────────────────────
  // ── History ───────────────────────────────────────────────
  List<ResponderIncidentModel> _history = [];
  bool _loadingHistory = false;
  String? _historyError;

  List<ResponderIncidentModel> get history => _history;
  bool get loadingHistory => _loadingHistory;
  String? get historyError => _historyError;

  // ── Public API ────────────────────────────────────────────

  /// Toggle availability: on_duty ↔ off_duty.
  Future<bool> toggleAvailability() async {
    _togglingAvailability = true;
    _availabilityError = null;
    notifyListeners();

    final newValue = _availability == 'on_duty' ? 'off_duty' : 'on_duty';
    try {
      await _repo.setAvailability(newValue);
      _availability = newValue;
      notifyListeners();
      return true;
    } on ServerFailure catch (e) {
      _availabilityError = e.message;
      notifyListeners();
      return false;
    } on NetworkFailure catch (e) {
      _availabilityError = e.message;
      notifyListeners();
      return false;
    } finally {
      _togglingAvailability = false;
      notifyListeners();
    }
  }

  /// Set availability directly (for initial load from server profile).
  void setAvailabilityLocal(String value) {
    if (_availability != value) {
      _availability = value;
      notifyListeners();
    }
  }

  /// Begin watching for a network and flush anything already waiting.
  ///
  /// Called once the responder is signed in. Safe to call again — the
  /// queue guards its own subscription, because the auth listener fires
  /// afresh on every token refresh.
  Future<void> startActionQueue() async {
    await _actions.start();
    await _refreshPendingCount();
  }

  Future<void> _refreshPendingCount() async {
    final count = await _actions.pendingCount();
    if (count == _pendingSyncCount) return;
    _pendingSyncCount = count;
    notifyListeners();
  }

  /// How the queue actually sends one action. Returns false to keep it.
  ///
  /// A ServerFailure returns TRUE — meaning "stop holding this". That
  /// reads backwards and is deliberate: the server answered, and its
  /// answer was no. Replaying a 422 every time the signal returns would
  /// block every action behind it in the queue forever. Only a
  /// NetworkFailure — nobody answered at all — is worth retrying.
  Future<bool> _send(PendingAction action) async {
    try {
      final id = action.incidentId;
      switch (action.kind) {
        case ResponderActionKind.accept:
          await _repo.acceptIncident(id!, occurredAt: action.occurredAt);
        case ResponderActionKind.decline:
          await _repo.declineIncident(
            id!,
            reason: action.body['reason'] as String,
            note: action.body['note'] as String?,
            occurredAt: action.occurredAt,
          );
        case ResponderActionKind.status:
          await _repo.updateStatus(id!, action.body['status'] as String);
        case ResponderActionKind.close:
          await _repo.closeIncident(
            id!,
            outcome: action.body['outcome'] as String,
            notes: action.body['notes'] as String?,
            injured: (action.body['injured'] as num?)?.toInt(),
            fatal: (action.body['fatal'] as num?)?.toInt(),
            transported: (action.body['transported'] as num?)?.toInt(),
            occurredAt: action.occurredAt,
          );
        case ResponderActionKind.sceneMedia:
          await _repo.attachSceneMedia(
            id!,
            (action.body['paths'] as List<dynamic>).cast<String>(),
          );
        case ResponderActionKind.distress:
          await _repo.raiseDistress(
            latitude: (action.body['latitude'] as num?)?.toDouble(),
            longitude: (action.body['longitude'] as num?)?.toDouble(),
            incidentId: action.body['incident_id'] as String?,
            note: action.body['note'] as String?,
          );
      }
      return true;
    } on NetworkFailure {
      return false;
    } on ServerFailure catch (e) {
      debugPrint(
        '[ResponderProvider] server refused ${action.kind.name}: ${e.message}',
      );
      return true;
    }
  }

  /// Load the active incident queue.
  Future<void> loadQueue() async {
    if (_loadingQueue) return;
    _loadingQueue = true;
    _queueError = null;
    notifyListeners();

    try {
      _queue = await _repo.getMyQueue();
      // Everything in hand is, by definition, not a new arrival. Without this
      // the first realtime event on any of these incidents would be announced
      // as a fresh assignment.
      onQueueLoaded?.call(_queue.map((i) => i.id));
    } on NetworkFailure catch (e) {
      _queueError = e.message;
    } on ServerFailure catch (e) {
      _queueError = e.message;
    } catch (_) {
      _queueError = 'Failed to load queue.';
    } finally {
      _loadingQueue = false;
      notifyListeners();
    }
  }

  /// Load this responder's own figures.
  Future<void> loadDashboard() async {
    if (_loadingDashboard) return;
    _loadingDashboard = true;
    _dashboardError = null;
    notifyListeners();

    try {
      _dashboard = await _repo.getDashboard();
    } on NetworkFailure catch (e) {
      _dashboardError = e.message;
    } on ServerFailure catch (e) {
      _dashboardError = e.message;
    } catch (_) {
      _dashboardError = 'Could not load your figures.';
    } finally {
      _loadingDashboard = false;
      notifyListeners();
    }
  }

  /// Load full detail for a single incident.
  Future<void> loadIncidentDetail(String incidentId) async {
    _loadingDetail = true;
    _detailError = null;
    _statusUpdateError = null;
    notifyListeners();

    try {
      _detailIncident = await _repo.getIncidentDetail(incidentId);
    } on ServerFailure catch (e) {
      _detailError = e.message;
    } on NetworkFailure catch (e) {
      _detailError = e.message;
    } catch (_) {
      _detailError = 'Could not load incident details.';
    } finally {
      _loadingDetail = false;
      notifyListeners();
    }
  }

  /// Advance the incident FSM to the next status.
  /// Returns true on success.
  Future<bool> advanceStatus(String incidentId, String newStatus) async {
    _updatingStatus = true;
    _statusUpdateError = null;
    notifyListeners();

    try {
      await _repo.updateStatus(incidentId, newStatus);

      // Update local state optimistically
      _queue =
          _queue.where((i) {
            // Remove from queue if resolved/cancelled
            if (i.id == incidentId && newStatus == 'resolved') return false;
            return true;
          }).toList();

      // Reload detail to reflect new status
      if (_detailIncident?.id == incidentId) {
        await loadIncidentDetail(incidentId);
      }

      notifyListeners();
      return true;
    } on ServerFailure catch (e) {
      _statusUpdateError = e.message;
      notifyListeners();
      return false;
    } on NetworkFailure catch (e) {
      _statusUpdateError = e.message;
      notifyListeners();
      return false;
    } finally {
      _updatingStatus = false;
      notifyListeners();
    }
  }

  // ── Phase 6D verbs ────────────────────────────────────────

  /// "I am taking this call."
  ///
  /// Optimistic, and it has to be: the crew is about to put the phone down
  /// and drive. The local model flips to accepted immediately, the action
  /// is queued, and the queue keeps it alive through a dead zone with the
  /// time it was actually pressed.
  Future<bool> acceptIncident(String incidentId) async {
    _answering = true;
    _answerError = null;
    notifyListeners();
    try {
      await _repo.acceptIncident(incidentId);
      await _afterAnswer(incidentId);
      return true;
    } on NetworkFailure {
      // Kept, not lost. This is the whole reason the queue exists — a
      // responder who accepted from a dead spot must not show as
      // unanswered on the dispatcher's board once signal returns.
      await _actions.enqueue(
        ResponderActionKind.accept,
        incidentId: incidentId,
      );
      await _refreshPendingCount();
      return true;
    } on ServerFailure catch (e) {
      _answerError = e.message;
      return false;
    } finally {
      _answering = false;
      notifyListeners();
    }
  }

  /// Hand the call back, with a reason the dispatcher can act on.
  Future<bool> declineIncident(
    String incidentId, {
    required String reason,
    String? note,
  }) async {
    _answering = true;
    _answerError = null;
    notifyListeners();
    try {
      await _repo.declineIncident(incidentId, reason: reason, note: note);
      _dropFromQueue(incidentId);
      return true;
    } on NetworkFailure {
      await _actions.enqueue(
        ResponderActionKind.decline,
        incidentId: incidentId,
        body: {'reason': reason, if (note != null) 'note': note},
      );
      _dropFromQueue(incidentId);
      await _refreshPendingCount();
      return true;
    } on ServerFailure catch (e) {
      _answerError = e.message;
      return false;
    } finally {
      _answering = false;
      notifyListeners();
    }
  }

  /// Close the call with what was actually found.
  ///
  /// The step that makes the severity rubric checkable: this is the first
  /// and only place the system learns whether the emergency it scored
  /// CRITICAL was one.
  Future<bool> closeIncident(
    String incidentId, {
    required String outcome,
    String? notes,
    int? injured,
    int? fatal,
    int? transported,
  }) async {
    _answering = true;
    _answerError = null;
    notifyListeners();
    try {
      await _repo.closeIncident(
        incidentId,
        outcome: outcome,
        notes: notes,
        injured: injured,
        fatal: fatal,
        transported: transported,
      );
      _dropFromQueue(incidentId);
      return true;
    } on NetworkFailure {
      await _actions.enqueue(
        ResponderActionKind.close,
        incidentId: incidentId,
        body: {
          'outcome': outcome,
          if (notes != null) 'notes': notes,
          if (injured != null) 'injured': injured,
          if (fatal != null) 'fatal': fatal,
          if (transported != null) 'transported': transported,
        },
      );
      _dropFromQueue(incidentId);
      await _refreshPendingCount();
      return true;
    } on ServerFailure catch (e) {
      _answerError = e.message;
      return false;
    } finally {
      _answering = false;
      notifyListeners();
    }
  }

  // ── Incident thread (field updates / Section 12 communication) ──
  //
  // Thin pass-throughs, same reasoning as the resident side: only one
  // thread is ever open on screen, so the widget that shows it owns its own
  // loading state.

  Future<List<IncidentNote>> fetchIncidentNotes(String incidentId) =>
      _repo.getIncidentNotes(incidentId);

  /// Returns an error message, or null on success.
  Future<String?> sendIncidentNote(String incidentId, String body) async {
    try {
      await _repo.addIncidentNote(incidentId, body);
      return null;
    } on ServerFailure catch (e) {
      return e.message;
    } on NetworkFailure catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not send your update.';
    }
  }

  // ── Escalation (Section 14) ──────────────────────────────────

  /// Returns an error message, or null on success.
  Future<String?> escalateIncident(String incidentId, String reason) async {
    _answering = true;
    _answerError = null;
    notifyListeners();
    try {
      await _repo.escalateIncident(incidentId, reason);
      return null;
    } on ServerFailure catch (e) {
      return e.message;
    } on NetworkFailure catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not send the escalation. Use the radio.';
    } finally {
      _answering = false;
      notifyListeners();
    }
  }

  /// Ask a second agency to attend. Returns their station name on success.
  Future<String?> requestBackup(
    String incidentId, {
    required String agencyType,
    required String reason,
  }) async {
    _answering = true;
    _answerError = null;
    notifyListeners();
    try {
      final result = await _repo.requestBackup(
        incidentId,
        agencyType: agencyType,
        reason: reason,
      );
      return result['station_name'] as String? ?? agencyType;
    } on NetworkFailure catch (e) {
      // NOT queued. A backup request creates a whole new incident for
      // another agency's dispatcher, and raising one twenty minutes late
      // from a queue — after the crew has probably called it in on the
      // radio — would put a duplicate emergency on somebody's board.
      _answerError = '${e.message} Use the radio.';
      return null;
    } on ServerFailure catch (e) {
      _answerError = e.message;
      return null;
    } finally {
      _answering = false;
      notifyListeners();
    }
  }

  /// The responder's own emergency.
  ///
  /// Tries live first and only falls back to the queue, because a distress
  /// signal that syncs in twenty minutes is not a distress signal. Returns
  /// false when it could only be queued, so the UI can say out loud that
  /// the radio is now the primary channel.
  Future<bool> raiseDistress({String? incidentId, String? note}) async {
    _raisingDistress = true;
    notifyListeners();
    double? lat;
    double? lng;
    try {
      // Best effort. A missing fix must never stop the signal — the
      // backend accepts one with no location at all for exactly this.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Keep going without it.
    }

    try {
      await _repo.raiseDistress(
        latitude: lat,
        longitude: lng,
        incidentId: incidentId,
        note: note,
      );
      return true;
    } catch (_) {
      await _actions.enqueue(
        ResponderActionKind.distress,
        body: {
          if (lat != null) 'latitude': lat,
          if (lng != null) 'longitude': lng,
          if (incidentId != null) 'incident_id': incidentId,
          if (note != null) 'note': note,
        },
      );
      await _refreshPendingCount();
      return false;
    } finally {
      _raisingDistress = false;
      notifyListeners();
    }
  }

  /// Attach photos taken on scene.
  Future<bool> attachSceneMedia(String incidentId, List<String> paths) async {
    if (paths.isEmpty) return true;
    try {
      await _repo.attachSceneMedia(incidentId, paths);
      return true;
    } on NetworkFailure {
      await _actions.enqueue(
        ResponderActionKind.sceneMedia,
        incidentId: incidentId,
        body: {'paths': paths},
      );
      await _refreshPendingCount();
      return true;
    } on ServerFailure catch (e) {
      _answerError = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Drop a closed or refused incident from the local queue immediately.
  ///
  /// The server has it, or the queue does. Either way it is no longer this
  /// crew's, and leaving it on screen until the next poll invites a second
  /// tap on something already handed back.
  void _dropFromQueue(String incidentId) {
    _queue = _queue.where((i) => i.id != incidentId).toList();
    if (_detailIncident?.id == incidentId) _detailIncident = null;
    notifyListeners();
  }

  /// Refresh after an acceptance so the detail screen shows the status
  /// button in place of ACCEPT / CAN'T RESPOND.
  Future<void> _afterAnswer(String incidentId) async {
    if (_detailIncident?.id == incidentId) {
      await loadIncidentDetail(incidentId);
    }
    await loadQueue();
  }

  /// Load resolved/cancelled history.
  Future<void> loadHistory() async {
    if (_loadingHistory) return;
    _loadingHistory = true;
    _historyError = null;
    notifyListeners();

    try {
      _history = await _repo.getHistory();
    } on NetworkFailure catch (e) {
      _historyError = e.message;
    } on ServerFailure catch (e) {
      _historyError = e.message;
    } catch (_) {
      _historyError = 'Failed to load history.';
    } finally {
      _loadingHistory = false;
      notifyListeners();
    }
  }

  /// Forget the incident the detail screen was showing.
  ///
  /// The detail screen calls this from its own `dispose`, and it passes
  /// [notify] false there. Notifying during `dispose` runs while the widget
  /// tree is being torn down, when nothing may be marked for rebuild, and it
  /// threw "setState() or markNeedsBuild() called when widget tree was
  /// locked" every time the screen was closed. Nothing still on screen reads
  /// the detail, and the next detail screen loads its own.
  void clearDetail({bool notify = true}) {
    _detailIncident = null;
    _detailError = null;
    _statusUpdateError = null;
    if (notify) notifyListeners();
  }

  // ── Location reporting ────────────────────────────────────

  /// How often an on-duty responder reports where they are.
  ///
  /// Two minutes is a compromise between a map that is useful and a battery
  /// that lasts a shift. A dispatcher deciding who is nearest does not need
  /// second-by-second truth; they need to not be looking at a position from
  /// an hour ago. GPS is the single largest power draw on the handset, and a
  /// responder whose phone dies is worse than a stale dot.
  static const _locationInterval = Duration(minutes: 2);

  Timer? _locationTimer;

  /// True once a ping has actually landed. Distinct from "on duty": a
  /// responder can be on duty with location permission denied, and the profile
  /// screen should be able to say so rather than implying the map knows where
  /// they are.
  bool _locationReported = false;
  bool get locationReported => _locationReported;

  /// Start reporting position, if the responder is on duty.
  ///
  /// Deliberately tied to duty status rather than to the app being open. An
  /// off-duty responder receives no assignments, so their position is nobody's
  /// business — tracking them anyway would be surveillance rather than
  /// dispatch, and the dashboard map filters to on-duty regardless.
  void startLocationReporting() {
    if (_locationTimer != null) return;
    _pingLocation();
    _locationTimer = Timer.periodic(_locationInterval, (_) => _pingLocation());
  }

  void stopLocationReporting() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _locationReported = false;
    // An off-duty responder is not eligible for a nearby alert (the backend
    // returns on_duty: false, items: []), and signing out must not leave the
    // next person on this handset looking at what this one was told.
    clearNearby();
  }

  Future<void> _pingLocation() async {
    if (!isOnDuty) return;
    try {
      // No permission REQUEST here. This runs on a timer, and a permission
      // dialog appearing unprompted while a responder is reading an incident
      // is an interruption at the worst possible moment. Permission is asked
      // for once, in the UI, when duty is switched on.
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final ok = await _repo.updateLocation(pos.latitude, pos.longitude);
      if (ok != _locationReported) {
        _locationReported = ok;
        notifyListeners();
      }
      // Piggy-backs on the fix this ping already paid for, rather than a
      // second timer and a second GPS read. Same two-minute cadence the map's
      // own responder-location freshness is already built around (the backend
      // trusts a position for ten minutes), and it is naturally gated on duty
      // status because this whole method only runs while on duty.
      unawaited(loadNearby(lat: pos.latitude, lng: pos.longitude));
    } catch (_) {
      // A failed fix is normal indoors and under cover. The next tick tries
      // again; nothing about it is worth telling a responder who is driving.
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }
}
