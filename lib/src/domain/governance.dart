import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';

/// What happens to a removed member's seat.
enum RemovalAction {
  /// Kept out for now; history stays, may return.
  suspend,

  /// Out for good.
  remove,

  /// Debts settled first, then out.
  settleAndRemove,
}

/// An admin's signed record of taking someone out of the group.
final class MemberRemoval {
  /// This record's id.
  final String id;

  /// The group they leave.
  final String groupId;

  /// Who leaves.
  final String removedPeerId;

  /// The admin who decided.
  final String removedByPeerId;

  /// Human reason, shown in history.
  final String reason;

  /// True when they still owed the group.
  final bool hasOutstandingLoan;

  /// How much was outstanding, in group currency.
  final double outstandingAmount;

  /// How the seat was handled.
  final RemovalAction action;

  /// When it happened.
  final DateTime removedAt;

  /// The admin's signature.
  final Uint8List adminSignature;

  /// The owner let this person back in; the ban no longer applies. Never
  /// reverts once set — like an invite's `used`.
  final bool lifted;

  /// Creates a removal record.
  const MemberRemoval({
    required this.id,
    required this.groupId,
    required this.removedPeerId,
    required this.removedByPeerId,
    required this.reason,
    this.hasOutstandingLoan = false,
    this.outstandingAmount = 0,
    required this.action,
    required this.removedAt,
    required this.adminSignature,
    this.lifted = false,
  });

  /// Structural checks: identifiers and a reason present, sane money.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('removalIdEmpty'));
    }
    if (reason.trim().isEmpty) {
      return const Err(ValidationFailure('removalReasonEmpty'));
    }
    if (outstandingAmount < 0) {
      return const Err(ValidationFailure('removalAmountNegative'));
    }
    return const Ok(unit);
  }

  /// Copies this record, replacing the given fields.
  MemberRemoval copyWith({bool? lifted}) => MemberRemoval(
        id: id,
        groupId: groupId,
        removedPeerId: removedPeerId,
        removedByPeerId: removedByPeerId,
        reason: reason,
        hasOutstandingLoan: hasOutstandingLoan,
        outstandingAmount: outstandingAmount,
        action: action,
        removedAt: removedAt,
        adminSignature: adminSignature,
        lifted: lifted ?? this.lifted,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberRemoval &&
          id == other.id &&
          groupId == other.groupId &&
          removedPeerId == other.removedPeerId &&
          removedByPeerId == other.removedByPeerId &&
          reason == other.reason &&
          hasOutstandingLoan == other.hasOutstandingLoan &&
          outstandingAmount == other.outstandingAmount &&
          action == other.action &&
          removedAt == other.removedAt &&
          bytesEqual(adminSignature, other.adminSignature) &&
          lifted == other.lifted;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        removedPeerId,
        removedByPeerId,
        reason,
        hasOutstandingLoan,
        outstandingAmount,
        action,
        removedAt,
        bytesHash(adminSignature),
        lifted,
      );
}

/// The old and new owner both sign; afterwards the old owner is an admin and
/// the new owner is the owner.
final class OwnershipTransfer {
  /// This transfer's id.
  final String id;

  /// The group changing hands.
  final String groupId;

  /// The outgoing owner.
  final String fromPeerId;

  /// The incoming owner (must already be an admin).
  final String toPeerId;

  /// When it happened.
  final DateTime transferredAt;

  /// Outgoing owner's signature.
  final Uint8List oldOwnerSignature;

  /// Incoming owner's signature.
  final Uint8List newOwnerSignature;

  /// Creates a transfer record.
  const OwnershipTransfer({
    required this.id,
    required this.groupId,
    required this.fromPeerId,
    required this.toPeerId,
    required this.transferredAt,
    required this.oldOwnerSignature,
    required this.newOwnerSignature,
  });

  /// Structural checks: identifiers present, and the two sides differ.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('transferIdEmpty'));
    }
    if (fromPeerId.isEmpty || toPeerId.isEmpty) {
      return const Err(ValidationFailure('transferPeerEmpty'));
    }
    if (fromPeerId == toPeerId) {
      return const Err(ValidationFailure('transferSelfTransfer'));
    }
    return const Ok(unit);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OwnershipTransfer &&
          id == other.id &&
          groupId == other.groupId &&
          fromPeerId == other.fromPeerId &&
          toPeerId == other.toPeerId &&
          transferredAt == other.transferredAt &&
          bytesEqual(oldOwnerSignature, other.oldOwnerSignature) &&
          bytesEqual(newOwnerSignature, other.newOwnerSignature);

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        fromPeerId,
        toPeerId,
        transferredAt,
        bytesHash(oldOwnerSignature),
        bytesHash(newOwnerSignature),
      );
}

/// Where winding a group up stands.
enum DissolutionStatus {
  /// Announced; stopping new business.
  initiating,

  /// Waiting on every loan to settle.
  settlingLoans,

  /// Paying each member their share.
  distributingFunds,

  /// Done; the group is a read-only archive.
  completed,
}

/// The owner-initiated winding up of a group.
final class GroupDissolution {
  /// This dissolution's id.
  final String id;

  /// The group winding up.
  final String groupId;

  /// The owner who started it.
  final String initiatedByPeerId;

  /// When it started.
  final DateTime initiatedAt;

  /// Current stage.
  final DissolutionStatus status;

  /// True once no loan is outstanding.
  final bool allLoansSettled;

  /// True once every share is paid out.
  final bool fundsDistributed;

  /// When it finished, once finished.
  final DateTime? completedAt;

  /// Creates a dissolution record.
  const GroupDissolution({
    required this.id,
    required this.groupId,
    required this.initiatedByPeerId,
    required this.initiatedAt,
    this.status = DissolutionStatus.initiating,
    this.allLoansSettled = false,
    this.fundsDistributed = false,
    this.completedAt,
  });

  /// Structural checks: identifiers present.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('dissolutionIdEmpty'));
    }
    if (groupId.isEmpty) {
      return const Err(ValidationFailure('dissolutionGroupEmpty'));
    }
    return const Ok(unit);
  }

  /// Copies this record, replacing the given fields.
  GroupDissolution copyWith({
    DissolutionStatus? status,
    bool? allLoansSettled,
    bool? fundsDistributed,
    DateTime? completedAt,
  }) =>
      GroupDissolution(
        id: id,
        groupId: groupId,
        initiatedByPeerId: initiatedByPeerId,
        initiatedAt: initiatedAt,
        status: status ?? this.status,
        allLoansSettled: allLoansSettled ?? this.allLoansSettled,
        fundsDistributed: fundsDistributed ?? this.fundsDistributed,
        completedAt: completedAt ?? this.completedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupDissolution &&
          id == other.id &&
          groupId == other.groupId &&
          initiatedByPeerId == other.initiatedByPeerId &&
          initiatedAt == other.initiatedAt &&
          status == other.status &&
          allLoansSettled == other.allLoansSettled &&
          fundsDistributed == other.fundsDistributed &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        initiatedByPeerId,
        initiatedAt,
        status,
        allLoansSettled,
        fundsDistributed,
        completedAt,
      );
}
