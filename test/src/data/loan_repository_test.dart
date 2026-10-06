import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/repositories/loan_repository.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/loans.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  group('SqlLoanRepository', () {
    RepaymentSchedule testInstalment(int n) => RepaymentSchedule(
          id: 's-$n',
          loanId: 'l-1',
          installmentNumber: n,
          expectedAmount: 110,
          dueDate: DateTime.utc(2026, 2, 8 + n * 7),
        );

    test('loans list newest first and find by id', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlLoanRepository repo = SqlLoanRepository(db);
      addTearDown(repo.close);
      await repo.saveLoan(testLoan('l-old'));
      await repo.saveLoan(
        testLoan(
          'l-new',
          approvedAmount: 300,
          status: LoanStatus.disbursed,
        ),
      );

      final List<LoanRequest> loans = (await repo.listByGroup('g-1')).value;

      expect(loans, hasLength(2));
      expect((await repo.findById('l-new')).value.approvedAmount, 300);
      expect(
        (await repo.findById('nope')).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('saving a schedule replaces it wholesale', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlLoanRepository repo = SqlLoanRepository(db);
      addTearDown(repo.close);
      await repo.saveLoan(testLoan('l-1'));
      await repo.saveSchedules('l-1', [testInstalment(1), testInstalment(2)]);

      expect(
        (await repo.schedulesByLoan('l-1')).value.map((s) => s.id),
        ['s-1', 's-2'],
      );

      await repo.saveSchedules('l-1', [testInstalment(1)]);

      expect(
        (await repo.schedulesByLoan('l-1')).value.map((s) => s.id),
        ['s-1'],
      );
    });

    test('watch follows new loans', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlLoanRepository repo = SqlLoanRepository(db);
      addTearDown(repo.close);
      final List<List<LoanRequest>> seen = [];
      final StreamSubscription<List<LoanRequest>> sub =
          repo.watchByGroup('g-1').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.single, isEmpty);

      await repo.saveLoan(testLoan('l-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.last, hasLength(1));
    });
  });
}
