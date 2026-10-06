import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';

/// What kind of movement a transaction records.
enum TransactionType {
  /// Member pays into the group fund.
  contribution,

  /// Group lends to a member.
  loan,

  /// Member pays a loan back.
  repayment,

  /// Member takes their own money out.
  withdrawal,

  /// Group charge.
  fee,

  /// Late-payment charge.
  penalty,

  /// Correction of an earlier transaction; both stay in history.
  reversal,
}

/// A transaction is `confirmed` for life unless a reversal voids it.
enum TransactionStatus {
  /// In force.
  confirmed,

  /// Voided by an approved reversal.
  reversed,
}

/// One signed movement of money. Immutable once signed: corrections are new
/// `reversal` transactions, never edits.
final class Transaction {
  /// UUID v7.
  final String id;

  /// The group this belongs to.
  final String groupId;

  /// Who the money conceptually comes from (`'group'` for payouts).
  final String fromPeerId;

  /// Who it goes to (`'group'` for contributions).
  final String toPeerId;

  /// What kind of movement this is.
  final TransactionType type;

  /// Positive amount, in [currency].
  final double amount;

  /// ISO code, e.g. `'ZMW'`.
  final String currency;

  /// Optional memo.
  final String? note;

  /// When it was recorded.
  final DateTime timestamp;

  /// Order within the group; higher wins conflicts.
  final int sequenceNumber;

  /// The author's Ed25519 signature over the payload.
  final Uint8List senderSignature;

  /// The owner/admin who recorded and signed this. For a contribution this
  /// is normally *not* [fromPeerId] — members are read-only.
  final String authorPeerId;

  /// Repayments and disbursements reference their loan.
  final String? loanId;

  /// Lifecycle state.
  final TransactionStatus status;

  /// Creates a transaction. [authorPeerId] defaults to [fromPeerId].
  const Transaction({
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
    String? authorPeerId,
    this.loanId,
    this.status = TransactionStatus.confirmed,
  }) : authorPeerId = authorPeerId ?? fromPeerId;

  /// True when this records a contribution.
  bool get isContribution => type == TransactionType.contribution;

  /// True when this records a loan payout.
  bool get isLoan => type == TransactionType.loan;

  /// True when this records a loan repayment.
  bool get isRepayment => type == TransactionType.repayment;

  /// True when this records a withdrawal.
  bool get isWithdrawal => type == TransactionType.withdrawal;

  /// True when this records a penalty.
  bool get isPenalty => type == TransactionType.penalty;

  /// True when this corrects an earlier transaction.
  bool get isReversal => type == TransactionType.reversal;

  /// Structural checks: identifiers present, amount positive, sequence sane.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('transactionIdEmpty'));
    }
    if (groupId.isEmpty) {
      return const Err(ValidationFailure('transactionGroupEmpty'));
    }
    if (amount <= 0) {
      return const Err(ValidationFailure('transactionAmountNotPositive'));
    }
    if (sequenceNumber < 0) {
      return const Err(ValidationFailure('transactionSequenceNegative'));
    }
    return const Ok(unit);
  }

  /// Copies this transaction, replacing the given fields.
  Transaction copyWith({TransactionStatus? status, String? note}) =>
      Transaction(
        id: id,
        groupId: groupId,
        fromPeerId: fromPeerId,
        toPeerId: toPeerId,
        type: type,
        amount: amount,
        currency: currency,
        note: note ?? this.note,
        timestamp: timestamp,
        sequenceNumber: sequenceNumber,
        senderSignature: senderSignature,
        authorPeerId: authorPeerId,
        loanId: loanId,
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transaction &&
          id == other.id &&
          groupId == other.groupId &&
          fromPeerId == other.fromPeerId &&
          toPeerId == other.toPeerId &&
          type == other.type &&
          amount == other.amount &&
          currency == other.currency &&
          note == other.note &&
          timestamp == other.timestamp &&
          sequenceNumber == other.sequenceNumber &&
          bytesEqual(senderSignature, other.senderSignature) &&
          authorPeerId == other.authorPeerId &&
          loanId == other.loanId &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        fromPeerId,
        toPeerId,
        type,
        amount,
        currency,
        note,
        timestamp,
        sequenceNumber,
        bytesHash(senderSignature),
        authorPeerId,
        loanId,
        status,
      );
}

