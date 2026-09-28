import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// One shared refresh in flight at a time, across every caller of
/// [withAuthRetry] — see its doc comment for why a call per 401 is wrong.
Future<void>? _refreshInFlight;

/// Refreshes the Supabase session, but only once no matter how many
/// concurrent callers ask for it at the same moment.
///
/// A responder screen's first load fires `loadQueue`, `loadDashboard`, and
/// `loadHistory` together (`Future.wait`). If the access token has expired,
/// all three see 401 within the same event-loop turn, and without this,
/// each of [withAuthRetry]'s three callers would independently call
/// `refreshSession()`. Supabase rotates the refresh token on use — the
/// first of those three calls to actually reach the server consumes it and
/// gets a new one back; the other two are still holding the token that
/// call just invalidated, and come back rejected. Two out of three retries
/// would then fail with the SAME 401 they were supposed to fix, which is
/// exactly what was observed live: dashboard and queue stayed 401'd while
/// history alone came back 200, all from one page load.
///
/// Making every caller share the one Future already in flight — rather
/// than each starting its own — means only one refresh call ever reaches
/// Supabase per expiry, and every concurrent 401 waits for that same
/// result before retrying.
Future<void> _sharedRefresh() {
  final existing = _refreshInFlight;
  if (existing != null) return existing;

  final future = Supabase.instance.client.auth.refreshSession();
  _refreshInFlight = future;
  // Cleared once the refresh this Future represents finishes, success or
  // failure — never mid-flight, and never a DIFFERENT, later refresh's
  // future by accident (the identical check).
  future.whenComplete(() {
    if (identical(_refreshInFlight, future)) {
      _refreshInFlight = null;
    }
  });
  return future;
}

/// One retry, with a refreshed Supabase session, for a request the backend
/// rejected with 401.
///
/// WHY THIS EXISTS
///
/// Every repository already reads Supabase's current access token fresh on
/// each request (a getter, not a cached string), so a session that quietly
/// refreshes on its own schedule was never the actual gap. The gap was what
/// happened next: the backend validates the token directly against
/// Supabase on every request (`get_current_user` in dependencies.py) and
/// returns a plain 401 the instant it's stale, and nothing on the client
/// ever retried that one request with a fresh token. A resident or
/// responder just saw "Invalid or expired token." — permanently, with no
/// recovery but manually logging out and back in.
///
/// HOW THE RETRY ACTUALLY PICKS UP THE NEW TOKEN
///
/// [request] is a closure, not a pre-built call — callers pass
/// `() => http.get(uri, headers: _headers)`, and `_headers` is itself a
/// getter that reads `Supabase.instance.client.auth.currentSession` live.
/// Calling [request] a second time after the refresh has updated that
/// session re-reads the getter and picks up the new token automatically;
/// nothing here has to know what a header even looks like.
///
/// ONLY ONE RETRY
///
/// If a freshly refreshed session still gets a 401, the token was never
/// the problem — the account itself was rejected (revoked, deleted, signed
/// out elsewhere) — and retrying again would just be the same failure on
/// a loop. That response is returned as-is for the caller's normal
/// status-code handling, same as any other non-200.
Future<http.Response> withAuthRetry(
  Future<http.Response> Function() request,
) async {
  var response = await request();
  if (response.statusCode != 401) return response;

  try {
    await _sharedRefresh();
  } catch (e) {
    // No refresh token, network down for the refresh call, or the
    // session is genuinely gone — none of that is retryable here.
    // Surface the original 401.
    debugPrint('[withAuthRetry] refresh failed, returning original 401: $e');
    return response;
  }

  response = await request();
  return response;
}
