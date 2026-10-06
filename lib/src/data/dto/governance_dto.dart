import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/governance.dart';
import 'dto.dart';

/// Row mapping for `removals`.
abstract final class RemovalDto {
  /// Serializes [removal] to a `removals` row.
  static Map<String, Object?> toRow(MemberRemoval removal) => {
        'id': removal.id,
        'group_id': removal.groupId,
        'removed_peer_id': removal.removedPeerId,
        'removed_by_peer_id': removal.removedByPeerId,
        'reason': removal.reason,
        'has_outstanding_loan': Dto.flagValue(removal.hasOutstandingLoan),
        'outstanding_amount': removal.outstandingAmount,
        'action': removal.action.name,
        'removed_at': Dto.instantValue(removal.removedAt),
        'admin_signature': removal.adminSignature,
        'lifted': Dto.flagValue(removal.lifted),
      };

  /// Parses a `removals` row.
  static Result<MemberRemoval> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        MemberRemoval(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          removedPeerId: Dto.text(row, 'removed_peer_id'),
          removedByPeerId: Dto.text(row, 'removed_by_peer_id'),
          reason: Dto.text(row, 'reason'),
          hasOutstandingLoan: Dto.flag(row, 'has_outstanding_loan'),
          outstandingAmount: Dto.real(row, 'outstanding_amount'),
          action: Dto.enumeration(row, 'action', RemovalAction.values),
          removedAt: Dto.instant(row, 'removed_at'),
          adminSignature: Dto.bytes(row, 'admin_signature'),
          lifted: Dto.flag(row, 'lifted'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `transfers`.
abstract final class TransferDto {
  /// Serializes [transfer] to a `transfers` row.
  static Map<String, Object?> toRow(OwnershipTransfer transfer) => {
        'id': transfer.id,
        'group_id': transfer.groupId,
        'from_peer_id': transfer.fromPeerId,
        'to_peer_id': transfer.toPeerId,
        'transferred_at': Dto.instantValue(transfer.transferredAt),
        'old_owner_signature': transfer.oldOwnerSignature,
        'new_owner_signature': transfer.newOwnerSignature,
      };

  /// Parses a `transfers` row.
  static Result<OwnershipTransfer> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        OwnershipTransfer(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          fromPeerId: Dto.text(row, 'from_peer_id'),
          toPeerId: Dto.text(row, 'to_peer_id'),
          transferredAt: Dto.instant(row, 'transferred_at'),
          oldOwnerSignature: Dto.bytes(row, 'old_owner_signature'),
          newOwnerSignature: Dto.bytes(row, 'new_owner_signature'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `dissolutions`.
abstract final class DissolutionDto {
  /// Serializes [dissolution] to a `dissolutions` row.
  static Map<String, Object?> toRow(GroupDissolution dissolution) => {
        'id': dissolution.id,
        'group_id': dissolution.groupId,
        'initiated_by_peer_id': dissolution.initiatedByPeerId,
        'initiated_at': Dto.instantValue(dissolution.initiatedAt),
        'status': dissolution.status.name,
        'all_loans_settled': Dto.flagValue(dissolution.allLoansSettled),
        'funds_distributed': Dto.flagValue(dissolution.fundsDistributed),
        'completed_at': dissolution.completedAt == null
            ? null
            : Dto.instantValue(dissolution.completedAt!),
      };

  /// Parses a `dissolutions` row.
  static Result<GroupDissolution> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        GroupDissolution(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          initiatedByPeerId: Dto.text(row, 'initiated_by_peer_id'),
          initiatedAt: Dto.instant(row, 'initiated_at'),
          status: Dto.enumeration(row, 'status', DissolutionStatus.values),
          allLoansSettled: Dto.flag(row, 'all_loans_settled'),
          fundsDistributed: Dto.flag(row, 'funds_distributed'),
          completedAt: Dto.instantOrNull(row, 'completed_at'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
