import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/transaction_reversal.dart';
import 'database.dart';

class ReversalDao {
  Future<void> upsert(TransactionReversal r) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'transaction_reversals',
      {
        'id': r.id,
        'original_transaction_id': r.originalTransactionId,
        'group_id': r.groupId,
        'requested_by_peer_id': r.requestedByPeerId,
        'approved_by_peer_id': r.approvedByPeerId,
        'reason': r.reason,
        'status': r.status.name,
        'requested_at': r.requestedAt.millisecondsSinceEpoch,
        'resolved_at': r.resolvedAt?.millisecondsSinceEpoch,
        'requester_signature': r.requesterSignature,
        'approver_signature': r.approverSignature,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TransactionReversal?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query('transaction_reversals', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _fromMap(rows.first);
  }

  Future<List<TransactionReversal>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'transaction_reversals',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'requested_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<List<TransactionReversal>> getForTransaction(String transactionId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'transaction_reversals',
      where: 'original_transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'requested_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<int> countPending(String groupId) async {
    final db = await AppDatabase.getInstance();
    return Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM transaction_reversals WHERE group_id = ? AND status = 'pending'",
          [groupId],
        )) ??
        0;
  }

  static TransactionReversal _fromMap(Map<String, dynamic> m) => TransactionReversal(
    id: m['id'] as String,
    originalTransactionId: m['original_transaction_id'] as String,
    groupId: m['group_id'] as String,
    requestedByPeerId: m['requested_by_peer_id'] as String,
    approvedByPeerId: m['approved_by_peer_id'] as String?,
    reason: m['reason'] as String,
    status: ReversalStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => ReversalStatus.pending,
    ),
    requestedAt: DateTime.fromMillisecondsSinceEpoch(m['requested_at'] as int, isUtc: true),
    resolvedAt: m['resolved_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(m['resolved_at'] as int, isUtc: true)
        : null,
    requesterSignature: Uint8List.fromList((m['requester_signature'] as List).cast<int>()),
    approverSignature: m['approver_signature'] != null
        ? Uint8List.fromList((m['approver_signature'] as List).cast<int>())
        : null,
  );
}
