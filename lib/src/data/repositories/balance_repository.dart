import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/balance.dart';
import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/repositories.dart';
import '../dto/balance_dto.dart';
import 'repository.dart';

/// Balance snapshots on sqflite.
final class SqlBalanceRepository extends SqlRepository
    implements BalanceRepository {
  /// Creates a balance repository on [db].
  SqlBalanceRepository(super.db);

  @override
  Stream<List<Balance>> watchByGroup(String groupId) =>
      watch(() => attempt(() => _ordered(groupId)));

  @override
  Future<Result<List<Balance>>> listByGroup(String groupId) =>
      attempt(() => _ordered(groupId));

  @override
  Future<Result<Balance>> find(String peerId, String groupId) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'balances',
        where: 'peer_id = ? AND group_id = ?',
        whereArgs: [peerId, groupId],
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('balance:$groupId:$peerId'));
      }
      return BalanceDto.fromRow(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveAll(String groupId, List<Balance> balances) async {
    final Result<Unit> result = await attempt(() async {
      await db.transaction((Transaction txn) async {
        await txn.delete(
          'balances',
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
        for (final Balance balance in balances) {
          await txn.insert(
            'balances',
            BalanceDto.toRow(balance),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  /// A group's snapshots, richest balance first.
  Future<List<Balance>> _ordered(String groupId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'balances',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'net_balance DESC',
    );
    final List<Balance> balances = [];
    for (final Map<String, Object?> row in rows) {
      final Result<Balance> balance = BalanceDto.fromRow(row);
      if (balance.isErr) {
        throw CorruptRow(balance.failure);
      }
      balances.add(balance.value);
    }
    return balances;
  }
}
