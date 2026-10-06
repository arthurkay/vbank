import 'dart:typed_data';

import '../crypto/signing.dart';
import '../domain/balance.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/group.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../domain/transactions.dart';
import 'context.dart';
import 'group_service.dart';
import 'signing_payloads.dart';

/// How an imported record fared.
enum ImportResult {
  /// Stored and applied.
  imported,

  /// Already known; skipped.
  duplicate,
}

/// Signed money movements with balance effects.
///
/// Recording needs an active owner/admin author. Balances move with the
/// record in the same call (no window where the ledger and the balances
/// disagree); reversals undo the exact effect. Remote imports verify the
/// author's signature against the roster's stored key before anything is
/// written.
final class TransactionService {
  /// Transactions and reversals.
  final TransactionRepository transactions;

  /// Groups and the roster (writer checks).
  final GroupRepository groups;

  /// Cached balance snapshots.
  final BalanceRepository balances;

  /// Author signatures.
  final SignPayload sign;

  /// Clock for timestamps.
  final AppClock clock;

  /// Record ids.
  final IdGenerator ids;

  /// Creates a transaction service.
  TransactionService({
    required this.transactions,
    required this.groups,
    required this.balances,
    required this.sign,
    required this.clock,
    required this.ids,
  });

  /// Records a signed transaction authored by [authorPeerId] (an active
  /// owner/admin). [fromPeerId]/[toPeerId] describe whose money moves (`'group'`
  /// marks the fund's side).
  Future<Result<Transaction>> createTransaction({
    required String groupId,
    required String authorPeerId,
    required String fromPeerId,
    required String toPeerId,
    required TransactionType type,
    required double amount,
    String currency = 'ZMW',
    String? note,
    String? loanId,
  }) async {
    if (amount <= 0) {
      return const Err(ValidationFailure('transactionAmountNotPositive'));
    }
    final Result<Group> group = await groups.findById(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    final Result<Member> author = _requireWriter(group.value, authorPeerId);
    if (author.isErr) {
      return Err(author.failure);
    }
    final Result<List<Transaction>> existing =
        await transactions.listByGroup(groupId);
    if (existing.isErr) {
      return Err(existing.failure);
    }
    var sequence = 0;
    for (final Transaction t in existing.value) {
      if (t.sequenceNumber >= sequence) {
        sequence = t.sequenceNumber + 1;
      }
    }
    // Truncated to millis: what is signed is what is stored.
    final DateTime timestamp = SigningPayloads.signedInstant(clock());
    final Transaction unsigned = Transaction(
      id: ids(),
      groupId: groupId,
      fromPeerId: fromPeerId,
      toPeerId: toPeerId,
      type: type,
      amount: amount,
      currency: currency,
      note: note,
      timestamp: timestamp,
      sequenceNumber: sequence,
      senderSignature: Uint8List(0),
      authorPeerId: authorPeerId,
      loanId: loanId,
    );
    final Transaction signed = Transaction(
      id: unsigned.id,
      groupId: unsigned.groupId,
      fromPeerId: unsigned.fromPeerId,
      toPeerId: unsigned.toPeerId,
      type: unsigned.type,
      amount: unsigned.amount,
      currency: unsigned.currency,
      note: unsigned.note,
      timestamp: unsigned.timestamp,
      sequenceNumber: unsigned.sequenceNumber,
      senderSignature: await sign(SigningPayloads.transaction(unsigned)),
      authorPeerId: unsigned.authorPeerId,
      loanId: unsigned.loanId,
    );
    final Result<Unit> saved = await transactions.save(signed);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    final Result<Unit> balanced = await _applyBalance(signed, 1);
    if (balanced.isErr) {
      return Err(balanced.failure);
    }
    return Ok(signed);
  }

  /// Verifies [tx]'s signature against the author's roster key.
  Future<bool> verifySignature(
    Transaction tx,
    List<int> authorPublicKey,
  ) =>
      SigningService.verifyWithBytes(
        SigningPayloads.transaction(tx),
        tx.senderSignature,
        authorPublicKey,
      );

  /// Stores a transaction received from a peer. The caller decrypted it and
  /// looked up the author's *stored* roster key and role; the signature is
  /// verified before anything is written.
  Future<Result<ImportResult>> importRemote(
    Transaction tx, {
    required List<int> authorPublicKey,
  }) async {
    if (tx.amount <= 0) {
      return const Err(ValidationFailure('transactionAmountNotPositive'));
    }
    if (!await verifySignature(tx, authorPublicKey)) {
      return Err(IntegrityFailure('transaction:${tx.id}'));
    }
    final Result<Transaction> existing = await transactions.findById(tx.id);
    if (existing.isOk) {
      return const Ok(ImportResult.duplicate);
    }
    final Result<Unit> saved = await transactions.save(tx);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    if (tx.status == TransactionStatus.confirmed) {
      final Result<Unit> balanced = await _applyBalance(tx, 1);
      if (balanced.isErr) {
        return Err(balanced.failure);
      }
    }
    return const Ok(ImportResult.imported);
  }

  /// Marks a transaction reversed and undoes its balance effect.
  /// Idempotent: already-reversed is a no-op success.
  Future<Result<Unit>> markReversed(String transactionId) async {
    final Result<Transaction> tx = await transactions.findById(transactionId);
    if (tx.isErr) {
      return Err(tx.failure);
    }
    if (tx.value.status == TransactionStatus.reversed) {
      return const Ok(unit);
    }
    final Result<Unit> marked = await transactions.markReversed(transactionId);
    if (marked.isErr) {
      return marked;
    }
    return _applyBalance(tx.value, -1);
  }

  /// One transaction, or `Err(NotFoundFailure)`.
  Future<Result<Transaction>> getById(String id) =>
      transactions.findById(id);

  /// A group's ledger, oldest first.
  Future<Result<List<Transaction>>> listByGroup(String groupId) =>
      transactions.listByGroup(groupId);

  /// Confirmed contribution count (loan eligibility).
  Future<Result<int>> countContributions(String groupId, String peerId) async {
    final Result<List<Transaction>> all = await transactions.listByGroup(
      groupId,
    );
    if (all.isErr) {
      return Err(all.failure);
    }
    var count = 0;
    for (final Transaction t in all.value) {
      if (t.type == TransactionType.contribution &&
          t.status == TransactionStatus.confirmed &&
          t.fromPeerId == peerId) {
        count++;
      }
    }
    return Ok(count);
  }

  /// The author check: live group, active membership, write rank.
  Result<Member> _requireWriter(Group group, String peerId) {
    if (group.status == GroupStatus.dissolved) {
      return const Err(PermissionFailure(GroupFailures.groupDissolved));
    }
    Member? found;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        found = m;
      }
    }
    if (found == null) {
      return const Err(PermissionFailure(GroupFailures.notMember));
    }
    if (found.status != MemberStatus.active) {
      return const Err(PermissionFailure(GroupFailures.membershipInactive));
    }
    if (!canWrite(found.role)) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    return Ok(found);
  }

  /// Applies (sign = 1) or undoes (sign = -1) a transaction's balance
  /// effect, read-modify-write on the group's snapshot set.
  Future<Result<Unit>> _applyBalance(Transaction tx, int sign) async {
    late String peer;
    Balance Function(Balance b)? adjust;
    switch (tx.type) {
      case TransactionType.contribution:
        peer = tx.fromPeerId;
        adjust = (Balance b) =>
            b.copyWith(totalContributed: b.totalContributed + tx.amount * sign);
      case TransactionType.loan:
        peer = tx.toPeerId;
        adjust = (Balance b) => b.copyWith(
              totalLoaned: b.totalLoaned + tx.amount * sign,
              outstandingLoan: b.outstandingLoan + tx.amount * sign,
            );
      case TransactionType.repayment:
        peer = tx.fromPeerId;
        adjust = (Balance b) => b.copyWith(
              totalRepaid: b.totalRepaid + tx.amount * sign,
              outstandingLoan: b.outstandingLoan - tx.amount * sign,
            );
      case TransactionType.penalty:
      case TransactionType.fee:
        peer = tx.fromPeerId;
        adjust = (Balance b) =>
            b.copyWith(totalPenalties: b.totalPenalties + tx.amount * sign);
      case TransactionType.withdrawal:
        peer = tx.toPeerId;
        adjust = (Balance b) =>
            b.copyWith(totalWithdrawn: b.totalWithdrawn + tx.amount * sign);
      case TransactionType.reversal:
        return const Ok(unit);
    }
    final Result<List<Balance>> all = await balances.listByGroup(tx.groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    final List<Balance> next = [];
    var matched = false;
    for (final Balance b in all.value) {
      if (b.peerId == peer) {
        next.add(adjust(b));
        matched = true;
      } else {
        next.add(b);
      }
    }
    if (!matched) {
      final Balance fresh = Balance(
        peerId: peer,
        groupId: tx.groupId,
        lastUpdated: clock().toUtc(),
      );
      next.add(adjust(fresh));
    }
    final Result<Unit> saved = await balances.saveAll(tx.groupId, next);
    if (saved.isErr) {
      return saved;
    }
    // Net follows the parts: contributions in, withdrawals out, loans and
    // repayments move through outstanding, penalties add up.
    return _refreshNet(tx.groupId);
  }

  /// Recomputes every net balance from its parts after an effect lands.
  /// Matches the legacy ledger penny for penny: contributions and
  /// repayments raise it; withdrawals, penalties and loans lower it.
  Future<Result<Unit>> _refreshNet(String groupId) async {
    final Result<List<Balance>> all = await balances.listByGroup(groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    final List<Balance> next = [
      for (final Balance b in all.value)
        b.copyWith(
          netBalance: b.totalContributed -
              b.totalWithdrawn -
              b.totalPenalties -
              b.totalLoaned +
              b.totalRepaid,
          lastUpdated: clock().toUtc(),
        ),
    ];
    return balances.saveAll(groupId, next);
  }
}
