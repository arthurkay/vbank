import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/backup.dart';
import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/identity.dart';
import '../../domain/repositories.dart';
import '../dto/backup_dto.dart';
import 'repository.dart';

/// Backups and the device identity on sqflite.
final class SqlBackupRepository extends SqlRepository
    implements BackupRepository {
  /// Creates a backup repository on [db].
  SqlBackupRepository(super.db);

  @override
  Future<Result<List<AppBackup>>> listBackups() async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'backups',
        orderBy: 'created_at DESC',
      );
      final List<AppBackup> backups = [];
      for (final Map<String, Object?> row in rows) {
        final Result<AppBackup> backup = BackupDto.fromRow(row);
        if (backup.isErr) {
          return Err(backup.failure);
        }
        backups.add(backup.value);
      }
      return Ok(backups);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveBackup(AppBackup backup) => attempt(() async {
        await db.insert(
          'backups',
          BackupDto.toRow(backup),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return unit;
      });

  @override
  Future<Result<Unit>> deleteBackup(String id) => attempt(() async {
        await db.delete('backups', where: 'id = ?', whereArgs: [id]);
        return unit;
      });

  @override
  Future<Result<UserIdentity?>> loadIdentity() async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'identity',
        limit: 1,
      );
      if (rows.isEmpty) {
        return const Ok(null);
      }
      final Result<UserIdentity> identity = IdentityDto.fromRow(rows.first);
      if (identity.isErr) {
        return Err(identity.failure);
      }
      return Ok(identity.value);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveIdentity(UserIdentity identity) =>
      attempt(() async {
        await db.insert(
          'identity',
          IdentityDto.toRow(identity),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return unit;
      });

  @override
  Future<Result<Unit>> clearIdentity() => attempt(() async {
        await db.delete('identity');
        return unit;
      });
}
