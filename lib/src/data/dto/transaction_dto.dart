import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/transactions.dart';
import 'dto.dart';

/// Row mapping for `transactions` and `reversals`.
abstract final class TransactionDto {
  /// Serializes [tx] to a `transactions` row.
  static Map<String, Object?> toRow(Transaction tx) => {
        'id': tx.id,
        'group_id': tx.groupId,
        'from_peer_id': tx.fromPeerId,
        'to_peer_id': tx.toPeerId,
        'type': tx.type.name,
        'amount': tx.amount,
        'currency': tx.currency,
        'note': tx.note,
        'timestamp': Dto.instantValue(tx.timestamp),
        'sequence_number': tx.sequenceNumber,
        'sender_signature': tx.senderSignature,
        'author_peer_id': tx.authorPeerId,
        'loan_id': tx.loanId,
        'status': tx.status.name,
      };

  /// Parses a `transactions` row.
  static Result<Transaction> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        Transaction(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          fromPeerId: Dto.text(row, 'from_peer_id'),
          toPeerId: Dto.text(row, 'to_peer_id'),
          type: Dto.enumeration(row, 'type', TransactionType.values),
          amount: Dto.real(row, 'amount'),
          currency: Dto.text(row, 'currency'),
          note: Dto.textOrNull(row, 'note'),
          timestamp: Dto.instant(row, 'timestamp'),
          sequenceNumber: Dto.integer(row, 'sequence_number'),
          senderSignature: Dto.bytes(row, 'sender_signature'),
          authorPeerId: Dto.text(row, 'author_peer_id'),
          loanId: Dto.textOrNull(row, 'loan_id'),
          status: Dto.enumeration(row, 'status', TransactionStatus.values),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `reversals`.
abstract final class ReversalDto {
  /// Serializes [reversal] to a `reversals` row.
  static Map<String, Object?> toRow(TransactionReversal reversal) => {
        'id': reversal.id,
        'original_transaction_id': reversal.originalTransactionId,
        'group_id': reversal.groupId,
        'requested_by_peer_id': reversal.requestedByPeerId,
        'approved_by_peer_id': reversal.approvedByPeerId,
        'reason': reversal.reason,
        'status': reversal.status.name,
        'requested_at': Dto.instantValue(reversal.requestedAt),
        'resolved_at': reversal.resolvedAt == null
            ? null
            : Dto.instantValue(reversal.resolvedAt!),
        'requester_signature': reversal.requesterSignature,
        'approver_signature': reversal.approverSignature,
      };

  /// Parses a `reversals` row.
  static Result<TransactionReversal> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        TransactionReversal(
          id: Dto.text(row, 'id'),
          originalTransactionId: Dto.text(row, 'original_transaction_id'),
          groupId: Dto.text(row, 'group_id'),
          requestedByPeerId: Dto.text(row, 'requested_by_peer_id'),
          approvedByPeerId: Dto.textOrNull(row, 'approved_by_peer_id'),
          reason: Dto.text(row, 'reason'),
          status: Dto.enumeration(row, 'status', ReversalStatus.values),
          requestedAt: Dto.instant(row, 'requested_at'),
          resolvedAt: Dto.instantOrNull(row, 'resolved_at'),
          requesterSignature: Dto.bytes(row, 'requester_signature'),
          approverSignature: Dto.bytesOrNull(row, 'approver_signature'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
