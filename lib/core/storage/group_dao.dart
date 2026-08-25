import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class GroupDao {
  Future<void> insert(GroupData group) async {
    final db = await AppDatabase.getInstance();
    await db.insert('groups', group.toMap());
  }

  /// Insert-or-replace (used when restoring from a backup or applying a
  /// snapshot from a peer).
  Future<void> upsert(GroupData group) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<GroupData?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return GroupData.fromMap(result.first);
  }

  Future<List<GroupData>> getAll() async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('groups', orderBy: 'created_at DESC');
    return result.map((map) => GroupData.fromMap(map)).toList();
  }

  Future<void> update(GroupData group) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'groups',
      group.toMap(),
      where: 'id = ?',
      whereArgs: [group.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.getInstance();
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSyncStatus(String id, String cid) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'groups',
      {'cid': cid},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await AppDatabase.getInstance();
    await db.update('groups', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  /// Every local mutation of group metadata (roster, roles, config, status)
  /// bumps the sequence number and timestamp so peers can order snapshots
  /// (DESIGN_PLAN §19). Returns the new sequence number.
  Future<int> bumpSequence(String id) async {
    final db = await AppDatabase.getInstance();
    return db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE groups SET sequence_number = sequence_number + 1, updated_at = ? WHERE id = ?',
        [DateTime.now().toUtc().millisecondsSinceEpoch, id],
      );
      final rows = await txn.query('groups', columns: ['sequence_number'], where: 'id = ?', whereArgs: [id]);
      return rows.isEmpty ? 0 : rows.first['sequence_number'] as int;
    });
  }
}

class GroupData {
  final String id;
  final String name;
  final Uint8List data;
  final Uint8List configData;
  final String? cid;
  final bool requireApproval;
  final String status;
  final DateTime createdAt;
  final int sequenceNumber;
  final DateTime? updatedAt;

  const GroupData({
    required this.id,
    required this.name,
    required this.data,
    required this.configData,
    this.cid,
    this.requireApproval = false,
    this.status = 'active',
    required this.createdAt,
    this.sequenceNumber = 0,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'data': data,
    'config_data': configData,
    'cid': cid,
    'require_approval': requireApproval ? 1 : 0,
    'status': status,
    'created_at': createdAt.millisecondsSinceEpoch,
    'sequence_number': sequenceNumber,
    'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
  };

  factory GroupData.fromMap(Map<String, dynamic> map) => GroupData(
    id: map['id'] as String,
    name: map['name'] as String,
    data: Uint8List.fromList((map['data'] as List).cast<int>()),
    configData: Uint8List.fromList((map['config_data'] as List).cast<int>()),
    cid: map['cid'] as String?,
    requireApproval: (map['require_approval'] as int) == 1,
    status: map['status'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    sequenceNumber: map['sequence_number'] as int,
    updatedAt: map['updated_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
        : null,
  );
}
