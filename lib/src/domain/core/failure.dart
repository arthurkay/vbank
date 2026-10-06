/// The single error type for the domain and application layers.
///
/// Every fallible operation returns [Result]; the [Failure] inside names what
/// went wrong in UI-agnostic terms. Presentation maps it to a message — domain
/// code never holds user-facing strings, so tests assert on types, not text.
sealed class Failure {
  const Failure();
}

/// The device cannot reach anyone: relays down, offline, dial refused.
final class NetworkFailure extends Failure {
  /// Peer or address that could not be reached, if any.
  final String? peer;

  /// Creates a network failure, optionally naming the unreachable [peer].
  const NetworkFailure({this.peer});
}

/// Stored or received data fails integrity checks: bad signature, CID
/// mismatch, undecryptable block.
final class IntegrityFailure extends Failure {
  /// What was being verified, e.g. a transaction id or CID.
  final String subject;

  /// Creates an integrity failure for [subject].
  const IntegrityFailure(this.subject);
}

/// The caller lacks permission: non-admin writing, non-owner promoting.
final class PermissionFailure extends Failure {
  /// What was attempted, e.g. `'approveLoan'`.
  final String action;

  /// Creates a permission failure for the attempted [action].
  const PermissionFailure(this.action);
}

/// Input violates a domain rule: negative amount, empty group name.
final class ValidationFailure extends Failure {
  /// Machine-readable reason, e.g. `'amountMustBePositive'`.
  final String reason;

  /// Creates a validation failure with the machine-readable [reason].
  const ValidationFailure(this.reason);
}

/// The record does not exist locally.
final class NotFoundFailure extends Failure {
  /// What was looked up, e.g. `'group:abc123'`.
  final String subject;

  /// Creates a not-found failure for [subject].
  const NotFoundFailure(this.subject);
}

/// The record already exists and must be unique: invite nonce reused.
final class ConflictFailure extends Failure {
  /// The conflicting record, e.g. `'invite:nonce…'`.
  final String subject;

  /// Creates a conflict failure for [subject].
  const ConflictFailure(this.subject);
}

/// Local storage failed: SQLCipher error, disk full.
final class StorageFailure extends Failure {
  /// The underlying error, kept for logging — never shown to users.
  final Object cause;

  /// Creates a storage failure wrapping [cause].
  const StorageFailure(this.cause);

  @override
  String toString() => 'StorageFailure($cause)';
}
