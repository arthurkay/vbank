import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';

/// Runs [run], mapping any database error to `Err(StorageFailure)`.
Future<Result<T>> attempt<T>(Future<T> Function() run) async {
  try {
    return Ok(await run());
  } catch (e) {
    return Err(StorageFailure(e));
  }
}

/// A stored row that no longer parses, surfacing inside `watch…` queries.
///
/// One-shot readers return `Err(StorageFailure)` instead; streams have no
/// `Result` channel, so corruption surfaces as a stream error carrying the
/// underlying [failure].
final class CorruptRow implements Exception {
  /// The parse failure for the offending row.
  final Failure failure;

  /// Creates a corruption error for [failure].
  const CorruptRow(this.failure);

  @override
  String toString() => 'CorruptRow($failure)';
}

/// Shared plumbing for the sqflite repositories: change notifications back
/// the `watch…` streams, which replay current state on subscribe.
abstract base class SqlRepository {
  /// The database. Owned by the opener, never closed here.
  final Database db;

  /// Creates a repository on [db].
  SqlRepository(this.db);

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Wakes every `watch…` stream. Call after each write.
  void notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// Replays [query] now, then after every [notify]. Query failures
  /// surface as stream errors carrying [CorruptRow].
  ///
  /// Implemented with an explicit controller rather than `async*`/`await
  /// for`: cancelling a subscription parked in `await for` over the change
  /// bus never completes, hanging whoever awaits the cancel.
  Stream<List<T>> watch<T>(Future<Result<List<T>>> Function() query) {
    StreamController<List<T>>? controller;
    StreamSubscription<void>? subscription;
    Future<void> emit() async {
      final StreamController<List<T>>? target = controller;
      if (target == null || target.isClosed) {
        return;
      }
      try {
        final Result<List<T>> result = await query();
        if (result.isErr) {
          throw CorruptRow(result.failure);
        }
        if (!target.isClosed) {
          target.add(result.value);
        }
      } catch (e, s) {
        if (!target.isClosed) {
          target.addError(e, s);
        }
      }
    }

    controller = StreamController<List<T>>(
      onListen: () {
        subscription = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Releases streams.
  Future<void> close() => _changes.close();
}
