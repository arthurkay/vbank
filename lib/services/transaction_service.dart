import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/signing.dart';
import '../core/storage/balance_dao.dart';
import '../core/storage/group_dao.dart';
import '../core/storage/member_dao.dart';
import '../core/storage/transaction_dao.dart';
import '../models/group.dart';
import '../models/transaction.dart';

class PermissionException implements Exception {
  final String message;
  const PermissionException(this.message);
  @override
  String toString() => message;
}

class TransactionService {
  final TransactionDao _transactionDao;
  final BalanceDao _balanceDao;
  final MemberDao _memberDao;
  final GroupDao _groupDao;
  static const _uuid = Uuid();

  TransactionService({
    TransactionDao? transactionDao,
    BalanceDao? balanceDao,
    MemberDao? memberDao,
    GroupDao? groupDao,
  })  : _transactionDao = transactionDao ?? TransactionDao(),
        _balanceDao = balanceDao ?? BalanceDao(),
        _memberDao = memberDao ?? MemberDao(),
        _groupDao = groupDao ?? GroupDao();

  /// The canonical bytes the author signs. Covers *every* field so nothing
  /// can be altered after the fact (DESIGN_PLAN §1 "immutable, signed").
  /// Timestamps in signed payloads are formatted at millisecond precision.
  ///
  /// `DateTime.now()` carries microseconds, the database stores milliseconds,
  /// and records are re-read from the database before they are sent — so a
  /// payload signed in memory would never match the one a peer rebuilds.
  static String signedInstant(DateTime t) =>
      DateTime.fromMillisecondsSinceEpoch(t.toUtc().millisecondsSinceEpoch, isUtc: true).toIso8601String();

  static List<int> signingPayload(Transaction tx) {
    return utf8.encode(jsonEncode({
      'v': 2,
      'id': tx.id,
      'groupId': tx.groupId,
      'author': tx.authorPeerId,
      'from': tx.fromPeerId,
      'to': tx.toPeerId,
      'type': tx.type.name,
      'amount': tx.amount,
      'currency': tx.currency,
      'note': tx.note,
      'timestamp': signedInstant(tx.timestamp),
      'seq': tx.sequenceNumber,
      'loanId': tx.loanId,
    }));
  }

  static bool _canWrite(String role) =>
      role == MemberRole.owner.name || role == MemberRole.admin.name;

  /// DESIGN_PLAN §13: only an active owner/admin may record transactions.
  Future<MemberData> _requireWriter(String groupId, String peerId) async {
    final g = await _groupDao.getById(groupId);
    if (g == null) throw StateError('Group $groupId not found');
    if (g.status == GroupStatus.dissolved.name) {
      throw const PermissionException('This group has been dissolved');
    }
    final m = await _memberDao.get(peerId, groupId);
    if (m == null) throw const PermissionException('You are not a member of this group');
    if (m.status != MemberStatus.active.name) {
      throw const PermissionException('Your membership is not active');
    }
    if (!_canWrite(m.role)) {
      throw const PermissionException('Only the group owner or an admin can record transactions');
    }
    return m;
  }

  /// Records a transaction authored (signed) by [authorPeerId], who must be an
  /// active owner/admin. [fromPeerId]/[toPeerId] describe whose money moves
  /// (e.g. a member's contribution: from = member, to = 'group').
  Future<Transaction> createTransaction({
    required String groupId,
    required String authorPeerId,
    required SimpleKeyPair authorKeyPair,
    required String fromPeerId,
    required String toPeerId,
    required TransactionType type,
    required double amount,
    String currency = 'ZMW',
    String? note,
    String? loanId,
    bool skipPermissionCheck = false,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }
    if (!skipPermissionCheck) await _requireWriter(groupId, authorPeerId);

    final txId = _uuid.v4();
    final timestamp = DateTime.now().toUtc();

    // Sequence allocation + insert happen inside one DB transaction so the
    // author cannot allocate the same number twice.
    final data = await _transactionDao.insertWithNextSequence(groupId, authorPeerId, (seqNum) async {
      final unsigned = Transaction(
        id: txId,
        groupId: groupId,
        fromPeerId: fromPeerId,
        toPeerId: toPeerId,
        type: type,
        amount: amount,
        currency: currency,
        note: note,
        timestamp: timestamp,
        sequenceNumber: seqNum,
        senderSignature: Uint8List(0),
        authorPeerId: authorPeerId,
        loanId: loanId,
      );
      final signature = await SigningService.sign(signingPayload(unsigned), authorKeyPair);

      return TransactionData(
        id: txId,
        groupId: groupId,
        fromPeerId: fromPeerId,
        toPeerId: toPeerId,
        type: type.name,
        amount: amount,
        currency: currency,
        note: note,
        timestamp: timestamp,
        sequenceNumber: seqNum,
        senderSignature: Uint8List.fromList(signature.bytes),
        authorPeerId: authorPeerId,
        loanId: loanId,
      );
    });

    final tx = _toModel(data);
    await _applyBalance(tx, 1);
    return tx;
  }

  /// Verifies [tx]'s signature against the author's known public key.
  Future<bool> verifySignature(Transaction tx, List<int> authorPublicKey) {
    return SigningService.verifyWithBytes(signingPayload(tx), tx.senderSignature, authorPublicKey);
  }

