import 'core/failure.dart';
import 'core/result.dart';

/// A meeting's lifecycle.
enum MeetingStatus {
  /// Announced, not yet held.
  scheduled,

  /// Underway now.
  inProgress,

  /// Held and closed with a total.
  completed,

  /// Called off.
  cancelled,
}

/// How one member showed up (or didn't).
enum MeetingAttendanceStatus {
  /// There in person.
  present,

  /// Nowhere to be seen.
  absent,

  /// Away with a reason.
  excused,
}

/// One member's attendance at one meeting.
final class Attendance {
  /// Who showed up.
  final String peerId;

  /// How they showed up; defaults to absent.
  final MeetingAttendanceStatus status;

  /// True when they paid their contribution at this meeting.
  final bool contributed;

  /// When they paid, once paid.
  final DateTime? contributionTime;

  /// Creates an attendance record.
  const Attendance({
    required this.peerId,
    this.status = MeetingAttendanceStatus.absent,
    this.contributed = false,
    this.contributionTime,
  });

  /// Copies this record, replacing the given fields.
  Attendance copyWith({
    MeetingAttendanceStatus? status,
    bool? contributed,
    DateTime? contributionTime,
  }) =>
      Attendance(
        peerId: peerId,
        status: status ?? this.status,
        contributed: contributed ?? this.contributed,
        contributionTime: contributionTime ?? this.contributionTime,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attendance &&
          peerId == other.peerId &&
          status == other.status &&
          contributed == other.contributed &&
          contributionTime == other.contributionTime;

  @override
  int get hashCode =>
      Object.hash(peerId, status, contributed, contributionTime);
}

/// A scheduled gathering: attendance taken, contributions ticked off, closed
/// with the total collected.
final class Meeting {
  /// This meeting's id.
  final String id;

  /// The group meeting.
  final String groupId;

  /// When it happens.
  final DateTime scheduledAt;

  /// Current state.
  final MeetingStatus status;

  /// One record per member who was expected.
  final List<Attendance> attendance;

  /// Free-form minutes.
  final String? notes;

  /// Counted at closing.
  final double totalCollected;

  /// When it was closed, once closed.
  final DateTime? completedAt;

  /// Creates a meeting.
  const Meeting({
    required this.id,
    required this.groupId,
    required this.scheduledAt,
    this.status = MeetingStatus.scheduled,
    this.attendance = const [],
    this.notes,
    this.totalCollected = 0,
    this.completedAt,
  });

  /// Members marked present.
  int get presentCount => attendance
      .where(
        (Attendance a) => a.status == MeetingAttendanceStatus.present,
      )
      .length;

  /// Members marked absent.
  int get absentCount => attendance
      .where(
        (Attendance a) => a.status == MeetingAttendanceStatus.absent,
      )
      .length;

  /// Structural checks: identifiers present, collection non-negative.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('meetingIdEmpty'));
    }
    if (groupId.isEmpty) {
      return const Err(ValidationFailure('meetingGroupEmpty'));
    }
    if (totalCollected < 0) {
      return const Err(ValidationFailure('meetingCollectedNegative'));
    }
    return const Ok(unit);
  }

  /// Copies this meeting, replacing the given fields.
  Meeting copyWith({
    MeetingStatus? status,
    List<Attendance>? attendance,
    String? notes,
    double? totalCollected,
    DateTime? completedAt,
  }) =>
      Meeting(
        id: id,
        groupId: groupId,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        attendance: attendance ?? this.attendance,
        notes: notes ?? this.notes,
        totalCollected: totalCollected ?? this.totalCollected,
        completedAt: completedAt ?? this.completedAt,
      );

  static bool _attendanceEqual(List<Attendance> a, List<Attendance> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Meeting &&
          id == other.id &&
          groupId == other.groupId &&
          scheduledAt == other.scheduledAt &&
          status == other.status &&
          _attendanceEqual(attendance, other.attendance) &&
          notes == other.notes &&
          totalCollected == other.totalCollected &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        scheduledAt,
        status,
        Object.hashAll(attendance),
        notes,
        totalCollected,
        completedAt,
      );
}
