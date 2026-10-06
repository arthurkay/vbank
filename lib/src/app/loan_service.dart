import 'dart:typed_data';

import '../crypto/signing.dart';
import '../domain/balance.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/group.dart';
import '../domain/loans.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../domain/transactions.dart';
import 'context.dart';
import 'group_service.dart';
import 'signing_payloads.dart';
import 'transaction_service.dart';

/// One reason a loan cannot be granted right now. Presentation renders
/// these; the codes and numbers are stable.
final class EligibilityIssue {
  /// Machine code: `inactiveBorrower`, `openLoan`, `minContributions` or
  /// `exceedsMax`.
  final String code;

  /// Numbers for the message, e.g. `{'required': 3, 'have': 1}`.
  final Map<String, double> params;

  /// Creates an eligibility issue.
  const EligibilityIssue(this.code, [this.params = const {}]);
}

/// Loan lifecycle: pending → approved/rejected → disbursed → repaying →
/// completed, or defaulted past the grace period.
///
/// Requesting needs an active borrower who qualifies; approving,
/// disbursing and recording repayments need an active owner/admin who is
/// not the borrower. Disbursement posts the loan transaction, builds the
/// schedule and flags the borrower; the last repayment clears the flag.
final class LoanService {
  /// Loans and schedules.
  final LoanRepository loans;

  /// Groups and roster checks.
  final GroupService groups;

  /// Money movements for disbursements and repayments.
  final TransactionService transactions;

  /// Cached snapshots (eligibility counts gross contributions).
  final BalanceRepository balances;

  /// Member signatures.
  final SignPayload sign;

  /// Clock for timestamps and overdue checks.
  final AppClock clock;

  /// Record ids.
  final IdGenerator ids;

  /// An installment this far past due defaults the whole loan.
  static const Duration defaultAfter = Duration(days: 30);

  /// Creates a loan service.
  LoanService({
    required this.loans,
    required this.groups,
    required this.transactions,
    required this.balances,
    required this.sign,
    required this.clock,
    required this.ids,
  });

  /// Verifies a request signature against the borrower's roster key.
  Future<bool> verifyRequestSignature(
    LoanRequest loan,
    List<int> borrowerPublicKey,
  ) =>
      SigningService.verifyWithBytes(
        SigningPayloads.loanRequest(loan),
        loan.borrowerSignature,
        borrowerPublicKey,
      );

  /// Verifies a decision signature against the approver's roster key.
  Future<bool> verifyApprovalSignature(
    LoanRequest loan,
    List<int> approverPublicKey,
  ) async {
    final Uint8List? sig = loan.approverSignature;
    if (sig == null) {
      return false;
    }
    return SigningService.verifyWithBytes(
      SigningPayloads.loanApproval(loan),
      sig,
      approverPublicKey,
    );
  }

