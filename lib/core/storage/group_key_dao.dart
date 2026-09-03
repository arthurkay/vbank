import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class GroupKeyDao {
  Future<void> upsert(String groupId, Uint8List key) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'group_keys',
      {
        'group_id': groupId,
        'key': key,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Uint8List?> get(String groupId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'group_keys',
      columns: ['key'],
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    if (rows.isEmpty) return null;
    return Uint8List.fromList(rows.first['key'] as List<int>);
  }

  Future<Map<String, Uint8List>> getAll() async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query('group_keys');
    return {
      for (final r in rows)
        r['group_id'] as String: Uint8List.fromList(r['key'] as List<int>),
    };
  }

  Future<void> delete(String groupId) async {
    final db = await AppDatabase.getInstance();
    await db.delete('group_keys', where: 'group_id = ?', whereArgs: [groupId]);
  }

  // --- key ring (rotation) ---------------------------------------------------

  Future<void> upsertVersion(String groupId, int version, Uint8List key) async {
    final db = await AppDatabase.getInstance();
    await db.insert('group_key_history', {'group_id': groupId, 'version': version, 'key': key},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// version → key, oldest first.
  Future<Map<int, Uint8List>> versions(String groupId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query('group_key_history', where: 'group_id = ?', whereArgs: [groupId], orderBy: 'version ASC');
    return {for (final r in rows) r['version'] as int: Uint8List.fromList(r['key'] as List<int>)};
  }

  Future<Map<String, Map<int, Uint8List>>> allVersions() async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query('group_key_history', orderBy: 'group_id, version ASC');
    final out = <String, Map<int, Uint8List>>{};
    for (final r in rows) {
      (out[r['group_id'] as String] ??= {})[r['version'] as int] = Uint8List.fromList(r['key'] as List<int>);
    }
    return out;
  }
}
