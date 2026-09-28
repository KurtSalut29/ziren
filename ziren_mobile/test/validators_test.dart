import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/core/utils/validators.dart';

/// The password rule here must stay in step with the server's
/// `RegisterRequest.password_strength` in
/// ziren_backend/app/models/user.py.
///
/// When it did not, the client checked only length: "abcdefgh" passed on the
/// phone, the API rejected it for the missing uppercase and digit, and the
/// user saw an opaque failure after appearing to submit successfully. These
/// tests exist to keep the two definitions from drifting again.
void main() {
  group('password — matches the server rule', () {
    test('accepts a password satisfying all three requirements', () {
      expect(Validators.password('Password1'), isNull);
    });

    test('rejects length-only passwords the server would refuse', () {
      // The exact case that used to pass on the client and fail on the API.
      expect(Validators.password('abcdefgh'), isNotNull);
    });

    test('requires an uppercase letter', () {
      expect(Validators.password('password1'), contains('uppercase'));
    });

    test('requires a number', () {
      expect(Validators.password('Passwordd'), contains('number'));
    });

    test('requires at least 8 characters', () {
      expect(Validators.password('Pass1'), contains('8 characters'));
    });
  });

  group('password — messages are actionable', () {
    test('names every missing requirement, not just the first', () {
      final message = Validators.password('abc')!;
      expect(message, contains('8 characters'));
      expect(message, contains('uppercase'));
      expect(message, contains('number'));
    });

    test('reads as a sentence rather than a list of codes', () {
      expect(Validators.password('abcdefgh'), contains(' and '));
    });

    test('empty password asks for one instead of reporting a rule', () {
      expect(Validators.password(''), 'Enter a password.');
    });
  });

  group('phoneNumber', () {
    test('accepts a plain 09 number', () {
      expect(Validators.phoneNumber('09171234567'), isNull);
    });

    test('accepts +639 form', () {
      expect(Validators.phoneNumber('+639171234567'), isNull);
    });

    test('accepts spaced and dashed input', () {
      // People type the number the way it is printed; formatting is not an
      // error worth blocking a registration over.
      expect(Validators.phoneNumber('0917 123 4567'), isNull);
      expect(Validators.phoneNumber('0917-123-4567'), isNull);
    });

    test('rejects a landline or truncated number', () {
      expect(Validators.phoneNumber('0532551234'), isNotNull);
      expect(Validators.phoneNumber('0917123'), isNotNull);
    });

    test('rejects free text — the field used to accept anything', () {
      expect(Validators.phoneNumber('wala akong number'), isNotNull);
    });

    test('gives an example rather than only a rule', () {
      expect(Validators.phoneNumber('123'), contains('0917'));
    });
  });

  group('email', () {
    test('accepts a normal address', () {
      expect(Validators.email('juan@example.com'), isNull);
    });

    test('calls out a missing @ specifically', () {
      expect(Validators.email('juan.example.com'), contains('@'));
    });

    test('rejects a missing domain', () {
      expect(Validators.email('juan@'), isNotNull);
    });

    test('suggests a correct example', () {
      expect(Validators.email('juan@@x'), contains('juan@example.com'));
    });
  });
}
