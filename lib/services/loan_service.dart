import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/signing.dart';
import '../core/storage/balance_dao.dart';
import '../core/storage/loan_dao.dart';
import '../core/storage/member_dao.dart';
import '../core/storage/repayment_schedule_dao.dart';
import '../models/group.dart';
import '../models/loan.dart';
import '../models/repayment_schedule.dart';
import '../models/transaction.dart';
import 'group_service.dart';
import 'transaction_service.dart';

class LoanAuthorizationException implements Exception {
  final String message;
  const LoanAuthorizationException(this.message);
  @override
  String toString() => message;
}

/// Loan lifecycle (DESIGN_PLAN §15):
/// pending → approved/rejected → disbursed → repaying → completed | defaulted.
class LoanService {
  final LoanDao _loanDao;
  final MemberDao _memberDao;
  final BalanceDao _balanceDao;
  final RepaymentScheduleDao _scheduleDao;
  final GroupService _groupService;
  final TransactionService _transactionService;
  static const _uuid = Uuid();

  /// An installment this far past due marks the whole loan defaulted.
  static const defaultAfter = Duration(days: 30);

  LoanService({
    required GroupService groupService,
    required TransactionService transactionService,
    LoanDao? loanDao,
    MemberDao? memberDao,
    BalanceDao? balanceDao,
    RepaymentScheduleDao? scheduleDao,
  })  : _groupService = groupService,
        _transactionService = transactionService,
        _loanDao = loanDao ?? LoanDao(),
        _memberDao = memberDao ?? MemberDao(),
        _balanceDao = balanceDao ?? BalanceDao(),
        _scheduleDao = scheduleDao ?? RepaymentScheduleDao();

  // --- signatures ----------------------------------------------------------------

  static List<int> requestSigningPayload(LoanRequest l) => utf8.encode(jsonEncode({
        'v': 2,
        'loanId': l.id,
        'groupId': l.groupId,
        'borrower': l.borrowerPeerId,
        'amount': l.requestedAmount,
        'rate': l.interestRate,
        'termWeeks': l.termWeeks,
        'reason': l.reason,
        'requestedAt': TransactionService.signedInstant(l.requestedAt),
      }));

  static List<int> approvalSigningPayload(LoanRequest l) => utf8.encode(jsonEncode({
        'v': 2,
        'loanId': l.id,
        'status': l.status == LoanStatus.rejected ? 'rejected' : 'approved',
        'approvedAmount': l.approvedAmount,
        'approver': l.approvedByPeerId,
        'approvedAt': l.approvedAt == null ? null : TransactionService.signedInstant(l.approvedAt!),
      }));

  Future<bool> verifyRequestSignature(LoanRequest l, List<int> borrowerPublicKey) =>
      SigningService.verifyWithBytes(requestSigningPayload(l), l.borrowerSignature, borrowerPublicKey);

  Future<bool> verifyApprovalSignature(LoanRequest l, List<int> approverPublicKey) {
    final sig = l.approverSignature;
    if (sig == null) return Future.value(false);
    return SigningService.verifyWithBytes(approvalSigningPayload(l), sig, approverPublicKey);
  }

  // --- helpers ---------------------------------------------------------------------

  Future<MemberData> _requireActiveAdmin(String groupId, String peerId) async {
    final m = await _memberDao.get(peerId, groupId);
    if (m == null) throw const LoanAuthorizationException('You are not a member of this group');
    if (m.status != MemberStatus.active.name) {
      throw const LoanAuthorizationException('Your membership is not active');
    }
    if (m.role != MemberRole.owner.name && m.role != MemberRole.admin.name) {
      throw const LoanAuthorizationException('Only the owner or an admin can do this');
    }
    return m;
  }

  Future<Group> _requireGroup(String groupId) async {
    final g = await _groupService.getGroup(groupId);
    if (g == null) throw StateError('Group $groupId not found');
    if (g.status == GroupStatus.dissolved) {
      throw const LoanAuthorizationException('This group has been dissolved');
    }
    return g;
  }

