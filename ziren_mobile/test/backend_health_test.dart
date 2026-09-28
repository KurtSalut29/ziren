import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Ziren/core/network/backend_health.dart';

/// "Online" on Home means OUR backend answered. The check used to treat any
/// status below 500 as online, so ngrok's own "this account has reached its
/// bandwidth limit" page (a 403) showed as "Connected" — on a phone that could
/// not reach the backend at all.
void main() {
  const ngrokPage = '<html>ERR_NGROK_725</html>';

  MockClient replying(int status, String body) =>
      MockClient((_) async => http.Response(body, status));

  test('a healthy backend', () async {
    final ok = await BackendHealth.isReachable(
      client: replying(
        200,
        '{"status":"ok","service":"ziren-api","triage":{"model_loaded":true}}',
      ),
    );
    expect(ok, isTrue);
  });

  for (final (label, client) in <(String, MockClient)>[
    ('a tunnel over its quota (403)', replying(403, ngrokPage)),
    ('a tunnel that is not running (404)', replying(404, ngrokPage)),
    ('a captive portal answering 200 with a page', replying(200, '<html>Buy data</html>')),
    ('a backend that says it is not ok', replying(200, '{"status":"degraded"}')),
    ('a server error', replying(500, '{"detail":"boom"}')),
    ('JSON that is not an object', replying(200, '[1,2,3]')),
    (
      'no route to the host',
      MockClient((_) async => throw const SocketException('unreachable')),
    ),
  ]) {
    test('not reachable: $label', () async {
      expect(await BackendHealth.isReachable(client: client), isFalse);
    });
  }

  test('a connection that never answers is not reachable, and does not hang',
      () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    final watch = Stopwatch()..start();
    final ok = await BackendHealth.isReachable(
      client: client,
      timeout: const Duration(milliseconds: 150),
    );
    expect(ok, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
