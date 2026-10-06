import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/context.dart';
import 'package:vbank/src/app/loan_service.dart';
import 'package:vbank/src/crypto/signing.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/reports.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('LoanService edges', () {
    test('creation validates everything up front', () async {
      final String gid = await world.seedGroup();
      final ServiceStack member = world.stackFor('member');

      expect(
        (await member.loans.requestLoan(
          groupId: gid,
          borrowerPeerId: 'member',
          requestedAmount: 0,
          termWeeks: 4,
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await member.loans.requestLoan(
          groupId: gid,
          borrowerPeerId: 'member',
          requestedAmount: 10,
          termWeeks: 0,
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await member.loans.requestLoan(
          groupId: 'nope',
          borrowerPeerId: 'member',
          requestedAmount: 10,
          termWeeks: 4,
        )).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('decisions guard state and rank', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }
      final LoanRequest loan = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 4,
      ))
          .value;

      // Strangers and missing loans fail.
      expect(
        (await world.stackFor('stranger').loans.approveLoan(
          loanId: loan.id,
          approvedAmount: 100,
          approverPeerId: 'stranger',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.loans.approveLoan(
          loanId: 'nope',
          approvedAmount: 100,
          approverPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
      // Over-approval is rejected.
      expect(
        (await owner.loans.approveLoan(
          loanId: loan.id,
          approvedAmount: 500,
          approverPeerId: 'owner',
        )).failure,
        isA<ValidationFailure>(),
      );
      await owner.loans.rejectLoan(
        loanId: loan.id,
        approverPeerId: 'owner',
      );
      // Decided loans stay decided.
      expect(
        (await owner.loans.approveLoan(
          loanId: loan.id,
          approvedAmount: 100,
          approverPeerId: 'owner',
        )).failure,
        isA<ConflictFailure>(),
      );
      expect(
        (await owner.loans.rejectLoan(
          loanId: 'nope',
          approverPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('disbursement and repayment guard state', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }
      final LoanRequest loan = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 4,
      ))
          .value;

      // Pending loans cannot disburse.
      expect(
        (await owner.loans.disburseLoan(
          loanId: loan.id,
          adminPeerId: 'owner',
        )).failure,
        isA<ConflictFailure>(),
      );
      expect(
        (await owner.loans.disburseLoan(
          loanId: 'nope',
          adminPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await member.loans.disburseLoan(
          loanId: loan.id,
          adminPeerId: 'member',
        )).failure,
        isA<PermissionFailure>(),
      );

      await owner.loans.approveLoan(
        loanId: loan.id,
        approvedAmount: 100,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(
        loanId: loan.id,
        adminPeerId: 'owner',
      );

      // Non-positive repayments are rejected.
      expect(
        (await owner.loans.recordRepayment(
          loanId: loan.id,
          adminPeerId: 'owner',
          amount: 0,
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await owner.loans.recordRepayment(
          loanId: 'nope',
          adminPeerId: 'owner',
          amount: 10,
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await member.loans.recordRepayment(
          loanId: loan.id,
          adminPeerId: 'member',
          amount: 10,
        )).failure,
        isA<PermissionFailure>(),
      );
    });

    test('reads hit and miss, schedules build exactly', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      expect(
        (await owner.loans.getById('nope')).failure,
        isA<NotFoundFailure>(),
      );
      expect((await owner.loans.listByGroup(gid)).value, isEmpty);
      expect(
        (await owner.loans.schedule('nope')).value,
        isEmpty,
      );

      final LoanRequest loan = LoanRequest(
        id: 'l',
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        approvedAmount: 100,
        interestRate: 0.10,
        termWeeks: 3,
        requestedAt: world.now,
        borrowerSignature: Uint8List(0),
      );
      final List<RepaymentSchedule> schedule =
          LoanService.buildSchedule(loan, from: world.now);
      expect(schedule.map((s) => s.installmentNumber), [1, 2, 3]);
      expect(
        schedule.fold<double>(0, (s, x) => s + x.expectedAmount),
        closeTo(110, 1e-6),
      );
    });

    test('approval signatures verify against the roster', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }
      final LoanRequest loan = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 4,
      ))
          .value;

      expect(
        await owner.loans.verifyRequestSignature(
          loan,
          world.publicKeys['member']!,
        ),
        isTrue,
      );
      final LoanRequest approved = (await owner.loans.approveLoan(
        loanId: loan.id,
        approvedAmount: 100,
        approverPeerId: 'owner',
      ))
          .value;
      expect(
        await owner.loans.verifyApprovalSignature(
          approved,
          world.publicKeys['owner']!,
        ),
        isTrue,
      );
      expect(
        await owner.loans.verifyApprovalSignature(
          loan,
          world.publicKeys['owner']!,
        ),
        isFalse,
        reason: 'no approver signature yet',
      );
      expect(
        await owner.loans.verifyApprovalSignature(
          approved,
          world.publicKeys['member']!,
        ),
        isFalse,
      );
    });
  });

  group('GovernanceService edges', () {
    test('requests validate membership, target and reason', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack stranger = world.stackFor('stranger');

      expect(
        (await stranger.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'stranger',
          transactionId: 't',
          reason: 'x',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'owner',
          transactionId: 'nope',
          reason: 'x',
        )).failure,
        isA<NotFoundFailure>(),
      );

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'owner',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 50,
      ))
          .value;
      // Uninvolved members cannot dispute strangers' money...
      expect(
        (await world.stackFor('member').governance.requestReversal(
          groupId: gid,
          actingPeerId: 'member',
          transactionId: tx.id,
          reason: 'nosy',
        )).failure,
        isA<PermissionFailure>(),
      );
      // ...but owners can dispute anything.
      expect(
        (await owner.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'owner',
          transactionId: tx.id,
          reason: 'audit',
        )).isOk,
        isTrue,
      );
      expect(
        (await owner.governance.reversalsForGroup(gid)).value,
        hasLength(1),
      );
    });

    test('decisions validate everything before signing', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      expect(
        (await member.governance.decideReversal(
          groupId: gid,
          actingPeerId: 'member',
          reversalId: 'nope',
          approve: true,
        )).failure,
        isA<PermissionFailure>(),
        reason: 'members cannot decide at all',
      );
      expect(
        (await owner.governance.decideReversal(
          groupId: 'nope',
          actingPeerId: 'owner',
          reversalId: 'nope',
          approve: true,
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.governance.decideReversal(
          groupId: gid,
          actingPeerId: 'owner',
          reversalId: 'nope',
          approve: true,
        )).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('dissolution validates rank and unknown groups', () async {
      final ServiceStack owner = world.stackFor('owner');

      expect(
        (await owner.governance.dissolutionBlockers('nope')).value,
        isEmpty,
      );
      expect(
        (await owner.governance.dissolveGroup(
          groupId: 'nope',
          actingPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
    });
  });

  group('KeyService edges', () {
    test('missing keys read as missing', () async {
      expect(await world.keys.getKey('nope'), isNull);
      expect(await world.keys.currentVersion('nope'), 1);
      expect(await world.keys.keyFor('nope', 1), isNull);
      expect(await world.keys.ring('nope'), isNull);
    });

    test('passphrase keys derive and store', () async {
      await world.keys.setFromPassphrase('g-1', 'harvest moon');
      expect(await world.keys.hasKey('g-1'), isTrue);
      expect(
        (await world.keys.requireKey('g-1')).isOk,
        isTrue,
      );
      expect(
        ((await world.keys.ring('g-1'))!.keys.keys.toList()),
        [1],
      );
    });
  });

  group('AppContext', () {
    test('identifies the device and signs', () async {
      await world.keyFor('me');
      final AppContext ctx = AppContext(
        peerId: 'me',
        displayName: 'Me',
        sign: world.signerFor('me'),
      );
      final Uint8List sig = await ctx.sign([1, 2, 3]);

      expect(ctx.peerId, 'me');
      expect(
        await SigningService.verifyWithBytes(
          [1, 2, 3],
          sig,
          world.publicKeys['me']!,
        ),
        isTrue,
      );
      expect(uuidV7(), isNot(uuidV7()));
    });
  });

  group('ReportService edges', () {
    test('missing groups fail, empty groups zero out', () async {
      expect(
        (await world.reports.generateGroupReport(
          groupId: 'nope',
          period: DateTimePeriod(
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 12, 31),
          ),
        )).failure,
        isA<NotFoundFailure>(),
      );

      final String gid = await world.seedGroup();
      final report = (await world.reports.generateGroupReport(
        groupId: gid,
        period: DateTimePeriod(
          start: DateTime.utc(2030, 1, 1),
          end: DateTime.utc(2030, 12, 31),
        ),
      ))
          .value;
      expect(report.totalTransactions, 0);
      expect(report.totalContributions, 0);
      expect(report.memberStatements, hasLength(2));
    });

    test('fees, withdrawals and reversals stay out of the sums', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Future<void> record(TransactionType type, double amount) async {
        final result = await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: type,
          amount: amount,
        );
        assert(result.isOk);
      }

      await record(TransactionType.fee, 7);
      await record(TransactionType.withdrawal, 13);

      final report = (await world.reports.generateGroupReport(
        groupId: gid,
        period: DateTimePeriod(
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 12, 31),
        ),
      ))
          .value;
      // Seed 200 only; fee and withdrawal do not move these sums.
      expect(report.totalContributions, 200);
      expect(report.totalTransactions, 4);
    });
  });
}
