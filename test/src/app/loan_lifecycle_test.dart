import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/loan_service.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

/// Builds a borrower with 4 contributions of 100 (max loan 1200).
Future<String> qualifyBorrower(AppHarness world, String gid) async {
  final ServiceStack owner = world.stackFor('owner');
  for (var i = 0; i < 3; i++) {
    final result = await owner.transactions.createTransaction(
      groupId: gid,
      authorPeerId: 'owner',
      fromPeerId: 'member',
      toPeerId: 'group',
      type: TransactionType.contribution,
      amount: 100,
    );
    assert(result.isOk);
  }
  return gid;
}

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('LoanService lifecycle', () {
    test('request, approve, disburse, repay to completion', () async {
      final String gid = await world.seedGroup();
      await qualifyBorrower(world, gid);
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final LoanRequest requested = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 400,
        termWeeks: 4,
        reason: 'seeds',
      ))
          .value;
      expect(requested.status, LoanStatus.pending);
      expect(requested.interestRate, 0.10);

      // Borrower cannot approve their own loan.
      expect(
        (await member.loans.approveLoan(
          loanId: requested.id,
          approvedAmount: 400,
          approverPeerId: 'member',
        )).failure,
        isA<PermissionFailure>(),
      );

      final LoanRequest approved = (await owner.loans.approveLoan(
        loanId: requested.id,
        approvedAmount: 300,
        approverPeerId: 'owner',
      ))
          .value;
      expect(approved.approvedAmount, 300);
      expect(approved.totalWithInterest, closeTo(330, 1e-9));

      final LoanRequest disbursed = (await owner.loans.disburseLoan(
        loanId: requested.id,
        adminPeerId: 'owner',
      ))
          .value;
      expect(disbursed.status, LoanStatus.disbursed);
      final schedules = await owner.loans.schedule(requested.id);
      expect(schedules.value, hasLength(4));
      expect(
        schedules.value.fold<double>(
          0,
          (double s, RepaymentSchedule x) => s + x.expectedAmount,
        ),
        closeTo(330, 1e-6),
      );

      // Weekly repayments of 82.50 complete the loan.
      LoanRequest loan = disbursed;
      for (var i = 0; i < 4; i++) {
        world.elapse(const Duration(days: 7));
        loan = (await owner.loans.recordRepayment(
          loanId: requested.id,
          adminPeerId: 'owner',
          amount: 82.50,
        ))
            .value;
      }
      expect(loan.status, LoanStatus.completed);
      final Group group = (await owner.groups.getGroup(gid)).value;
      final Member borrower = group.members
          .where((Member m) => m.peerId == 'member')
          .single;
      expect(borrower.hasOutstandingLoan, isFalse);

      // Repaying a closed loan is refused.
      expect(
        (await owner.loans.recordRepayment(
          loanId: requested.id,
          adminPeerId: 'owner',
          amount: 10,
        )).failure,
        isA<ConflictFailure>(),
      );
    });

    test('eligibility blocks the unqualified with reasons', () async {
      final String gid = await world.seedGroup();
      final ServiceStack member = world.stackFor('member');

      // One contribution only: too few, and 5000 exceeds 1×100×3.
      final List<EligibilityIssue> problems = (await member.loans
              .eligibilityProblems(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 5000,
      ))
          .value;
      expect(problems.map((EligibilityIssue e) => e.code), [
        'minContributions',
        'exceedsMax',
      ]);

      expect(
        (await member.loans.requestLoan(
          groupId: gid,
          borrowerPeerId: 'member',
          requestedAmount: 5000,
          termWeeks: 4,
        )).failure,
        isA<ValidationFailure>(),
      );
    });

    test('approval-free groups self-approve on request', () async {
      await world.keyFor('owner');
      await world.keyFor('member');
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      const GroupConfig autoConfig = GroupConfig(
        groupId: 'template',
        contributionAmount: 100,
        requireLoanApproval: false,
      );
      final Group group = (await owner.groups.createGroup(
        name: 'Auto Group',
        config: autoConfig,
        ownerPeerId: 'owner',
        ownerName: 'Owner',
        ownerPublicKey: world.publicKeys['owner']!,
      ))
          .value;
      await owner.groups.addMember(
        group,
        Member(
          peerId: 'member',
          name: 'Member',
          joinedAt: world.now,
          publicKey: world.publicKeys['member']!,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: group.id,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }

      final LoanRequest loan = (await member.loans.requestLoan(
        groupId: group.id,
        borrowerPeerId: 'member',
        requestedAmount: 150,
        termWeeks: 2,
      ))
          .value;

      expect(loan.status, LoanStatus.approved);
      expect(loan.approvedAmount, 150);
      expect(loan.approvedByPeerId, 'member');
      expect(
        await member.loans.verifyApprovalSignature(
          loan,
          world.publicKeys['member']!,
        ),
        isTrue,
      );
      // And it disburses like any approved loan.
      final LoanRequest disbursed = (await owner.loans.disburseLoan(
        loanId: loan.id,
        adminPeerId: 'owner',
      ))
          .value;
      expect(disbursed.status, LoanStatus.disbursed);
    });

    test('fresh imports insert, completions clear flags', () async {
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
      final LoanRequest requested = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 2,
      ))
          .value;

      // Unknown id inserts outright.
      expect(
        (await owner.loans.importRemote(requested)).isOk,
        isTrue,
      );

      // A completed record clears the borrower flag.
      await owner.loans.approveLoan(
        loanId: requested.id,
        approvedAmount: 100,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(
        loanId: requested.id,
        adminPeerId: 'owner',
      );
      LoanRequest loan = (await owner.loans.getById(requested.id)).value;
      for (var i = 0; i < 2; i++) {
        world.elapse(const Duration(days: 7));
        loan = (await owner.loans.recordRepayment(
          loanId: loan.id,
          adminPeerId: 'owner',
          amount: 55,
        ))
            .value;
      }
      expect(loan.status, LoanStatus.completed);
      expect(
        (await owner.loans.importRemote(loan)).isOk,
        isTrue,
      );
      final Group group = (await owner.groups.getGroup(gid)).value;
      final Member borrower = group.members
          .where((Member m) => m.peerId == 'member')
          .single;
      expect(borrower.hasOutstandingLoan, isFalse);

      // The public schedule allocator delegates faithfully.
      final LoanRequest again = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 2,
      ))
          .value;
      await owner.loans.approveLoan(
        loanId: again.id,
        approvedAmount: 100,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(
        loanId: again.id,
        adminPeerId: 'owner',
      );
      final LoanRequest moved = (await owner.loans.applyRepaymentToSchedule(
        (await owner.loans.getById(again.id)).value,
        55,
      ))
          .value;
      expect(moved.status, LoanStatus.repaying);
    });

    test('open loans block second requests until settled', () async {
      final String gid = await world.seedGroup();
      await qualifyBorrower(world, gid);
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final LoanRequest first = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 4,
      ))
          .value;
      final List<EligibilityIssue> problems = (await member.loans
              .eligibilityProblems(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
      ))
          .value;
      expect(problems.map((EligibilityIssue e) => e.code), ['openLoan']);

      await owner.loans.rejectLoan(
        loanId: first.id,
        approverPeerId: 'owner',
      );
      final List<EligibilityIssue> clear = (await member.loans
              .eligibilityProblems(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
      ))
          .value;
      expect(clear, isEmpty);
    });

    test('overdue loans penalise once and default after 30 days', () async {
      final String gid = await world.seedGroup();
      await qualifyBorrower(world, gid);
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final LoanRequest requested = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 400,
        termWeeks: 4,
      ))
          .value;
      await owner.loans.approveLoan(
        loanId: requested.id,
        approvedAmount: 400,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(
        loanId: requested.id,
        adminPeerId: 'owner',
      );

      // Two weeks: first instalment overdue, penalised 10% once.
      world.elapse(const Duration(days: 14));
      await owner.loans.refreshOverdue(gid);
      var schedules = (await owner.loans.schedule(requested.id)).value;
      expect(schedules.first.status, RepaymentStatus.overdue);
      expect(schedules.first.penalty, closeTo(5.5, 1e-9));

      // Refreshing again does not double-charge.
      await owner.loans.refreshOverdue(gid);
      schedules = (await owner.loans.schedule(requested.id)).value;
      expect(schedules.first.penalty, closeTo(5.5, 1e-9));

      // Past 30 days overdue: defaulted.
      world.elapse(const Duration(days: 25));
      await owner.loans.refreshOverdue(gid);
      expect(
        (await owner.loans.getById(requested.id)).value.status,
        LoanStatus.defaulted,
      );
    });

    test('remote loans import forward-only with side effects', () async {
      // Signatures are verified by the sync layer before import; here the
      // status machine and its side effects are proven.
      final String gid = await world.seedGroup();
      await qualifyBorrower(world, gid);
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final LoanRequest requested = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 200,
        termWeeks: 2,
      ))
          .value;
      final LoanRequest approved = (await owner.loans.approveLoan(
        loanId: requested.id,
        approvedAmount: 200,
        approverPeerId: 'owner',
      ))
          .value;

      // Fresh device learns the loan at approval: stored, no schedule.
      await owner.loans.importRemote(approved);
      expect((await owner.loans.getById(requested.id)).value.status,
          LoanStatus.approved);
      expect(
        (await owner.loans.schedule(requested.id)).value,
        isEmpty,
      );

      // Disbursement arrives: schedule built, borrower flagged.
      final LoanRequest disbursed = (await owner.loans.disburseLoan(
        loanId: requested.id,
        adminPeerId: 'owner',
      ))
          .value;
      await owner.loans.importRemote(disbursed);
      expect(
        (await owner.loans.schedule(requested.id)).value,
        hasLength(2),
      );
      final Group group = (await owner.groups.getGroup(gid)).value;
      final Member borrower = group.members
          .where((Member m) => m.peerId == 'member')
          .single;
      expect(borrower.hasOutstandingLoan, isTrue);

      // A stale copy changes nothing.
      await owner.loans.importRemote(requested);
      expect(
        (await owner.loans.getById(requested.id)).value.status,
        LoanStatus.disbursed,
      );

      // Repayment transactions arriving remotely allocate installments.
      await owner.loans.applyRemoteRepayment(requested.id, 115.50);
      final schedules = await owner.loans.schedule(requested.id);
      expect(schedules.value.first.status, RepaymentStatus.paid);

      // Unknown loans are ignored, not errors.
      expect(
        (await owner.loans.applyRemoteRepayment('nope', 10)).isOk,
        isTrue,
      );
    });
  });
}
