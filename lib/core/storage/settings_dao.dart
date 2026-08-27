import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

/// Key/value app settings stored in the (encrypted) `node_config` table:
/// notification preferences, sync preferences, etc.
class SettingsDao {
  Future<void> set(String key, Object? value) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'node_config',
      {'key': key, 'value': utf8.encode(jsonEncode(value))},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<T?> get<T>(String key) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query('node_config', columns: ['value'], where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final raw = rows.first['value'];
    final bytes = raw is List<int> ? raw : (raw as List).cast<int>();
    return jsonDecode(utf8.decode(bytes)) as T?;
  }

  Future<bool> getBool(String key, {bool defaultValue = true}) async =>
      (await get<bool>(key)) ?? defaultValue;

  Future<void> delete(String key) async {
    final db = await AppDatabase.getInstance();
    await db.delete('node_config', where: 'key = ?', whereArgs: [key]);
  }
}

/// Well-known setting keys.
class SettingKeys {
  static const notificationsEnabled = 'notifications.enabled';
  static const notifyMeetings = 'notifications.meetings';
  static const notifyContributions = 'notifications.contributions';
  static const notifyLoans = 'notifications.loans';
  static const notifyActivity = 'notifications.activity'; // tx / joins / approvals
  static const syncIntervalMinutes = 'sync.interval_minutes';
  static const syncWifiOnly = 'sync.wifi_only';
  static const pendingJoins = 'pendingJoins'; // joins waiting for a member to come online
}
