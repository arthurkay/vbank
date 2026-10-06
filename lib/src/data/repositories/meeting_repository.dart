import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/meetings.dart';
import '../../domain/repositories.dart';
import '../dto/meeting_dto.dart';
import 'repository.dart';

/// Meetings and attendance sheets on sqflite.
final class SqlMeetingRepository extends SqlRepository
    implements MeetingRepository {
  /// Creates a meeting repository on [db].
  SqlMeetingRepository(super.db);

  @override
  Stream<List<Meeting>> watchByGroup(String groupId) =>
      watch(() => attempt(() => _ordered(groupId)));

  @override
  Future<Result<List<Meeting>>> listByGroup(String groupId) =>
      attempt(() => _ordered(groupId));

  @override
  Future<Result<Meeting>> findById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'meetings',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('meeting:$id'));
      }
      return _withAttendance(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> save(Meeting meeting) async {
    final Result<Unit> result = await attempt(() async {
      await db.transaction((Transaction txn) async {
        await txn.insert(
          'meetings',
          MeetingDto.toRow(meeting),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          'attendance',
          where: 'meeting_id = ?',
          whereArgs: [meeting.id],
        );
        for (final Attendance record in meeting.attendance) {
          await txn.insert(
            'attendance',
            AttendanceDto.toRow(meeting.id, record),
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

  /// A group's meetings, newest first, with attendance attached.
  Future<List<Meeting>> _ordered(String groupId) async {
    final List<Map<String, Object?>> rows = await db.query(
      'meetings',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'scheduled_at DESC',
    );
    final List<Meeting> meetings = [];
    for (final Map<String, Object?> row in rows) {
      final Result<Meeting> meeting = await _withAttendance(row);
      if (meeting.isErr) {
        throw CorruptRow(meeting.failure);
      }
      meetings.add(meeting.value);
    }
    return meetings;
  }

  /// Attaches a meeting row's attendance sheet.
  ///
  /// Database errors propagate: every caller maps them to
  /// `Err(StorageFailure)` itself.
  Future<Result<Meeting>> _withAttendance(Map<String, Object?> row) async {
    final String meetingId = row['id']! as String;
    final List<Map<String, Object?>> attendanceRows = await db.query(
      'attendance',
      where: 'meeting_id = ?',
      whereArgs: [meetingId],
    );
    final List<Attendance> attendance = [];
    for (final Map<String, Object?> attendanceRow in attendanceRows) {
      final Result<Attendance> record = AttendanceDto.fromRow(attendanceRow);
      if (record.isErr) {
        return Err(record.failure);
      }
      attendance.add(record.value);
    }
    return MeetingDto.fromRow(row, attendance);
  }
}
