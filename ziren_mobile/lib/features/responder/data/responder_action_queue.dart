import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';

/// Responder actions that survive a dead zone.
///
/// WHY THIS EXISTS
///
/// The responder is the one person in this system guaranteed to lose signal.
/// They are driving away from the town centre, into the barangays, up the
/// mountain — that is the job. Every other role sits still somewhere with
/// coverage.
///
/// Until now every write from that phone was fire-and-forget over HTTP with a
/// 10-second timeout, and a failure was a red toast. Which means: a crew that
/// accepted a call in a dead spot was still shown as UNANSWERED on the
/// dispatcher's board. A crew that marked ARRIVED at the scene lost the
/// arrival time permanently — and arrival time is the numerator of the only
/// response-time figure this product reports.
///
/// THE TIMESTAMP IS THE POINT, NOT THE RETRY
///
/// A naive retry queue would replay the action later and let the server stamp
/// the time it finally landed. That is worse than useless for measurement: an
/// acceptance that happened at 14:02 and synced at 14:40 would be recorded as
/// a 38-minute response. So every queued action carries `occurred_at`, the
/// instant the responder actually pressed the button, and the backend clamps
/// it to [dispatched_at, now] rather than trusting it outright — a client that
/// can set its own timestamps unbounded can rewrite its own performance.
///
/// WHAT IS DELIBERATELY NOT QUEUED
///
/// Reads. A queue full of stale GETs is just a slow way to show old data.
/// And the panic button, which is queued only as a last resort and is always
/// attempted live first — a distress signal that syncs in twenty minutes is
/// not a distress signal.
class ResponderActionQueue {
  ResponderActionQueue({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// One key, one JSON list. The queue is bounded by how many actions a single
  /// crew can take in one dead zone — realistically under ten — so a row-per-
  /// action store would be more machinery than the problem deserves.
  static const _storageKey = 'responder_pending_actions_v1';

  /// Refuse to grow without limit. If this is ever hit, the phone has been
  /// offline for a whole shift and the oldest actions are the least useful:
  /// dropping the front keeps the most recent picture of what the crew did.
  static const _maxQueued = 50;

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// Serialises every read-modify-write on the store.
  ///
  /// THE BUG THIS EXISTS TO PREVENT, which the tests caught: enqueue and
  /// flush both do read → modify → write, and enqueue kicks off a flush it
  /// does not await. So a second enqueue arriving while that flush was in
  /// flight could read the list, append, and write — and then the flush's
  /// own write would land on top with the pre-append copy. A LOST UPDATE,
  /// and what it loses is a responder's action in a dead zone, which is the
  /// one thing this class exists to not do.
  ///
  /// A chained Future is enough. There is no contention worth a real lock
  /// here — one handset, a handful of actions — and the ordering it
  /// guarantees is the whole requirement.
  Future<void> _lock = Future<void>.value();

  /// Run [body] after every previously scheduled store operation.
  Future<T> _serial<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Called for each action when it is time to send it. Returns true when the
  /// server accepted it, false to keep it queued for the next attempt.
  ///
  /// Injected rather than holding a ResponderRepository, so the queue has no
  /// opinion about HTTP and can be tested with a function.
  Future<bool> Function(PendingAction action)? sender;

  /// Fired after any change, so the UI can show "3 waiting to sync".
  VoidCallback? onChanged;

  // ── Lifecycle ─────────────────────────────────────────────

  /// Start watching for connectivity and flush whatever is already waiting.
  ///
  /// Safe to call more than once — the auth listener can fire again on a token
  /// refresh, and a second subscription would double every flush.
  Future<void> start() async {
    _connSub ??= _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(flush());
    });
    await flush();
  }

  void stop() {
    _connSub?.cancel();
    _connSub = null;
  }

  // ── Queue operations ──────────────────────────────────────

