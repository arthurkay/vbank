import '../../domain/balance.dart';
import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import 'dto.dart';

/// Row mapping for `balances`.
abstract final class BalanceDto {
  /// Serializes [balance] to a `balances` row.
  static Map<String, Object?> toRow(Balance balance) => {
        'peer_id': balance.peerId,
        'group_id': balance.groupId,
        'total_contributed': balance.totalContributed,
        'total_loaned': balance.totalLoaned,
        'total_repaid': balance.totalRepaid,
        'total_withdrawn': balance.totalWithdrawn,
        'total_penalties': balance.totalPenalties,
        'outstanding_loan': balance.outstandingLoan,
        'net_balance': balance.netBalance,
        'last_updated': Dto.instantValue(balance.lastUpdated),
      };

  /// Parses a `balances` row.
  static Result<Balance> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        Balance(
          peerId: Dto.text(row, 'peer_id'),
          groupId: Dto.text(row, 'group_id'),
          totalContributed: Dto.real(row, 'total_contributed'),
          totalLoaned: Dto.real(row, 'total_loaned'),
          totalRepaid: Dto.real(row, 'total_repaid'),
          totalWithdrawn: Dto.real(row, 'total_withdrawn'),
          totalPenalties: Dto.real(row, 'total_penalties'),
          outstandingLoan: Dto.real(row, 'outstanding_loan'),
          netBalance: Dto.real(row, 'net_balance'),
          lastUpdated: Dto.instant(row, 'last_updated'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
