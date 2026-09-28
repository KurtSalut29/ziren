import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Ziren/core/errors/failures.dart';
import 'package:Ziren/features/incident_report/data/incident_repository.dart';
import 'package:Ziren/features/incident_report/domain/incident_model.dart';

/// Whether a failed submit is a NetworkFailure (nothing answered: a text
/// message is worth trying) or a ServerFailure (our backend answered and said
/// no: a text would be refused the same way) decides whether the resident is
/// texted. These pin down where each response lands — including the ones that
/// used to land in the wrong place.
void main() {
  const created = {
    'id': '11111111-2222-3333-4444-555555555555',
    'report_text': 'May sunog sa amin sa Naval',
    'status': 'received',
    'submitted_via': 'internet',
    'created_at': '2026-09-24T01:00:00+00:00',
  };

  /// What ngrok answers, with a 403, once the account is over its monthly
  /// bandwidth (and with a 404 when the tunnel is simply not running).
  const ngrokPage =
      '<!DOCTYPE html><html><body>This ngrok account has reached its network '
      'bandwidth limit for the month. (ERR_NGROK_725)</body></html>';

  Future<IncidentModel?> submit(
    MockClient client, {
    Duration timeout = const Duration(seconds: 2),
    String? stationId,
  }) => http.runWithClient(
    () => IncidentRepository(
      accessToken: () => 'test-token',
      submitTimeout: timeout,
    ).submitIncident(
      reportText: 'May sunog sa amin sa Naval',
      stationId: stationId,
      latitude: 11.5836,
      longitude: 124.4063,
    ),
    () => client,
  );

  MockClient replying(int status, String body) => MockClient(
    (_) async => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json'},
    ),
  );

  test('a saved report comes back as a model', () async {
    final model = await submit(replying(201, jsonEncode(created)));
    expect(model, isNotNull);
    expect(model!.id, created['id']);
    expect(model.submittedVia, 'internet');
  });

  test('sends the token, and omits station_id when there is no station',
      () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode(created), 201);
    });
    await submit(client);
    expect(seen.url.path, '/incidents/');
    expect(seen.headers['Authorization'], 'Bearer test-token');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body.containsKey('station_id'), isFalse);
    expect(body['latitude'], 11.5836);
    expect(body['longitude'], 124.4063);
  });

  test('sends station_id when one is chosen', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode(created), 201);
    });
    await submit(client, stationId: 'station-1');
    expect(jsonDecode(seen.body)['station_id'], 'station-1');
  });

  test('saved but unreadable reply: null, NOT a network failure', () async {
    // The server has the report. Calling this a network failure texted it a
    // second time.
    expect(await submit(replying(201, 'not json at all')), isNull);
    expect(await submit(replying(201, '{"id": 5}')), isNull);
  });

  group('the server answered and refused: ServerFailure, no text', () {
    test('a plain detail', () async {
      await expectLater(
        submit(replying(403, '{"detail": "Only residents can submit."}')),
        throwsA(
          isA<ServerFailure>().having(
            (e) => e.message,
            'message',
            'Only residents can submit.',
          ),
        ),
      );
    });

    test('a 422 whose detail is a LIST reads as the reason it was refused',
        () async {
      // detail is a list of {loc, msg, type} for a validation error. It used
      // to be handed straight to a String parameter, threw a TypeError, and
      // was caught as "no connection" — so a report the server had refused was
      // texted as if the internet were down.
      const body =
          '{"detail":[{"loc":["body","report_text"],"msg":"Value error, '
          'Report text must be at least 10 characters.","type":"value_error"}]}';
      await expectLater(
        submit(replying(422, body)),
        throwsA(
          isA<ServerFailure>().having(
            (e) => e.message,
            'message',
            'Report text must be at least 10 characters.',
          ),
        ),
      );
    });

    test('a 500 our backend itself sent', () async {
      await expectLater(
        submit(
          replying(500, '{"detail": "Failed to save incident report."}'),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('nothing of ours answered: NetworkFailure, a text is worth trying', () {
    test('a tunnel over its quota (403 HTML)', () async {
      await expectLater(
        submit(replying(403, ngrokPage)),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('a tunnel that is not running (404 HTML)', () async {
      await expectLater(
        submit(replying(404, ngrokPage)),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('a gateway error page (502 HTML)', () async {
      await expectLater(
        submit(replying(502, '<html>Bad Gateway</html>')),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('a JSON error that is not FastAPI\'s (no "detail")', () async {
      await expectLater(
        submit(replying(403, '{"error_code": 725}')),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('no route to the host', () async {
      final client = MockClient(
        (_) async => throw const SocketException('Failed host lookup'),
      );
      await expectLater(submit(client), throwsA(isA<NetworkFailure>()));
    });

    test('a connection that is open but never answered gives up on time',
        () async {
      // Signal but no data: never refused, never answered. This request used
      // to have no deadline at all.
      final client = MockClient((_) => Completer<http.Response>().future);
      final watch = Stopwatch()..start();
      await expectLater(
        submit(client, timeout: const Duration(milliseconds: 150)),
        throwsA(isA<NetworkFailure>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('errorDetail', () {
    test('reads a string, a list, and refuses what is not FastAPI', () {
      expect(IncidentRepository.errorDetail('{"detail": "No."}'), 'No.');
      expect(
        IncidentRepository.errorDetail(
          '{"detail":[{"msg":"a"},{"msg":"Value error, b"}]}',
        ),
        'a b',
      );
      expect(IncidentRepository.errorDetail('{"detail": 5}'), 'Submission failed.');
      expect(IncidentRepository.errorDetail('{"other": 1}'), isNull);
      expect(IncidentRepository.errorDetail('[1, 2]'), isNull);
      expect(IncidentRepository.errorDetail('<html></html>'), isNull);
      expect(IncidentRepository.errorDetail(''), isNull);
    });
  });
}
