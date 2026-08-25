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
}
