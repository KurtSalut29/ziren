import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Asks the Ziren backend, by name, whether it is actually there.
///
/// "Is there a network" and "can this phone reach OUR server" are different
/// questions, and only the second one matters for sending a report. A phone can
/// have full LTE bars and no data at all (a prepaid SIM with no active promo
/// parks every packet behind a captive portal), and a phone on perfect Wi-Fi
/// can be talking to a tunnel that is down or over its quota. In both, a
/// connectivity check that only looks at the radio says "online".
///
/// The answer is a 200 with `{"status": "ok"}` and nothing less. This used to
/// count any status below 500 as reachable, which made ngrok's own 403 page
/// ("this account has reached its bandwidth limit") read as "Connected".
abstract final class BackendHealth {
  static Future<bool> isReachable({
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse('${AppConfig.apiBaseUrl}/health'))
          .timeout(timeout);
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body);
      return body is Map && body['status'] == 'ok';
    } catch (_) {
      return false;
    } finally {
      // Closing also abandons a request that outlived its timeout, instead of
      // leaving a socket open to a server that is not answering.
      if (client == null) c.close();
    }
  }
}
