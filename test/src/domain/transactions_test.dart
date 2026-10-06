import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'fixtures.dart';

void main() {
  group('Transaction', () {
    test('author defaults to the sender', () {
      expect(testTransaction('t').authorPeerId, 'alice');
      expect(
        testTransaction('t', fromPeerId: 'bob').authorPeerId,
        'bob',
      );
    });

    test('type predicates match the type', () {
      expect(
        testTransaction(
          't',
          type: TransactionType.contribution,
        ).isContribution,
        isTrue,
      );
      expect(
        testTransaction('t', type: TransactionType.loan).isLoan,
        isTrue,
      );
      expect(
        testTransaction(
          't',
          type: TransactionType.repayment,
        ).isRepayment,
        isTrue,
      );
      expect(
        testTransaction(
          't',
          type: TransactionType.withdrawal,
        ).isWithdrawal,
        isTrue,
      );
      expect(
        testTransaction('t', type: TransactionType.penalty).isPenalty,
        isTrue,
      );
      expect(
        testTransaction('t', type: TransactionType.reversal).isReversal,
        isTrue,
      );
      expect(
        testTransaction(
          't',
          type: TransactionType.contribution,
        ).isLoan,
        isFalse,
      );
    });

    test('rejects blank ids, non-positive amounts, bad sequences', () {
      expect(
        testTransaction('').validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testTransaction('t', amount: 0).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testTransaction('t', sequenceNumber: -1).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(testTransaction('t').validate().isOk, isTrue);
    });

    test('copyWith flips status on reversal', () {
      final Transaction reversed = testTransaction('t').copyWith(
        status: TransactionStatus.reversed,
      );

      expect(reversed.status, TransactionStatus.reversed);
      expect(reversed.id, 't');
    });

    test('equality is by value', () {
      expect(testTransaction('t'), testTransaction('t'));
      expect(
        testTransaction('t') == testTransaction('u'),
        isFalse,
      );
    });
  });

  group('TransactionReversal', () {
    TransactionReversal testReversal() => TransactionReversal(
          id: 'r-1',
          originalTransactionId: 't-1',
          groupId: 'g-1',
          requestedByPeerId: 'alice',
          reason: 'wrong amount',
          requestedAt: DateTime.utc(2026, 2, 2),
          requesterSignature: testSignature(),
        );

    test('starts pending and validates', () {
      final TransactionReversal r = testReversal();

      expect(r.isPending, isTrue);
      expect(r.isApproved, isFalse);
      expect(r.isRejected, isFalse);
      expect(r.validate().isOk, isTrue);
    });

    test('rejects blank id, target and reason', () {
      expect(
        TransactionReversal(
          id: '',
          originalTransactionId: 't',
          groupId: 'g',
          requestedByPeerId: 'a',
          reason: 'x',
          requestedAt: DateTime.utc(2026, 2, 2),
          requesterSignature: testSignature(),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testReversal().copyWith(status: ReversalStatus.approved).isApproved,
        isTrue,
      );
    });
  });
}
