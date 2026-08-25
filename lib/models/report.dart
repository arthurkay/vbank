class GroupReport {
  final String groupId;
  final DateTimePeriod period;
  final double totalContributions;
  final double totalLoansDisbursed;
  final double totalLoansRepaid;
  final double totalPenalties;
  final double groupFundBalance;
  final int totalMeetings;
  final int totalTransactions;
  final List<MemberStatement> memberStatements;

  const GroupReport({
    required this.groupId,
    required this.period,
    required this.totalContributions,
    required this.totalLoansDisbursed,
    required this.totalLoansRepaid,
    required this.totalPenalties,
    required this.groupFundBalance,
    required this.totalMeetings,
    required this.totalTransactions,
    required this.memberStatements,
  });

  double get netFundChange => totalContributions + totalLoansRepaid - totalLoansDisbursed - totalPenalties;
}

class DateTimePeriod {
  final DateTime start;
  final DateTime end;

  const DateTimePeriod({required this.start, required this.end});

  Duration get duration => end.difference(start);
}

class MemberStatement {
  final String peerId;
  final String memberName;
  final double totalContributed;
  final double totalLoaned;
  final double totalRepaid;
  final double outstandingBalance;

  const MemberStatement({
    required this.peerId,
    required this.memberName,
    required this.totalContributed,
    required this.totalLoaned,
    required this.totalRepaid,
    required this.outstandingBalance,
  });
}
