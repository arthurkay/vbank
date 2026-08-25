import '../models/report.dart';
import '../core/storage/transaction_dao.dart';
import '../core/storage/meeting_dao.dart';
import '../core/storage/balance_dao.dart';

class ReportService {
  final TransactionDao _transactionDao = TransactionDao();
  final MeetingDao _meetingDao = MeetingDao();
  final BalanceDao _balanceDao = BalanceDao();

  Future<GroupReport> generateGroupReport({
    required String groupId,
    required DateTimePeriod period,
  }) async {
    final transactions = await _transactionDao.getByGroupId(groupId);
    final meetings = await _meetingDao.getByGroupId(groupId);
    final balances = await _balanceDao.getByGroupId(groupId);

    final periodTransactions = transactions.where((t) =>
        t.timestamp.isAfter(period.start) &&
        t.timestamp.isBefore(period.end)).toList();

    double totalContributions = 0;
    double totalLoansDisbursed = 0;
    double totalLoansRepaid = 0;
    double totalPenalties = 0;

    for (final tx in periodTransactions) {
      switch (tx.type) {
        case 'contribution':
          totalContributions += tx.amount;
          break;
        case 'loan':
          totalLoansDisbursed += tx.amount;
          break;
        case 'repayment':
          totalLoansRepaid += tx.amount;
          break;
        case 'penalty':
          totalPenalties += tx.amount;
          break;
        default:
          break;
      }
    }

    final periodMeetings = meetings.where((m) =>
        m.scheduledAt.isAfter(period.start) &&
        m.scheduledAt.isBefore(period.end)).length;

    final groupFundBalance = balances.fold(
      0.0,
      (sum, b) => sum + b.netBalance,
    );

    final memberStatements = <MemberStatement>[];
    for (final balance in balances) {
      memberStatements.add(MemberStatement(
        peerId: balance.peerId,
        memberName: balance.peerId,
        totalContributed: balance.totalContributed,
        totalLoaned: balance.totalLoaned,
        totalRepaid: balance.totalRepaid,
        outstandingBalance: balance.outstandingLoan,
      ));
    }

    return GroupReport(
      groupId: groupId,
      period: period,
      totalContributions: totalContributions,
      totalLoansDisbursed: totalLoansDisbursed,
      totalLoansRepaid: totalLoansRepaid,
      totalPenalties: totalPenalties,
      groupFundBalance: groupFundBalance,
      totalMeetings: periodMeetings,
      totalTransactions: periodTransactions.length,
      memberStatements: memberStatements,
    );
  }
}
