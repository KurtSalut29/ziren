import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ziren/features/sos/domain/sos_provider.dart';
import 'package:ziren/features/sos/domain/sos_result.dart';
import 'package:ziren/core/errors/failures.dart';

import 'support/fake_sos_repository.dart';

/// SOS has one route: the internet. This locks in how each outcome of that one
/// call is handled — success starts the cooldown, a failure is shown honestly,
/// and an unrecognised error still points the resident at 911.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  SosProvider build(Future<SosResult> Function() online) =>
      SosProvider(repository: FakeSosRepository(online))
        ..debugPosition = kNavalPosition();

  test('a successful submit starts the cooldown', () async {
    final p = build(() async => kSosResult);

    expect(await p.submit(), isTrue);

    expect(p.status, SosStatus.success);
    expect(p.lastResult, isNotNull);
    expect(p.isCoolingDown, isTrue);
  });

  test('the server refusing (cooldown, suspension, ...) is shown as-is',
      () async {
    final p = build(
      () async =>
          throw const ServerFailure(
            'You submitted an SOS report recently. Please wait 12 minute(s).',
          ),
    );

    expect(await p.submit(), isFalse);

    expect(p.status, SosStatus.error);
    expect(p.errorMessage, 'You submitted an SOS report recently. Please wait 12 minute(s).');
    expect(p.isCoolingDown, isFalse);
  });

  test('no route to the server is shown as-is too', () async {
    final p = build(
      () async =>
          throw const NetworkFailure(
            'Could not reach the server. Check your connection.',
          ),
    );

    expect(await p.submit(), isFalse);

    expect(p.errorMessage, 'Could not reach the server. Check your connection.');
  });

  test('an unrecognised error still points at 911, not a stack trace',
      () async {
    final p = build(() async => throw StateError('bug'));

    expect(await p.submit(), isFalse);

    expect(p.errorMessage, 'SOS could not be sent. Please call 911 directly.');
  });

  test('reset clears the result and error together', () async {
    final p = build(() async => throw const NetworkFailure('x'));
    await p.submit();
    expect(p.errorMessage, isNotNull);

    p.reset();

    expect(p.status, SosStatus.idle);
    expect(p.errorMessage, isNull);
    expect(p.lastResult, isNull);
  });
}
