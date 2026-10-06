import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/invites.dart';
import '../../domain/repositories.dart';
import '../dto/invite_dto.dart';
import 'repository.dart';

/// Invites on sqflite.
final class SqlInviteRepository extends SqlRepository
    implements InviteRepository {
  /// Creates an invite repository on [db].
  SqlInviteRepository(super.db);

  @override
  Future<Result<Invite>> findById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'invites',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('invite:$id'));
      }
      return InviteDto.fromRow(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<List<Invite>>> listByGroup(String groupId) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'invites',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'created_at DESC',
      );
      final List<Invite> invites = [];
      for (final Map<String, Object?> row in rows) {
        final Result<Invite> invite = InviteDto.fromRow(row);
        if (invite.isErr) {
          return Err(invite.failure);
        }
        invites.add(invite.value);
      }
      return Ok(invites);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> save(Invite invite) async {
    final Result<Unit> result = await attempt(() async {
      await db.insert(
        'invites',
        InviteDto.toRow(invite),
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
  Future<Result<Unit>> markUsed(String id) async {
    final Result<Unit> result = await attempt(() async {
      await db.update(
        'invites',
        {'used': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }
}
