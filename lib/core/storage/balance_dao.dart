import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class BalanceDao {
  Future<void> upsert(BalanceData balance) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'balances',
      balance.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<BalanceData?> get(String peerId, String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'balances',
      where: 'peer_id = ? AND group_id = ?',
      whereArgs: [peerId, groupId],
    );
    if (result.isEmpty) return null;
    return BalanceData.fromMap(result.first);
  }

  Future<List<BalanceData>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'balances',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    return result.map((map) => BalanceData.fromMap(map)).toList();
  }

  /// Creates a zeroed balance row if none exists. The UPDATE statements below
  /// match zero rows otherwise, silently dropping the movement.
  Future<void> ensureExists(String peerId, String groupId) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'balances',
      BalanceData(
        peerId: peerId,
        groupId: groupId,
        lastUpdated: DateTime.now().toUtc(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateContribution(String peerId, String groupId, double amount) async {
    await ensureExists(peerId, groupId);
    final db = await AppDatabase.getInstance();
    await db.rawUpdate('''
      UPDATE balances 
      SET total_contributed = total_contributed + ?,
          net_balance = net_balance + ?,
          last_updated = ?
      WHERE peer_id = ? AND group_id = ?
    ''', [amount, amount, DateTime.now().millisecondsSinceEpoch, peerId, groupId]);
  }

  Future<void> updateLoan(String peerId, String groupId, double amount) async {
    await ensureExists(peerId, groupId);
    final db = await AppDatabase.getInstance();
    await db.rawUpdate('''
      UPDATE balances 
      SET total_loaned = total_loaned + ?,
          outstanding_loan = outstanding_loan + ?,
          net_balance = net_balance - ?,
          last_updated = ?
      WHERE peer_id = ? AND group_id = ?
    ''', [amount, amount, amount, DateTime.now().millisecondsSinceEpoch, peerId, groupId]);
  }

  Future<void> updatePenalty(String peerId, String groupId, double amount) async {
    await ensureExists(peerId, groupId);
    final db = await AppDatabase.getInstance();
    await db.rawUpdate('''
      UPDATE balances
      SET total_penalties = total_penalties + ?,
          net_balance = net_balance - ?,
          last_updated = ?
      WHERE peer_id = ? AND group_id = ?
    ''', [amount, amount, DateTime.now().millisecondsSinceEpoch, peerId, groupId]);
  }

  Future<void> updateWithdrawal(String peerId, String groupId, double amount) async {
    await ensureExists(peerId, groupId);
    final db = await AppDatabase.getInstance();
    await db.rawUpdate('''
      UPDATE balances
      SET total_withdrawn = total_withdrawn + ?,
          net_balance = net_balance - ?,
          last_updated = ?
      WHERE peer_id = ? AND group_id = ?
    ''', [amount, amount, DateTime.now().millisecondsSinceEpoch, peerId, groupId]);
  }

  Future<void> updateRepayment(String peerId, String groupId, double amount) async {
    await ensureExists(peerId, groupId);
    final db = await AppDatabase.getInstance();
    await db.rawUpdate('''
      UPDATE balances 
      SET total_repaid = total_repaid + ?,
          outstanding_loan = outstanding_loan - ?,
          net_balance = net_balance + ?,
          last_updated = ?
      WHERE peer_id = ? AND group_id = ?
    ''', [amount, amount, amount, DateTime.now().millisecondsSinceEpoch, peerId, groupId]);
  }
}

class BalanceData {
  final String peerId;
  final String groupId;
  final double totalContributed;
  final double totalLoaned;
  final double totalRepaid;
  final double totalWithdrawn;
  final double totalPenalties;
  final double outstandingLoan;
  final double netBalance;
  final DateTime lastUpdated;

  const BalanceData({
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

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'group_id': groupId,
    'total_contributed': totalContributed,
    'total_loaned': totalLoaned,
    'total_repaid': totalRepaid,
    'total_withdrawn': totalWithdrawn,
    'total_penalties': totalPenalties,
    'outstanding_loan': outstandingLoan,
    'net_balance': netBalance,
    'last_updated': lastUpdated.millisecondsSinceEpoch,
  };

  factory BalanceData.fromMap(Map<String, dynamic> map) => BalanceData(
    peerId: map['peer_id'] as String,
    groupId: map['group_id'] as String,
    totalContributed: (map['total_contributed'] as num).toDouble(),
    totalLoaned: (map['total_loaned'] as num).toDouble(),
    totalRepaid: (map['total_repaid'] as num).toDouble(),
    totalWithdrawn: (map['total_withdrawn'] as num).toDouble(),
    totalPenalties: (map['total_penalties'] as num).toDouble(),
    outstandingLoan: (map['outstanding_loan'] as num).toDouble(),
    netBalance: (map['net_balance'] as num).toDouble(),
    lastUpdated: DateTime.fromMillisecondsSinceEpoch(map['last_updated'] as int),
  );
}
