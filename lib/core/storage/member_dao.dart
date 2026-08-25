import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class MemberDao {
  Future<void> insert(MemberData member) async {
    final db = await AppDatabase.getInstance();
    await db.insert('members', member.toMap());
  }

  /// Insert-or-replace (used when restoring from a backup).
  Future<void> upsert(MemberData member) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'members',
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MemberData>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    return result.map((map) => MemberData.fromMap(map)).toList();
  }

  Future<MemberData?> get(String peerId, String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'members',
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [peerId, groupId],
    );
    if (result.isEmpty) return null;
    return MemberData.fromMap(result.first);
  }

  Future<void> update(MemberData member) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'members',
      member.toMap(),
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [member.peerId, member.groupId],
    );
  }

  Future<void> delete(String peerId, String groupId) async {
    final db = await AppDatabase.getInstance();
    await db.delete(
      'members',
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [peerId, groupId],
    );
  }

  /// Partial update: changes only the role, leaving status etc. untouched.
  Future<void> updateRole(String peerId, String groupId, String role) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'members',
      {'role': role},
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [peerId, groupId],
    );
  }

  /// Partial update: changes only the membership status.
  Future<void> updateStatus(String peerId, String groupId, String status) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'members',
      {'status': status},
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [peerId, groupId],
    );
  }

  Future<void> updateLoanStatus(String peerId, String groupId, bool hasLoan) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'members',
      {'has_outstanding_loan': hasLoan ? 1 : 0},
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [peerId, groupId],
    );
  }
}

class MemberData {
  final String peerId;
  final String groupId;
  final String name;
  final String role;
  final String status;
  final Uint8List publicKey;
  final DateTime joinedAt;
  final bool hasOutstandingLoan;

  const MemberData({
    required this.peerId,
    required this.groupId,
    required this.name,
    this.role = 'member',
    this.status = 'active',
    required this.publicKey,
    required this.joinedAt,
    this.hasOutstandingLoan = false,
  });

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'group_id': groupId,
    'name': name,
    'role': role,
    'status': status,
    'public_key': publicKey,
    'joined_at': joinedAt.millisecondsSinceEpoch,
    'has_outstanding_loan': hasOutstandingLoan ? 1 : 0,
  };

  factory MemberData.fromMap(Map<String, dynamic> map) => MemberData(
    peerId: map['peer_id'] as String,
    groupId: map['group_id'] as String,
    name: map['name'] as String,
    role: map['role'] as String,
    status: map['status'] as String,
    publicKey: Uint8List.fromList(map['public_key'] as List<int>),
    joinedAt: DateTime.fromMillisecondsSinceEpoch(map['joined_at'] as int),
    hasOutstandingLoan: (map['has_outstanding_loan'] as int) == 1,
  );
}
