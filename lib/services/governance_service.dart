import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/signing.dart';
import '../core/storage/balance_dao.dart';
import '../core/storage/loan_dao.dart';
import '../core/storage/reversal_dao.dart';
import '../models/group_dissolution.dart';
import '../models/loan.dart';
import '../models/transaction.dart';
import '../models/transaction_reversal.dart';
import 'group_service.dart';
import 'transaction_service.dart';

/// Transaction reversals (DESIGN_PLAN §27/§35) and group dissolution (§18).
class GovernanceService {
  final GroupService _groupService;
  final TransactionService _transactionService;
  final ReversalDao _reversalDao;
  final BalanceDao _balanceDao;
  final LoanDao _loanDao;
  static const _uuid = Uuid();

  GovernanceService({
    required GroupService groupService,
    required TransactionService transactionService,
    ReversalDao? reversalDao,
    BalanceDao? balanceDao,
    LoanDao? loanDao,
  })  : _groupService = groupService,
        _transactionService = transactionService,
        _reversalDao = reversalDao ?? ReversalDao(),
        _balanceDao = balanceDao ?? BalanceDao(),
        _loanDao = loanDao ?? LoanDao();

  // ---------------------------------------------------------------------------
  // Reversals
  // ---------------------------------------------------------------------------

  static List<int> reversalRequestPayload(TransactionReversal r) => utf8.encode(
        'vbank:reversal:${r.id}:${r.groupId}:${r.originalTransactionId}:${r.requestedByPeerId}:${r.reason}',
      );

  static List<int> reversalDecisionPayload(TransactionReversal r) => utf8.encode(
        'vbank:reversal-decision:${r.id}:${r.status.name}:${r.approvedByPeerId}',
      );

  /// Any active member may request a reversal of a transaction that affects
  /// them; owners/admins may request one for any transaction.
  Future<TransactionReversal> requestReversal({
    required String groupId,
    required String actingPeerId,
    required SimpleKeyPair actingKeyPair,
    required String transactionId,
    required String reason,
  }) async {
    final acting = await _groupService.requireActiveMember(groupId, actingPeerId);
    final tx = await _transactionService.getById(transactionId);
    if (tx == null || tx.groupId != groupId) throw StateError('Transaction not found');
    if (tx.status == TransactionStatus.reversed) {
      throw const PermissionException('Transaction is already reversed');
    }
    final involved = tx.fromPeerId == actingPeerId || tx.toPeerId == actingPeerId;
    if (!involved && !_groupService.canWrite(acting.role)) {
      throw const PermissionException('You can only request reversals of your own transactions');
    }
    if ((await _reversalDao.getForTransaction(transactionId)).any((r) => r.isPending)) {
      throw const PermissionException('A reversal request is already pending for this transaction');
    }
    if (reason.trim().isEmpty) throw ArgumentError('A reason is required');

    var reversal = TransactionReversal(
      id: _uuid.v4(),
      originalTransactionId: transactionId,
      groupId: groupId,
      requestedByPeerId: actingPeerId,
      reason: reason.trim(),
      requestedAt: DateTime.now().toUtc(),
      requesterSignature: Uint8List(0),
    );
    final sig = await SigningService.sign(reversalRequestPayload(reversal), actingKeyPair);
    reversal = _withRequesterSig(reversal, Uint8List.fromList(sig.bytes));
    await _reversalDao.upsert(reversal);
    return reversal;
  }

  /// Owner/admin (not the requester) approves or rejects.
  Future<TransactionReversal> decideReversal({
    required String groupId,
    required String actingPeerId,
    required SimpleKeyPair actingKeyPair,
    required String reversalId,
    required bool approve,
  }) async {
    await _groupService.requireWriter(groupId, actingPeerId);
    final r = await _reversalDao.getById(reversalId);
    if (r == null || r.groupId != groupId) throw StateError('Reversal not found');
    if (!r.isPending) throw PermissionException('Reversal is already ${r.status.name}');
    if (r.requestedByPeerId == actingPeerId) {
      throw const PermissionException('You cannot decide your own reversal request');
    }

    var decided = TransactionReversal(
      id: r.id,
      originalTransactionId: r.originalTransactionId,
      groupId: r.groupId,
      requestedByPeerId: r.requestedByPeerId,
      approvedByPeerId: actingPeerId,
      reason: r.reason,
      status: approve ? ReversalStatus.approved : ReversalStatus.rejected,
      requestedAt: r.requestedAt,
      resolvedAt: DateTime.now().toUtc(),
      requesterSignature: r.requesterSignature,
    );
    final sig = await SigningService.sign(reversalDecisionPayload(decided), actingKeyPair);
    decided = _withApproverSig(decided, Uint8List.fromList(sig.bytes));
    await _reversalDao.upsert(decided);
    if (approve) await _transactionService.markReversed(r.originalTransactionId);
    return decided;
  }

