import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/repayment_schedule.dart';
import 'database.dart';

class RepaymentScheduleDao {
  Future<void> insertAll(List<RepaymentSchedule> items) async {
    final db = await AppDatabase.getInstance();
    final batch = db.batch();
    for (final s in items) {
      batch.insert('repayment_schedules', _toMap(s), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsert(RepaymentSchedule s) async {
    final db = await AppDatabase.getInstance();
    await db.insert('repayment_schedules', _toMap(s), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<RepaymentSchedule>> getByLoanId(String loanId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'repayment_schedules',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'installment_number ASC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<void> deleteByLoanId(String loanId) async {
    final db = await AppDatabase.getInstance();
    await db.delete('repayment_schedules', where: 'loan_id = ?', whereArgs: [loanId]);
  }

  static Map<String, dynamic> _toMap(RepaymentSchedule s) => {
    'id': s.id,
    'loan_id': s.loanId,
    'installment_number': s.installmentNumber,
    'expected_amount': s.expectedAmount,
    'due_date': s.dueDate.millisecondsSinceEpoch,
    'paid_amount': s.paidAmount,
    'paid_at': s.paidAt?.millisecondsSinceEpoch,
    'is_overdue': s.isOverdue ? 1 : 0,
    'penalty': s.penalty,
    'status': s.status.name,
  };

  static RepaymentSchedule _fromMap(Map<String, dynamic> m) => RepaymentSchedule(
    id: m['id'] as String,
    loanId: m['loan_id'] as String,
    installmentNumber: m['installment_number'] as int,
    expectedAmount: (m['expected_amount'] as num).toDouble(),
    dueDate: DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int, isUtc: true),
    paidAmount: (m['paid_amount'] as num?)?.toDouble() ?? 0,
    paidAt: m['paid_at'] != null ? DateTime.fromMillisecondsSinceEpoch(m['paid_at'] as int, isUtc: true) : null,
    isOverdue: (m['is_overdue'] as int? ?? 0) == 1,
    penalty: (m['penalty'] as num?)?.toDouble() ?? 0,
    status: RepaymentStatus.values.firstWhere(
      (v) => v.name == m['status'],
      orElse: () => RepaymentStatus.pending,
    ),
  );
}