  static const importedNew = 'imported';
  static const importedDuplicate = 'duplicate';

  /// Stores a transaction received from a peer (DESIGN_PLAN §9 steps 9-11).
  /// The caller has decrypted it and looked up the author's *stored* public
  /// key and role; this verifies the signature before anything is written.
  Future<String> importRemote(
    Transaction tx, {
    required List<int> authorPublicKey,
    required String cid,
  }) async {
    if (tx.amount <= 0) {
      throw ArgumentError.value(tx.amount, 'amount', 'must be positive');
    }
    if (!await verifySignature(tx, authorPublicKey)) {
      throw StateError('Rejected transaction ${tx.id}: invalid author signature');
    }
    if (await _transactionDao.exists(tx.id)) {
      await _transactionDao.markSynced(tx.id, cid);
      return importedDuplicate;
    }

    await _transactionDao.insert(TransactionData(
      id: tx.id,
      groupId: tx.groupId,
      fromPeerId: tx.fromPeerId,
      toPeerId: tx.toPeerId,
      type: tx.type.name,
      amount: tx.amount,
      currency: tx.currency,
      note: tx.note,
      timestamp: tx.timestamp,
      sequenceNumber: tx.sequenceNumber,
      senderSignature: tx.senderSignature,
      status: tx.status.name,
      cid: cid,
      synced: true,
      syncStatus: SyncStatus.synced,
      authorPeerId: tx.authorPeerId,
      loanId: tx.loanId,
    ));
    if (tx.status == TransactionStatus.confirmed) await _applyBalance(tx, 1);
    return importedNew;
  }

  /// Marks a transaction reversed and undoes its effect on balances.
  Future<void> markReversed(String transactionId) async {
    final data = await _transactionDao.getById(transactionId);
    if (data == null) throw StateError('Transaction $transactionId not found');
    if (data.status == TransactionStatus.reversed.name) return;
    await _transactionDao.updateStatus(transactionId, TransactionStatus.reversed.name);
    await _applyBalance(_toModel(data), -1);
  }

  /// Applies (sign = 1) or undoes (sign = -1) a transaction's balance effect.
  Future<void> _applyBalance(Transaction tx, int sign) async {
    final amount = tx.amount * sign;
    switch (tx.type) {
      case TransactionType.contribution:
        await _balanceDao.updateContribution(tx.fromPeerId, tx.groupId, amount);
        break;
      case TransactionType.loan:
        await _balanceDao.updateLoan(tx.toPeerId, tx.groupId, amount);
        break;
      case TransactionType.repayment:
        await _balanceDao.updateRepayment(tx.fromPeerId, tx.groupId, amount);
        break;
      case TransactionType.penalty:
      case TransactionType.fee:
        await _balanceDao.updatePenalty(tx.fromPeerId, tx.groupId, amount);
        break;
      case TransactionType.withdrawal:
        await _balanceDao.updateWithdrawal(tx.toPeerId, tx.groupId, amount);
        break;
      case TransactionType.reversal:
        break;
    }
  }

  Future<Transaction?> getById(String id) async {
    final data = await _transactionDao.getById(id);
    if (data == null) return null;
    return _toModel(data);
  }

  Future<List<Transaction>> getByGroupId(String groupId) async {
    final data = await _transactionDao.getByGroupId(groupId);
    return data.map(_toModel).toList();
  }

  Future<List<Transaction>> getAll() async {
    final data = await _transactionDao.getAll();
    return data.map(_toModel).toList();
  }

  Future<List<Transaction>> getByLoanId(String loanId) async {
    final data = await _transactionDao.getByLoanId(loanId);
    return data.map(_toModel).toList();
  }

  Future<int> countContributions(String groupId, String peerId) =>
      _transactionDao.countContributions(groupId, peerId);

  // --- offline queue (DESIGN_PLAN §21) ----------------------------------------

  Future<List<Transaction>> getUnsynced() async {
    final data = await _transactionDao.getUnsynced();
    return data.map(_toModel).toList();
  }

  Future<List<TransactionData>> getFailed() => _transactionDao.getFailed();
  Future<Map<String, int>> syncCounts() => _transactionDao.syncCounts();
  Future<void> markSyncing(String id) => _transactionDao.markSyncing(id);
  Future<void> markSynced(String id, String cid) => _transactionDao.markSynced(id, cid);
  Future<void> markSyncFailed(String id, String error) => _transactionDao.markSyncFailed(id, error);
  Future<void> retry(String id) => _transactionDao.resetForRetry(id);

  Transaction _toModel(TransactionData data) => Transaction(
    id: data.id,
    groupId: data.groupId,
    fromPeerId: data.fromPeerId,
    toPeerId: data.toPeerId,
    type: TransactionType.values.firstWhere(
      (t) => t.name == data.type,
      orElse: () => throw StateError('Unknown transaction type "${data.type}"'),
    ),
    amount: data.amount,
    currency: data.currency,
    note: data.note,
    timestamp: data.timestamp,
    sequenceNumber: data.sequenceNumber,
    senderSignature: data.senderSignature,
    status: TransactionStatus.values.firstWhere(
      (s) => s.name == data.status,
      orElse: () => TransactionStatus.confirmed,
    ),
    authorPeerId: data.authorPeerId,
    loanId: data.loanId,
  );
}
