import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/balance.dart';
import '../../domain/loans.dart';
import '../../domain/meetings.dart';
import '../../domain/transactions.dart';
import '../app_scope.dart';

/// A group's ledger, oldest first, live.
final transactionsProvider =
    StreamProvider.family<List<Transaction>, String>((ref, groupId) {
  final transactions = ref.watch(appRepositoriesProvider).transactions;
  return transactions.watchByGroup(groupId);
});

/// A group's balance snapshots, live.
final balancesProvider =
    StreamProvider.family<List<Balance>, String>((ref, groupId) {
  final balances = ref.watch(appRepositoriesProvider).balances;
  return balances.watchByGroup(groupId);
});

/// A group's loans, newest first, live.
final loanListProvider =
    StreamProvider.family<List<LoanRequest>, String>((ref, groupId) {
  final loans = ref.watch(appRepositoriesProvider).loans;
  return loans.watchByGroup(groupId);
});

/// A group's meetings, newest first, live.
final meetingListProvider =
    StreamProvider.family<List<Meeting>, String>((ref, groupId) {
  final meetings = ref.watch(appRepositoriesProvider).meetings;
  return meetings.watchByGroup(groupId);
});

/// Where the group's money is, recomputed whenever the ledger or the
/// loans change.
final fundProvider = FutureProvider.family<GroupFund, String>(
  (ref, groupId) async {
    final List<Transaction> transactions =
        await ref.watch(transactionsProvider(groupId).future);
    final List<LoanRequest> loans =
        await ref.watch(loanListProvider(groupId).future);
    return GroupFund.compute(transactions, loans);
  },
);

/// One loan's schedule, instalment order.
final scheduleProvider =
    FutureProvider.family<List<RepaymentSchedule>, String>(
  (ref, loanId) => ref
      .watch(appServicesProvider)
      .loans.schedule(loanId)
      .then((r) => r.value),
);
