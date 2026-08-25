import 'package:uuid/uuid.dart';
import '../core/storage/meeting_dao.dart';
import '../models/group.dart';
import '../models/meeting.dart';
import 'group_service.dart';

/// Meetings (DESIGN_PLAN §13: admins manage meetings). All mutating calls
/// take the acting peer so the role is enforced here, not in the UI.
class MeetingService {
  final MeetingDao _meetingDao;
  final AttendanceDao _attendanceDao;
  final GroupService _groupService;
  static const _uuid = Uuid();

  MeetingService({
    GroupService? groupService,
    MeetingDao? meetingDao,
    AttendanceDao? attendanceDao,
  })  : _groupService = groupService ?? GroupService(),
        _meetingDao = meetingDao ?? MeetingDao(),
        _attendanceDao = attendanceDao ?? AttendanceDao();

  Future<Meeting> createMeeting({
    required String groupId,
    required String actingPeerId,
    required DateTime scheduledAt,
    String? notes,
  }) async {
    await _groupService.requireWriter(groupId, actingPeerId);
    final group = await _groupService.getGroup(groupId);
    if (group == null) throw StateError('Group not found');

    final meetingId = _uuid.v4();
    await _meetingDao.insert(MeetingData(
      id: meetingId,
      groupId: groupId,
      scheduledAt: scheduledAt.toUtc(),
      notes: notes,
    ));
    // Pre-create an attendance row (absent) for every active member.
    for (final m in group.members.where((m) => m.status == MemberStatus.active)) {
      await _attendanceDao.insert(AttendanceData(meetingId: meetingId, peerId: m.peerId));
    }
    return (await getById(meetingId))!;
  }

  Future<void> recordAttendance({
    required String groupId,
    required String actingPeerId,
    required String meetingId,
    required String peerId,
    required MeetingAttendanceStatus status,
    bool contributed = false,
  }) async {
    await _groupService.requireWriter(groupId, actingPeerId);
    final meeting = await _meetingDao.getById(meetingId);
    if (meeting == null || meeting.groupId != groupId) throw StateError('Meeting not found');
    if (meeting.status == MeetingStatus.completed.name) {
      throw StateError('Meeting is already completed');
    }
    await _attendanceDao.upsert(AttendanceData(
      meetingId: meetingId,
      peerId: peerId,
      status: status.name,
      contributed: contributed,
      contributionTime: contributed ? DateTime.now().toUtc() : null,
    ));
  }

  Future<void> completeMeeting({
    required String groupId,
    required String actingPeerId,
    required String meetingId,
    required double totalCollected,
    String? notes,
  }) async {
    await _groupService.requireWriter(groupId, actingPeerId);
    final existing = await _meetingDao.getById(meetingId);
    if (existing == null || existing.groupId != groupId) throw StateError('Meeting not found');
    if (existing.status == MeetingStatus.completed.name) return;
    await _meetingDao.complete(meetingId, totalCollected, DateTime.now().toUtc(), notes: notes);
  }

  Future<void> cancelMeeting({
    required String groupId,
    required String actingPeerId,
    required String meetingId,
  }) async {
    await _groupService.requireWriter(groupId, actingPeerId);
    final existing = await _meetingDao.getById(meetingId);
    if (existing == null || existing.groupId != groupId) throw StateError('Meeting not found');
    await _meetingDao.updateStatus(meetingId, MeetingStatus.cancelled.name);
  }

  /// Applies a meeting received from an admin's device (already verified by
  /// the sync layer).
  Future<void> importRemote(Meeting meeting) async {
    await _meetingDao.upsert(MeetingData(
      id: meeting.id,
      groupId: meeting.groupId,
      scheduledAt: meeting.scheduledAt,
      status: meeting.status.name,
      notes: meeting.notes,
      totalCollected: meeting.totalCollected,
      completedAt: meeting.completedAt,
    ));
    for (final a in meeting.attendance) {
      await _attendanceDao.upsert(AttendanceData(
        meetingId: meeting.id,
        peerId: a.peerId,
        status: a.status.name,
        contributed: a.contributed,
        contributionTime: a.contributionTime,
      ));
    }
  }

  Future<Meeting?> getById(String id) async {
    final data = await _meetingDao.getById(id);
    if (data == null) return null;

    final attendance = await _attendanceDao.getByMeetingId(id);
    return Meeting(
      id: data.id,
      groupId: data.groupId,
      scheduledAt: data.scheduledAt,
      status: MeetingStatus.values.firstWhere(
        (s) => s.name == data.status,
        orElse: () => MeetingStatus.scheduled,
      ),
      attendance: attendance
          .map((a) => Attendance(
                peerId: a.peerId,
                status: MeetingAttendanceStatus.values.firstWhere(
                  (s) => s.name == a.status,
                  orElse: () => MeetingAttendanceStatus.absent,
                ),
                contributed: a.contributed,
                contributionTime: a.contributionTime,
              ))
          .toList(),
      notes: data.notes,
      totalCollected: data.totalCollected,
      completedAt: data.completedAt,
    );
  }

  Future<List<Meeting>> getByGroupId(String groupId) async {
    final data = await _meetingDao.getByGroupId(groupId);
    final result = <Meeting>[];
    for (final m in data) {
      final meeting = await getById(m.id);
      if (meeting != null) result.add(meeting);
    }
    return result;
  }

  /// Upcoming meetings across all groups (for the home tab).
  Future<List<Meeting>> getUpcoming() async {
    final data = await _meetingDao.getUpcoming(DateTime.now().toUtc());
    final result = <Meeting>[];
    for (final m in data) {
      final meeting = await getById(m.id);
      if (meeting != null) result.add(meeting);
    }
    return result;
  }
}
