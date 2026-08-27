import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/models/loan.dart';
import 'package:vbank/models/loan_progress.dart';
import 'package:vbank/models/transaction.dart';

LoanRequest loan(String id, LoanStatus status, {double approved = 100, double rate = 0.1}) => LoanRequest(
      id: id,
      groupId: 'g',
      borrowerPeerId: 'bob',
      requestedAmount: approved,
      approvedAmount: status == LoanStatus.pending || status == LoanStatus.rejected ? 0 : approved,
      interestRate: rate,
      termWeeks: 4,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      borrowerSignature: Uint8List(0),
    );

Transaction tx(TransactionType type, double amount, {String? loanId, TransactionStatus status = TransactionStatus.confirmed, int day = 1}) =>
    Transaction(
      id: '${type.name}-$amount-$day',
      groupId: 'g',
      fromPeerId: 'bob',
      toPeerId: 'group',
      type: type,
      amount: amount,
      currency: 'ZMW',
      timestamp: DateTime.utc(2026, 1, day),
      sequenceNumber: day,
      senderSignature: Uint8List(0),
      status: status,
      loanId: loanId,
    );

void main() {
  test('loan progress sums confirmed repayments against principal + interest', () {
    final l = loan('L', LoanStatus.repaying);
    final progress = LoanProgress.forGroup([l], [
      tx(TransactionType.repayment, 30, loanId: 'L', day: 3),
      tx(TransactionType.repayment, 25, loanId: 'L', day: 2),
      tx(TransactionType.repayment, 99, loanId: 'L', status: TransactionStatus.reversed, day: 4),
      tx(TransactionType.repayment, 10, loanId: 'OTHER', day: 5),
      tx(TransactionType.contribution, 50, day: 1),
    ])['L']!;
    expect(progress.borrowed, 100);
    expect(progress.totalDue, closeTo(110, 1e-9));
    expect(progress.repaid, 55);
    expect(progress.remaining, closeTo(55, 1e-9));
    expect(progress.fraction, closeTo(0.5, 1e-9));
    expect(progress.principalOutstanding, 45, reason: 'repayments count against principal first');
    expect(progress.repayments.map((t) => t.amount), [25, 30], reason: 'oldest first');
  });

  test('pending loans owe nothing yet; completed loans have no principal out', () {
    final pending = LoanProgress(loan: loan('P', LoanStatus.pending), repayments: const []);
    expect(pending.totalDue, 0);
    expect(pending.principalOutstanding, 0);
    final done = LoanProgress(loan: loan('D', LoanStatus.completed), repayments: [tx(TransactionType.repayment, 110, loanId: 'D')]);
    expect(done.principalOutstanding, 0);
    expect(done.fraction, closeTo(1, 1e-9));
  });

  test('group fund splits cash available to lend from principal lent out', () {
    final active = loan('A', LoanStatus.repaying, approved: 100);
    final approvedOnly = loan('B', LoanStatus.approved, approved: 40);
    final fund = GroupFund.compute([
      tx(TransactionType.contribution, 200, day: 1),
      tx(TransactionType.contribution, 100, day: 2),
      tx(TransactionType.loan, 100, loanId: 'A', day: 3),
      tx(TransactionType.repayment, 30, loanId: 'A', day: 4),
      tx(TransactionType.withdrawal, 20, day: 5),
      tx(TransactionType.penalty, 5, day: 6),
      tx(TransactionType.contribution, 999, status: TransactionStatus.reversed, day: 7),
    ], [active, approvedOnly]);
    expect(fund.available, closeTo(215, 1e-9)); // 300 - 100 + 30 - 20 + 5
    expect(fund.lentOut, closeTo(70 + 40, 1e-9)); // A: 100 - 30 outstanding, B: committed 40
    expect(fund.total, closeTo(325, 1e-9));
    expect(fund.interestExpected, closeTo(10, 1e-9)); // A: 110 due - 30 repaid - 70 principal
  });
}
