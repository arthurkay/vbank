import '../core/storage/balance_dao.dart';
import '../models/balance.dart';

class BalanceService {
  final BalanceDao _balanceDao = BalanceDao();

  Future<Balance?> getBalance(String peerId, String groupId) async {
    final data = await _balanceDao.get(peerId, groupId);
    if (data == null) return null;
    return _toModel(data);
  }

  Future<List<Balance>> getByGroupId(String groupId) async {
    final data = await _balanceDao.getByGroupId(groupId);
    return data.map(_toModel).toList();
  }

  Future<void> initializeBalance({
    required String peerId,
    required String groupId,
  }) async {
    final existing = await _balanceDao.get(peerId, groupId);
    if (existing != null) return;

    await _balanceDao.upsert(BalanceData(
      peerId: peerId,
      groupId: groupId,
      lastUpdated: DateTime.now().toUtc(),
    ));
  }

  Balance _toModel(BalanceData data) => Balance(
    peerId: data.peerId,
    groupId: data.groupId,
    totalContributed: data.totalContributed,
    totalLoaned: data.totalLoaned,
    totalRepaid: data.totalRepaid,
    totalWithdrawn: data.totalWithdrawn,
    totalPenalties: data.totalPenalties,
    outstandingLoan: data.outstandingLoan,
    netBalance: data.netBalance,
    lastUpdated: data.lastUpdated,
  );
}
