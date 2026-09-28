import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/authorized_http.dart';

/// What a notification is about.
///
/// [status] is the workflow moving - being reviewed, a responder on the way,
/// arrived, resolved - and always has been; [AppNotification.newStatus] says
/// which. The rest are things the AGENCY did that no status can say:
///
///  * [accepted]      it confirmed the report is real (changes no status),
///  * [rejected]      it turned the report down (wire status `cancelled`),
///  * [clarification] it asked a question (changes no status at all),
///  * [cancelled]     it cancelled the report (wire status `cancelled`, the same
///                    word the resident's own Trash gives - told apart by
///                    `withdrawn_at`),
///  * [message]       it, or the crew, wrote to the resident.
///
/// Each used to be invisible, or arrived as a bare "Cancelled".
enum NotificationKind {
  status,
  accepted,
  rejected,
  clarification,
  cancelled,
  message,
}

/// In-app notification model.
class AppNotification {
  const AppNotification({
    required this.incidentId,
    required this.reportText,
    required this.newStatus,
    required this.receivedAt,
    this.etaMinutes,
    this.respondingAgency,
    this.kind = NotificationKind.status,
    this.detail,
    this.serverId,
    this.eventKey,
    this.serverTitle,
  });

  final String incidentId;
  final String reportText;
  final String newStatus;
  final DateTime receivedAt;

  /// Only meaningful once [newStatus] is 'dispatched' or 'en_route' - how the
  /// notice answers "is somebody coming to my house", the same figures
  /// [IncidentModel] carries for the My Reports card. Realtime hands us the
  /// whole updated row, so these ride along for free; nothing extra to fetch.
  final int? etaMinutes;
  final String? respondingAgency;

  final NotificationKind kind;

  /// The agency's own words: the reason it gave (rejected, cancelled), the
  /// question it asked (clarification) or what it wrote (message). Null for a
  /// plain status change.
  final String? detail;

  /// The row in the backend's notifications table, when this came from there -
  /// what marks it read so it does not come back on the next launch.
  final String? serverId;

  /// (incident, kind, when) - the same event arrives twice, once over realtime
  /// and once from the stored list, and this is how the two are one.
  final String? eventKey;

  /// The headline the server wrote for a stored notice. Only used where the
  /// wording depends on who acted (a message from the agency or from the crew).
  final String? serverTitle;

  /// Something the agency decided or said, as against the workflow moving.
  bool get isAgencyAct => kind != NotificationKind.status;

  String get shortId =>
      incidentId.length >= 8 ? incidentId.substring(0, 8) : incidentId;

  AppNotification withServerId(String id, {String? detail}) => AppNotification(
    incidentId: incidentId,
    reportText: reportText,
    newStatus: newStatus,
    receivedAt: receivedAt,
    etaMinutes: etaMinutes,
    respondingAgency: respondingAgency,
    kind: kind,
    detail: (detail != null && detail.isNotEmpty) ? detail : this.detail,
    serverId: id,
    eventKey: eventKey,
    serverTitle: serverTitle,
  );
}

int? _ms(String? at) =>
    at == null ? null : DateTime.tryParse(at)?.millisecondsSinceEpoch;

/// The identity of one review event. Timestamps are compared as instants, not
/// as strings - Postgres and Python format the same moment differently
/// (`+00:00` vs `Z`, six fractional digits vs three).
String reviewEventKey(String incidentId, NotificationKind kind, String? at) =>
    '$incidentId:${kind.name}:${_ms(at) ?? 'unknown'}';

/// One move of the workflow. Only dispatch and resolution carry a time on the
/// row itself (`dispatched_at`, `resolved_at`); the other moves happen once per
/// report, so the status alone identifies them.
String statusEventKey(String incidentId, String status, String? at) =>
    '$incidentId:status:$status:${(status == 'dispatched' || status == 'resolved') ? (_ms(at) ?? 'unknown') : 'once'}';

/// A report can only be cancelled once.
String cancelEventKey(String incidentId) => '$incidentId:cancelled';

/// One message in the report's thread, by its own id.
String messageEventKey(String incidentId, String? noteId) =>
    '$incidentId:message:${noteId ?? 'unknown'}';

