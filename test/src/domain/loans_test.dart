import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'fixtures.dart';

void main() {
  group('LoanRequest', () {
    test('interest math matches the legacy schedule', () {
      final LoanRequest loan = testLoan(
        'l',
        approvedAmount: 300,
        status: LoanStatus.disbursed,
      );

      expect(loan.totalWithInterest, closeTo(330, 1e-9));
      expect(loan.weeklyPayment, closeTo(82.5, 1e-9));
      expect(loan.isActive, isTrue);
      expect(loan.isPending, isFalse);
    });

    test('unapproved loans owe nothing yet', () {
      final LoanRequest loan = testLoan('l');

      expect(loan.totalWithInterest, 0);
      expect(loan.isActive, isFalse);
      expect(loan.isPending, isTrue);
    });

    test('rejects bad amounts, terms and rates', () {
      expect(
        testLoan('l', requestedAmount: 0).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testLoan('l').copyWith(status: LoanStatus.pending).validate().isOk,
        isTrue,
      );
      expect(
        LoanRequest(
          id: 'l',
          groupId: 'g',
          borrowerPeerId: 'a',
          requestedAmount: 100,
          interestRate: 0.1,
          termWeeks: 0,
          requestedAt: DateTime.utc(2026, 2, 1),
          borrowerSignature: testSignature(),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        LoanRequest(
          id: 'l',
          groupId: 'g',
          borrowerPeerId: 'a',
          requestedAmount: 100,
          interestRate: 2,
          termWeeks: 4,
          requestedAt: DateTime.utc(2026, 2, 1),
          borrowerSignature: testSignature(),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
    });
  });

  group('RepaymentSchedule', () {
    RepaymentSchedule testInstalment() => RepaymentSchedule(
          id: 's-1',
          loanId: 'l-1',
          installmentNumber: 1,
          expectedAmount: 82.5,
          dueDate: DateTime.utc(2026, 2, 8),
        );

    test('tracks what is left and validates', () {
      final RepaymentSchedule s = testInstalment();

      expect(s.remainingAmount, 82.5);
      expect(s.isPending, isTrue);
      expect(s.isPaid, isFalse);
      expect(s.validate().isOk, isTrue);
      expect(
        s.copyWith(status: RepaymentStatus.paid).isPaid,
        isTrue,
      );
    });

    test('rejects bad numbering and negative money', () {
      expect(
        RepaymentSchedule(
          id: 's',
          loanId: 'l',
          installmentNumber: 0,
          expectedAmount: 10,
          dueDate: DateTime.utc(2026, 2, 8),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testInstalment().copyWith(paidAmount: 10).remainingAmount,
        72.5,
      );
    });
  });

  group('LoanProgress and GroupFund', () {
    test('progress follows confirmed repayments for its loan', () {
      final LoanRequest loan = testLoan(
        'l-1',
        approvedAmount: 400,
        status: LoanStatus.repaying,
      );
      final Map<String, LoanProgress> all = LoanProgress.forGroup(
        [loan],
        [
          testTransaction(
            'r-1',
            type: TransactionType.repayment,
            amount: 110,
            loanId: 'l-1',
          ),
          testTransaction(
            'r-2',
            type: TransactionType.repayment,
            amount: 110,
            loanId: 'l-1',
          ),
          // Another loan's repayment must not leak in.
          testTransaction(
            'r-3',
            type: TransactionType.repayment,
            amount: 500,
            loanId: 'l-2',
          ),
          // Unconfirmed repayments do not count.
          testTransaction(
            'r-4',
            type: TransactionType.repayment,
            amount: 500,
            loanId: 'l-1',
          ).copyWith(status: TransactionStatus.reversed),
        ],
      );

      final LoanProgress p = all['l-1']!;
      expect(p.borrowed, 400);
      expect(p.totalDue, closeTo(440, 1e-9));
      expect(p.repaid, 220);
      expect(p.remaining, closeTo(220, 1e-9));
      expect(p.fraction, closeTo(0.5, 1e-9));
      expect(p.principalOutstanding, closeTo(180, 1e-9));
    });

    test('fund splits cash, lent principal and expected interest', () {
      final LoanRequest loan = testLoan(
        'l-1',
        approvedAmount: 400,
        status: LoanStatus.repaying,
      );
      final GroupFund fund = GroupFund.compute(
        [
          testTransaction('c-1', amount: 1000),
          testTransaction('c-2', amount: 1000),
          testTransaction(
            'd-1',
            type: TransactionType.loan,
            fromPeerId: 'group',
            toPeerId: 'alice',
            amount: 400,
            loanId: 'l-1',
          ),
          testTransaction(
            'r-1',
            type: TransactionType.repayment,
            amount: 110,
            loanId: 'l-1',
          ),
        ],
        [loan],
      );

      // Cash: 2000 in, 400 out, 110 back.
      expect(fund.available, 1710);
      // Principal out: 400 borrowed minus 110 repaid.
      expect(fund.lentOut, 290);
      // Interest: 440 due minus 110 repaid minus 290 principal.
      expect(fund.interestExpected, closeTo(40, 1e-9));
      expect(fund.total, 2000);
    });

    test('reversed transactions leave the fund alone', () {
      final GroupFund fund = GroupFund.compute(
        [
          testTransaction('c-1', amount: 100),
          testTransaction('c-2', amount: 100).copyWith(
            status: TransactionStatus.reversed,
          ),
        ],
        const [],
      );

      expect(fund.available, 100);
    });
  });
}
