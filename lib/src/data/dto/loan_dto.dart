import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/loans.dart';
import 'dto.dart';

/// Row mapping for `loans` and `schedules`.
abstract final class LoanDto {
  /// Serializes [loan] to a `loans` row.
  static Map<String, Object?> toRow(LoanRequest loan) => {
        'id': loan.id,
        'group_id': loan.groupId,
        'borrower_peer_id': loan.borrowerPeerId,
        'requested_amount': loan.requestedAmount,
        'approved_amount': loan.approvedAmount,
        'interest_rate': loan.interestRate,
        'term_weeks': loan.termWeeks,
        'reason': loan.reason,
        'status': loan.status.name,
        'requested_at': Dto.instantValue(loan.requestedAt),
        'approved_at': loan.approvedAt == null
            ? null
            : Dto.instantValue(loan.approvedAt!),
        'approved_by_peer_id': loan.approvedByPeerId,
        'disbursed_at': loan.disbursedAt == null
            ? null
            : Dto.instantValue(loan.disbursedAt!),
        'completed_at': loan.completedAt == null
            ? null
            : Dto.instantValue(loan.completedAt!),
        'defaulted_at': loan.defaultedAt == null
            ? null
            : Dto.instantValue(loan.defaultedAt!),
        'borrower_signature': loan.borrowerSignature,
        'approver_signature': loan.approverSignature,
      };

  /// Parses a `loans` row.
  static Result<LoanRequest> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        LoanRequest(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          borrowerPeerId: Dto.text(row, 'borrower_peer_id'),
          requestedAmount: Dto.real(row, 'requested_amount'),
          approvedAmount: Dto.real(row, 'approved_amount'),
          interestRate: Dto.real(row, 'interest_rate'),
          termWeeks: Dto.integer(row, 'term_weeks'),
          reason: Dto.textOrNull(row, 'reason'),
          status: Dto.enumeration(row, 'status', LoanStatus.values),
          requestedAt: Dto.instant(row, 'requested_at'),
          approvedAt: Dto.instantOrNull(row, 'approved_at'),
          approvedByPeerId: Dto.textOrNull(row, 'approved_by_peer_id'),
          disbursedAt: Dto.instantOrNull(row, 'disbursed_at'),
          completedAt: Dto.instantOrNull(row, 'completed_at'),
          defaultedAt: Dto.instantOrNull(row, 'defaulted_at'),
          borrowerSignature: Dto.bytes(row, 'borrower_signature'),
          approverSignature: Dto.bytesOrNull(row, 'approver_signature'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `schedules`.
abstract final class ScheduleDto {
  /// Serializes [schedule] to a `schedules` row.
  static Map<String, Object?> toRow(RepaymentSchedule schedule) => {
        'id': schedule.id,
        'loan_id': schedule.loanId,
        'installment_number': schedule.installmentNumber,
        'expected_amount': schedule.expectedAmount,
        'due_date': Dto.instantValue(schedule.dueDate),
        'paid_amount': schedule.paidAmount,
        'paid_at': schedule.paidAt == null
            ? null
            : Dto.instantValue(schedule.paidAt!),
        'is_overdue': Dto.flagValue(schedule.isOverdue),
        'penalty': schedule.penalty,
        'status': schedule.status.name,
      };

  /// Parses a `schedules` row.
  static Result<RepaymentSchedule> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        RepaymentSchedule(
          id: Dto.text(row, 'id'),
          loanId: Dto.text(row, 'loan_id'),
          installmentNumber: Dto.integer(row, 'installment_number'),
          expectedAmount: Dto.real(row, 'expected_amount'),
          dueDate: Dto.instant(row, 'due_date'),
          paidAmount: Dto.real(row, 'paid_amount'),
          paidAt: Dto.instantOrNull(row, 'paid_at'),
          isOverdue: Dto.flag(row, 'is_overdue'),
          penalty: Dto.real(row, 'penalty'),
          status: Dto.enumeration(row, 'status', RepaymentStatus.values),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
