import '../crypto/signing.dart';
import '../domain/balance.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/governance.dart';
import '../domain/group.dart';
import '../domain/loans.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../domain/transactions.dart';
import 'context.dart';
import 'group_service.dart';
import 'signing_payloads.dart';
import 'transaction_service.dart';

/// Corrections and endings: reversal requests with owner/admin decisions,
/// and owner-run dissolution with pre-flight checks and payouts.
///
/// Requesting needs an active member involved in the transaction (or an
/// owner/admin for any of them); deciding needs an owner/admin who is not
/// the requester. An approved decision flips the transaction to reversed
/// and undoes its balance effect in the same call.
final class GovernanceService {
  /// Groups and roster checks.
  final GroupService groups;

  /// Ledger effects for decisions.
  final TransactionService transactions;

  /// Reversal rows.
  final TransactionRepository reversals;

  /// Removals, transfers, dissolutions.
  final GovernanceRepository governance;

  /// Loans (dissolution pre-flight).
  final LoanRepository loans;

  /// Balance snapshots (dissolution payouts read net balances).
  final BalanceRepository balances;

  /// Member signatures.
  final SignPayload sign;

  /// Clock for timestamps.
  final AppClock clock;

  /// Record ids.
  final IdGenerator ids;

  /// Creates a governance service.
  GovernanceService({
    required this.groups,
    required this.transactions,
    required this.reversals,
    required this.governance,
    required this.loans,
    required this.balances,
    required this.sign,
    required this.clock,
    required this.ids,
  });

