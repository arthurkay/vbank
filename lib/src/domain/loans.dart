import 'dart:math' as math;
import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';
import 'transactions.dart';

/// Where a loan stands: requested → approved/rejected → disbursed → repaying
/// → completed, or defaulted past the grace period.
enum LoanStatus {
  /// Requested, awaiting approval.
  pending,

  /// Admin approved an amount.
  approved,

  /// Admin declined.
  rejected,

  /// Cash handed to the borrower.
  disbursed,

  /// Repayments coming in.
  repaying,

  /// Fully repaid.
  completed,

  /// Overdue past the grace period.
  defaulted,
}

/// A member's loan from the group fund.
final class LoanRequest {
  /// This loan's id.
  final String id;

  /// The group lending.
  final String groupId;

  /// Who borrows.
  final String borrowerPeerId;

  /// What was asked for, in group currency.
  final double requestedAmount;

  /// What the admin granted; 0 until approved (may differ from requested).
  final double approvedAmount;

  /// Interest as a fraction, e.g. `0.10` = 10%.
  final double interestRate;

  /// Repayment window in weeks; drives the instalment schedule.
  final int termWeeks;

  /// Why the money is needed.
  final String? reason;

  /// Current state.
  final LoanStatus status;

  /// When it was requested.
  final DateTime requestedAt;

  /// When it was approved, once approved.
  final DateTime? approvedAt;

  /// The deciding admin, once decided.
  final String? approvedByPeerId;

  /// When cash changed hands, once disbursed.
  final DateTime? disbursedAt;

  /// When the last instalment landed, once completed.
  final DateTime? completedAt;

  /// When it was written off as defaulted, if ever.
  final DateTime? defaultedAt;

  /// Borrower's signature over the request.
  final Uint8List borrowerSignature;

  /// Approver's signature, once decided.
  final Uint8List? approverSignature;

  /// Creates a loan request.
  const LoanRequest({
    required this.id,
    required this.groupId,
    required this.borrowerPeerId,
    required this.requestedAmount,
    this.approvedAmount = 0,
    required this.interestRate,
    required this.termWeeks,
    this.reason,
    this.status = LoanStatus.pending,
    required this.requestedAt,
    this.approvedAt,
    this.approvedByPeerId,
    this.disbursedAt,
    this.completedAt,
    this.defaultedAt,
    required this.borrowerSignature,
    this.approverSignature,
  });

  /// Principal plus interest owed once approved; 0 before that.
  double get totalWithInterest => approvedAmount * (1 + interestRate);

  /// Weekly instalment once approved.
  double get weeklyPayment => totalWithInterest / termWeeks;

  /// True while awaiting approval.
  bool get isPending => status == LoanStatus.pending;

  /// True while cash is out with the borrower.
  bool get isActive =>
      status == LoanStatus.disbursed || status == LoanStatus.repaying;

  /// Structural checks: positive request, sane term and rate.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('loanIdEmpty'));
    }
    if (requestedAmount <= 0) {
      return const Err(ValidationFailure('loanAmountNotPositive'));
    }
    if (approvedAmount < 0) {
      return const Err(ValidationFailure('loanApprovedNegative'));
    }
    if (termWeeks <= 0) {
      return const Err(ValidationFailure('loanTermNotPositive'));
    }
    if (interestRate < 0 || interestRate > 1) {
      return const Err(ValidationFailure('loanRateRange'));
    }
    return const Ok(unit);
  }

  /// Copies this loan, replacing the given fields.
  LoanRequest copyWith({
    double? approvedAmount,
    LoanStatus? status,
    DateTime? approvedAt,
    String? approvedByPeerId,
    DateTime? disbursedAt,
    DateTime? completedAt,
    DateTime? defaultedAt,
    Uint8List? approverSignature,
  }) =>
      LoanRequest(
        id: id,
        groupId: groupId,
        borrowerPeerId: borrowerPeerId,
        requestedAmount: requestedAmount,
        approvedAmount: approvedAmount ?? this.approvedAmount,
        interestRate: interestRate,
        termWeeks: termWeeks,
        reason: reason,
        status: status ?? this.status,
        requestedAt: requestedAt,
        approvedAt: approvedAt ?? this.approvedAt,
        approvedByPeerId: approvedByPeerId ?? this.approvedByPeerId,
        disbursedAt: disbursedAt ?? this.disbursedAt,
        completedAt: completedAt ?? this.completedAt,
        defaultedAt: defaultedAt ?? this.defaultedAt,
        borrowerSignature: borrowerSignature,
        approverSignature: approverSignature ?? this.approverSignature,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoanRequest &&
          id == other.id &&
          groupId == other.groupId &&
          borrowerPeerId == other.borrowerPeerId &&
          requestedAmount == other.requestedAmount &&
          approvedAmount == other.approvedAmount &&
          interestRate == other.interestRate &&
          termWeeks == other.termWeeks &&
          reason == other.reason &&
          status == other.status &&
          requestedAt == other.requestedAt &&
          approvedAt == other.approvedAt &&
          approvedByPeerId == other.approvedByPeerId &&
          disbursedAt == other.disbursedAt &&
          completedAt == other.completedAt &&
          defaultedAt == other.defaultedAt &&
          bytesEqual(borrowerSignature, other.borrowerSignature) &&
          (approverSignature == null || other.approverSignature == null
              ? approverSignature == other.approverSignature
              : bytesEqual(approverSignature!, other.approverSignature!));

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        borrowerPeerId,
        requestedAmount,
        approvedAmount,
        interestRate,
        termWeeks,
        reason,
        status,
        requestedAt,
        approvedAt,
        approvedByPeerId,
        disbursedAt,
        completedAt,
        defaultedAt,
        bytesHash(borrowerSignature),
        approverSignature == null ? null : bytesHash(approverSignature!),
      );
}

