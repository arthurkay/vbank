import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/loans.dart';
import '../../domain/repositories.dart';
import '../dto/loan_dto.dart';
import 'repository.dart';

/// Loans and schedules on sqflite.
final class SqlLoanRepository extends SqlRepository
    implements LoanRepository {
  /// Creates a loan repository on [db].
  SqlLoanRepository(super.db);

  @override
  Stream<List<LoanRequest>> watchByGroup(String groupId) =>
      watch(() => attempt(() => _ordered(groupId)));

  @override
  Future<Result<List<LoanRequest>>> listByGroup(String groupId) =>
      attempt(() => _ordered(groupId));

  @override
  Future<Result<LoanRequest>> findById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'loans',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('loan:$id'));
      }
      return LoanDto.fromRow(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> saveLoan(LoanRequest loan) async {
    final Result<Unit> result = await attempt(() async {
      await db.insert(
        'loans',
        LoanDto.toRow(loan),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  @override
  Future<Result<Unit>> saveSchedules(
    String loanId,
    List<RepaymentSchedule> schedules,
  ) async {
    final Result<Unit> result = await attempt(() async {
      await db.transaction((Transaction txn) async {
        await txn.delete(
          'schedules',
          where: 'loan_id = ?',
          whereArgs: [loanId],
        );
        for (final RepaymentSchedule schedule in schedules) {
          await txn.insert(
            'schedules',
            ScheduleDto.toRow(schedule),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  @override
  Future<Result<List<RepaymentSchedule>>> schedulesByLoan(
    String loanId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'schedules',
        where: 'loan_id = ?',
        whereArgs: [loanId],
        orderBy: 'installment_number ASC',
      );
      final List<RepaymentSchedule> schedules = [];
      for (final Map<String, Object?> row in rows) {
        final Result<RepaymentSchedule> schedule = ScheduleDto.fromRow(row);
        if (schedule.isErr) {
          return Err(schedule.failure);
        }
        schedules.add(schedule.value);
      }
      return Ok(schedules);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// A group's loans, newest first.
  Future<List<LoanRequest>> _ordered(String groupId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'loans',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'requested_at DESC',
    );
    final List<LoanRequest> loans = [];
    for (final Map<String, Object?> row in rows) {
      final Result<LoanRequest> loan = LoanDto.fromRow(row);
      if (loan.isErr) {
        throw CorruptRow(loan.failure);
      }
      loans.add(loan.value);
    }
    return loans;
  }
}
