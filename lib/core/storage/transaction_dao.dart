import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

/// Offline-queue states for a locally created transaction (DESIGN_PLAN §21).
class SyncStatus {
  static const queued = 'queued';
  static const syncing = 'syncing';
  static const synced = 'synced';
  static const failed = 'failed';

  /// After this many consecutive failures the row is parked as `failed` and
  /// only a manual retry resets it.
  static const maxAttempts = 5;
}

class TransactionDao {
  Future<void> insert(TransactionData transaction) async {
    final db = await AppDatabase.getInstance();
    await db.insert('transactions', transaction.toMap());
  }

  /// Insert-or-replace by id (backup restore).
  Future<void> upsert(TransactionData transaction) async {
    final db = await AppDatabase.getInstance();
    await db.insert('transactions', transaction.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> exists(String id) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'transactions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<TransactionData?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return TransactionData.fromMap(result.first);
  }

  Future<List<TransactionData>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'transactions',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => TransactionData.fromMap(map)).toList();
  }

  Future<List<TransactionData>> getAll() async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('transactions', orderBy: 'timestamp DESC');
    return result.map((map) => TransactionData.fromMap(map)).toList();
  }

  Future<List<TransactionData>> getByLoanId(String loanId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'transactions',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'timestamp ASC',
    );
    return result.map((map) => TransactionData.fromMap(map)).toList();
  }

  /// Number of contribution transactions [peerId] has made in [groupId].
  Future<int> countContributions(String groupId, String peerId) async {
    final db = await AppDatabase.getInstance();
    return Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM transactions WHERE group_id = ? AND from_peer_id = ? AND type = 'contribution' AND status = 'confirmed'",
          [groupId, peerId],
        )) ??
        0;
  }

  /// Only the mutable bookkeeping column (`status`) is intended to change;
  /// signed fields must never be edited after creation.
  Future<void> updateStatus(String id, String status) async {
    final db = await AppDatabase.getInstance();
    await db.update('transactions', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Offline queue
  // ---------------------------------------------------------------------------

  Future<void> markSynced(String id, String cid) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'transactions',
      {
        'synced': 1,
        'cid': cid,
        'sync_status': SyncStatus.synced,
        'last_sync_error': null,
        'last_sync_attempt_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncing(String id) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'transactions',
      {
        'sync_status': SyncStatus.syncing,
        'last_sync_attempt_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records a failed attempt; parks the row as `failed` once
  /// [SyncStatus.maxAttempts] is reached.
  Future<void> markSyncFailed(String id, String error) async {
    final db = await AppDatabase.getInstance();
    await db.rawUpdate('''
      UPDATE transactions
      SET sync_attempts = sync_attempts + 1,
          last_sync_error = ?,
          last_sync_attempt_at = ?,
          sync_status = CASE WHEN sync_attempts + 1 >= ? THEN ? ELSE ? END
      WHERE id = ?
    ''', [
      error,
      DateTime.now().toUtc().millisecondsSinceEpoch,
      SyncStatus.maxAttempts,
      SyncStatus.failed,
      SyncStatus.queued,
      id,
    ]);
  }

  /// Manual retry: back to `queued` with a fresh attempt counter.
  Future<void> resetForRetry(String id) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'transactions',
      {'sync_status': SyncStatus.queued, 'sync_attempts': 0, 'last_sync_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Rows waiting to be pushed (excludes `failed` — those need a manual retry).
  Future<List<TransactionData>> getUnsynced() async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'transactions',
      where: 'synced = 0 AND sync_status IN (?, ?)',
      whereArgs: [SyncStatus.queued, SyncStatus.syncing],
      orderBy: 'timestamp ASC',
    );
    return result.map((map) => TransactionData.fromMap(map)).toList();
  }

  Future<List<TransactionData>> getFailed() async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'transactions',
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.failed],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => TransactionData.fromMap(map)).toList();
  }

  Future<Map<String, int>> syncCounts() async {
    final db = await AppDatabase.getInstance();
    final rows = await db.rawQuery(
      'SELECT sync_status, COUNT(*) AS n FROM transactions GROUP BY sync_status',
    );
    return {for (final r in rows) (r['sync_status'] as String? ?? 'queued'): r['n'] as int};
  }

  // ---------------------------------------------------------------------------
  // Sequence numbers (per author — DESIGN_PLAN §19)
  // ---------------------------------------------------------------------------

  static Future<int> _maxSequenceNumber(
    DatabaseExecutor db,
    String groupId,
    String authorPeerId,
  ) async {
    final result = await db.rawQuery(
      'SELECT MAX(sequence_number) AS max_seq FROM transactions WHERE group_id = ? AND author_peer_id = ?',
      [groupId, authorPeerId],
    );
    return (result.first['max_seq'] as int?) ?? 0;
  }

  Future<int> getMaxSequenceNumber(String groupId, String authorPeerId) async {
    final db = await AppDatabase.getInstance();
    return _maxSequenceNumber(db, groupId, authorPeerId);
  }

  /// Allocates the author's next sequence number and inserts the row built by
  /// [build] in a single DB transaction. Numbers are per (group, author), so
  /// members working offline never collide with each other.
  Future<TransactionData> insertWithNextSequence(
    String groupId,
    String authorPeerId,
    Future<TransactionData> Function(int sequenceNumber) build,
  ) async {
    final db = await AppDatabase.getInstance();
    return db.transaction((txn) async {
      final seq = await _maxSequenceNumber(txn, groupId, authorPeerId) + 1;
      final data = await build(seq);
      await txn.insert('transactions', data.toMap());
      return data;
    });
  }
}

