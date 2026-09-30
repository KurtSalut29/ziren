/// Shared input validation utilities.
///
/// These are client-side convenience checks only.
/// Server-side validation is always the authoritative check.
///
/// Messages here follow one rule: say what is wrong AND what to do about it.
/// "Invalid password" tells someone they failed; "Add 1 uppercase letter and
/// 1 number" tells them how to succeed. On a rural connection a rejected
/// submit can cost a minute, so the fix belongs in the first message rather
/// than the third attempt.
class Validators {
  Validators._();

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your email address.';
    }
    final v = value.trim();
    if (!v.contains('@')) {
      return 'Email addresses need an @ sign, like juan@example.com.';
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) {
      return 'That email does not look right. Example: juan@example.com';
    }
    return null;
  }

  /// The password rules, one predicate each.
  ///
  /// Kept as named functions because two things must never disagree about them:
  /// [password] (what is refused) and the requirements panel under the field
  /// (what the person is told, and ticked off as they type). When each had its
  /// own copy of "8 characters", changing one left the other lying.
  static const int passwordMinLength = 8;
  static bool passwordHasMinLength(String v) => v.length >= passwordMinLength;
  static bool passwordHasUppercase(String v) => v.contains(RegExp(r'[A-Z]'));
  static bool passwordHasNumber(String v) => v.contains(RegExp(r'[0-9]'));

  /// Mirrors the server rule in `RegisterRequest.password_strength`
  /// (ziren_backend/app/models/user.py). These two MUST agree — when the
  /// client checked only length, a password like "abcdefgh" passed here and
  /// was then rejected by the API, surfacing as an opaque failure after the
  /// account had seemingly been submitted.
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password.';

    final missing = <String>[];
    if (!passwordHasMinLength(value)) {
      missing.add('at least $passwordMinLength characters');
    }
    if (!passwordHasUppercase(value)) missing.add('1 uppercase letter');
    if (!passwordHasNumber(value)) missing.add('1 number');

    if (missing.isEmpty) return null;
    return 'Your password still needs ${_readableList(missing)}.';
  }

  static String? phoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your mobile number so responders can reach you.';
    }
    // Accept spaces, dashes and +63 forms; judge the digits, not the styling.
    final digits = value.replaceAll(RegExp(r'[\s\-()]'), '');
    final phoneRegex = RegExp(r'^(\+639|09)\d{9}$');
    if (!phoneRegex.hasMatch(digits)) {
      return 'Use an 11-digit mobile number starting with 09, '
          'like 0917 123 4567.';
    }
    return null;
  }

  /// Whether two mobile numbers are the same line, however each is written
  /// (0917 123 4567, +63 917 123 4567, 09171234567): compares the last ten
  /// digits. The commonest emergency-contact mistake is typing one's OWN
  /// number, so registration and the profile editor both refuse it.
  static bool sameMobile(String a, String b) {
    String tail(String s) {
      final digits = s.replaceAll(RegExp(r'\D'), '');
      return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    }

    final x = tail(a);
    final y = tail(b);
    return x.length >= 10 && x == y;
  }

  /// "a", "a and b", "a, b and c" — reads as a sentence rather than a list of
  /// error codes.
  static String _readableList(List<String> items) {
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }
}
