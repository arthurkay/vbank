import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/repositories.dart';
import 'repository.dart';

/// Opaque settings on sqflite.
final class SqlSettingsRepository extends SqlRepository
    implements SettingsRepository {
  /// Creates a settings repository on [db].
  SqlSettingsRepository(super.db);

  @override
  Future<Result<List<String>>> keysWithPrefix(String prefix) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'settings',
        columns: ['key'],
      );
      return Ok([
        for (final Map<String, Object?> row in rows)
          if ((row['key']! as String).startsWith(prefix))
            row['key']! as String,
      ]);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Uint8List?>> get(String key) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
      );
      if (rows.isEmpty) {
        return const Ok(null);
      }
      return Ok(rows.first['value'] as Uint8List?);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> set(String key, Uint8List value) =>
      attempt(() async {
        await db.insert(
          'settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return unit;
      });

  @override
  Future<Result<Unit>> remove(String key) => attempt(() async {
        await db.delete('settings', where: 'key = ?', whereArgs: [key]);
        return unit;
      });
}