  /// DESIGN_PLAN §15 eligibility rules, evaluated against the group config.
  Future<List<String>> eligibilityProblems({
    required String groupId,
    required String borrowerPeerId,
    required double requestedAmount,
  }) async {
    final problems = <String>[];
    final group = await _requireGroup(groupId);
    final cfg = group.config;

    final borrower = await _memberDao.get(borrowerPeerId, groupId);
    if (borrower == null || borrower.status != MemberStatus.active.name) {
      problems.add('Only active members can request loans');
      return problems;
    }
    if (borrower.hasOutstandingLoan ||
        (await _loanDao.getByGroupId(groupId)).any((l) =>
            l.borrowerPeerId == borrowerPeerId &&
            (l.status == LoanStatus.pending.name ||
                l.status == LoanStatus.approved.name ||
                l.status == LoanStatus.disbursed.name ||
                l.status == LoanStatus.repaying.name))) {
      problems.add('You already have an open loan');
    }

    final contributions = await _transactionService.countContributions(groupId, borrowerPeerId);
    if (contributions < cfg.minContributionsForLoan) {
      problems.add('At least ${cfg.minContributionsForLoan} contributions are required '
          '(you have $contributions)');
    }

    final balance = await _balanceDao.get(borrowerPeerId, groupId);
    final maxLoan = (balance?.totalContributed ?? 0) * cfg.maxLoanMultiplier;
    if (requestedAmount > maxLoan) {
      problems.add('Maximum loan is ${cfg.maxLoanMultiplier}× your contributions '
          '(${cfg.currency} ${maxLoan.toStringAsFixed(2)})');
    }
    return problems;
  }

  // --- lifecycle ---------------------------------------------------------------------

  Future<LoanRequest> requestLoan({
    required String groupId,
    required String borrowerPeerId,
    required SimpleKeyPair borrowerKeyPair,
    required double requestedAmount,
    required int termWeeks,
    String? reason,
  }) async {
    if (requestedAmount <= 0) throw ArgumentError('Amount must be positive');
    if (termWeeks <= 0) throw ArgumentError('Term must be at least 1 week');
    final group = await _requireGroup(groupId);
    final problems = await eligibilityProblems(
      groupId: groupId, borrowerPeerId: borrowerPeerId, requestedAmount: requestedAmount);
    if (problems.isNotEmpty) throw LoanAuthorizationException(problems.join('\n'));

    var loan = LoanRequest(
      id: _uuid.v4(),
      groupId: groupId,
      borrowerPeerId: borrowerPeerId,
      requestedAmount: requestedAmount,
      interestRate: group.config.loanInterestRate,
      termWeeks: termWeeks,
      reason: reason,
      requestedAt: DateTime.now().toUtc(),
      borrowerSignature: Uint8List(0),
    );
    final sig = await SigningService.sign(requestSigningPayload(loan), borrowerKeyPair);
    loan = _copy(loan, borrowerSignature: Uint8List.fromList(sig.bytes));

    // Groups without loan approval auto-approve at the requested amount; the
    // borrower's own signature stands as the approval record.
    if (!group.config.requireLoanApproval) {
      loan = _copy(loan,
          status: LoanStatus.approved,
          approvedAmount: requestedAmount,
          approvedAt: DateTime.now().toUtc(),
          approvedByPeerId: borrowerPeerId);
      final aSig = await SigningService.sign(approvalSigningPayload(loan), borrowerKeyPair);
      loan = _copy(loan, approverSignature: Uint8List.fromList(aSig.bytes));
    }

    await _loanDao.insert(_toData(loan));
    return loan;
  }

  Future<LoanRequest> approveLoan({
    required String loanId,
    required double approvedAmount,
    required String approverPeerId,
    required SimpleKeyPair approverKeyPair,
  }) async {
    final data = await _loanDao.getById(loanId);
    if (data == null) throw StateError('Loan $loanId not found');
    var loan = _toModel(data);
    await _requireGroup(loan.groupId);
    await _requireActiveAdmin(loan.groupId, approverPeerId);
    if (approverPeerId == loan.borrowerPeerId) {
      throw const LoanAuthorizationException('You cannot approve your own loan');
    }
    if (loan.status != LoanStatus.pending) {
      throw LoanAuthorizationException('Loan is already ${loan.status.name}');
    }
    if (approvedAmount <= 0 || approvedAmount > loan.requestedAmount) {
      throw ArgumentError('Approved amount must be between 0 and the requested amount');
    }

    loan = _copy(loan,
        status: LoanStatus.approved,
        approvedAmount: approvedAmount,
        approvedAt: DateTime.now().toUtc(),
        approvedByPeerId: approverPeerId);
    final sig = await SigningService.sign(approvalSigningPayload(loan), approverKeyPair);
    loan = _copy(loan, approverSignature: Uint8List.fromList(sig.bytes));
    await _loanDao.update(_toData(loan));
    return loan;
  }

