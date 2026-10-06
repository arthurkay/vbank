import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:vbank/src/data/repositories/transaction_repository.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/transactions.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  group('SqlTransactionRepository', () {
    TransactionReversal testReversal() => TransactionReversal(
          id: 'r-1',
          originalTransactionId: 't-1',
          groupId: 'g-1',
          requestedByPeerId: 'alice',
          reason: 'wrong amount',
          requestedAt: DateTime.utc(2026, 2, 2),
          requesterSignature: testSignature(),
        );

    test('lists a group ledger in sequence order', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlTransactionRepository repo = SqlTransactionRepository(db);
      addTearDown(repo.close);
      await repo.save(testTransaction('t-2', sequenceNumber: 2));
      await repo.save(testTransaction('t-1', sequenceNumber: 1));

      final List<Transaction> ledger =
          (await repo.listByGroup('g-1')).value;

      expect(
        ledger.map((Transaction t) => t.id),
        ['t-1', 't-2'],
      );
      expect((await repo.findById('t-1')).value, ledger.first);
      expect(
        (await repo.findById('nope')).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('markReversed flips confirmed transactions only', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlTransactionRepository repo = SqlTransactionRepository(db);
      addTearDown(repo.close);
      await repo.save(testTransaction('t-1'));

      expect((await repo.markReversed('t-1')).isOk, isTrue);
      expect(
        (await repo.findById('t-1')).value.status,
        TransactionStatus.reversed,
      );
      // Second call is a no-op, still ok.
      expect((await repo.markReversed('t-1')).isOk, isTrue);
    });

    test('reversals round-trip per group', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlTransactionRepository repo = SqlTransactionRepository(db);
      addTearDown(repo.close);
      await repo.save(testTransaction('t-1'));
      await repo.saveReversal(testReversal());

      final List<TransactionReversal> reversals =
          (await repo.reversalsByGroup('g-1')).value;

      expect(reversals, hasLength(1));
      expect(reversals.first.id, 'r-1');
      expect(
        (await repo.reversalsByGroup('other')).value,
        isEmpty,
      );
    });

    test('watch follows new records', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlTransactionRepository repo = SqlTransactionRepository(db);
      addTearDown(repo.close);
      final List<List<Transaction>> seen = [];
      final StreamSubscription<List<Transaction>> sub =
          repo.watchByGroup('g-1').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.single, isEmpty);

      await repo.save(testTransaction('t-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.last, hasLength(1));
    });
  });
}
