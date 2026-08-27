import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ipfs/sync_manager.dart';
import '../models/loan.dart';
import '../models/loan_progress.dart';
import '../models/repayment_schedule.dart';
import '../services/loan_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart' show groupServiceProvider;
import 'ipfs_provider.dart';
import 'notification_provider.dart';
import 'data_version.dart';
import 'transaction_provider.dart' show transactionServiceProvider, syncTickProvider;

final loanServiceProvider = Provider<LoanService>((ref) {
  return LoanService(
    groupService: ref.watch(groupServiceProvider),
    transactionService: ref.watch(transactionServiceProvider),
  );
});

class LoanListNotifier extends StateNotifier<AsyncValue<List<LoanRequest>>> {
  final Ref _ref;
  final LoanService _service;
  final String groupId;
  StreamSubscription<SyncChange>? _changesSub;

  LoanListNotifier(this._ref, this._service, this.groupId) : super(const AsyncValue.loading()) {
    loadLoans();
    _changesSub = _ref.read(syncManagerProvider).changes.listen((change) {
      if (change.groupId == groupId &&
          (change.type == SyncChangeType.loan || change.type == SyncChangeType.transaction)) {
        loadLoans();
      }
    });
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> loadLoans() async {
    state = const AsyncValue.loading();
    try {
      await _service.refreshOverdue(groupId);
      state = AsyncValue.data(await _service.getByGroupId(groupId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _publish(LoanRequest loan) async {
    try {
      await _ref.read(syncManagerProvider).publishLoan(loan);
    } catch (_) {}
  }

  Future<List<String>> eligibilityProblems(double amount) async {
    final me = _ref.read(authProvider.notifier).requireIdentity().peerId;
    return _service.eligibilityProblems(groupId: groupId, borrowerPeerId: me, requestedAmount: amount);
  }

  Future<LoanRequest> requestLoan({
    required double requestedAmount,
    required int termWeeks,
    String? reason,
  }) async {
    final auth = _ref.read(authProvider.notifier);
    final identity = auth.requireIdentity();
    final keyPair = await auth.requireSigningKeyPair();
    final loan = await _service.requestLoan(
      groupId: groupId,
      borrowerPeerId: identity.peerId,
      borrowerKeyPair: keyPair,
      requestedAmount: requestedAmount,
      termWeeks: termWeeks,
      reason: reason,
    );
    await loadLoans();
    bumpDataVersion(_ref);
    unawaited(_publish(loan));
    return loan;
  }

  Future<void> approveLoan({required String loanId, required double approvedAmount}) async {
    final auth = _ref.read(authProvider.notifier);
    final loan = await _service.approveLoan(
      loanId: loanId,
      approvedAmount: approvedAmount,
      approverPeerId: auth.requireIdentity().peerId,
      approverKeyPair: await auth.requireSigningKeyPair(),
    );
    await loadLoans();
    bumpDataVersion(_ref);
    unawaited(_publish(loan));
  }

  Future<void> rejectLoan({required String loanId}) async {
    final auth = _ref.read(authProvider.notifier);
    final loan = await _service.rejectLoan(
      loanId: loanId,
      approverPeerId: auth.requireIdentity().peerId,
      approverKeyPair: await auth.requireSigningKeyPair(),
    );
    await loadLoans();
    bumpDataVersion(_ref);
    unawaited(_publish(loan));
  }

  Future<void> disburseLoan({required String loanId}) async {
    final auth = _ref.read(authProvider.notifier);
    final loan = await _service.disburseLoan(
      loanId: loanId,
      adminPeerId: auth.requireIdentity().peerId,
      adminKeyPair: await auth.requireSigningKeyPair(),
    );
    await loadLoans();
    bumpDataVersion(_ref);
    unawaited(_publish(loan));
    unawaited(_ref.read(syncManagerProvider).startManualSync());
    // Repayment reminders for the borrower's own device happen when the loan
    // arrives there; here we schedule for the local user if they are the borrower.
    final group = await _ref.read(groupServiceProvider).getGroup(groupId);
    if (group != null && loan.borrowerPeerId == auth.requireIdentity().peerId) {
      final schedule = await _service.schedule(loanId);
      await _ref.read(notificationSchedulerProvider).scheduleForLoan(
        loanId: loanId,
        groupId: groupId,
        groupName: group.name,
        currency: group.config.currency,
        installments: schedule.map((s) => (number: s.installmentNumber, amount: s.expectedAmount, dueDate: s.dueDate)).toList(),
      );
    }
  }

  Future<void> recordRepayment({required String loanId, required double amount, String? note}) async {
    final auth = _ref.read(authProvider.notifier);
    final loan = await _service.recordRepayment(
      loanId: loanId,
      adminPeerId: auth.requireIdentity().peerId,
      adminKeyPair: await auth.requireSigningKeyPair(),
      amount: amount,
      note: note,
    );
    await loadLoans();
    bumpDataVersion(_ref);
    unawaited(_publish(loan));
    unawaited(_ref.read(syncManagerProvider).startManualSync());
  }

  Future<void> refresh() => loadLoans();
}

final loanListProvider =
    StateNotifierProvider.family<LoanListNotifier, AsyncValue<List<LoanRequest>>, String>((ref, groupId) {
  return LoanListNotifier(ref, ref.watch(loanServiceProvider), groupId);
});

final loanScheduleProvider = FutureProvider.family<List<RepaymentSchedule>, String>((ref, loanId) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider); // local approve/disburse/repay
  return ref.watch(loanServiceProvider).schedule(loanId);
});

final loanProvider = FutureProvider.family<LoanRequest?, String>((ref, loanId) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider); // local approve/disburse/repay
  return ref.watch(loanServiceProvider).getById(loanId);
});

/// Repayment progress for every loan in a group, keyed by loan id.
final groupLoanProgressProvider = FutureProvider.family<Map<String, LoanProgress>, String>((ref, groupId) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider);
  final loans = await ref.watch(loanServiceProvider).getByGroupId(groupId);
  final txs = await ref.watch(transactionServiceProvider).getByGroupId(groupId);
  return LoanProgress.forGroup(loans, txs);
});

/// Repayment progress for one loan (null when the loan is unknown).
final loanProgressProvider = FutureProvider.family<LoanProgress?, String>((ref, loanId) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider);
  final loan = await ref.watch(loanServiceProvider).getById(loanId);
  if (loan == null) return null;
  final progress = await ref.watch(groupLoanProgressProvider(loan.groupId).future);
  return progress[loanId];
});

/// Cash available to lend vs principal out on loan, per group.
final groupFundProvider = FutureProvider.family<GroupFund, String>((ref, groupId) async {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider);
  final loans = await ref.watch(loanServiceProvider).getByGroupId(groupId);
  final txs = await ref.watch(transactionServiceProvider).getByGroupId(groupId);
  return GroupFund.compute(txs, loans);
});
