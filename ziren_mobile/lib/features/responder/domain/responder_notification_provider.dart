import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-app notification model for Responder-facing events.
///
/// Only things that happen TO a responder become notifications: an assignment,
/// dispatch standing them down, a change of priority. The responder's own
/// progress (marking themselves en route, on scene, closed) used to raise one too
/// - every tap of "I'm on my way" left an unread "Incident update" in their own
/// bell - and none of it said what had actually happened.
class ResponderNotification {
  const ResponderNotification({
    required this.incidentId,
    required this.category,
    required this.severity,
    required this.eventType,
    required this.receivedAt,
    this.address,
    this.previousSeverity,
  });

  final String incidentId;
  final String category;
  final String severity;

  /// 'assigned' | 'cancelled' | 'severity' | 'status_update'
  final String eventType;
  final DateTime receivedAt;

  /// Where it is, when the row says.
  final String? address;

  /// What the priority was before, for a 'severity' change.
  final String? previousSeverity;

  bool get isNewAssignment => eventType == 'assigned';

  /// Dispatch cancelled an incident this responder was on. Time-critical: a crew
  /// that is already driving needs to hear it, and the assignment alarm must stop.
  bool get isStandDown => eventType == 'cancelled';

  String get label {
    final cat = _categoryLabel(category);
    return switch (eventType) {
      'assigned' => 'New incident assigned to you — $cat',
      'cancelled' => 'Stand down — $cat incident cancelled',
      'severity' => 'Priority changed — $cat',
      _ => 'Incident update — $cat',
    };
  }

  /// The second line: what to know or do, said for THIS event.
  String get detail {
    final where = (address ?? '').trim();
    switch (eventType) {
      case 'assigned':
        final sev = severity.toUpperCase();
        final head =
            sev == 'PENDING'
                // "Severity PENDING" would read as a system fault to a responder
                // at 3am. It means the dispatcher sent the crew before setting a
                // severity, which is a legitimate thing to do in a hurry.
                ? 'Incident ${shortId.toUpperCase()}'
                : sev;
        return where.isEmpty
            ? '$head — open Ziren for the details.'
            : '$head · $where';
      case 'cancelled':
        return 'Dispatch cancelled this incident. You do not need to respond.';
      case 'severity':
        final was = (previousSeverity ?? '').toUpperCase();
        final now = severity.toUpperCase();
        return was.isEmpty
            ? 'Now $now.'
            : '$was → $now. Open Ziren for the details.';
      default:
        return 'Open Ziren for the details.';
    }
  }

  String get shortId =>
      incidentId.length >= 8 ? incidentId.substring(0, 8) : incidentId;

  /// These keys are the raw `incidents.incident_category` values read at
  /// line 133 — not shorthand. Four of them used to be abbreviated
  /// ('medical', 'flood', 'crime', 'missing'), which matched nothing the
  /// database actually stores, so every medical, flood and crime assignment
  /// notified the responder as a bare "Incident".
  ///
  /// hazmat and missing_person were retired as reportable categories in
  /// Phase 4 (see IncidentCategory). They stay here so incidents filed before
  /// migration 019 — or rows in an environment where it has not been applied —
  /// still read correctly on the responder's screen.
  String _categoryLabel(String cat) {
    return switch (cat) {
      'fire' => 'Fire',
      'medical_trauma' => 'Medical/Trauma',
      'vehicular' => 'Vehicular',
      'flood_landslide_calamity' => 'Flood/Landslide',
      'domestic_dispute_crime' => 'Domestic Dispute/Crime',
      'other' => 'Incident',
      'hazmat' => 'HAZMAT', // legacy, pre-migration 019
      'missing_person' => 'Missing Person', // legacy, pre-migration 019
      _ => 'Incident',
    };
  }
}

/// Supabase Realtime subscription for the authenticated Responder.
///
/// Subscribes to `postgres_changes` on the `incidents` table filtered by
/// `assigned_responder_id = auth.uid()`.
///
/// Security: the filter is belt-and-suspenders on top of RLS — the Realtime
/// channel only receives rows where `assigned_responder_id = auth.uid()`,
/// consistent with the guarantee already enforced server-side.
///
/// TWO BUGS LIVED HERE, AND THEY CANCELLED EACH OTHER INTO SILENCE
///
/// 1. The table was not on the `supabase_realtime` publication, so no event of
///    any kind ever arrived. Fixed in migration 022 — and note that the
///    channel reports SUBSCRIBED either way, which is why this went unnoticed:
///    a subscription to an unpublished table looks exactly like a quiet night.
///
/// 2. This class treated INSERT as "you have been assigned" and UPDATE as "the
///    status changed". That is backwards for how an assignment actually
///    happens. A resident files the report, so the INSERT carries
///    assigned_responder_id = NULL and never matches the filter. The
///    dispatcher assigns later, which is an UPDATE. So even with the
///    publication fixed, every real assignment would have arrived labelled
///    "Incident update", and [onNewAssignment] — the callback that reloads the
///    queue — would never have fired.
///
/// What replaces the event type is [_known]: the set of incident ids this
/// session has already seen assigned to us. Anything outside it is new. That
/// is correct across a reconnect, a cold start, a reassignment away and back,
/// and it does not need REPLICA IDENTITY FULL to diff the old row — see
/// migration 022 for why that matters.
///
/// On a new assignment, [onNewAssignment] is called so the caller (main.dart)
/// can trigger a queue reload in [ResponderProvider] without creating a
/// circular dependency between providers.
class ResponderNotificationProvider extends ChangeNotifier {
  ResponderNotificationProvider({this.onNewAssignment, this.onAlert});

  /// Called when a new assignment arrives — use this to reload the queue.
  final VoidCallback? onNewAssignment;

