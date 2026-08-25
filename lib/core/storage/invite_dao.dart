import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class InviteDao {
  Future<void> upsert(InviteData invite) async {
    final db = await AppDatabase.getInstance();
    await db.insert('invites', invite.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<InviteData?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('invites', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return InviteData.fromMap(result.first);
  }

  Future<List<InviteData>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'invites',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => InviteData.fromMap(map)).toList();
  }

  Future<void> markUsed(String id, String usedByPeerId) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'invites',
      {'used': 1, 'used_by_peer_id': usedByPeerId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.getInstance();
    await db.delete('invites', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteExpired(String groupId, DateTime now) async {
    final db = await AppDatabase.getInstance();
    await db.delete(
      'invites',
      where: 'group_id = ? AND used = 0 AND expires_at < ?',
      whereArgs: [groupId, now.millisecondsSinceEpoch],
    );
  }
}

class InviteData {
  final String id;
  final String groupId;
  final String? cid;
  final bool used;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Uint8List? nonce;
  final String? inviterPeerId;
  final Uint8List? inviterSignature;
  final String? usedByPeerId;

  const InviteData({
    required this.id,
    required this.groupId,
    this.cid,
    this.used = false,
    required this.createdAt,
    required this.expiresAt,
    this.nonce,
    this.inviterPeerId,
    this.inviterSignature,
    this.usedByPeerId,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
  bool get isValid => !used && !isExpired;

  Map<String, dynamic> toMap() => {
    'id': id,
    'group_id': groupId,
    'cid': cid,
    'used': used ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'expires_at': expiresAt.millisecondsSinceEpoch,
    'nonce': nonce,
    'inviter_peer_id': inviterPeerId,
    'inviter_signature': inviterSignature,
    'used_by_peer_id': usedByPeerId,
  };

  factory InviteData.fromMap(Map<String, dynamic> map) => InviteData(
    id: map['id'] as String,
    groupId: map['group_id'] as String,
    cid: map['cid'] as String?,
    used: (map['used'] as int) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int, isUtc: true),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int, isUtc: true),
    nonce: map['nonce'] != null ? Uint8List.fromList((map['nonce'] as List).cast<int>()) : null,
    inviterPeerId: map['inviter_peer_id'] as String?,
    inviterSignature: map['inviter_signature'] != null
        ? Uint8List.fromList((map['inviter_signature'] as List).cast<int>())
        : null,
    usedByPeerId: map['used_by_peer_id'] as String?,
  );
}
