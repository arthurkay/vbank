import '../domain/balance.dart';
import '../domain/core/result.dart';
import '../domain/group.dart';
import '../domain/meetings.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../domain/reports.dart';
import '../domain/transactions.dart';

/// Read-only statements: a group's finances over a period with a
/// per-member breakdown. Sums mirror the legacy report exactly.
final class ReportService {
  /// Ledger reads.
  final TransactionRepository transactions;

  /// Meeting reads.
  final MeetingRepository meetings;

  /// Snapshot reads.
  final BalanceRepository balances;

  /// Groups (member names).
  final GroupRepository groups;

  /// Creates a report service.
  ReportService({
    required this.transactions,
    required this.meetings,
    required this.balances,
    required this.groups,
  });

  /// Builds the statement for [groupId] over [period].
  Future<Result<GroupReport>> generateGroupReport({
    required String groupId,
    required DateTimePeriod period,
  }) async {
    final Result<List<Transaction>> txs = await transactions.listByGroup(
      groupId,
    );
    if (txs.isErr) {
      return Err(txs.failure);
    }
    final Result<List<Meeting>> all = await meetings.listByGroup(groupId);
    if (all.isErr) {
      return Err(all.failure);
    }
    final Result<List<Balance>> snapshots = await balances.listByGroup(
      groupId,
    );
    if (snapshots.isErr) {
      return Err(snapshots.failure);
    }
    final Result<Group> group = await groups.findById(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    final Map<String, String> names = {
      for (final Member m in group.value.members) m.peerId: m.name,
    };

    final List<Transaction> inPeriod = txs.value
        .where(
          (Transaction t) =>
              t.timestamp.isAfter(period.start) &&
              t.timestamp.isBefore(period.end),
        )
        .toList();
    var contributions = 0.0;
    var disbursed = 0.0;
    var repaid = 0.0;
    var penalties = 0.0;
    for (final Transaction t in inPeriod) {
      switch (t.type) {
        case TransactionType.contribution:
          contributions += t.amount;
        case TransactionType.loan:
          disbursed += t.amount;
        case TransactionType.repayment:
          repaid += t.amount;
        case TransactionType.penalty:
          penalties += t.amount;
        case TransactionType.fee:
        case TransactionType.withdrawal:
        case TransactionType.reversal:
          break;
      }
    }
    final int meetingCount = all.value
        .where(
          (Meeting m) =>
              m.scheduledAt.isAfter(period.start) &&
              m.scheduledAt.isBefore(period.end),
        )
        .length;
    var fundBalance = 0.0;
    for (final Balance b in snapshots.value) {
      fundBalance += b.netBalance;
    }
    return Ok(
      GroupReport(
        groupId: groupId,
        period: period,
        totalContributions: contributions,
        totalLoansDisbursed: disbursed,
        totalLoansRepaid: repaid,
        totalPenalties: penalties,
        groupFundBalance: fundBalance,
        totalMeetings: meetingCount,
        totalTransactions: inPeriod.length,
        memberStatements: [
          for (final Balance b in snapshots.value)
            MemberStatement(
              peerId: b.peerId,
              memberName: names[b.peerId] ?? 'Former member',
              totalContributed: b.totalContributed,
              totalLoaned: b.totalLoaned,
              totalRepaid: b.totalRepaid,
              outstandingBalance: b.outstandingLoan,
            ),
        ],
      ),
    );
  }
}
