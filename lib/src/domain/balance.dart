import 'core/failure.dart';
import 'core/result.dart';

/// One member's running totals in one group.
///
/// Balances are computed by the application layer from the transaction log
/// and cached for display; this entity is the snapshot shape both use.
final class Balance {
  /// Whose balance this is.
  final String peerId;

  /// Which group's fund it is measured against.
  final String groupId;

  /// Paid in, all time.
  final double totalContributed;

  /// Borrowed, all time.
  final double totalLoaned;

  /// Repaid, all time.
  final double totalRepaid;

  /// Taken out, all time.
  final double totalWithdrawn;

  /// Penalties charged, all time.
  final double totalPenalties;

  /// Still owed right now.
  final double outstandingLoan;

  /// Contributed minus withdrawn, adjusted for loans.
  final double netBalance;

  /// When the snapshot was computed.
  final DateTime lastUpdated;

  /// Creates a balance snapshot.
  const Balance({
    required this.peerId,
    required this.groupId,
    this.totalContributed = 0,
    this.totalLoaned = 0,
    this.totalRepaid = 0,
    this.totalWithdrawn = 0,
    this.totalPenalties = 0,
    this.outstandingLoan = 0,
    this.netBalance = 0,
    required this.lastUpdated,
  });

  /// What the member could still borrow against: net minus owed.
  double get availableBalance => netBalance - outstandingLoan;

  /// Structural checks: identifiers present.
  Result<Unit> validate() {
    if (peerId.isEmpty) {
      return const Err(ValidationFailure('balancePeerIdEmpty'));
    }
    if (groupId.isEmpty) {
      return const Err(ValidationFailure('balanceGroupEmpty'));
    }
    return const Ok(unit);
  }

  /// Copies this snapshot, replacing the given fields.
  Balance copyWith({
    double? totalContributed,
    double? totalLoaned,
    double? totalRepaid,
    double? totalWithdrawn,
    double? totalPenalties,
    double? outstandingLoan,
    double? netBalance,
    DateTime? lastUpdated,
  }) =>
      Balance(
        peerId: peerId,
        groupId: groupId,
        totalContributed: totalContributed ?? this.totalContributed,
        totalLoaned: totalLoaned ?? this.totalLoaned,
        totalRepaid: totalRepaid ?? this.totalRepaid,
        totalWithdrawn: totalWithdrawn ?? this.totalWithdrawn,
        totalPenalties: totalPenalties ?? this.totalPenalties,
        outstandingLoan: outstandingLoan ?? this.outstandingLoan,
        netBalance: netBalance ?? this.netBalance,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Balance &&
          peerId == other.peerId &&
          groupId == other.groupId &&
          totalContributed == other.totalContributed &&
          totalLoaned == other.totalLoaned &&
          totalRepaid == other.totalRepaid &&
          totalWithdrawn == other.totalWithdrawn &&
          totalPenalties == other.totalPenalties &&
          outstandingLoan == other.outstandingLoan &&
          netBalance == other.netBalance &&
          lastUpdated == other.lastUpdated;

  @override
  int get hashCode => Object.hash(
        peerId,
        groupId,
        totalContributed,
        totalLoaned,
        totalRepaid,
        totalWithdrawn,
        totalPenalties,
        outstandingLoan,
        netBalance,
        lastUpdated,
      );
}