  Future<LoanRequest> rejectLoan({
    required String loanId,
    required String approverPeerId,
    required SimpleKeyPair approverKeyPair,
  }) async {
    final data = await _loanDao.getById(loanId);
    if (data == null) throw StateError('Loan $loanId not found');
    var loan = _toModel(data);
    await _requireActiveAdmin(loan.groupId, approverPeerId);
    if (loan.status != LoanStatus.pending) {
      throw LoanAuthorizationException('Loan is already ${loan.status.name}');
    }
    loan = _copy(loan,
        status: LoanStatus.rejected,
        approvedAt: DateTime.now().toUtc(),
        approvedByPeerId: approverPeerId);
    final sig = await SigningService.sign(approvalSigningPayload(loan), approverKeyPair);
    loan = _copy(loan, approverSignature: Uint8List.fromList(sig.bytes));
    await _loanDao.update(_toData(loan));
    return loan;
  }

  /// Disbursement (§15): records the loan transaction (group → borrower),
  /// generates the repayment schedule, flags the borrower.
  Future<LoanRequest> disburseLoan({
    required String loanId,
    required String adminPeerId,
    required SimpleKeyPair adminKeyPair,
  }) async {
    final data = await _loanDao.getById(loanId);
    if (data == null) throw StateError('Loan $loanId not found');
    var loan = _toModel(data);
    await _requireGroup(loan.groupId);
    await _requireActiveAdmin(loan.groupId, adminPeerId);
    if (loan.status != LoanStatus.approved) {
      throw LoanAuthorizationException('Only approved loans can be disbursed (loan is ${loan.status.name})');
    }

    await _transactionService.createTransaction(
      groupId: loan.groupId,
      authorPeerId: adminPeerId,
      authorKeyPair: adminKeyPair,
      fromPeerId: 'group',
      toPeerId: loan.borrowerPeerId,
      type: TransactionType.loan,
      amount: loan.approvedAmount,
      note: 'Loan disbursement',
      loanId: loan.id,
    );

    final disbursedAt = DateTime.now().toUtc();
    loan = _copy(loan, status: LoanStatus.disbursed, disbursedAt: disbursedAt);
    await _loanDao.update(_toData(loan));
    await _scheduleDao.deleteByLoanId(loan.id);
    await _scheduleDao.insertAll(buildSchedule(loan, from: disbursedAt));
    await _memberDao.updateLoanStatus(loan.borrowerPeerId, loan.groupId, true);
    return loan;
  }

  /// Equal weekly installments of (principal × (1 + rate)) / termWeeks.
  static List<RepaymentSchedule> buildSchedule(LoanRequest loan, {required DateTime from}) {
    final perWeek = loan.totalWithInterest / loan.termWeeks;
    final rounded = (perWeek * 100).round() / 100;
    final total = (loan.totalWithInterest * 100).round() / 100;
    return List.generate(loan.termWeeks, (i) {
      final n = i + 1;
      // Last installment absorbs rounding so the sum is exact.
      final amount = n == loan.termWeeks ? total - rounded * (loan.termWeeks - 1) : rounded;
      return RepaymentSchedule(
        id: '${loan.id}:$n',
        loanId: loan.id,
        installmentNumber: n,
        expectedAmount: (amount * 100).round() / 100,
        dueDate: from.add(Duration(days: 7 * n)),
      );
    });
  }