/// Where a correction request stands.
enum ReversalStatus {
  /// Awaiting an admin's decision.
  pending,

  /// Accepted; the original is voided.
  approved,

  /// Declined; the original stands.
  rejected,
}

/// A request to void a transaction. The original stays visible; an approved
/// reversal flips its status to `reversed` and posts the offsetting movement.
final class TransactionReversal {
  /// This request's id.
  final String id;

  /// The transaction being voided.
  final String originalTransactionId;

  /// The group both belong to.
  final String groupId;

  /// Who asked for the correction.
  final String requestedByPeerId;

  /// The admin who decided, once decided.
  final String? approvedByPeerId;

  /// Human reason, shown in history.
  final String reason;

  /// Current state.
  final ReversalStatus status;

  /// When it was requested.
  final DateTime requestedAt;

  /// When it was decided, once decided.
  final DateTime? resolvedAt;

  /// Requester's signature.
  final Uint8List requesterSignature;

  /// Decider's signature, once decided.
  final Uint8List? approverSignature;

  /// Creates a reversal request.
  const TransactionReversal({
    required this.id,
    required this.originalTransactionId,
    required this.groupId,
    required this.requestedByPeerId,
    this.approvedByPeerId,
    required this.reason,
    this.status = ReversalStatus.pending,
    required this.requestedAt,
    this.resolvedAt,
    required this.requesterSignature,
    this.approverSignature,
  });

  /// True while awaiting a decision.
  bool get isPending => status == ReversalStatus.pending;

  /// True once approved.
  bool get isApproved => status == ReversalStatus.approved;

  /// True once rejected.
  bool get isRejected => status == ReversalStatus.rejected;

  /// Structural checks: identifiers and a reason present.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('reversalIdEmpty'));
    }
    if (originalTransactionId.isEmpty) {
      return const Err(ValidationFailure('reversalTargetEmpty'));
    }
    if (reason.trim().isEmpty) {
      return const Err(ValidationFailure('reversalReasonEmpty'));
    }
    return const Ok(unit);
  }

  /// Copies this request, replacing the given fields.
  TransactionReversal copyWith({
    ReversalStatus? status,
    String? approvedByPeerId,
    DateTime? resolvedAt,
    Uint8List? approverSignature,
  }) =>
      TransactionReversal(
        id: id,
        originalTransactionId: originalTransactionId,
        groupId: groupId,
        requestedByPeerId: requestedByPeerId,
        approvedByPeerId: approvedByPeerId ?? this.approvedByPeerId,
        reason: reason,
        status: status ?? this.status,
        requestedAt: requestedAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        requesterSignature: requesterSignature,
        approverSignature: approverSignature ?? this.approverSignature,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionReversal &&
          id == other.id &&
          originalTransactionId == other.originalTransactionId &&
          groupId == other.groupId &&
          requestedByPeerId == other.requestedByPeerId &&
          approvedByPeerId == other.approvedByPeerId &&
          reason == other.reason &&
          status == other.status &&
          requestedAt == other.requestedAt &&
          resolvedAt == other.resolvedAt &&
          bytesEqual(requesterSignature, other.requesterSignature) &&
          (approverSignature == null || other.approverSignature == null
              ? approverSignature == other.approverSignature
              : bytesEqual(approverSignature!, other.approverSignature!));

  @override
  int get hashCode => Object.hash(
        id,
        originalTransactionId,
        groupId,
        requestedByPeerId,
        approvedByPeerId,
        reason,
        status,
        requestedAt,
        resolvedAt,
        bytesHash(requesterSignature),
        approverSignature == null ? null : bytesHash(approverSignature!),
      );
}
