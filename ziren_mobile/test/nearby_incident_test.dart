import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/core/errors/failures.dart';
import 'package:Ziren/features/responder/data/responder_repository.dart';
import 'package:Ziren/features/responder/domain/nearby_incident.dart';
import 'package:Ziren/features/responder/domain/responder_provider.dart';

/// Undispatched incidents near an on-duty responder — an invitation to help,
/// never a command. Before this, a responder heard about an incident only once
/// a dispatcher had already assigned it to them.
///
/// Properties worth pinning:
///   1. A poll announces only incidents THIS SESSION has not shown before —
///      the same incident on the next poll is silent.
///   2. An incident that drops off a later poll (dispatched to someone,
///      answered, aged out) is reported as "resolved" exactly once, and — if
///      it later reappears — is treated as new again.
///   3. Answering is optimistic (the card reflects the answer at once) and
///      never assigns anything; a stale answer (already dispatched to someone
///      else) drops the card rather than leaving a dead button.
///   4. A network hiccup on a background poll must not wipe what is already
///      on screen.
void main() {
  final createdAt = DateTime.utc(2026, 9, 25, 10);

  Map<String, dynamic> row(
    String id, {
    String category = 'fire',
    String severity = 'high',
    String state = 'free',
    String? answered,
  }) => {
    'incident_id': id,
    'record_number': 'ZIR-2026-000$id',
    'severity': severity,
    'category': category,
    'report_text': 'Smoke coming from a house',
    'location_address': 'Brgy Casiawan, Cabucgayan',
    'latitude': 11.56,
    'longitude': 124.40,
    'created_at': createdAt.toIso8601String(),
    'sos_flagged': false,
    'distance_km': 1.2,
    'eta_min': 4,
    'direction': 'N',
    'level': 'alarm',
    'reason': 'nearest',
    'rank': 1,
    'units_free_in_range': 2,
    'you': {'state': state, 'current_calls': const []},
    'answered': answered,
  };

  Map<String, dynamic> result(List<Map<String, dynamic>> items, {bool onDuty = true}) => {
    'on_duty': onDuty,
    'position': 'device',
    'items': items,
  };

  group('a poll announces only what is genuinely new', () {
    test('the first sighting of an incident is announced once', () async {
      final repo = _FakeRepo(nearbyResults: [result([row('1')])]);
      final provider = ResponderProvider(repository: repo);
      final announced = <List<NearbyIncident>>[];
      provider.onNearbyArrived = announced.add;

      await provider.loadNearby();

      expect(announced, hasLength(1));
      expect(announced.single.map((i) => i.incidentId), ['1']);
      expect(provider.nearby.map((i) => i.incidentId), ['1']);
    });

    test('the same incident on the next poll is silent', () async {
      final repo = _FakeRepo(
        nearbyResults: [result([row('1')]), result([row('1')])],
      );
      final provider = ResponderProvider(repository: repo);
      final announced = <List<NearbyIncident>>[];
      provider.onNearbyArrived = announced.add;

      await provider.loadNearby();
      await provider.loadNearby();

      expect(announced, hasLength(1), reason: 'only the first poll should announce it');
    });

    test('a second incident arriving later is announced on its own', () async {
      final repo = _FakeRepo(
        nearbyResults: [
          result([row('1')]),
          result([row('1'), row('2')]),
        ],
      );
      final provider = ResponderProvider(repository: repo);
      final announced = <List<NearbyIncident>>[];
      provider.onNearbyArrived = announced.add;

      await provider.loadNearby();
      await provider.loadNearby();

      expect(announced, hasLength(2));
      expect(announced.last.map((i) => i.incidentId), ['2']);
    });
  });

  group('an incident that drops out is resolved, and can come back as new', () {
    test('dropping off a poll reports it resolved exactly once', () async {
      final repo = _FakeRepo(
        nearbyResults: [result([row('1')]), result(const [])],
      );
      final provider = ResponderProvider(repository: repo);
      final resolved = <List<String>>[];
      provider.onNearbyResolved = resolved.add;

      await provider.loadNearby();
      await provider.loadNearby();

      expect(resolved, [
        ['1'],
      ]);
      expect(provider.nearby, isEmpty);
    });

    test('a resolved incident that reappears is announced again', () async {
      final repo = _FakeRepo(
        nearbyResults: [
          result([row('1')]),
          result(const []),
          result([row('1')]),
        ],
      );
      final provider = ResponderProvider(repository: repo);
      final announced = <List<NearbyIncident>>[];
      provider.onNearbyArrived = announced.add;

      await provider.loadNearby();
      await provider.loadNearby();
      await provider.loadNearby();

      expect(announced, hasLength(2), reason: 'gone, then genuinely new again');
    });
  });

  group('answering', () {
    test('is optimistic: the card reflects the answer before the server replies', () async {
      final repo = _FakeRepo(nearbyResults: [result([row('1')])]);
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();

      final future = provider.answerNearby('1', 'can_respond');
      // Applied synchronously, before the (fake, slightly-delayed) network call resolves.
      expect(provider.nearby.single.answered, 'can_respond');
      expect(await future, isTrue);
      expect(repo.answered, [('1', 'can_respond')]);
    });

    test('a stale answer (already dispatched to someone else) drops the card', () async {
      final repo = _FakeRepo(
        nearbyResults: [result([row('1')])],
        answerFailure: const ServerFailure('A responder has already been assigned.'),
      );
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();

      final ok = await provider.answerNearby('1', 'can_respond');

      expect(ok, isFalse);
      expect(provider.nearby, isEmpty);
    });

    test('never assigns anything - only the answer is sent, nothing about the FSM', () async {
      final repo = _FakeRepo(nearbyResults: [result([row('1')])]);
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();
      await provider.answerNearby('1', 'unavailable', lat: 11.5, lng: 124.4);

      expect(repo.answered, [('1', 'unavailable')]);
      expect(repo.answerCoords, [(11.5, 124.4)]);
    });

    test('a network failure keeps the answer applied locally, to reconcile on the next poll', () async {
      final repo = _FakeRepo(
        nearbyResults: [result([row('1')])],
        answerFailure: const NetworkFailure('offline'),
      );
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();

      final ok = await provider.answerNearby('1', 'can_respond');

      expect(ok, isTrue);
      expect(provider.nearby.single.answered, 'can_respond');
    });
  });

  group('resilience', () {
    test('a network hiccup on a background poll keeps what is already on screen', () async {
      final repo = _FakeRepo(
        nearbyResults: [result([row('1')])],
        loadFailure: const NetworkFailure('offline'),
      );
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();
      expect(provider.nearby, hasLength(1));

      await provider.loadNearby(); // this one fails
      expect(provider.nearby, hasLength(1), reason: 'a failed poll must not clear the list');
      expect(provider.nearbyError, isNull, reason: 'a network hiccup is quiet, not an error banner');
    });

    test('a server error is surfaced, not swallowed', () async {
      final repo = _FakeRepo(
        nearbyResults: const [],
        loadFailure: const ServerFailure('boom'),
      );
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();
      expect(provider.nearbyError, 'boom');
    });

    test('an off-duty responder gets an empty list, not an error', () async {
      final repo = _FakeRepo(nearbyResults: [result(const [], onDuty: false)]);
      final provider = ResponderProvider(repository: repo);
      await provider.loadNearby();
      expect(provider.nearby, isEmpty);
      expect(provider.nearbyError, isNull);
    });

    test('clearNearby forgets everything - the next sign-in starts fresh', () async {
      final repo = _FakeRepo(nearbyResults: [result([row('1')]), result([row('1')])]);
      final provider = ResponderProvider(repository: repo);
      final announced = <List<NearbyIncident>>[];
      provider.onNearbyArrived = announced.add;

      await provider.loadNearby();
      provider.clearNearby();
      await provider.loadNearby();

      expect(provider.nearby, hasLength(1));
      expect(announced, hasLength(2), reason: 'forgotten, so it reads as new again');
    });
  });

  group('NearbyIncident.fromJson', () {
    test('a responder already on a call carries what they are on', () {
      final n = NearbyIncident.fromJson(
        row('1', state: 'en_route')..['you'] = {
          'state': 'en_route',
          'current_calls': [
            {'incident_id': '9', 'status': 'en_route', 'severity': 'low', 'category': 'vehicular'},
          ],
        },
      );
      expect(n.you.isFree, isFalse);
      expect(n.you.currentCategory, 'vehicular');
    });

    test('a free responder with no current call', () {
      final n = NearbyIncident.fromJson(row('1'));
      expect(n.you.isFree, isTrue);
      expect(n.you.currentIncidentId, isNull);
    });

    test('an unlocated responder has no distance, not a zero', () {
      final j = row('1')..['distance_km'] = null..['eta_min'] = null..['direction'] = null;
      final n = NearbyIncident.fromJson(j);
      expect(n.distanceKm, isNull);
      expect(n.etaMinutes, isNull);
    });
  });
}