  Future<List<PendingAction>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PendingAction.fromJson)
          .toList();
    } catch (e) {
      // Corrupt store. Dropping it is the right call: a queue that cannot be
      // parsed cannot be sent either, and keeping it would fail on every
      // future flush forever.
      debugPrint('[ResponderActionQueue] unreadable queue, dropping: $e');
      await prefs.remove(_storageKey);
      return const [];
    }
  }

  Future<int> pendingCount() async => (await pending()).length;

  Future<void> _write(List<PendingAction> actions) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        actions.length > _maxQueued
            ? actions.sublist(actions.length - _maxQueued)
            : actions;
    await prefs.setString(
      _storageKey,
      jsonEncode(trimmed.map((a) => a.toJson()).toList()),
    );
    onChanged?.call();
  }

  /// Record an action to be sent when there is a network again.
  ///
  /// `occurredAt` defaults to now and should almost never be passed — the
  /// whole design rests on it being the moment the button was pressed, not the
  /// moment somebody got around to enqueuing it.
  Future<void> enqueue(
    ResponderActionKind kind, {
    String? incidentId,
    Map<String, dynamic> body = const {},
    DateTime? occurredAt,
  }) async {
    // The timestamp is taken HERE, before the lock, so that waiting behind
    // another store operation cannot shift the moment the responder is
    // recorded as having pressed the button.
    final action = PendingAction(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      incidentId: incidentId,
      body: body,
      occurredAt: occurredAt ?? DateTime.now().toUtc(),
    );

    await _serial(() async {
      final actions = List<PendingAction>.from(await pending());

      // Supersede rather than append for the actions that are a STATE, not
      // an EVENT. Two queued "accept"s for one incident are the same fact
      // recorded twice, and replaying both would make the second overwrite
      // the first with a later timestamp — losing exactly the number this
      // queue exists to preserve.
      if (action.kind.supersedesEarlier) {
        actions.removeWhere(
          (a) => a.kind == action.kind && a.incidentId == action.incidentId,
        );
      }

      actions.add(action);
      await _write(actions);
    });

    unawaited(flush());
  }

  /// Try to send everything, oldest first.
  ///
  /// ORDER MATTERS AND IS NOT NEGOTIABLE. Accept must land before En Route,
  /// which must land before Arrived, which must land before Close — the
  /// backend's FSM rejects anything else with a 422. Sending in parallel would
  /// be faster and would fail most of the queue.
  Future<void> flush() async {
    if (sender == null) return;

    // NO "already flushing" GUARD, deliberately.
    //
    // The obvious version returns early when a flush is in progress. Two
    // things go wrong with it, and the tests found both. A flush requested
    // during one is silently dropped, so an action enqueued mid-flush waits
    // for the next connectivity change — which on a phone that regains signal
    // once and then holds it may never come. And the early return makes
    // flush() complete before the work does, so every caller that awaits it
    // (startActionQueue, and every test) is lied to.
    //
    // _serial already gives the only property the guard was reaching for:
    // passes run one at a time, in order. A redundant second pass just reads
    // an empty list and returns, which costs one decode.
    await _serial(_flushOnce);
  }

  /// One pass over the queue. Always called inside [_serial].
  Future<void> _flushOnce() async {
    {
      final actions = await pending();
      if (actions.isEmpty) return;

      final survivors = <PendingAction>[];
      var stopped = false;

      for (final action in actions) {
        if (stopped) {
          // Once one action fails on the network, the rest stay queued
          // untried. Skipping ahead would let a later status land before an
          // earlier one.
          survivors.add(action);
          continue;
        }
        try {
          final ok = await sender!(action);
          if (!ok) {
            survivors.add(action.withAttempt());
            stopped = true;
          }
        } catch (e) {
          debugPrint('[ResponderActionQueue] ${action.kind.name} failed: $e');
          survivors.add(action.withAttempt());
          stopped = true;
        }
      }

      // Anything that has failed this many times is not a connectivity
      // problem — it is an action the server will never accept (a call
      // somebody else was reassigned, an incident already closed). Retrying it
      // forever would block every action behind it in the queue.
      final kept = survivors.where((a) => a.attempts < 8).toList();
      if (kept.length != survivors.length) {
        debugPrint(
          '[ResponderActionQueue] dropped ${survivors.length - kept.length} '
          'action(s) the server kept refusing',
        );
      }

      await _write(kept);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    onChanged?.call();
  }
}

/// The verbs that can wait for a network.
enum ResponderActionKind {
  accept,
  decline,
  status,
  close,
  sceneMedia,
  distress;

  /// True when a second instance of this action for the same incident
  /// replaces the first rather than following it.
  ///
  /// `accept` is a state: pressed twice, it happened once. `sceneMedia` is an
  /// event: two batches of photos are two batches, and collapsing them would
  /// lose the first one.
  bool get supersedesEarlier => switch (this) {
    ResponderActionKind.accept => true,
    ResponderActionKind.status => true,
    ResponderActionKind.decline => true,
    ResponderActionKind.close => true,
    ResponderActionKind.sceneMedia => false,
    ResponderActionKind.distress => false,
  };
}

/// One queued action, with the time it really happened.
class PendingAction {
  const PendingAction({
    required this.id,
    required this.kind,
    required this.occurredAt,
    this.incidentId,
    this.body = const {},
    this.attempts = 0,
  });

  final String id;
  final ResponderActionKind kind;
  final String? incidentId;
  final Map<String, dynamic> body;

  /// When the responder pressed the button — NOT when this was sent.
  final DateTime occurredAt;

  final int attempts;

  PendingAction withAttempt() => PendingAction(
    id: id,
    kind: kind,
    incidentId: incidentId,
    body: body,
    occurredAt: occurredAt,
    attempts: attempts + 1,
  );

  /// The body as it goes over the wire, with the true time attached.
  Map<String, dynamic> get wireBody => {
    ...body,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'incident_id': incidentId,
    'body': body,
    'occurred_at': occurredAt.toIso8601String(),
    'attempts': attempts,
  };

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
    id: json['id'] as String? ?? '0',
    kind: ResponderActionKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ResponderActionKind.status,
    ),
    incidentId: json['incident_id'] as String?,
    body: Map<String, dynamic>.from(json['body'] as Map? ?? const {}),
    occurredAt:
        DateTime.tryParse(json['occurred_at'] as String? ?? '') ??
        DateTime.now().toUtc(),
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
  );

  /// What the responder is shown while this is waiting.
  String label(AppLocalizations t) => switch (kind) {
    ResponderActionKind.accept => t.respActionAccept,
    ResponderActionKind.decline => t.respActionDecline,
    ResponderActionKind.status => t.respActionStatusUpdate,
    ResponderActionKind.close => t.respActionClose,
    ResponderActionKind.sceneMedia => t.respActionSceneMedia,
    ResponderActionKind.distress => t.respActionDistress,
  };
}