class TransactionData {
  final String id;
  final String groupId;
  final String fromPeerId;
  final String toPeerId;
  final String type;
  final double amount;
  final String currency;
  final String? note;
  final DateTime timestamp;
  final int sequenceNumber;
  final Uint8List senderSignature;
  final String status;
  final String? cid;
  final bool synced;
  final String syncStatus;
  final int syncAttempts;
  final DateTime? lastSyncAttemptAt;
  final String? lastSyncError;
  final String? loanId;

  /// Who signed this transaction (owner/admin). Defaults to [fromPeerId].
  final String authorPeerId;

  const TransactionData({
    required this.id,
    required this.groupId,
    required this.fromPeerId,
    required this.toPeerId,
    required this.type,
    required this.amount,
    this.currency = 'ZMW',
    this.note,
    required this.timestamp,
    required this.sequenceNumber,
    required this.senderSignature,
    this.status = 'confirmed',
    this.cid,
    this.synced = false,
    this.syncStatus = SyncStatus.queued,
    this.syncAttempts = 0,
    this.lastSyncAttemptAt,
    this.lastSyncError,
    this.loanId,
    String? authorPeerId,
  }) : authorPeerId = authorPeerId ?? fromPeerId;

  Map<String, dynamic> toMap() => {
    'id': id,
    'group_id': groupId,
    'from_peer_id': fromPeerId,
    'to_peer_id': toPeerId,
    'type': type,
    'amount': amount,
    'currency': currency,
    'note': note,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'sequence_number': sequenceNumber,
    'sender_signature': senderSignature,
    'status': status,
    'cid': cid,
    'synced': synced ? 1 : 0,
    'sync_status': syncStatus,
    'sync_attempts': syncAttempts,
    'last_sync_attempt_at': lastSyncAttemptAt?.millisecondsSinceEpoch,
    'last_sync_error': lastSyncError,
    'loan_id': loanId,
    'author_peer_id': authorPeerId,
  };

  factory TransactionData.fromMap(Map<String, dynamic> map) => TransactionData(
    id: map['id'] as String,
    groupId: map['group_id'] as String,
    fromPeerId: map['from_peer_id'] as String,
    toPeerId: map['to_peer_id'] as String,
    type: map['type'] as String,
    amount: (map['amount'] as num).toDouble(),
    currency: map['currency'] as String? ?? 'ZMW',
    note: map['note'] as String?,
    timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    sequenceNumber: map['sequence_number'] as int,
    senderSignature: Uint8List.fromList((map['sender_signature'] as List).cast<int>()),
    status: map['status'] as String? ?? 'confirmed',
    cid: map['cid'] as String?,
    synced: (map['synced'] as int? ?? 0) == 1,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.queued,
    syncAttempts: map['sync_attempts'] as int? ?? 0,
    lastSyncAttemptAt: map['last_sync_attempt_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['last_sync_attempt_at'] as int)
        : null,
    lastSyncError: map['last_sync_error'] as String?,
    loanId: map['loan_id'] as String?,
    authorPeerId: map['author_peer_id'] as String? ?? map['from_peer_id'] as String,
  );
}
