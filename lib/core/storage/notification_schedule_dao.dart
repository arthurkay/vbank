import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

/// Tracks scheduled local notifications so they can be cancelled/rescheduled
/// per item (DESIGN_PLAN §20, `notification_schedules`).
class NotificationScheduleDao {
  Future<void> upsert({
    required String id,
    String? groupId,
    required String type,
    required DateTime scheduledAt,
    String? payload,
  }) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'notification_schedules',
      {
        'id': id,
        'group_id': groupId,
        'notification_type': type,
        'scheduled_at': scheduledAt.toUtc().millisecondsSinceEpoch,
        'payload': payload,
        'is_active': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deactivate(String id) async {
    final db = await AppDatabase.getInstance();
    await db.update('notification_schedules', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> activeIdsWithPrefix(String prefix) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'notification_schedules',
      columns: ['id'],
      where: 'is_active = 1 AND id LIKE ?',
      whereArgs: ['$prefix%'],
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> active() async {
    final db = await AppDatabase.getInstance();
    return db.query('notification_schedules', where: 'is_active = 1', orderBy: 'scheduled_at ASC');
  }
}
