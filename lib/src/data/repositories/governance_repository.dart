import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/governance.dart';
import '../../domain/repositories.dart';
import '../dto/governance_dto.dart';
import 'repository.dart';

/// Removals, transfers and dissolutions on sqflite.
final class SqlGovernanceRepository extends SqlRepository
    implements GovernanceRepository {
  /// Creates a governance repository on [db].
  SqlGovernanceRepository(super.db);

  @override
  Future<Result<List<MemberRemoval>>> removalsByGroup(String groupId) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'removals',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'removed_at DESC',
      );
      final List<MemberRemoval> removals = [];
      for (final Map<String, Object?> row in rows) {
        final Result<MemberRemoval> removal = RemovalDto.fromRow(row);
        if (removal.isErr) {
          return Err(removal.failure);
        }
        removals.add(removal.value);
      }
      return Ok(removals);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveRemoval(MemberRemoval removal) =>
      attempt(() async {
        await db.insert(
          'removals',
          RemovalDto.toRow(removal),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return unit;
      });

  @override
  Future<Result<Unit>> liftRemoval(String id) => attempt(() async {
        await db.update(
          'removals',
          {'lifted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        return unit;
      });

  @override
  Future<Result<List<OwnershipTransfer>>> transfersByGroup(
    String groupId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'transfers',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'transferred_at DESC',
      );
      final List<OwnershipTransfer> transfers = [];
      for (final Map<String, Object?> row in rows) {
        final Result<OwnershipTransfer> transfer = TransferDto.fromRow(row);
        if (transfer.isErr) {
          return Err(transfer.failure);
        }
        transfers.add(transfer.value);
      }
      return Ok(transfers);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveTransfer(OwnershipTransfer transfer) =>
      attempt(() async {
        await db.insert(
          'transfers',
          TransferDto.toRow(transfer),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return unit;
      });

  @override
  Future<Result<GroupDissolution>> dissolutionByGroup(String groupId) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'dissolutions',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'initiated_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('dissolution:$groupId'));
      }
      return DissolutionDto.fromRow(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveDissolution(GroupDissolution dissolution) =>
      attempt(() async {
        await db.insert(
          'dissolutions',
          DissolutionDto.toRow(dissolution),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return unit;
      });
}
