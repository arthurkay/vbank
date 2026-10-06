import 'core/failure.dart';
import 'core/result.dart';

/// A closed date range a report covers.
final class DateTimePeriod {
  /// First instant included.
  final DateTime start;

  /// Last instant included.
  final DateTime end;

  /// Creates a period.
  const DateTimePeriod({required this.start, required this.end});

  /// Length of the period.
  Duration get duration => end.difference(start);

  /// Structural check: [end] must not precede [start].
  Result<Unit> validate() {
    if (end.isBefore(start)) {
      return const Err(ValidationFailure('periodEndBeforeStart'));
    }
    return const Ok(unit);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateTimePeriod && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// One member's totals inside a [GroupReport].
final class MemberStatement {
  /// Whose statement this is.
  final String peerId;

  /// Their display name at report time.
  final String memberName;

  /// Paid in over the period.
  final double totalContributed;

  /// Borrowed over the period.
  final double totalLoaned;

  /// Repaid over the period.
  final double totalRepaid;

  /// Still owed at period end.
  final double outstandingBalance;

  /// Creates a member statement.
  const MemberStatement({
    required this.peerId,
    required this.memberName,
    required this.totalContributed,
    required this.totalLoaned,
    required this.totalRepaid,
    required this.outstandingBalance,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberStatement &&
          peerId == other.peerId &&
          memberName == other.memberName &&
          totalContributed == other.totalContributed &&
          totalLoaned == other.totalLoaned &&
          totalRepaid == other.totalRepaid &&
          outstandingBalance == other.outstandingBalance;

  @override
  int get hashCode => Object.hash(
        peerId,
        memberName,
        totalContributed,
        totalLoaned,
        totalRepaid,
        outstandingBalance,
      );
}

/// A group's finances over a [period], with a per-member breakdown.
final class GroupReport {
  /// The group reported on.
  final String groupId;

  /// The range covered.
  final DateTimePeriod period;

  /// Contributions recorded in range.
  final double totalContributions;

  /// Loans paid out in range.
  final double totalLoansDisbursed;

  /// Repayments collected in range.
  final double totalLoansRepaid;

  /// Penalties charged in range.
  final double totalPenalties;

  /// Fund balance at period end.
  final double groupFundBalance;

  /// Meetings held in range.
  final int totalMeetings;

  /// Transactions recorded in range.
  final int totalTransactions;

  /// One entry per member.
  final List<MemberStatement> memberStatements;

  /// Creates a group report.
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

  /// Net movement over the period, mirroring the legacy computation.
  double get netFundChange =>
      totalContributions +
      totalLoansRepaid -
      totalLoansDisbursed -
      totalPenalties;

  static bool _statementsEqual(
    List<MemberStatement> a,
    List<MemberStatement> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupReport &&
          groupId == other.groupId &&
          period == other.period &&
          totalContributions == other.totalContributions &&
          totalLoansDisbursed == other.totalLoansDisbursed &&
          totalLoansRepaid == other.totalLoansRepaid &&
          totalPenalties == other.totalPenalties &&
          groupFundBalance == other.groupFundBalance &&
          totalMeetings == other.totalMeetings &&
          totalTransactions == other.totalTransactions &&
          _statementsEqual(memberStatements, other.memberStatements);

  @override
  int get hashCode => Object.hash(
        groupId,
        period,
        totalContributions,
        totalLoansDisbursed,
        totalLoansRepaid,
        totalPenalties,
        groupFundBalance,
        totalMeetings,
        totalTransactions,
        Object.hashAll(memberStatements),
      );
}