  /// Eligibility against the group config: active borrower, no open loan,
  /// enough contributions, within the multiplier.
  Future<Result<List<EligibilityIssue>>> eligibilityProblems({
    required String groupId,
    required String borrowerPeerId,
    required double requestedAmount,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    final List<EligibilityIssue> problems = [];
    final Member? borrower = await groups.getMember(groupId, borrowerPeerId);
    if (borrower == null || borrower.status != MemberStatus.active) {
      return const Ok([EligibilityIssue('inactiveBorrower')]);
    }
    final Result<List<LoanRequest>> existing = await loans.listByGroup(
      groupId,
    );
    if (existing.isErr) {
      return Err(existing.failure);
    }
    final bool busy = borrower.hasOutstandingLoan ||
        existing.value.any(
          (LoanRequest l) =>
              l.borrowerPeerId == borrowerPeerId &&
              (l.isPending ||
                  l.status == LoanStatus.approved ||
                  l.isActive),
        );
    if (busy) {
      problems.add(const EligibilityIssue('openLoan'));
    }
    final Result<int> contributions = await transactions.countContributions(
      groupId,
      borrowerPeerId,
    );
    if (contributions.isErr) {
      return Err(contributions.failure);
    }
    final GroupConfig cfg = group.value.config;
    if (contributions.value < cfg.minContributionsForLoan) {
      problems.add(
        EligibilityIssue('minContributions', {
          'required': cfg.minContributionsForLoan.toDouble(),
          'have': contributions.value.toDouble(),
        }),
      );
    }
    final Result<Balance> balance = await balances.find(
      borrowerPeerId,
      groupId,
    );
    // No snapshot yet means nothing contributed yet.
    final double contributed =
        balance.isOk ? balance.value.totalContributed : 0;
    final double maxLoan = contributed * cfg.maxLoanMultiplier;
    if (requestedAmount > maxLoan) {
      problems.add(EligibilityIssue('exceedsMax', {'max': maxLoan}));
    }
    return Ok(problems);
  }

  /// Requests a loan. Groups without approval auto-approve at the requested
  /// amount, countersigned by the borrower's own key.
  Future<Result<LoanRequest>> requestLoan({
    required String groupId,
    required String borrowerPeerId,
    required double requestedAmount,
    required int termWeeks,
    String? reason,
  }) async {
    if (requestedAmount <= 0) {
      return const Err(ValidationFailure('loanAmountNotPositive'));
    }
    if (termWeeks <= 0) {
      return const Err(ValidationFailure('loanTermNotPositive'));
    }
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (group.value.status == GroupStatus.dissolved) {
      return const Err(PermissionFailure(GroupFailures.groupDissolved));
    }
    final Result<List<EligibilityIssue>> problems = await eligibilityProblems(
      groupId: groupId,
      borrowerPeerId: borrowerPeerId,
      requestedAmount: requestedAmount,
    );
    if (problems.isErr) {
      return Err(problems.failure);
    }
    if (problems.value.isNotEmpty) {
      return const Err(ValidationFailure('loanIneligible'));
    }
    final DateTime now = clock().toUtc();
    LoanRequest loan = LoanRequest(
      id: ids(),
      groupId: groupId,
      borrowerPeerId: borrowerPeerId,
      requestedAmount: requestedAmount,
      interestRate: group.value.config.loanInterestRate,
      termWeeks: termWeeks,
      reason: reason,
      requestedAt: now,
      borrowerSignature: Uint8List(0),
    );
    loan = loan.copyWith(
      borrowerSignature: await sign(SigningPayloads.loanRequest(loan)),
    );
    if (!group.value.config.requireLoanApproval) {
      LoanRequest approved = loan.copyWith(
        status: LoanStatus.approved,
        approvedAmount: requestedAmount,
        approvedAt: now,
        approvedByPeerId: borrowerPeerId,
      );
      approved = approved.copyWith(
        approverSignature: await sign(SigningPayloads.loanApproval(approved)),
      );
      loan = approved;
    }
    final Result<Unit> saved = await loans.saveLoan(loan);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(loan);
  }

  /// Approves a pending loan for [approvedAmount] (which may be less than
  /// asked). The approver must be an active owner/admin and not the
  /// borrower.
  Future<Result<LoanRequest>> approveLoan({
    required String loanId,
    required double approvedAmount,
    required String approverPeerId,
  }) async {
    final Result<LoanRequest> current = await loans.findById(loanId);
    if (current.isErr) {
      return current;
    }
    final LoanRequest loan = current.value;
    final Result<Group> group = await groups.getGroup(loan.groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (group.value.status == GroupStatus.dissolved) {
      return const Err(PermissionFailure(GroupFailures.groupDissolved));
    }
    final Result<Member> permitted = groups.requireRole(
      group.value,
      approverPeerId,
      canWrite,
      'approveLoan',
    );
    if (permitted.isErr) {
      return const Err(PermissionFailure('approveLoan'));
    }
    if (approverPeerId == loan.borrowerPeerId) {
      return const Err(PermissionFailure('approveOwnLoan'));
    }
    if (!loan.isPending) {
      return Err(ConflictFailure('loan:${loan.id}:alreadyDecided'));
    }
    if (approvedAmount <= 0 || approvedAmount > loan.requestedAmount) {
      return const Err(ValidationFailure('approvedAmountRange'));
    }
    LoanRequest approved = loan.copyWith(
      status: LoanStatus.approved,
      approvedAmount: approvedAmount,
      approvedAt: clock().toUtc(),
      approvedByPeerId: approverPeerId,
    );
    approved = approved.copyWith(
      approverSignature: await sign(SigningPayloads.loanApproval(approved)),
    );
    final Result<Unit> saved = await loans.saveLoan(approved);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(approved);
  }

  /// Rejects a pending loan.
  Future<Result<LoanRequest>> rejectLoan({
    required String loanId,
    required String approverPeerId,
  }) async {
    final Result<LoanRequest> current = await loans.findById(loanId);
    if (current.isErr) {
      return current;
    }
    final LoanRequest loan = current.value;
    final Result<Group> group = await groups.getGroup(loan.groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    final Result<Member> permitted = groups.requireRole(
      group.value,
      approverPeerId,
      canWrite,
      'rejectLoan',
    );
    if (permitted.isErr) {
      return const Err(PermissionFailure('rejectLoan'));
    }
    if (!loan.isPending) {
      return Err(ConflictFailure('loan:${loan.id}:alreadyDecided'));
    }
    LoanRequest rejected = loan.copyWith(
      status: LoanStatus.rejected,
      approvedAt: clock().toUtc(),
      approvedByPeerId: approverPeerId,
    );
    rejected = rejected.copyWith(
      approverSignature: await sign(SigningPayloads.loanApproval(rejected)),
    );
    final Result<Unit> saved = await loans.saveLoan(rejected);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(rejected);
  }

  /// Disburses an approved loan: posts the group→borrower transaction,
  /// generates the schedule from now, flags the borrower.
  Future<Result<LoanRequest>> disburseLoan({
    required String loanId,
    required String adminPeerId,
  }) async {
    final Result<LoanRequest> current = await loans.findById(loanId);
    if (current.isErr) {
      return current;
    }
    final LoanRequest loan = current.value;
    final Result<Group> group = await groups.getGroup(loan.groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (group.value.status == GroupStatus.dissolved) {
      return const Err(PermissionFailure(GroupFailures.groupDissolved));
    }
    final Result<Member> permitted = groups.requireRole(
      group.value,
      adminPeerId,
      canWrite,
      'disburseLoan',
    );
    if (permitted.isErr) {
      return const Err(PermissionFailure('disburseLoan'));
    }
    if (loan.status != LoanStatus.approved) {
      return Err(ConflictFailure('loan:${loan.id}:notApproved'));
    }
    final Result<Transaction> posted = await transactions.createTransaction(
      groupId: loan.groupId,
      authorPeerId: adminPeerId,
      fromPeerId: 'group',
      toPeerId: loan.borrowerPeerId,
      type: TransactionType.loan,
      amount: loan.approvedAmount,
      currency: group.value.config.currency,
      note: 'Loan disbursement',
      loanId: loan.id,
    );
    if (posted.isErr) {
      return Err(posted.failure);
    }
    final DateTime disbursedAt = clock().toUtc();
    final LoanRequest disbursed = loan.copyWith(
      status: LoanStatus.disbursed,
      disbursedAt: disbursedAt,
    );
    final Result<Unit> saved = await loans.saveLoan(disbursed);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    final Result<Unit> scheduled = await loans.saveSchedules(
      loan.id,
      buildSchedule(disbursed, from: disbursedAt),
    );
    if (scheduled.isErr) {
      return Err(scheduled.failure);
    }
    final Result<Unit> flagged = await _setLoanFlag(
      loan.groupId,
      loan.borrowerPeerId,
      true,
    );
    if (flagged.isErr) {
      return Err(flagged.failure);
    }
    return Ok(disbursed);
  }

  /// Equal weekly installments of principal plus interest over the term.
  /// The last one absorbs rounding so the sum is exact.
  static List<RepaymentSchedule> buildSchedule(
    LoanRequest loan, {
    required DateTime from,
  }) {
    final double perWeek = loan.totalWithInterest / loan.termWeeks;
    final double rounded = (perWeek * 100).round() / 100;
    final double total = (loan.totalWithInterest * 100).round() / 100;
    return List<RepaymentSchedule>.generate(loan.termWeeks, (int i) {
      final int n = i + 1;
      final double amount = n == loan.termWeeks
          ? total - rounded * (loan.termWeeks - 1)
          : rounded;
      return RepaymentSchedule(
        id: '${loan.id}:$n',
        loanId: loan.id,
        installmentNumber: n,
        expectedAmount: (amount * 100).round() / 100,
        dueDate: from.add(Duration(days: 7 * n)),
      );
    });
  }

  /// Records a repayment authored by an admin and allocates it to the
  /// earliest unpaid installments. Returns the loan, now `repaying` or
  /// `completed` (flag cleared).
  Future<Result<LoanRequest>> recordRepayment({
    required String loanId,
    required String adminPeerId,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) {
      return const Err(ValidationFailure('repaymentNotPositive'));
    }
    final Result<LoanRequest> current = await loans.findById(loanId);
    if (current.isErr) {
      return current;
    }
    final LoanRequest loan = current.value;
    final Result<Group> group = await groups.getGroup(loan.groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (group.value.status == GroupStatus.dissolved) {
      return const Err(PermissionFailure(GroupFailures.groupDissolved));
    }
    final Result<Member> permitted = groups.requireRole(
      group.value,
      adminPeerId,
      canWrite,
      'recordRepayment',
    );
    if (permitted.isErr) {
      return const Err(PermissionFailure('recordRepayment'));
    }
    if (!loan.isActive) {
      return Err(ConflictFailure('loan:${loan.id}:notRepayable'));
    }
    final Result<Transaction> posted = await transactions.createTransaction(
      groupId: loan.groupId,
      authorPeerId: adminPeerId,
      fromPeerId: loan.borrowerPeerId,
      toPeerId: 'group',
      type: TransactionType.repayment,
      amount: amount,
      currency: group.value.config.currency,
      note: note ?? 'Loan repayment',
      loanId: loan.id,
    );
    if (posted.isErr) {
      return Err(posted.failure);
    }
    return _applyRepaymentToSchedule(loan, amount);
  }

  /// Allocates [amount] across installments in order; shared by local
  /// repayments and repayments arriving from peers.
  Future<Result<LoanRequest>> applyRepaymentToSchedule(
    LoanRequest loan,
    double amount,
  ) =>
      _applyRepaymentToSchedule(loan, amount);

  /// Applies a repayment transaction imported from a peer. Unknown or
  /// inactive loans are ignored (their own records will converge).
  Future<Result<Unit>> applyRemoteRepayment(
    String loanId,
    double amount,
  ) async {
    final Result<LoanRequest> current = await loans.findById(loanId);
    if (current.isErr) {
      return const Ok(unit);
    }
    if (!current.value.isActive) {
      return const Ok(unit);
    }
    final Result<LoanRequest> updated = await _applyRepaymentToSchedule(
      current.value,
      amount,
    );
    return updated.isErr ? Err(updated.failure) : const Ok(unit);
  }

  /// Marks overdue installments (penalty once each: rate × expected) and
  /// defaults loans with an installment more than [defaultAfter] overdue.
  /// Idempotent; runs on start, sync and screen open.
  Future<Result<Unit>> refreshOverdue(String groupId) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    final Result<List<LoanRequest>> all = await loans.listByGroup(groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    final DateTime now = clock().toUtc();
    for (final LoanRequest loan in all.value) {
      if (!loan.isActive) {
        continue;
      }
      final Result<List<RepaymentSchedule>> schedules =
          await loans.schedulesByLoan(loan.id);
      if (schedules.isErr) {
        return Err(schedules.failure);
      }
      var defaulted = false;
      for (final RepaymentSchedule inst in schedules.value) {
        if (inst.isPaid || !now.isAfter(inst.dueDate)) {
          continue;
        }
        if (!inst.isOverdue) {
          final double penalty =
              (inst.expectedAmount * group.value.config.latePenaltyRate * 100)
                      .round() /
                  100;
          final Result<Unit> penalised = await loans.saveSchedules(
            loan.id,
            _withInstalment(
              schedules.value,
              inst.copyWith(
                isOverdue: true,
                penalty: penalty,
                status: RepaymentStatus.overdue,
              ),
            ),
          );
          if (penalised.isErr) {
            return Err(penalised.failure);
          }
        }
        if (now.difference(inst.dueDate) > defaultAfter) {
          defaulted = true;
        }
      }
      if (defaulted) {
        final Result<Unit> saved = await loans.saveLoan(
          loan.copyWith(
            status: LoanStatus.defaulted,
            defaultedAt: now,
          ),
        );
        if (saved.isErr) {
          return Err(saved.failure);
        }
      }
    }
    return const Ok(unit);
  }

  /// Applies a loan record from a peer (signatures already verified against
  /// the roster). Status only moves forward; disbursement rebuilds the
  /// schedule and flags the borrower, completion clears the flag.
  Future<Result<Unit>> importRemote(LoanRequest incoming) async {
    final Result<LoanRequest> local = await loans.findById(incoming.id);
    if (local.isErr) {
      final Result<Unit> saved = await loans.saveLoan(incoming);
      if (saved.isErr) {
        return saved;
      }
    } else if (incoming.status.index > local.value.status.index) {
      // Status only moves forward; stale copies still refresh side
      // effects below.
      final Result<Unit> saved = await loans.saveLoan(incoming);
      if (saved.isErr) {
        return saved;
      }
    }
    if (incoming.status == LoanStatus.disbursed ||
        incoming.status == LoanStatus.repaying) {
      final Result<List<RepaymentSchedule>> schedules =
          await loans.schedulesByLoan(incoming.id);
      if (schedules.isErr) {
        return Err(schedules.failure);
      }
      if (schedules.value.isEmpty && incoming.disbursedAt != null) {
        final Result<Unit> built = await loans.saveSchedules(
          incoming.id,
          buildSchedule(incoming, from: incoming.disbursedAt!),
        );
        if (built.isErr) {
          return Err(built.failure);
        }
      }
      final Result<Unit> flagged = await _setLoanFlag(
        incoming.groupId,
        incoming.borrowerPeerId,
        true,
      );
      if (flagged.isErr) {
        return Err(flagged.failure);
      }
    }
    if (incoming.status == LoanStatus.completed ||
        incoming.status == LoanStatus.defaulted) {
      final Result<Unit> cleared = await _setLoanFlag(
        incoming.groupId,
        incoming.borrowerPeerId,
        false,
      );
      if (cleared.isErr) {
        return Err(cleared.failure);
      }
    }
    return const Ok(unit);
  }

  /// One loan, or `Err(NotFoundFailure)`.
  Future<Result<LoanRequest>> getById(String id) => loans.findById(id);

  /// A group's loans, newest first.
  Future<Result<List<LoanRequest>>> listByGroup(String groupId) =>
      loans.listByGroup(groupId);

  /// One loan's schedule, instalment order.
  Future<Result<List<RepaymentSchedule>>> schedule(String loanId) =>
      loans.schedulesByLoan(loanId);

  Future<Result<LoanRequest>> _applyRepaymentToSchedule(
    LoanRequest loan,
    double amount,
  ) async {
    var remaining = amount;
    final DateTime now = clock().toUtc();
    final Result<List<RepaymentSchedule>> current =
        await loans.schedulesByLoan(loan.id);
    if (current.isErr) {
      return Err(current.failure);
    }
    final List<RepaymentSchedule> updated = [];
    for (final RepaymentSchedule inst in current.value) {
      if (remaining <= 0 || inst.isPaid) {
        updated.add(inst);
        continue;
      }
      final double owed =
          inst.expectedAmount + inst.penalty - inst.paidAmount;
      final double pay = remaining >= owed ? owed : remaining;
      remaining -= pay;
      final double paid = inst.paidAmount + pay;
      final bool fullyPaid =
          paid + 0.005 >= inst.expectedAmount + inst.penalty;
      updated.add(
        inst.copyWith(
          paidAmount: paid,
          paidAt: fullyPaid ? now : inst.paidAt,
          isOverdue: fullyPaid ? false : inst.isOverdue,
          status: fullyPaid ? RepaymentStatus.paid : inst.status,
        ),
      );
    }
    final Result<Unit> saved = await loans.saveSchedules(loan.id, updated);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    final bool allPaid =
        updated.isNotEmpty && updated.every((RepaymentSchedule s) => s.isPaid);
    final LoanRequest next = loan.copyWith(
      status: allPaid ? LoanStatus.completed : LoanStatus.repaying,
      completedAt: allPaid ? now : loan.completedAt,
    );
    final Result<Unit> stored = await loans.saveLoan(next);
    if (stored.isErr) {
      return Err(stored.failure);
    }
    if (allPaid) {
      final Result<Unit> cleared = await _setLoanFlag(
        loan.groupId,
        loan.borrowerPeerId,
        false,
      );
      if (cleared.isErr) {
        return Err(cleared.failure);
      }
    }
    return Ok(next);
  }

  /// Borrower's outstanding-loan flag, via a roster save.
  Future<Result<Unit>> _setLoanFlag(
    String groupId,
    String peerId,
    bool value,
  ) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    var found = false;
    final List<Member> members = [];
    for (final Member m in group.value.members) {
      if (m.peerId == peerId) {
        members.add(m.copyWith(hasOutstandingLoan: value));
        found = true;
      } else {
        members.add(m);
      }
    }
    if (!found) {
      return Err(NotFoundFailure('member:$peerId'));
    }
    return groups.saveGroup(
      group.value.copyWith(members: members),
    );
  }

  /// Swaps one instalment in a schedule list.
  List<RepaymentSchedule> _withInstalment(
    List<RepaymentSchedule> schedules,
    RepaymentSchedule instalment,
  ) => [
    for (final RepaymentSchedule s in schedules)
      if (s.id == instalment.id) instalment else s,
  ];
}