  /// Applies a reversal record from a peer after verifying both signatures
  /// against the roster.
  Future<void> importRemote(TransactionReversal r) async {
    final requester = await _groupService.getMember(r.groupId, r.requestedByPeerId);
    if (requester == null) throw StateError('Unknown requester ${r.requestedByPeerId}');
    final reqOk = await SigningService.verifyWithBytes(
      reversalRequestPayload(r), r.requesterSignature, requester.publicKey);
    if (!reqOk) throw StateError('Invalid reversal request signature');

    if (!r.isPending) {
      final approver = r.approvedByPeerId == null
          ? null
          : await _groupService.getMember(r.groupId, r.approvedByPeerId!);
      if (approver == null || !_groupService.canWrite(approver.role) || r.approverSignature == null) {
        throw StateError('Reversal decision not made by an owner/admin');
      }
      final decOk = await SigningService.verifyWithBytes(
        reversalDecisionPayload(r), r.approverSignature!, approver.publicKey);
      if (!decOk) throw StateError('Invalid reversal decision signature');
    }

    final local = await _reversalDao.getById(r.id);
    if (local != null && !local.isPending) return; // decisions are final
    await _reversalDao.upsert(r);
    if (r.isApproved) await _transactionService.markReversed(r.originalTransactionId);
  }

  Future<List<TransactionReversal>> reversalsForGroup(String groupId) => _reversalDao.getByGroupId(groupId);
  Future<List<TransactionReversal>> reversalsForTransaction(String txId) => _reversalDao.getForTransaction(txId);

  static TransactionReversal _withRequesterSig(TransactionReversal r, Uint8List sig) => TransactionReversal(
        id: r.id, originalTransactionId: r.originalTransactionId, groupId: r.groupId,
        requestedByPeerId: r.requestedByPeerId, approvedByPeerId: r.approvedByPeerId,
        reason: r.reason, status: r.status, requestedAt: r.requestedAt, resolvedAt: r.resolvedAt,
        requesterSignature: sig, approverSignature: r.approverSignature,
      );

  static TransactionReversal _withApproverSig(TransactionReversal r, Uint8List sig) => TransactionReversal(
        id: r.id, originalTransactionId: r.originalTransactionId, groupId: r.groupId,
        requestedByPeerId: r.requestedByPeerId, approvedByPeerId: r.approvedByPeerId,
        reason: r.reason, status: r.status, requestedAt: r.requestedAt, resolvedAt: r.resolvedAt,
        requesterSignature: r.requesterSignature, approverSignature: sig,
      );

  // ---------------------------------------------------------------------------
  // Dissolution (DESIGN_PLAN §18)
  // ---------------------------------------------------------------------------

  /// Pre-flight: what blocks a dissolution right now.
  Future<List<String>> dissolutionBlockers(String groupId) async {
    final blockers = <String>[];
    final loans = await _loanDao.getByGroupId(groupId);
    final active = loans.where((l) =>
        l.status == LoanStatus.disbursed.name || l.status == LoanStatus.repaying.name).length;
    if (active > 0) blockers.add('$active loan(s) still outstanding');
    final pendingReversals = await _reversalDao.countPending(groupId);
    if (pendingReversals > 0) blockers.add('$pendingReversals reversal request(s) pending');
    return blockers;
  }

  /// Owner dissolves the group: verifies no loans/reversals are open, pays
  /// each member their net balance out as a withdrawal transaction, marks the
  /// group dissolved. Returns the created distribution transactions.
  Future<List<Transaction>> dissolveGroup({
    required String groupId,
    required String actingPeerId,
    required SimpleKeyPair actingKeyPair,
  }) async {
    await _groupService.requireRole(
        groupId, actingPeerId, _groupService.canDissolve, 'Only the owner can dissolve the group');
    final blockers = await dissolutionBlockers(groupId);
    if (blockers.isNotEmpty) {
      throw PermissionException('Cannot dissolve: ${blockers.join('; ')}');
    }

    final now = DateTime.now().toUtc();
    var record = GroupDissolution(
      id: _uuid.v4(),
      groupId: groupId,
      initiatedByPeerId: actingPeerId,
      initiatedAt: now,
      status: DissolutionStatus.settlingLoans,
      allLoansSettled: true,
    );
    await _groupService.saveDissolution(record);

    record = _copyDissolution(record, status: DissolutionStatus.distributingFunds);
    await _groupService.saveDissolution(record);

    final created = <Transaction>[];
    for (final b in await _balanceDao.getByGroupId(groupId)) {
      if (b.netBalance <= 0) continue;
      created.add(await _transactionService.createTransaction(
        groupId: groupId,
        authorPeerId: actingPeerId,
        authorKeyPair: actingKeyPair,
        fromPeerId: 'group',
        toPeerId: b.peerId,
        type: TransactionType.withdrawal,
        amount: b.netBalance,
        note: 'Dissolution payout',
      ));
    }

    record = _copyDissolution(record,
        status: DissolutionStatus.completed, fundsDistributed: true, completedAt: DateTime.now().toUtc());
    await _groupService.saveDissolution(record);
    return created;
  }

  static GroupDissolution _copyDissolution(
    GroupDissolution d, {
    DissolutionStatus? status,
    bool? fundsDistributed,
    DateTime? completedAt,
  }) =>
      GroupDissolution(
        id: d.id,
        groupId: d.groupId,
        initiatedByPeerId: d.initiatedByPeerId,
        initiatedAt: d.initiatedAt,
        status: status ?? d.status,
        allLoansSettled: d.allLoansSettled,
        fundsDistributed: fundsDistributed ?? d.fundsDistributed,
        completedAt: completedAt ?? d.completedAt,
      );
}