/// A minimal double: only the two methods this feature exercises are real,
/// everything else falls through to the base class (unused here) so the
/// override stays small and honest about what it fakes.
class _FakeRepo extends ResponderRepository {
  _FakeRepo({
    required this.nearbyResults,
    this.loadFailure,
    this.answerFailure,
  });

  final List<Map<String, dynamic>> nearbyResults;
  final Object? loadFailure;
  final Object? answerFailure;

  int _loadCalls = 0;
  final List<(String, String)> answered = [];
  final List<(double?, double?)> answerCoords = [];

  @override
  Future<NearbyResult> getNearby({double? lat, double? lng}) async {
    // A failure applies once THIS call has run out of canned successes to
    // return — so a test can script "succeeds, succeeds, then fails".
    if (loadFailure != null && _loadCalls >= nearbyResults.length) {
      final f = loadFailure!;
      if (f is NetworkFailure) throw f;
      if (f is ServerFailure) throw f;
      throw f;
    }
    final json = nearbyResults[_loadCalls.clamp(0, nearbyResults.length - 1)];
    _loadCalls++;
    return NearbyResult.fromJson(json);
  }

  @override
  Future<void> answerNearby(
    String incidentId,
    String answer, {
    double? lat,
    double? lng,
  }) async {
    answered.add((incidentId, answer));
    answerCoords.add((lat, lng));
    if (answerFailure != null) {
      final f = answerFailure!;
      if (f is NetworkFailure) throw f;
      if (f is ServerFailure) throw f;
      throw f;
    }
  }
}
