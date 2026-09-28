import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Ziren/features/responder/data/responder_action_queue.dart';
import 'package:Ziren/features/responder/domain/responder_ack.dart';
import 'package:Ziren/l10n/app_localizations.dart';
import 'package:Ziren/l10n/app_localizations_en.dart';
import 'package:Ziren/l10n/app_localizations_fil.dart';
import 'package:Ziren/features/responder/domain/responder_incident_model.dart';

/// The offline queue and the acceptance verdict.
///
/// These two carry the responder features that are hardest to check by hand.
/// The queue only ever does its real job in a place with no signal — a
/// barangay road on the far side of Biliran — which is precisely where nobody
/// is holding a debugger, and where a silent bug looks exactly like bad
/// coverage.
///
/// Run with: flutter test test/responder_action_queue_test.dart
void main() {
  setUp(() {
    // Fresh store per test. Without this the queue from one test leaks into
    // the next and the ordering assertions become meaningless.
    SharedPreferences.setMockInitialValues({});
  });

  group('ResponderActionQueue — keeping what was pressed', () {
    test('an action survives being written and read back', () async {
      final queue = ResponderActionQueue();
      queue.sender = (_) async => false; // never accepted, so it stays

      await queue.enqueue(
        ResponderActionKind.accept,
        incidentId: 'inc-1',
      );

      final pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.first.kind, ResponderActionKind.accept);
      expect(pending.first.incidentId, 'inc-1');
    });

    test('the time the button was pressed is what is stored', () async {
      // THE POINT OF THE WHOLE FEATURE. If the queue let the server stamp the
      // sync time instead, a call accepted at 14:02 in a dead zone and synced
      // at 14:40 would be recorded as a 38-minute response — measuring the
      // mountain rather than the crew.
      final queue = ResponderActionQueue();
      queue.sender = (_) async => false;

      final pressed = DateTime.utc(2026, 9, 5, 14, 2);
      await queue.enqueue(
        ResponderActionKind.accept,
        incidentId: 'inc-1',
        occurredAt: pressed,
      );

      final action = (await queue.pending()).single;
      expect(action.occurredAt, pressed);
      expect(action.wireBody['occurred_at'], pressed.toIso8601String());
    });

    test('a second accept for one incident replaces the first', () async {
      // Accept is a STATE, not an event. Pressed twice, it happened once —
      // and replaying both would let the later timestamp overwrite the
      // earlier, losing exactly the number this queue exists to preserve.
      final queue = ResponderActionQueue();
      queue.sender = (_) async => false;

      final first = DateTime.utc(2026, 9, 5, 14, 2);
      await queue.enqueue(
        ResponderActionKind.accept,
        incidentId: 'inc-1',
        occurredAt: first,
      );
      await queue.enqueue(
        ResponderActionKind.accept,
        incidentId: 'inc-1',
        occurredAt: DateTime.utc(2026, 9, 5, 14, 9),
      );

      final pending = await queue.pending();
      expect(pending, hasLength(1), reason: 'one accept, not two');
    });

    test('two batches of scene photos are two batches', () async {
      // Media is an EVENT, not a state. Collapsing these would silently throw
      // away the first set of photos.
      final queue = ResponderActionQueue();
      queue.sender = (_) async => false;

      await queue.enqueue(
        ResponderActionKind.sceneMedia,
        incidentId: 'inc-1',
        body: {'paths': ['a.jpg']},
      );
      await queue.enqueue(
        ResponderActionKind.sceneMedia,
        incidentId: 'inc-1',
        body: {'paths': ['b.jpg']},
      );

      expect(await queue.pendingCount(), 2);
    });

    test('accepts for different incidents do not collide', () async {
      final queue = ResponderActionQueue();
      queue.sender = (_) async => false;

      await queue.enqueue(ResponderActionKind.accept, incidentId: 'inc-1');
      await queue.enqueue(ResponderActionKind.accept, incidentId: 'inc-2');

      expect(await queue.pendingCount(), 2);
    });
  });

  group('ResponderActionQueue — flushing', () {
    test('a successful send clears the action', () async {
      final queue = ResponderActionQueue();
      queue.sender = (_) async => true;

      await queue.enqueue(ResponderActionKind.accept, incidentId: 'inc-1');
      await queue.flush();

      expect(await queue.pendingCount(), 0);
    });

    test('one network failure stops the rest of the queue untried', () async {
      // ORDER IS NOT NEGOTIABLE. Accept must land before En Route, which must
      // land before Arrived — the backend FSM rejects anything else with a
      // 422. Skipping past a failure would let a later status arrive first and
      // be permanently refused.
      final attempted = <String>[];
      final queue = ResponderActionQueue();
      queue.sender = (action) async {
        attempted.add(action.kind.name);
        return false;
      };

      await queue.enqueue(ResponderActionKind.accept, incidentId: 'inc-1');
      await queue.enqueue(
        ResponderActionKind.status,
        incidentId: 'inc-1',
        body: {'status': 'en_route'},
      );
      await queue.flush();

      // The status update is NEVER attempted while the accept ahead of it is
      // still failing. Asserting on the set rather than the list because
      // enqueue kicks off its own flush, so 'accept' is tried more than once.
      expect(attempted.toSet(), {'accept'});
      expect(await queue.pendingCount(), 2, reason: 'both kept');
    });

    test('actions are sent oldest first', () async {
      final order = <String>[];
      final queue = ResponderActionQueue();
      queue.sender = (action) async {
        order.add(action.body['status'] as String? ?? action.kind.name);
        return true;
      };

      await queue.enqueue(ResponderActionKind.accept, incidentId: 'inc-1');
      await queue.enqueue(
        ResponderActionKind.sceneMedia,
        incidentId: 'inc-1',
        body: {'paths': ['a.jpg']},
      );
      await queue.flush();

      expect(order, ['accept', 'sceneMedia']);
    });

    test('an action the server keeps refusing is eventually dropped', () async {
      // Not a connectivity problem — an action the server will never accept
      // (a call somebody else was reassigned, an incident already closed).
      // Retrying it forever would block everything behind it in the queue.
      final queue = ResponderActionQueue();
      queue.sender = (_) async => false;

      await queue.enqueue(ResponderActionKind.accept, incidentId: 'inc-1');
      for (var i = 0; i < 10; i++) {
        await queue.flush();
      }

      expect(await queue.pendingCount(), 0);
    });

    test('a corrupt store is dropped rather than failing forever', () async {
      SharedPreferences.setMockInitialValues({
        'responder_pending_actions_v1': 'not json at all',
      });
      final queue = ResponderActionQueue();
      expect(await queue.pending(), isEmpty);
    });
  });

  group('ResponderAck — what the phone shows', () {
    test('a missing verdict does not make the phone shout', () {
      // An incident from a backend that predates migration 024. Defaulting to
      // 'pending' would raise a full-screen alarm for every historical row.
      final ack = ResponderAck.fromJson(null);
      expect(ack.state, 'not_applicable');
      expect(ack.needsAnswer, isFalse);
    });

    test('pending and overdue both need an answer', () {
      expect(
        ResponderAck.fromJson({'state': 'pending', 'deadline_seconds': 60})
            .needsAnswer,
        isTrue,
      );
      expect(
        ResponderAck.fromJson({'state': 'overdue', 'deadline_seconds': 60})
            .needsAnswer,
        isTrue,
      );
      expect(
        ResponderAck.fromJson({'state': 'accepted', 'deadline_seconds': 60})
            .needsAnswer,
        isFalse,
      );
    });

    test('ticking past the deadline flips pending to overdue', () {
      final ack = ResponderAck.fromJson({
        'state': 'pending',
        'deadline_seconds': 60,
        'seconds_waiting': 58,
        'seconds_remaining': 2,
      });
      expect(ack.tick(1).state, 'pending');
      expect(ack.tick(5).state, 'overdue');
      expect(ack.tick(5).secondsRemaining, 0);
    });

    test('ticking returns a new instance rather than mutating', () {
      // These hang off immutable incident models. A mutable clock inside one
      // would make two widgets holding the same incident disagree.
      final ack = ResponderAck.fromJson({
        'state': 'pending',
        'deadline_seconds': 60,
        'seconds_waiting': 10,
        'seconds_remaining': 50,
      });
      final later = ack.tick(5);
      expect(ack.secondsWaiting, 10, reason: 'original untouched');
      expect(later.secondsWaiting, 15);
    });

    test('the countdown reads as minutes and seconds', () {
      final ack = ResponderAck.fromJson({
        'state': 'pending',
        'deadline_seconds': 180,
        'seconds_remaining': 47,
      });
      expect(ack.remainingLabel, '0:47');
    });

    test('elapsed fraction is clamped to the deadline', () {
      final ack = ResponderAck.fromJson({
        'state': 'overdue',
        'deadline_seconds': 60,
        'seconds_waiting': 300,
      });
      expect(ack.elapsedFraction, 1.0);
    });
  });

  _coordinateTests();

  group('Wire contracts', () {
    test('decline reason keys match the backend CHECK constraint', () {
      // These six strings are duplicated in three places: this list, the
      // service's _DECLINE_REASONS, and the database constraint. Translating
      // a KEY instead of a LABEL would fail validation with a 422 no
      // responder can act on.
      expect(
        DeclineReason.all.map((r) => r.key).toSet(),
        {
          'vehicle_down',
          'already_committed',
          'out_of_area',
          'insufficient_crew',
          'road_impassable',
          'other',
        },
      );
    });

    test('outcome keys match the backend CHECK constraint', () {
      expect(
        IncidentOutcome.all.map((o) => o.key).toSet(),
        {
          'handled_on_scene',
          'transported',
          'turned_over',
          'false_alarm',
          'nobody_found',
          'refused_assistance',
          'unable_to_access',
          'other',
        },
      );
    });

    test('every reason and outcome reads in BOTH languages', () {
      // Stronger than it looks. The labels moved out of these classes and into
      // the .arb files, so a key with no Filipino translation would fall back
      // to English silently — a responder who chose Filipino would get a sheet
      // in two languages and nothing would fail. This walks both locales.
      for (final t in <AppLocalizations>[AppLocalizationsEn(), AppLocalizationsFil()]) {
        for (final r in DeclineReason.all) {
          expect(r.label(t).trim(), isNotEmpty, reason: r.key);
          expect(r.hint(t).trim(), isNotEmpty, reason: '${r.key} hint');
        }
        for (final o in IncidentOutcome.all) {
          expect(o.label(t).trim(), isNotEmpty, reason: o.key);
          expect(o.hint(t).trim(), isNotEmpty, reason: '${o.key} hint');
        }
      }
    });

    test('the two locales actually differ', () {
      // Guards the failure the test above cannot see: a Filipino catalogue
      // that exists but was filled in with the English strings.
      final en = AppLocalizationsEn();
      final fil = AppLocalizationsFil();
      final differing = DeclineReason.all
          .where((r) => r.label(en) != r.label(fil))
          .length;
      expect(
        differing,
        greaterThan(3),
        reason: 'app_fil.arb looks like a copy of app_en.arb',
      );
    });
  });
}

