/// Base class for all domain-level failures in Ziren.
///
/// Using a sealed failure type instead of raw exceptions keeps error
/// handling explicit and exhaustive at the call site.
sealed class Failure {
  const Failure(this.message);
  final String message;
}

/// Network / connectivity failure.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection.']);
}

/// Server returned an unexpected error (5xx).
final class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error. Please try again.']);
}

/// Auth-related failure (wrong credentials, expired session, etc.).
final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed.']);
}

/// Changing the password: the current password given was not correct.
final class WrongPasswordFailure extends Failure {
  const WrongPasswordFailure() : super('Current password is not correct.');
}

/// Changing the password: the new one is the same as the current one.
final class SamePasswordFailure extends Failure {
  const SamePasswordFailure() : super('New password matches the current one.');
}

/// Permission denied / unauthorized access.
final class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'You do not have permission.']);
}

/// Local storage / cache failure.
final class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Local storage error.']);
}

/// Input validation failure (client-side catch before sending to server).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
