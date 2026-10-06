import 'package:sqflite_sqlcipher/sqflite.dart' hide Transaction;

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/repositories.dart';
import '../../domain/transactions.dart';
import '../dto/transaction_dto.dart';
import 'repository.dart';

/// Transactions and reversals on sqflite.
final class SqlTransactionRepository extends SqlRepository
    implements TransactionRepository {
  /// Creates a transaction repository on [db].
  SqlTransactionRepository(super.db);

  @override
  Stream<List<Transaction>> watchByGroup(String groupId) =>
      watch(() => attempt(() => _ordered(groupId)));

  @override
  Future<Result<List<Transaction>>> listByGroup(String groupId) =>
      attempt(() => _ordered(groupId));

  @override
  Future<Result<Transaction>> findById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('transaction:$id'));
      }
      return TransactionDto.fromRow(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> save(Transaction transaction) async {
    final Result<Unit> result = await attempt(() async {
      await upsertRow(
        db,
        'transactions',
        TransactionDto.toRow(transaction),
        'id = ?',
        [transaction.id],
      );
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  @override
  Future<Result<Unit>> markReversed(String id) async {
    final Result<Unit> result = await attempt(() async {
      await db.update(
        'transactions',
        {'status': TransactionStatus.reversed.name},
        where: 'id = ? AND status = ?',
        whereArgs: [id, TransactionStatus.confirmed.name],
      );
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  @override
  Future<Result<Unit>> saveReversal(TransactionReversal reversal) async {
    final Result<Unit> result = await attempt(() async {
      await db.insert(
        'reversals',
        ReversalDto.toRow(reversal),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  @override
  Future<Result<List<TransactionReversal>>> reversalsByGroup(
    String groupId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'reversals',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'requested_at DESC',
      );
      final List<TransactionReversal> reversals = [];
      for (final Map<String, Object?> row in rows) {
        final Result<TransactionReversal> reversal =
            ReversalDto.fromRow(row);
        if (reversal.isErr) {
          return Err(reversal.failure);
        }
        reversals.add(reversal.value);
      }
      return Ok(reversals);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// A group's transactions, oldest first (ledger order).
  Future<List<Transaction>> _ordered(String groupId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'sequence_number ASC',
    );
    final List<Transaction> transactions = [];
    for (final Map<String, Object?> row in rows) {
      final Result<Transaction> tx = TransactionDto.fromRow(row);
      if (tx.isErr) {
        throw CorruptRow(tx.failure);
      }
      transactions.add(tx.value);
    }
    return transactions;
  }
}