  /// Called for anything worth interrupting the responder about.
  ///
  /// Separate from [onNewAssignment] because they are different jobs: one
  /// refreshes data, the other raises an OS notification and a sound. Keeping
  /// them apart means a queue reload cannot accidentally buzz the phone, and a
  /// notification cannot be dropped by a caller that only wanted the reload.
  final void Function(ResponderNotification)? onAlert;

  final List<ResponderNotification> _unread = [];

  /// Incident ids already known to be assigned to this responder.
  ///
  /// Seeded from the queue by [seedKnown] on every load, so an app that starts
  /// with three incidents in hand does not announce all three as new.
  final Set<String> _known = <String>{};

  /// Where each held incident last stood, so a change of priority or a
  /// cancellation can be told apart from an update that changed neither.
  final Map<String, String> _lastStatus = <String, String>{};
  final Map<String, String> _lastSeverity = <String, String>{};
  final Set<String> _stoodDown = <String>{};

  RealtimeChannel? _channel;
  bool _subscribed = false;

  List<ResponderNotification> get unread => List.unmodifiable(_unread);
  int get unreadCount => _unread.length;
  bool get hasUnread => _unread.isNotEmpty;
  bool get isSubscribed => _subscribed;

  /// Record incidents already in hand, so they are not reported as new.
  ///
  /// Called after every queue load. Deliberately additive: an incident that
  /// has since been resolved and dropped out of the queue must stay in the set,
  /// or a late UPDATE on it would be announced as a fresh assignment.
  void seedKnown(Iterable<String> incidentIds) {
    _known.addAll(incidentIds);
  }

  // ── Subscribe ─────────────────────────────────────────────

  void subscribe() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null || _subscribed) return;

    _channel =
        client
            .channel('responder_assignments_$userId')
            // Both event types route to the same handler. Which one carried the
            // assignment is not knowable from the event type — see the class
            // docstring — so _onEvent decides from the incident id instead.
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'incidents',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'assigned_responder_id',
                value: userId,
              ),
              callback: _onEvent,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'incidents',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'assigned_responder_id',
                value: userId,
              ),
              callback: _onEvent,
            )
            .subscribe();

    _subscribed = true;
  }

  Future<void> unsubscribe() async {
    if (_channel != null) {
      await Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
    _subscribed = false;
    _unread.clear();
    // The known set is per-session and per-account. Leaving it populated
    // across a logout would mean the next responder to sign in on this handset
    // silently swallows their first notification for any incident this one
    // happened to hold.
    _known.clear();
    _lastStatus.clear();
    _lastSeverity.clear();
    _stoodDown.clear();
    notifyListeners();
  }

  // ── Realtime callback ─────────────────────────────────────

  /// Exposed so the announce/ignore decisions can be tested without a socket.
  @visibleForTesting
  void handleEvent(PostgresChangePayload payload) => _onEvent(payload);

  void _onEvent(PostgresChangePayload payload) {
    final row = payload.newRecord;
    if (row.isEmpty) return;

    final id = row['id'] as String? ?? '';
    if (id.isEmpty) return;

    final status = row['status'] as String?;
    final severity = row['severity'] as String?;
    final previousSeverity = _lastSeverity[id];
    if (status != null) _lastStatus[id] = status;
    if (severity != null) _lastSeverity[id] = severity;

    // New to this responder, whatever the event type says. An assignment
    // reaches us as an UPDATE, because the row was INSERTed by the resident
    // with no responder on it. And an assignment always leaves the incident
    // `dispatched`: an event for a row we do not hold that says anything else
    // (a cancelled incident that is no longer in the queue we were seeded
    // from, say) is not a call, and must not sound like one.
    final wasKnown = _known.contains(id);
    final isNewAssignment =
        !wasKnown && (status == null || status == 'dispatched');
    _known.add(id);

    final category = row['incident_category'] as String? ?? 'other';
    final address = row['location_address'] as String?;

    ResponderNotification make(String type) => ResponderNotification(
      incidentId: id,
      category: category,
      severity: severity ?? 'pending',
      eventType: type,
      receivedAt: DateTime.now(),
      address: address,
      previousSeverity: previousSeverity,
    );

    if (isNewAssignment) {
      final notification = make('assigned');
      _unread.insert(0, notification);
      notifyListeners();
      // Reload so the badge and the list update without a manual pull, and
      // raise an OS notification: a responder is not looking at the screen
      // when the call comes in, which is the whole point of the feature.
      onNewAssignment?.call();
      onAlert?.call(notification);
      return;
    }

    // Dispatch cancelled it while this responder held it. Once per incident:
    // a later update to the same row must not stand them down again.
    if (status == 'cancelled' && wasKnown && _stoodDown.add(id)) {
      final notification = make('cancelled');
      _unread.insert(0, notification);
      notifyListeners();
      // The queue has to drop it, and the OS notification both tells the crew and
      // silences the assignment alarm that may still be sounding for it.
      onNewAssignment?.call();
      onAlert?.call(notification);
      return;
    }

    // The dispatcher changed the priority. A real change only: with no earlier
    // reading there is nothing to compare, and an update that left it alone is
    // not news. Everything else - the responder's own en route / on scene /
    // closed, a field edited - says nothing to the person who did it.
    if (severity != null &&
        previousSeverity != null &&
        severity != previousSeverity &&
        status != 'cancelled') {
      _unread.insert(0, make('severity'));
      notifyListeners();
    }
  }

  // ── Read / dismiss ────────────────────────────────────────

  void markAllRead() {
    if (_unread.isEmpty) return;
    _unread.clear();
    notifyListeners();
  }

  void dismiss(int index) {
    if (index >= 0 && index < _unread.length) {
      _unread.removeAt(index);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}
