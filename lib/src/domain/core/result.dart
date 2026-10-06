import 'failure.dart';

/// The outcome of a fallible operation: either [Ok] with a value or [Err]
/// with a [Failure]. No exceptions cross layer boundaries — repositories,
/// services and sync code all return [Result].
sealed class Result<T> {
  const Result();

  /// True when this is [Ok].
  bool get isOk => this is Ok<T>;

  /// True when this is [Err].
  bool get isErr => this is Err<T>;

  /// The value, or throws [StateError] when this is [Err].
  T get value => switch (this) {
        Ok(value: final v) => v,
        Err() => throw StateError('Result.value on Err'),
      };

  /// The failure, or throws [StateError] when this is [Ok].
  Failure get failure => switch (this) {
        Err(failure: final e) => e,
        Ok() => throw StateError('Result.failure on Ok'),
      };

  /// Maps the value, passing failures through untouched.
  Result<U> map<U>(U Function(T value) f) => switch (this) {
        Ok(value: final v) => Ok(f(v)),
        Err(failure: final e) => Err(e),
      };

  /// Chains fallible operations without nested switches.
  Result<U> flatMap<U>(Result<U> Function(T value) f) => switch (this) {
        Ok(value: final v) => f(v),
        Err(failure: final e) => Err(e),
      };
}

/// Success carrying [value]. `const Ok(null)` is valid for `Result<void>`-ish
/// flows — prefer `Result<Unit>` via [unit] instead.
final class Ok<T> extends Result<T> {
  @override
  final T value;

  /// Creates a success carrying [value].
  const Ok(this.value);
}

/// Failure carrying [failure].
final class Err<T> extends Result<T> {
  @override
  final Failure failure;

  /// Creates a failure carrying [failure].
  const Err(this.failure);
}

/// Unit value for operations that succeed with nothing to return.
typedef Unit = ();

/// The [Unit] constant to return from operations with no value.
const Unit unit = ();