/// Phase 10 - Supabase Realtime subscription to the authenticated
/// Resident's own incidents, plus the stored notifications the backend keeps
/// for them.
///
/// When the incident moves (e.g., received -> dispatched), or the agency
/// decides or says something, this provider adds an [AppNotification] to
/// [_unread] and notifies listeners. The UI shows an in-app notice and updates
/// the bell badge.
///
/// THE RESIDENT'S OWN ACTIONS ARE NEVER ANNOUNCED BACK
///
/// Moving a report to Trash is wire status `cancelled` with `withdrawn_at` set.
/// The resident has just done it, and the screen they did it on already said so
/// ("Moved to Trash. It will be permanently deleted in 30 days."). Announcing
/// the same row again as "Report update - Cancelled" - which is what happened -
/// told them something that had not happened to them (a cancellation by the
/// agency) at the moment they least expected one.
///
/// TWO ROADS, ONE EVENT
///
/// Realtime tells the resident the moment it happens; the backend also writes a
/// notification row for each agency act, which [syncFromServer] reads - on
/// launch, on resume, and every half minute while the app is open - so a
/// resident whose phone was off or out of signal is still told, and a message
/// from the agency (which changes nothing on the incident row, so realtime never
/// sees it) arrives too. The two copies are recognised by their event key and
/// shown once.
///
/// Architecture: uses Supabase Realtime (postgres_changes) filtered by
/// `reporter_id = auth.uid()`. No FCM/Firebase required - all traffic
/// stays on the existing Supabase connection.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider();

  final List<AppNotification> _unread = [];
  final Set<String> _seenKeys = {};

  /// The status each of the resident's reports was last known to have.
  ///
  /// Realtime fires for ANY update to a row - the resident's own reply flips
  /// review_status, an agency edits a field - and for this table the old row
  /// in the event carries only its id, so "did the status change?" cannot be
  /// read from the event. It has to be remembered. Without it, answering an
  /// agency's question popped a "Report update - Being reviewed" sheet for a
  /// status that had not moved.
  final Map<String, String> _lastStatus = {};
  bool _statusesSeeded = false;
  RealtimeChannel? _channel;
  bool _subscribed = false;
  bool _syncing = false;
  Timer? _retry;
  Timer? _poll;

  /// Whether the live channel last reported that it is joined. Kept here
  /// because the channel's own flag is internal to the realtime package.
  bool _joined = false;

  /// A review event older than this is not "just happened". Realtime fires for
  /// ANY update to the row, so without a cut-off an unrelated update to a
  /// report rejected last week would announce the rejection again after every
  /// restart. Older, still-unread ones come from [syncFromServer] instead.
  static const _recent = Duration(minutes: 10);

  /// How often the stored notifications are read while the app is open. Cheap
  /// (one small GET), and the only way a message from the agency - which changes
  /// nothing on the incident row - reaches an open app.
  static const _pollEvery = Duration(seconds: 30);

  List<AppNotification> get unread => List.unmodifiable(_unread);
  int get unreadCount => _unread.length;
  bool get hasUnread => _unread.isNotEmpty;
  bool get isSubscribed => _subscribed;

  // ── Subscribe ─────────────────────────────────────────────

  /// Subscribe to incident status changes for the current user.
  /// Call this once after a successful login.
  void subscribe() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null || _subscribed) return;

    _channel =
        client
            .channel('incident_status_$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'incidents',
              // RLS ensures the user only receives rows where reporter_id = uid()
              // The filter here is belt-and-suspenders.
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'reporter_id',
                value: userId,
              ),
              callback: _onIncidentUpdate,
            )
            // The status is watched, not ignored. A channel that fails to join
            // (a dropped socket, a token that had just been refreshed) used to
            // stay dead without a word: the resident saw nothing when an agency
            // acted on their report, and there was nothing in the log to say
            // why. Now it is logged, and joined again a few seconds later.
            .subscribe((status, error) {
              debugPrint(
                '[notifications] realtime $status${error == null ? '' : ' ($error)'}',
              );
              _joined = status == RealtimeSubscribeStatus.subscribed;
              if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                _scheduleResubscribe();
              }
            });

    _subscribed = true;
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) => unawaited(syncFromServer()));
    unawaited(syncFromServer());
    unawaited(_seedStatuses());
  }

  /// Learn where each report stands right now, so the first update to one of
  /// them can be told apart from a change of status. Best-effort: with no
  /// baseline an update is announced, which is how it always behaved.
  Future<void> _seedStatuses() async {
    if (_statusesSeeded) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    _statusesSeeded = true;
    try {
      final response = await withAuthRetry(
        () => http
            .get(
              Uri.parse('${AppConfig.apiBaseUrl}/incidents/my'),
              headers: {
                'Authorization':
                    'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken}',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode != 200) {
        _statusesSeeded = false;
        return;
      }
      for (final raw in jsonDecode(response.body) as List) {
        final row = raw as Map<String, dynamic>;
        final id = row['id'] as String?;
        final status = row['status'] as String?;
        // An event that got here first is newer than this list.
        if (id != null && status != null) rememberStatus(id, status);
      }
    } catch (_) {
      _statusesSeeded = false;
    }
  }

  /// Record where a report stands without announcing anything. Never
  /// overwrites: whatever an event said is newer than a list fetched earlier.
  @visibleForTesting
  void rememberStatus(String id, String status) =>
      _lastStatus.putIfAbsent(id, () => status);

  void _scheduleResubscribe() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), () async {
      await _dropChannel();
      subscribe();
    });
  }

  Future<void> _dropChannel() async {
    final channel = _channel;
    _channel = null;
    _subscribed = false;
    _joined = false;
    _poll?.cancel();
    _poll = null;
    if (channel != null) {
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Called when the app comes back to the foreground: a phone that spent a
  /// while in a pocket has usually lost its websocket, and a channel that is
  /// not joined delivers nothing. Join it again if it is not.
  Future<void> ensureSubscribed() async {
    final channel = _channel;
    if (channel != null && _joined) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    await _dropChannel();
    subscribe();
  }

  /// Unsubscribe - call on logout.
  Future<void> unsubscribe() async {
    _retry?.cancel();
    await _dropChannel();
    _unread.clear();
    _seenKeys.clear();
    _lastStatus.clear();
    _statusesSeeded = false;
    notifyListeners();
  }

  // ── Realtime callback ─────────────────────────────────────

  /// Exposed so the announce/ignore decision can be tested without a socket.
  @visibleForTesting
  void handleIncidentUpdate(PostgresChangePayload payload) =>
      _onIncidentUpdate(payload);

  void _announce(AppNotification n) {
    _unread.insert(0, n);
    notifyListeners();
  }

  bool _recentEnough(String? at) {
    final when = at == null ? null : DateTime.tryParse(at);
    return when != null && DateTime.now().difference(when) <= _recent;
  }

  void _onIncidentUpdate(PostgresChangePayload payload) {
    final newRow = payload.newRecord;
    if (newRow.isEmpty) return;

    final id = newRow['id'] as String? ?? '';
    final text = newRow['report_text'] as String? ?? '';

    // Remember the status whatever else this update turns out to be, so the
    // NEXT update to the same row can be compared against it.
    final newStatus = newRow['status'] as String?;
    final previousStatus = _lastStatus[id];
    if (newStatus != null) _lastStatus[id] = newStatus;

    // The resident's own action. Moving a report to Trash is status
    // `cancelled` with `withdrawn_at` set: they did it a moment ago and the
    // screen they did it on already said so - telling them again, as "Cancelled",
    // is telling them something that did not happen to them.
    if (newStatus == 'cancelled' && newRow['withdrawn_at'] != null) return;

    // The agency's decision comes first: a rejected report is ALSO status
    // 'cancelled', and must not fall through to a bare "Cancelled" sheet.
    final review = newRow['review_status'] as String?;
    if (review == 'rejected' || review == 'clarification_requested') {
      final kind =
          review == 'rejected'
              ? NotificationKind.rejected
              : NotificationKind.clarification;
      final at =
          (kind == NotificationKind.rejected
                  ? newRow['reviewed_at']
                  : newRow['clarification_requested_at'])
              as String?;
      var announced = false;
      if (_recentEnough(at)) {
        final key = reviewEventKey(id, kind, at);
        if (_seenKeys.add(key)) {
          announced = true;
          _announce(
            AppNotification(
              incidentId: id,
              reportText: text,
              newStatus: review!,
              receivedAt: DateTime.now(),
              kind: kind,
              detail:
                  (kind == NotificationKind.rejected
                          ? newRow['rejection_reason']
                          : newRow['clarification_note'])
                      as String?,
              eventKey: key,
            ),
          );
          // The stored copy carries the row id needed to mark it read.
          unawaited(syncFromServer());
        }
      }
      // A rejected report is finished: its status is 'cancelled', and a second
      // notice saying "Cancelled" would contradict the rejection. A report that
      // is only waiting on an answer is still moving, though - the agency can
      // start on it - and that update must not be swallowed because the
      // question is still open on the same row.
      if (kind == NotificationKind.rejected || announced) return;
    }

    // The agency accepted it. Accepting changes no status, so this is the only
    // sign of it - and it is not announced when the same update also moves the
    // report on (dispatching a pending report accepts it implicitly, and the
    // resident should hear "a responder is on the way", not two things).
    if (review == 'accepted' &&
        (newStatus == null || newStatus == 'received' || newStatus == 'processing')) {
      final at = newRow['reviewed_at'] as String?;
      if (_recentEnough(at)) {
        final key = reviewEventKey(id, NotificationKind.accepted, at);
        if (_seenKeys.add(key)) {
          _announce(
            AppNotification(
              incidentId: id,
              reportText: text,
              newStatus: 'accepted',
              receivedAt: DateTime.now(),
              kind: NotificationKind.accepted,
              eventKey: key,
            ),
          );
          unawaited(syncFromServer());
        }
      }
    }

    // Only notify on meaningful status transitions (not 'received' - that
    // fires immediately on submit and the user is still on the success screen)
    if (newStatus == null || newStatus == 'received') return;
    // The row changed but its status did not: the resident's own reply, a
    // field edited by the agency. Nothing to tell them.
    if (previousStatus == newStatus) return;

    // Cancelled, and not by the resident (returned above) and not a rejection
    // (handled above): the agency cancelled it. The reason is in the stored
    // notification, which the sync below brings in and attaches.
    if (newStatus == 'cancelled') {
      final key = cancelEventKey(id);
      if (!_seenKeys.add(key)) return;
      _announce(
        AppNotification(
          incidentId: id,
          reportText: text,
          newStatus: 'cancelled',
          receivedAt: DateTime.now(),
          kind: NotificationKind.cancelled,
          eventKey: key,
        ),
      );
      unawaited(syncFromServer());
      return;
    }

    final at =
        newStatus == 'dispatched'
            ? newRow['dispatched_at'] as String?
            : newStatus == 'resolved'
            ? newRow['resolved_at'] as String?
            : null;
    final key = statusEventKey(id, newStatus, at);
    if (!_seenKeys.add(key)) return;

    _announce(
      AppNotification(
        incidentId: id,
        reportText: text,
        newStatus: newStatus,
        receivedAt: DateTime.now(),
        etaMinutes: (newRow['eta_minutes'] as num?)?.toInt(),
        respondingAgency: newRow['responding_agency'] as String?,
        eventKey: key,
      ),
    );
    unawaited(syncFromServer());
  }

  // ── The stored copy ───────────────────────────────────────

  /// What each stored notification type is, in this app's terms - or null for a
  /// type meant for somebody else (an agency admin's own alerts share the table).
  static ({NotificationKind kind, String status})? _storedKind(String? type) =>
      switch (type) {
        'incident.rejected' => (kind: NotificationKind.rejected, status: 'rejected'),
        'incident.clarification_requested' => (
          kind: NotificationKind.clarification,
          status: 'clarification_requested',
        ),
        'incident.accepted' => (kind: NotificationKind.accepted, status: 'accepted'),
        'incident.cancelled' => (kind: NotificationKind.cancelled, status: 'cancelled'),
        'incident.message' => (kind: NotificationKind.message, status: 'message'),
        'incident.dispatched' => (kind: NotificationKind.status, status: 'dispatched'),
        'incident.en_route' => (kind: NotificationKind.status, status: 'en_route'),
        'incident.arrived' => (kind: NotificationKind.status, status: 'arrived'),
        'incident.resolved' => (kind: NotificationKind.status, status: 'resolved'),
        _ => null,
      };

  static String _storedKey(
    NotificationKind kind,
    String status,
    String incidentId,
    Map meta,
  ) {
    final at = meta['at'] as String?;
    return switch (kind) {
      NotificationKind.cancelled => cancelEventKey(incidentId),
      NotificationKind.message => messageEventKey(incidentId, meta['note_id'] as String?),
      NotificationKind.status => statusEventKey(incidentId, status, at),
      _ => reviewEventKey(incidentId, kind, at),
    };
  }

  /// "Reason: Duplicate" -> "Duplicate". The server writes the label into the
  /// body; the app has its own (localised) label to put back.
  static String _stripReasonLabel(String body) {
    final m = RegExp(r'^\s*(reason|dahilan)\s*:\s*', caseSensitive: false).firstMatch(body);
    return m == null ? body.trim() : body.substring(m.end).trim();
  }

  /// Read the notifications the backend has kept for this resident and merge
  /// the unread ones in.
  ///
  /// This is what reaches someone who was not looking when it happened: the
  /// phone was off, or there was no signal in the barangay - and, for a message
  /// from the agency, it is the ONLY road, since a note changes nothing on the
  /// incident row that realtime watches. Best-effort - a failure changes
  /// nothing, and realtime still delivers the live ones.
  Future<void> syncFromServer() async {
    if (_syncing) return;
    final Session? session;
    try {
      session = Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return; // no Supabase yet (a test, or start-up) - nothing to read
    }
    if (session == null) return;
    _syncing = true;
    try {
      final response = await withAuthRetry(
        () => http.get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/notifications/?unread_only=true&limit=50',
          ),
          headers: {
            'Authorization':
                'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken}',
          },
        ),
      );
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      var changed = false;
      for (final raw in (body['items'] as List? ?? const [])) {
        final row = raw as Map<String, dynamic>;
        final mapped = _storedKind(row['type'] as String?);
        final meta = row['metadata'];
        if (mapped == null || meta is! Map) continue;
        final incidentId = meta['incident_id'] as String?;
        final serverId = row['id'] as String?;
        if (incidentId == null || serverId == null) continue;

        final key = _storedKey(mapped.kind, mapped.status, incidentId, meta);
        var detail = row['body'] as String?;
        if (mapped.kind == NotificationKind.cancelled && detail != null) {
          detail = _stripReasonLabel(detail);
        }
        // A plain status change carries no words of the agency's own.
        if (mapped.kind == NotificationKind.status) detail = null;

        final at = _unread.indexWhere((n) => n.eventKey == key);
        if (at >= 0) {
          // Already showing (it arrived live) - learn the row id, and any words
          // the live copy did not have (the reason for a cancellation).
          final current = _unread[at];
          if (current.serverId == null ||
              (detail != null && detail.isNotEmpty && (current.detail ?? '').isEmpty)) {
            _unread[at] = current.withServerId(serverId, detail: detail);
            changed = true;
          }
          continue;
        }
        if (!_seenKeys.add(key)) {
          // Shown and cleared this session. Its stored twin would otherwise be
          // read again on every sync, and announced afresh on the next launch.
          unawaited(_markRowRead(serverId));
          continue;
        }

        _unread.add(
          AppNotification(
            incidentId: incidentId,
            reportText: '',
            newStatus: mapped.status,
            receivedAt:
                DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
            kind: mapped.kind,
            detail: detail,
            serverId: serverId,
            eventKey: key,
            serverTitle: row['title'] as String?,
          ),
        );
        changed = true;
      }
      if (changed) {
        _unread.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[notifications] sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _markRowRead(String id) async {
    try {
      await withAuthRetry(
        () => http.patch(
          Uri.parse('${AppConfig.apiBaseUrl}/notifications/$id/read'),
          headers: {
            'Authorization':
                'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken}',
          },
        ),
      );
    } catch (e) {
      debugPrint('[notifications] mark read failed: $e');
    }
  }

  /// Tell the backend this one has been seen, so it is not announced again on
  /// the next launch. Fire-and-forget: if it fails, the worst outcome is being
  /// shown once more.
  Future<void> markServerRead(AppNotification n) async {
    final id = n.serverId;
    if (id == null) return;
    await _markRowRead(id);
  }

  // ── Read / dismiss ────────────────────────────────────────

  void markAllRead() {
    if (_unread.isEmpty) return;
    for (final n in _unread) {
      unawaited(markServerRead(n));
    }
    _unread.clear();
    notifyListeners();
  }

  void dismiss(int index) {
    if (index >= 0 && index < _unread.length) {
      unawaited(markServerRead(_unread[index]));
      _unread.removeAt(index);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    unsubscribe();
    super.dispose();
  }
}