  /// Requests a correction of [transactionId] with a human [reason].
  Future<Result<TransactionReversal>> requestReversal({
    required String groupId,
    required String actingPeerId,
    required String transactionId,
    required String reason,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    final Result<Member> acting = groups.activeMember(
      group.value,
      actingPeerId,
    );
    if (acting.isErr) {
      return Err(acting.failure);
    }
    final Result<Transaction> tx = await transactions.getById(transactionId);
    if (tx.isErr) {
      return Err(tx.failure);
    }
    if (tx.value.groupId != groupId) {
      return Err(NotFoundFailure('transaction:$transactionId'));
    }
    if (tx.value.status == TransactionStatus.reversed) {
      return const Err(ConflictFailure('transaction:alreadyReversed'));
    }
    final bool involved = tx.value.fromPeerId == actingPeerId ||
        tx.value.toPeerId == actingPeerId;
    if (!involved && !canWrite(acting.value.role)) {
      return const Err(PermissionFailure('reversalUnrelated'));
    }
    final Result<List<TransactionReversal>> existing =
        await reversals.reversalsByGroup(groupId);
    if (existing.isErr) {
      return Err(existing.failure);
    }
    final bool pending = existing.value.any(
      (TransactionReversal r) =>
          r.originalTransactionId == transactionId && r.isPending,
    );
    if (pending) {
      return const Err(ConflictFailure('reversal:alreadyPending'));
    }
    if (reason.trim().isEmpty) {
      return const Err(ValidationFailure('reversalReasonEmpty'));
    }
    final String id = ids();
    final TransactionReversal reversal = TransactionReversal(
      id: id,
      originalTransactionId: transactionId,
      groupId: groupId,
      requestedByPeerId: actingPeerId,
      reason: reason.trim(),
      requestedAt: clock().toUtc(),
      requesterSignature: await sign(
        SigningPayloads.reversalRequest(
          reversalId: id,
          groupId: groupId,
          originalTransactionId: transactionId,
          requestedByPeerId: actingPeerId,
          reason: reason.trim(),
        ),
      ),
    );
    final Result<Unit> saved = await reversals.saveReversal(reversal);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(reversal);
  }

  /// Approves or rejects a pending request. The decider must be an
  /// owner/admin and someone else than the requester. Approving flips the
  /// transaction and undoes its balances in the same call.
  Future<Result<TransactionReversal>> decideReversal({
    required String groupId,
    required String actingPeerId,
    required String reversalId,
    required bool approve,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireWriter(group.value, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Result<List<TransactionReversal>> all =
        await reversals.reversalsByGroup(groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    TransactionReversal? found;
    for (final TransactionReversal r in all.value) {
      if (r.id == reversalId) {
        found = r;
      }
    }
    if (found == null) {
      return Err(NotFoundFailure('reversal:$reversalId'));
    }
    if (!found.isPending) {
      return Err(ConflictFailure('reversal:${found.id}:alreadyDecided'));
    }
    if (found.requestedByPeerId == actingPeerId) {
      return const Err(PermissionFailure('reversalOwnRequest'));
    }
    final TransactionReversal decided = found.copyWith(
      status: approve ? ReversalStatus.approved : ReversalStatus.rejected,
      approvedByPeerId: actingPeerId,
      resolvedAt: clock().toUtc(),
    );
    final TransactionReversal signed = decided.copyWith(
      approverSignature: await sign(
        SigningPayloads.reversalDecision(
          reversalId: decided.id,
          status: decided.status.name,
          approvedByPeerId: actingPeerId,
        ),
      ),
    );
    final Result<Unit> saved = await reversals.saveReversal(signed);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    if (approve) {
      final Result<Unit> reversed = await transactions.markReversed(
        found.originalTransactionId,
      );
      if (reversed.isErr) {
        return Err(reversed.failure);
      }
    }
    return Ok(signed);
  }

  /// Applies a reversal from a peer: both signatures verify against the
  /// roster, decisions are final once stored.
  Future<Result<Unit>> importRemote(TransactionReversal reversal) async {
    final Member? requester = await groups.getMember(
      reversal.groupId,
      reversal.requestedByPeerId,
    );
    if (requester == null) {
      return Err(NotFoundFailure('member:${reversal.requestedByPeerId}'));
    }
    final bool requestOk = await SigningService.verifyWithBytes(
      SigningPayloads.reversalRequest(
        reversalId: reversal.id,
        groupId: reversal.groupId,
        originalTransactionId: reversal.originalTransactionId,
        requestedByPeerId: reversal.requestedByPeerId,
        reason: reversal.reason,
      ),
      reversal.requesterSignature,
      requester.publicKey,
    );
    if (!requestOk) {
      return Err(IntegrityFailure('reversal:${reversal.id}'));
    }
    if (!reversal.isPending) {
      final Member? approver = reversal.approvedByPeerId == null
          ? null
          : await groups.getMember(
              reversal.groupId,
              reversal.approvedByPeerId!,
            );
      if (approver == null ||
          !canWrite(approver.role) ||
          reversal.approverSignature == null) {
        return Err(IntegrityFailure('reversal:${reversal.id}:decision'));
      }
      final bool decisionOk = await SigningService.verifyWithBytes(
        SigningPayloads.reversalDecision(
          reversalId: reversal.id,
          status: reversal.status.name,
          approvedByPeerId: reversal.approvedByPeerId,
        ),
        reversal.approverSignature!,
        approver.publicKey,
      );
      if (!decisionOk) {
        return Err(IntegrityFailure('reversal:${reversal.id}:decision'));
      }
    }
    final Result<List<TransactionReversal>> all =
        await reversals.reversalsByGroup(reversal.groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    for (final TransactionReversal r in all.value) {
      if (r.id == reversal.id && !r.isPending) {
        return const Ok(unit);
      }
    }
    final Result<Unit> saved = await reversals.saveReversal(reversal);
    if (saved.isErr) {
      return saved;
    }
    if (reversal.isApproved) {
      return transactions.markReversed(reversal.originalTransactionId);
    }
    return const Ok(unit);
  }

  /// A group's reversals, newest first.
  Future<Result<List<TransactionReversal>>> reversalsForGroup(
    String groupId,
  ) =>
      reversals.reversalsByGroup(groupId);

  /// What blocks a dissolution right now: open loans and pending
  /// reversals.
  Future<Result<List<String>>> dissolutionBlockers(String groupId) async {
    final List<String> blockers = [];
    final Result<List<LoanRequest>> all = await loans.listByGroup(groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    final int active = all.value.where((LoanRequest l) => l.isActive).length;
    if (active > 0) {
      blockers.add('$active loan(s) still outstanding');
    }
    final Result<List<TransactionReversal>> open =
        await reversals.reversalsByGroup(groupId);
    if (open.isErr) {
      return Err(open.failure);
    }
    final int pending = open.value
        .where((TransactionReversal r) => r.isPending)
        .length;
    if (pending > 0) {
      blockers.add('$pending reversal request(s) pending');
    }
    return Ok(blockers);
  }

  /// Owner winds the group up: pre-flight, then every positive net balance
  /// pays out as a withdrawal, then the group dissolves. Returns the
  /// payout transactions.
  Future<Result<List<Transaction>>> dissolveGroup({
    required String groupId,
    required String actingPeerId,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireOwner(group.value, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notOwner));
    }
    final Result<List<String>> blockers = await dissolutionBlockers(groupId);
    if (blockers.isErr) {
      return Err(blockers.failure);
    }
    if (blockers.value.isNotEmpty) {
      return Err(ConflictFailure('dissolutionBlocked'));
    }
    final DateTime now = clock().toUtc();
    GroupDissolution record = GroupDissolution(
      id: ids(),
      groupId: groupId,
      initiatedByPeerId: actingPeerId,
      initiatedAt: now,
      status: DissolutionStatus.settlingLoans,
      allLoansSettled: true,
    );
    Result<Unit> saved = await groups.saveDissolution(record);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    record = record.copyWith(status: DissolutionStatus.distributingFunds);
    saved = await groups.saveDissolution(record);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    final Result<List<Balance>> snapshots = await balances.listByGroup(
      groupId,
    );
    if (snapshots.isErr) {
      return Err(snapshots.failure);
    }
    final List<Transaction> payouts = [];
    for (final Balance b in snapshots.value) {
      if (b.netBalance <= 0) {
        continue;
      }
      final Result<Transaction> payout = await transactions.createTransaction(
        groupId: groupId,
        authorPeerId: actingPeerId,
        fromPeerId: 'group',
        toPeerId: b.peerId,
        type: TransactionType.withdrawal,
        amount: b.netBalance,
        currency: group.value.config.currency,
        note: 'Dissolution payout',
      );
      if (payout.isErr) {
        return Err(payout.failure);
      }
      payouts.add(payout.value);
    }
    record = record.copyWith(
      status: DissolutionStatus.completed,
      fundsDistributed: true,
      completedAt: clock().toUtc(),
    );
    saved = await groups.saveDissolution(record);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(payouts);
  }
}