  /// Records a repayment (§15) authored by an admin on behalf of the borrower
  /// and applies it to the earliest unpaid installments. Returns the updated
  /// loan (status `repaying` or `completed`).
  Future<LoanRequest> recordRepayment({
    required String loanId,
    required String adminPeerId,
    required SimpleKeyPair adminKeyPair,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('Amount must be positive');
    final data = await _loanDao.getById(loanId);
    if (data == null) throw StateError('Loan $loanId not found');
    var loan = _toModel(data);
    await _requireGroup(loan.groupId);
    await _requireActiveAdmin(loan.groupId, adminPeerId);
    if (!loan.isActive) {
      throw LoanAuthorizationException('Loan is not open for repayment (${loan.status.name})');
    }

    await _transactionService.createTransaction(
      groupId: loan.groupId,
      authorPeerId: adminPeerId,
      authorKeyPair: adminKeyPair,
      fromPeerId: loan.borrowerPeerId,
      toPeerId: 'group',
      type: TransactionType.repayment,
      amount: amount,
      note: note ?? 'Loan repayment',
      loanId: loan.id,
    );
    return _applyRepaymentToSchedule(loan, amount);
  }

  /// Allocates [amount] across installments in order; used both for local
  /// repayments and when a repayment transaction arrives from a peer.
  Future<LoanRequest> _applyRepaymentToSchedule(LoanRequest loan, double amount) async {
    var remaining = amount;
    final now = DateTime.now().toUtc();
    final schedule = await _scheduleDao.getByLoanId(loan.id);
    for (final inst in schedule) {
      if (remaining <= 0) break;
      if (inst.isPaid) continue;
      final owed = inst.expectedAmount + inst.penalty - inst.paidAmount;
      final pay = remaining >= owed ? owed : remaining;
      remaining -= pay;
      final newPaid = inst.paidAmount + pay;
      final fullyPaid = newPaid + 0.005 >= inst.expectedAmount + inst.penalty;
      await _scheduleDao.upsert(RepaymentSchedule(
        id: inst.id,
        loanId: inst.loanId,
        installmentNumber: inst.installmentNumber,
        expectedAmount: inst.expectedAmount,
        dueDate: inst.dueDate,
        paidAmount: newPaid,
        paidAt: fullyPaid ? now : inst.paidAt,
        isOverdue: fullyPaid ? false : inst.isOverdue,
        penalty: inst.penalty,
        status: fullyPaid ? RepaymentStatus.paid : inst.status,
      ));
    }

    final after = await _scheduleDao.getByLoanId(loan.id);
    final allPaid = after.isNotEmpty && after.every((s) => s.isPaid);
    var updated = _copy(loan,
        status: allPaid ? LoanStatus.completed : LoanStatus.repaying,
        completedAt: allPaid ? now : loan.completedAt);
    await _loanDao.update(_toData(updated));
    if (allPaid) await _memberDao.updateLoanStatus(loan.borrowerPeerId, loan.groupId, false);
    return updated;
  }

  /// Called when a repayment transaction is imported from a peer.
  Future<void> applyRemoteRepayment(String loanId, double amount) async {
    final data = await _loanDao.getById(loanId);
    if (data == null) return;
    final loan = _toModel(data);
    if (!loan.isActive) return;
    await _applyRepaymentToSchedule(loan, amount);
  }

  /// Marks overdue installments, applies the late penalty once per
  /// installment (§15: `latePenaltyRate × expectedAmount`) and defaults loans
  /// with an installment more than [defaultAfter] overdue. Idempotent; run on
  /// app start / sync / screen open.
  Future<void> refreshOverdue(String groupId) async {
    final group = await _groupService.getGroup(groupId);
    if (group == null) return;
    final now = DateTime.now().toUtc();
    for (final data in await _loanDao.getByGroupId(groupId)) {
      final loan = _toModel(data);
      if (!loan.isActive) continue;
      var defaulted = false;
      for (final inst in await _scheduleDao.getByLoanId(loan.id)) {
        if (inst.isPaid || !now.isAfter(inst.dueDate)) continue;
        if (!inst.isOverdue) {
          final penalty = (inst.expectedAmount * group.config.latePenaltyRate * 100).round() / 100;
          await _scheduleDao.upsert(RepaymentSchedule(
            id: inst.id,
            loanId: inst.loanId,
            installmentNumber: inst.installmentNumber,
            expectedAmount: inst.expectedAmount,
            dueDate: inst.dueDate,
            paidAmount: inst.paidAmount,
            paidAt: inst.paidAt,
            isOverdue: true,
            penalty: penalty,
            status: RepaymentStatus.overdue,
          ));
        }
        if (now.difference(inst.dueDate) > defaultAfter) defaulted = true;
      }
      if (defaulted) {
        await _loanDao.update(_toData(_copy(loan, status: LoanStatus.defaulted, defaultedAt: now)));
      }
    }
  }

  /// Applies a loan record from a peer after the sync layer verified the
  /// borrower/approver signatures against the roster.
  Future<void> importRemote(LoanRequest incoming) async {
    final existing = await _loanDao.getById(incoming.id);
    if (existing == null) {
      await _loanDao.insert(_toData(incoming));
    } else {
      // Status only moves forward.
      final order = LoanStatus.values;
      final localIdx = order.indexWhere((s) => s.name == existing.status);
      if (incoming.status.index <= localIdx) return;
      await _loanDao.update(_toData(incoming));
    }
    if (incoming.status == LoanStatus.disbursed || incoming.status == LoanStatus.repaying) {
      if ((await _scheduleDao.getByLoanId(incoming.id)).isEmpty && incoming.disbursedAt != null) {
        await _scheduleDao.insertAll(buildSchedule(incoming, from: incoming.disbursedAt!));
      }
      await _memberDao.updateLoanStatus(incoming.borrowerPeerId, incoming.groupId, true);
    }
    if (incoming.status == LoanStatus.completed || incoming.status == LoanStatus.defaulted) {
      await _memberDao.updateLoanStatus(incoming.borrowerPeerId, incoming.groupId, false);
    }
  }

  // --- queries -----------------------------------------------------------------------

  Future<LoanRequest?> getById(String id) async {
    final data = await _loanDao.getById(id);
    return data == null ? null : _toModel(data);
  }

  Future<List<LoanRequest>> getByGroupId(String groupId) async =>
      (await _loanDao.getByGroupId(groupId)).map(_toModel).toList();

  Future<List<RepaymentSchedule>> schedule(String loanId) => _scheduleDao.getByLoanId(loanId);

  // --- mapping -----------------------------------------------------------------------

  LoanRequest _toModel(LoanData d) => LoanRequest(
        id: d.id,
        groupId: d.groupId,
        borrowerPeerId: d.borrowerPeerId,
        requestedAmount: d.requestedAmount,
        approvedAmount: d.approvedAmount ?? 0,
        interestRate: d.interestRate,
        termWeeks: d.termWeeks,
        reason: d.reason,
        status: LoanStatus.values.firstWhere((s) => s.name == d.status, orElse: () => LoanStatus.pending),
        requestedAt: d.requestedAt,
        approvedAt: d.approvedAt,
        approvedByPeerId: d.approvedByPeerId,
        disbursedAt: d.disbursedAt,
        completedAt: d.completedAt,
        defaultedAt: d.defaultedAt,
        borrowerSignature: d.borrowerSignature,
        approverSignature: d.approverSignature,
      );

  LoanData _toData(LoanRequest l) => LoanData(
        id: l.id,
        groupId: l.groupId,
        borrowerPeerId: l.borrowerPeerId,
        requestedAmount: l.requestedAmount,
        approvedAmount: l.approvedAmount,
        interestRate: l.interestRate,
        termWeeks: l.termWeeks,
        reason: l.reason,
        status: l.status.name,
        requestedAt: l.requestedAt,
        approvedAt: l.approvedAt,
        approvedByPeerId: l.approvedByPeerId,
        disbursedAt: l.disbursedAt,
        completedAt: l.completedAt,
        defaultedAt: l.defaultedAt,
        borrowerSignature: l.borrowerSignature,
        approverSignature: l.approverSignature,
      );

  static LoanRequest _copy(
    LoanRequest l, {
    LoanStatus? status,
    double? approvedAmount,
    DateTime? approvedAt,
    String? approvedByPeerId,
    DateTime? disbursedAt,
    DateTime? completedAt,
    DateTime? defaultedAt,
    Uint8List? borrowerSignature,
    Uint8List? approverSignature,
  }) =>
      LoanRequest(
        id: l.id,
        groupId: l.groupId,
        borrowerPeerId: l.borrowerPeerId,
        requestedAmount: l.requestedAmount,
        approvedAmount: approvedAmount ?? l.approvedAmount,
        interestRate: l.interestRate,
        termWeeks: l.termWeeks,
        reason: l.reason,
        status: status ?? l.status,
        requestedAt: l.requestedAt,
        approvedAt: approvedAt ?? l.approvedAt,
        approvedByPeerId: approvedByPeerId ?? l.approvedByPeerId,
        disbursedAt: disbursedAt ?? l.disbursedAt,
        completedAt: completedAt ?? l.completedAt,
        defaultedAt: defaultedAt ?? l.defaultedAt,
        borrowerSignature: borrowerSignature ?? l.borrowerSignature,
        approverSignature: approverSignature ?? l.approverSignature,
      );
}