/// Where one instalment stands. Unpaid instalments are simply due — display
/// text lives in presentation, not here.
enum RepaymentStatus {
  /// Due, awaiting payment.
  pending,

  /// Fully paid.
  paid,

  /// Past due and unpaid.
  overdue,

  /// Forgiven by an admin.
  waived,
}

/// One instalment of a loan's repayment schedule.
final class RepaymentSchedule {
  /// This instalment's id.
  final String id;

  /// The loan it repays.
  final String loanId;

  /// 1-based position in the schedule.
  final int installmentNumber;

  /// Due for this instalment, in group currency.
  final double expectedAmount;

  /// When it is due.
  final DateTime dueDate;

  /// Paid so far against this instalment.
  final double paidAmount;

  /// When it was fully paid, once paid.
  final DateTime? paidAt;

  /// True once past due and unpaid.
  final bool isOverdue;

  /// Accumulated late penalty.
  final double penalty;

  /// Current state.
  final RepaymentStatus status;

  /// Creates a schedule instalment.
  const RepaymentSchedule({
    required this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.expectedAmount,
    required this.dueDate,
    this.paidAmount = 0,
    this.paidAt,
    this.isOverdue = false,
    this.penalty = 0,
    this.status = RepaymentStatus.pending,
  });

  /// Still owed on this instalment.
  double get remainingAmount => expectedAmount - paidAmount;

  /// True once paid.
  bool get isPaid => status == RepaymentStatus.paid;

  /// True while awaiting payment.
  bool get isPending => status == RepaymentStatus.pending;

  /// Structural checks: sane numbering and non-negative money.
  Result<Unit> validate() {
    if (installmentNumber <= 0) {
      return const Err(ValidationFailure('installmentNotPositive'));
    }
    if (expectedAmount < 0) {
      return const Err(ValidationFailure('installmentExpectedNegative'));
    }
    if (paidAmount < 0) {
      return const Err(ValidationFailure('installmentPaidNegative'));
    }
    if (penalty < 0) {
      return const Err(ValidationFailure('installmentPenaltyNegative'));
    }
    return const Ok(unit);
  }

  /// Copies this instalment, replacing the given fields.
  RepaymentSchedule copyWith({
    double? paidAmount,
    DateTime? paidAt,
    bool? isOverdue,
    double? penalty,
    RepaymentStatus? status,
  }) =>
      RepaymentSchedule(
        id: id,
        loanId: loanId,
        installmentNumber: installmentNumber,
        expectedAmount: expectedAmount,
        dueDate: dueDate,
        paidAmount: paidAmount ?? this.paidAmount,
        paidAt: paidAt ?? this.paidAt,
        isOverdue: isOverdue ?? this.isOverdue,
        penalty: penalty ?? this.penalty,
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepaymentSchedule &&
          id == other.id &&
          loanId == other.loanId &&
          installmentNumber == other.installmentNumber &&
          expectedAmount == other.expectedAmount &&
          dueDate == other.dueDate &&
          paidAmount == other.paidAmount &&
          paidAt == other.paidAt &&
          isOverdue == other.isOverdue &&
          penalty == other.penalty &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
        id,
        loanId,
        installmentNumber,
        expectedAmount,
        dueDate,
        paidAmount,
        paidAt,
        isOverdue,
        penalty,
        status,
      );
}

