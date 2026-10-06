import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/meetings.dart';
import 'dto.dart';

/// Row mapping for `meetings` and `attendance`.
abstract final class MeetingDto {
  /// Serializes [meeting] to a `meetings` row (attendance rides separately).
  static Map<String, Object?> toRow(Meeting meeting) => {
        'id': meeting.id,
        'group_id': meeting.groupId,
        'scheduled_at': Dto.instantValue(meeting.scheduledAt),
        'status': meeting.status.name,
        'notes': meeting.notes,
        'total_collected': meeting.totalCollected,
        'completed_at': meeting.completedAt == null
            ? null
            : Dto.instantValue(meeting.completedAt!),
      };

  /// Parses a `meetings` row with its [attendance] records.
  static Result<Meeting> fromRow(
    Map<String, Object?> row,
    List<Attendance> attendance,
  ) {
    try {
      return Ok(
        Meeting(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          scheduledAt: Dto.instant(row, 'scheduled_at'),
          status: Dto.enumeration(row, 'status', MeetingStatus.values),
          attendance: attendance,
          notes: Dto.textOrNull(row, 'notes'),
          totalCollected: Dto.real(row, 'total_collected'),
          completedAt: Dto.instantOrNull(row, 'completed_at'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `attendance`.
abstract final class AttendanceDto {
  /// Serializes [attendance] of [meetingId] to an `attendance` row.
  static Map<String, Object?> toRow(String meetingId, Attendance attendance) =>
      {
        'meeting_id': meetingId,
        'peer_id': attendance.peerId,
        'status': attendance.status.name,
        'contributed': Dto.flagValue(attendance.contributed),
        'contribution_time': attendance.contributionTime == null
            ? null
            : Dto.instantValue(attendance.contributionTime!),
      };

  /// Parses an `attendance` row.
  static Result<Attendance> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        Attendance(
          peerId: Dto.text(row, 'peer_id'),
          status: Dto.enumeration(
            row,
            'status',
            MeetingAttendanceStatus.values,
          ),
          contributed: Dto.flag(row, 'contributed'),
          contributionTime: Dto.instantOrNull(row, 'contribution_time'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
