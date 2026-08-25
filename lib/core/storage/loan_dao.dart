import 'dart:typed_data';
import 'database.dart';

class LoanDao {
  Future<void> insert(LoanData loan) async {
    final db = await AppDatabase.getInstance();
    await db.insert('loans', loan.toMap());
  }

  Future<LoanData?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('loans', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return LoanData.fromMap(result.first);
  }

  Future<List<LoanData>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'loans',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'requested_at DESC',
    );
    return result.map((map) => LoanData.fromMap(map)).toList();
  }

  Future<void> update(LoanData loan) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'loans',
      loan.toMap(),
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'loans',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class LoanData {
  final String id;
  final String groupId;
  final String borrowerPeerId;
  final double requestedAmount;
  final double? approvedAmount;
  final double interestRate;
  final int termWeeks;
  final String? reason;
  final String status;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final String? approvedByPeerId;
  final DateTime? disbursedAt;
  final DateTime? completedAt;
  final DateTime? defaultedAt;
  final Uint8List borrowerSignature;
  final Uint8List? approverSignature;

  const LoanData({
    required this.id,
    required this.groupId,
    required this.borrowerPeerId,
    required this.requestedAmount,
    this.approvedAmount,
    required this.interestRate,
    required this.termWeeks,
    this.reason,
    this.status = 'pending',
    required this.requestedAt,
    this.approvedAt,
    this.approvedByPeerId,
    this.disbursedAt,
    this.completedAt,
    this.defaultedAt,
    required this.borrowerSignature,
    this.approverSignature,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'group_id': groupId,
    'borrower_peer_id': borrowerPeerId,
    'requested_amount': requestedAmount,
    'approved_amount': approvedAmount,
    'interest_rate': interestRate,
    'term_weeks': termWeeks,
    'reason': reason,
    'status': status,
    'requested_at': requestedAt.millisecondsSinceEpoch,
    'approved_at': approvedAt?.millisecondsSinceEpoch,
    'approved_by_peer_id': approvedByPeerId,
    'disbursed_at': disbursedAt?.millisecondsSinceEpoch,
    'completed_at': completedAt?.millisecondsSinceEpoch,
    'defaulted_at': defaultedAt?.millisecondsSinceEpoch,
    'borrower_signature': borrowerSignature,
    'approver_signature': approverSignature,
  };

  factory LoanData.fromMap(Map<String, dynamic> map) => LoanData(
    id: map['id'] as String,
    groupId: map['group_id'] as String,
    borrowerPeerId: map['borrower_peer_id'] as String,
    requestedAmount: (map['requested_amount'] as num).toDouble(),
    approvedAmount: (map['approved_amount'] as num?)?.toDouble(),
    interestRate: (map['interest_rate'] as num).toDouble(),
    termWeeks: map['term_weeks'] as int,
    reason: map['reason'] as String?,
    status: map['status'] as String,
    requestedAt: DateTime.fromMillisecondsSinceEpoch(map['requested_at'] as int),
    approvedAt: map['approved_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['approved_at'] as int)
        : null,
    approvedByPeerId: map['approved_by_peer_id'] as String?,
    disbursedAt: map['disbursed_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['disbursed_at'] as int)
        : null,
    completedAt: map['completed_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
        : null,
    defaultedAt: map['defaulted_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['defaulted_at'] as int)
        : null,
    borrowerSignature: Uint8List.fromList(map['borrower_signature'] as List<int>),
    approverSignature: map['approver_signature'] != null
        ? Uint8List.fromList(map['approver_signature'] as List<int>)
        : null,
  );
}