/// Coordinates, and why the Navigate button was dead.
///
/// The responder endpoints never send `latitude`/`longitude`. The incidents
/// table stores a PostGIS `location`, and PostgREST returns it as GeoJSON — so
/// a model reading json['latitude'] got null on every single incident, on
/// every screen, forever. Nothing threw. The Navigate button fell through to a
/// text search of the address, and when the address was null too it built no
/// URI at all and the tap did nothing.
void _coordinateTests() {
  group('ResponderIncidentModel — coordinates', () {
    Map<String, dynamic> base() => {
      'id': 'inc-1',
      'report_text': 'May sunog',
      'status': 'dispatched',
      'created_at': '2026-09-05T08:00:00Z',
    };

    test('reads a PostGIS GeoJSON point', () {
      final m = ResponderIncidentModel.fromJson({
        ...base(),
        'location': {
          'type': 'Point',
          'coordinates': [124.4084881, 11.5817497],
        },
      });
      expect(m.latitude, closeTo(11.5817497, 1e-9));
      expect(m.longitude, closeTo(124.4084881, 1e-9));
    });

    test('does not transpose the pair', () {
      // GeoJSON is [lng, lat] — the opposite of how every screen names them.
      // Reading it backwards does not throw; it puts a Biliran fire in the sea
      // off Somalia, which is why this is asserted rather than assumed.
      final m = ResponderIncidentModel.fromJson({
        ...base(),
        'location': {
          'type': 'Point',
          'coordinates': [124.4, 11.58],
        },
      });
      expect(m.latitude, lessThan(90));
      expect(m.latitude, closeTo(11.58, 1e-9));
      expect(m.longitude, closeTo(124.4, 1e-9));
    });

    test('flat keys still win if the backend ever sends them', () {
      final m = ResponderIncidentModel.fromJson({
        ...base(),
        'latitude': 1.5,
        'longitude': 2.5,
        'location': {
          'type': 'Point',
          'coordinates': [99.0, 99.0],
        },
      });
      expect(m.latitude, 1.5);
      expect(m.longitude, 2.5);
    });

    test('a missing or malformed geometry is null, not a crash', () {
      for (final loc in <dynamic>[
        null,
        'POINT(1 2)',
        {'type': 'Point'},
        {'type': 'Point', 'coordinates': <dynamic>[]},
        {'type': 'Point', 'coordinates': [1]},
      ]) {
        final m = ResponderIncidentModel.fromJson({...base(), 'location': loc});
        expect(m.latitude, isNull, reason: 'location=$loc');
        expect(m.longitude, isNull, reason: 'location=$loc');
      }
    });
  });
}