/// A loan with the repayments recorded against it.
///
/// Screens show how much borrowed money has come back, so this is computed
/// once from the group's transactions (repayments carry `loanId`) rather
/// than from the schedule, which only tracks instalments.
final class LoanProgress {
  /// The loan in question.
  final LoanRequest loan;

  /// Confirmed repayments for it, oldest first.
  final List<Transaction> repayments;

  /// Creates a progress snapshot.
  const LoanProgress({required this.loan, required this.repayments});

  /// Money handed to the borrower (approved once approved).
  double get borrowed =>
      loan.approvedAmount > 0 ? loan.approvedAmount : loan.requestedAmount;

  /// Principal plus interest owed once approved; 0 while pending/rejected.
  double get totalDue => loan.approvedAmount > 0 ? loan.totalWithInterest : 0;

  /// Repaid across all instalments.
  double get repaid => repayments.fold(
        0,
        (double sum, Transaction t) => sum + t.amount,
      );

  /// Still owed, never negative.
  double get remaining => math.max(0, totalDue - repaid);

  /// Share of the total due repaid, 0–1.
  double get fraction =>
      totalDue <= 0 ? 0 : (repaid / totalDue).clamp(0, 1).toDouble();

  /// Principal still out: repayments count against principal first, so this
  /// is what the group could not lend to someone else.
  double get principalOutstanding => loan.isActive
      ? math.max(0, borrowed - repaid)
      : (loan.status == LoanStatus.approved ? borrowed : 0);

  /// Progress for every loan in [loans], keyed by loan id.
  static Map<String, LoanProgress> forGroup(
    Iterable<LoanRequest> loans,
    Iterable<Transaction> transactions,
  ) {
    final Map<String, List<Transaction>> byLoan = {};
    for (final Transaction t in transactions) {
      if (t.type != TransactionType.repayment ||
          t.status != TransactionStatus.confirmed ||
          t.loanId == null) {
        continue;
      }
      byLoan.putIfAbsent(t.loanId!, () => <Transaction>[]).add(t);
    }
    return {
      for (final LoanRequest l in loans)
        l.id: LoanProgress(
          loan: l,
          repayments: [...?byLoan[l.id]]
            ..sort(
              (Transaction a, Transaction b) =>
                  a.timestamp.compareTo(b.timestamp),
            ),
        ),
    };
  }
}

/// Where the group's money is: in the box or out on loan.
final class GroupFund {
  /// Cash held and lendable: contributions, repayments, penalties and fees
  /// in; loans and withdrawals out.
  final double available;

  /// Principal out with borrowers (approved-but-undisbursed loans are
  /// committed and counted here too).
  final double lentOut;

  /// Interest still expected on active loans — not money yet.
  final double interestExpected;

  /// Creates a fund snapshot.
  const GroupFund({
    required this.available,
    required this.lentOut,
    required this.interestExpected,
  });

  /// Everything the group owns: cash plus owed principal.
  double get total => available + lentOut;

  /// Computes the fund from confirmed [transactions] and [loans].
  factory GroupFund.compute(
    Iterable<Transaction> transactions,
    Iterable<LoanRequest> loans,
  ) {
    var cash = 0.0;
    for (final Transaction t in transactions) {
      if (t.status != TransactionStatus.confirmed) {
        continue;
      }
      switch (t.type) {
        case TransactionType.contribution:
        case TransactionType.repayment:
        case TransactionType.penalty:
        case TransactionType.fee:
          cash += t.amount;
        case TransactionType.loan:
        case TransactionType.withdrawal:
          cash -= t.amount;
        case TransactionType.reversal:
          break;
      }
    }
    final Iterable<LoanProgress> progress =
        LoanProgress.forGroup(loans, transactions).values;
    var lent = 0.0;
    var interest = 0.0;
    for (final LoanProgress p in progress) {
      lent += p.principalOutstanding;
      if (p.loan.isActive) {
        interest += math.max(0, p.remaining - p.principalOutstanding);
      }
    }
    return GroupFund(
      available: cash,
      lentOut: lent,
      interestExpected: interest,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupFund &&
          available == other.available &&
          lentOut == other.lentOut &&
          interestExpected == other.interestExpected;

  @override
  int get hashCode => Object.hash(available, lentOut, interestExpected);
}
