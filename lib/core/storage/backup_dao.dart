import 'dart:typed_data';
import 'database.dart';

class BackupDao {
  Future<void> insert(BackupData backup) async {
    final db = await AppDatabase.getInstance();
    await db.insert('app_backups', backup.toMap());
  }

  Future<BackupData?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('app_backups', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return BackupData.fromMap(result.first);
  }

  Future<List<BackupData>> getAll() async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('app_backups', orderBy: 'created_at DESC');
    return result.map((map) => BackupData.fromMap(map)).toList();
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.getInstance();
    await db.delete('app_backups', where: 'id = ?', whereArgs: [id]);
  }
}

class BackupData {
  final String id;
  final Uint8List encryptedPayload;
  final DateTime createdAt;
  final int version;
  final String backupType;

  const BackupData({
    required this.id,
    required this.encryptedPayload,
    required this.createdAt,
    this.version = 1,
    required this.backupType,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'encrypted_payload': encryptedPayload,
    'created_at': createdAt.millisecondsSinceEpoch,
    'version': version,
    'backup_type': backupType,
  };

  factory BackupData.fromMap(Map<String, dynamic> map) => BackupData(
    id: map['id'] as String,
    encryptedPayload: Uint8List.fromList(map['encrypted_payload'] as List<int>),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    version: map['version'] as int,
    backupType: map['backup_type'] as String,
  );
}
