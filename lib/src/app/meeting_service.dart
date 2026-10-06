import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/group.dart';
import '../domain/meetings.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import 'context.dart';
import 'group_service.dart';

/// Meetings: scheduling, attendance, closing and cancellation.
///
/// All mutations need an active owner/admin. Creating a meeting pre-fills
/// an absent row per active member; closing freezes the total collected.
final class MeetingService {
  /// Meetings and attendance.
  final MeetingRepository meetings;

  /// Groups and roster checks.
  final GroupService groups;

  /// Clock for contribution stamps and closing times.
  final AppClock clock;

  /// Record ids.
  final IdGenerator ids;

  /// Creates a meeting service.
  MeetingService({
    required this.meetings,
    required this.groups,
    required this.clock,
    required this.ids,
  });

  /// Schedules a meeting with an absent row per active member.
  Future<Result<Meeting>> createMeeting({
    required String groupId,
    required String actingPeerId,
    required DateTime scheduledAt,
    String? notes,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireWriter(group.value, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Meeting meeting = Meeting(
      id: ids(),
      groupId: groupId,
      scheduledAt: scheduledAt.toUtc(),
      notes: notes,
      attendance: [
        for (final Member m in group.value.members)
          if (m.status == MemberStatus.active) Attendance(peerId: m.peerId),
      ],
    );
    final Result<Unit> saved = await meetings.save(meeting);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(meeting);
  }

  /// Records one member's attendance. Closed meetings are frozen.
  Future<Result<Unit>> recordAttendance({
    required String groupId,
    required String actingPeerId,
    required String meetingId,
    required String peerId,
    required MeetingAttendanceStatus status,
    bool contributed = false,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireWriter(group.value, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Result<Meeting> current = await meetings.findById(meetingId);
    if (current.isErr) {
      return Err(current.failure);
    }
    final Meeting meeting = current.value;
    if (meeting.groupId != groupId) {
      return Err(NotFoundFailure('meeting:$meetingId'));
    }
    if (meeting.status == MeetingStatus.completed) {
      return const Err(ConflictFailure('meeting:alreadyCompleted'));
    }
    final List<Attendance> attendance = [];
    var known = false;
    for (final Attendance a in meeting.attendance) {
      if (a.peerId == peerId) {
        known = true;
        attendance.add(
          Attendance(
            peerId: peerId,
            status: status,
            contributed: contributed,
            contributionTime: contributed ? clock().toUtc() : null,
          ),
        );
      } else {
        attendance.add(a);
      }
    }
    if (!known) {
      attendance.add(
        Attendance(
          peerId: peerId,
          status: status,
          contributed: contributed,
          contributionTime: contributed ? clock().toUtc() : null,
        ),
      );
    }
    return meetings.save(meeting.copyWith(attendance: attendance));
  }

  /// Closes a meeting with its collected total. Idempotent.
  Future<Result<Unit>> completeMeeting({
    required String groupId,
    required String actingPeerId,
    required String meetingId,
    required double totalCollected,
    String? notes,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireWriter(group.value, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Result<Meeting> current = await meetings.findById(meetingId);
    if (current.isErr) {
      return Err(current.failure);
    }
    final Meeting meeting = current.value;
    if (meeting.groupId != groupId) {
      return Err(NotFoundFailure('meeting:$meetingId'));
    }
    if (meeting.status == MeetingStatus.completed) {
      return const Ok(unit);
    }
    if (totalCollected < 0) {
      return const Err(ValidationFailure('meetingCollectedNegative'));
    }
    return meetings.save(
      meeting.copyWith(
        status: MeetingStatus.completed,
        totalCollected: totalCollected,
        notes: notes ?? meeting.notes,
        completedAt: clock().toUtc(),
      ),
    );
  }

  /// Calls a meeting off.
  Future<Result<Unit>> cancelMeeting({
    required String groupId,
    required String actingPeerId,
    required String meetingId,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireWriter(group.value, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Result<Meeting> current = await meetings.findById(meetingId);
    if (current.isErr) {
      return Err(current.failure);
    }
    final Meeting meeting = current.value;
    if (meeting.groupId != groupId) {
      return Err(NotFoundFailure('meeting:$meetingId'));
    }
    return meetings.save(meeting.copyWith(status: MeetingStatus.cancelled));
  }

  /// Stores a meeting received from an admin's device (already verified by
  /// the sync layer).
  Future<Result<Unit>> importRemote(Meeting meeting) =>
      meetings.save(meeting);

  /// One meeting, or `Err(NotFoundFailure)`.
  Future<Result<Meeting>> getById(String id) => meetings.findById(id);

  /// A group's meetings, newest first.
  Future<Result<List<Meeting>>> listByGroup(String groupId) =>
      meetings.listByGroup(groupId);
}
