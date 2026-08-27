import 'dart:math' as math;

import 'loan.dart';
import 'transaction.dart';

/// A loan together with the repayments recorded against it.
///
/// Everywhere the app shows a loan it also shows how much of the borrowed
/// money has come back, so this is computed once from the group's transactions
/// (the repayment transactions carry `loanId`) rather than from the schedule,
/// which only tracks instalments.
class LoanProgress {
  final LoanRequest loan;

  /// Confirmed repayment transactions for this loan, oldest first.
  final List<Transaction> repayments;

  const LoanProgress({required this.loan, required this.repayments});

  /// Money handed to the borrower (the approved amount once approved).
  double get borrowed => loan.approvedAmount > 0 ? loan.approvedAmount : loan.requestedAmount;

  /// Principal plus interest owed once approved; 0 while pending/rejected.
  double get totalDue => loan.approvedAmount > 0 ? loan.totalWithInterest : 0;

  double get repaid => repayments.fold(0, (s, t) => s + t.amount);

  double get remaining => math.max(0, totalDue - repaid);

  /// 0..1 share of the total due that has been repaid.
  double get fraction => totalDue <= 0 ? 0 : (repaid / totalDue).clamp(0, 1).toDouble();

  /// Principal still out with the borrower: repayments count against the
  /// principal first, so this is what the group could not lend to someone else.
  double get principalOutstanding =>
      loan.isActive ? math.max(0, borrowed - repaid) : (loan.status == LoanStatus.approved ? borrowed : 0);

  static Map<String, LoanProgress> forGroup(Iterable<LoanRequest> loans, Iterable<Transaction> transactions) {
    final byLoan = <String, List<Transaction>>{};
    for (final t in transactions) {
      if (t.type != TransactionType.repayment || t.status != TransactionStatus.confirmed || t.loanId == null) continue;
      byLoan.putIfAbsent(t.loanId!, () => []).add(t);
    }
    return {
      for (final l in loans)
        l.id: LoanProgress(
          loan: l,
          repayments: [...?byLoan[l.id]]..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
        ),
    };
  }
}

/// Where the group's money is: in the box (available to lend) or out on loan.
class GroupFund {
  /// Cash the group holds and can lend: contributions, repayments, penalties
  /// and fees in; loans and withdrawals out.
  final double available;

  /// Principal currently out with borrowers (approved-but-undisbursed loans
  /// are committed and counted here too).
  final double lentOut;

  /// Interest still expected on active loans — not money yet.
  final double interestExpected;

  const GroupFund({required this.available, required this.lentOut, required this.interestExpected});

  /// Everything the group owns: cash plus what borrowers still owe in principal.
  double get total => available + lentOut;

  static GroupFund compute(Iterable<Transaction> transactions, Iterable<LoanRequest> loans) {
    var cash = 0.0;
    for (final t in transactions) {
      if (t.status != TransactionStatus.confirmed) continue;
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
    final progress = LoanProgress.forGroup(loans, transactions).values;
    var lent = 0.0;
    var interest = 0.0;
    for (final p in progress) {
      lent += p.principalOutstanding;
      if (p.loan.isActive) interest += math.max(0, p.remaining - p.principalOutstanding);
    }
    return GroupFund(available: cash, lentOut: lent, interestExpected: interest);
  }
}
