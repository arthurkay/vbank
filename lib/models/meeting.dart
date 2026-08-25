enum MeetingStatus { scheduled, inProgress, completed, cancelled }
enum MeetingAttendanceStatus { present, absent, excused }

class Meeting {
  final String id;
  final String groupId;
  final DateTime scheduledAt;
  final MeetingStatus status;
  final List<Attendance> attendance;
  final String? notes;
  final double totalCollected;
  final DateTime? completedAt;

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

  int get presentCount => attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
  int get absentCount => attendance.where((a) => a.status == MeetingAttendanceStatus.absent).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'scheduledAt': scheduledAt.toIso8601String(),
    'status': status.name,
    'attendance': attendance.map((a) => a.toJson()).toList(),
    'notes': notes,
    'totalCollected': totalCollected,
    'completedAt': completedAt?.toIso8601String(),
  };

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    scheduledAt: DateTime.parse(json['scheduledAt'] as String),
    status: MeetingStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => MeetingStatus.scheduled,
    ),
    attendance: (json['attendance'] as List?)
        ?.map((a) => Attendance.fromJson(a as Map<String, dynamic>))
        .toList() ?? [],
    notes: json['notes'] as String?,
    totalCollected: (json['totalCollected'] as num?)?.toDouble() ?? 0,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
  );
}

class Attendance {
  final String peerId;
  final MeetingAttendanceStatus status;
  final bool contributed;
  final DateTime? contributionTime;

  const Attendance({
    required this.peerId,
    this.status = MeetingAttendanceStatus.absent,
    this.contributed = false,
    this.contributionTime,
  });

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'status': status.name,
    'contributed': contributed,
    'contributionTime': contributionTime?.toIso8601String(),
  };

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
    peerId: json['peerId'] as String,
    status: MeetingAttendanceStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => MeetingAttendanceStatus.absent,
    ),
    contributed: json['contributed'] as bool? ?? false,
    contributionTime: json['contributionTime'] != null
        ? DateTime.parse(json['contributionTime'] as String)
        : null,
  );
}
