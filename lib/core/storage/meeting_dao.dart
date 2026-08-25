import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class MeetingDao {
  Future<void> insert(MeetingData meeting) async {
    final db = await AppDatabase.getInstance();
    await db.insert('meetings', meeting.toMap());
  }

  Future<void> upsert(MeetingData meeting) async {
    final db = await AppDatabase.getInstance();
    await db.insert('meetings', meeting.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Scheduled meetings from [now] onwards, across all groups.
  Future<List<MeetingData>> getUpcoming(DateTime now) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'meetings',
      where: "scheduled_at >= ? AND status = 'scheduled'",
      whereArgs: [now.millisecondsSinceEpoch],
      orderBy: 'scheduled_at ASC',
    );
    return result.map((map) => MeetingData.fromMap(map)).toList();
  }

  Future<MeetingData?> getById(String id) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('meetings', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return MeetingData.fromMap(result.first);
  }

  Future<List<MeetingData>> getByGroupId(String groupId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'meetings',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'scheduled_at DESC',
    );
    return result.map((map) => MeetingData.fromMap(map)).toList();
  }

  Future<void> update(MeetingData meeting) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'meetings',
      meeting.toMap(),
      where: 'id = ?',
      whereArgs: [meeting.id],
    );
  }

  /// Partial update for completing a meeting — leaves group_id, scheduled_at
  /// and notes untouched.
  Future<void> complete(String id, double totalCollected, DateTime completedAt, {String? notes}) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'meetings',
      {
        'status': 'completed',
        'total_collected': totalCollected,
        'completed_at': completedAt.millisecondsSinceEpoch,
        'notes': ?notes,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'meetings',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class MeetingData {
  final String id;
  final String groupId;
  final DateTime scheduledAt;
  final String status;
  final String? notes;
  final double totalCollected;
  final DateTime? completedAt;

  const MeetingData({
    required this.id,
    required this.groupId,
    required this.scheduledAt,
    this.status = 'scheduled',
    this.notes,
    this.totalCollected = 0,
    this.completedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'group_id': groupId,
    'scheduled_at': scheduledAt.millisecondsSinceEpoch,
    'status': status,
    'notes': notes,
    'total_collected': totalCollected,
    'completed_at': completedAt?.millisecondsSinceEpoch,
  };

  factory MeetingData.fromMap(Map<String, dynamic> map) => MeetingData(
    id: map['id'] as String,
    groupId: map['group_id'] as String,
    scheduledAt: DateTime.fromMillisecondsSinceEpoch(map['scheduled_at'] as int),
    status: map['status'] as String,
    notes: map['notes'] as String?,
    totalCollected: (map['total_collected'] as num).toDouble(),
    completedAt: map['completed_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
        : null,
  );
}

class AttendanceDao {
  Future<void> insert(AttendanceData attendance) async {
    final db = await AppDatabase.getInstance();
    await db.insert('attendance', attendance.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> upsert(AttendanceData attendance) async {
    final db = await AppDatabase.getInstance();
    await db.insert('attendance', attendance.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AttendanceData>> getByMeetingId(String meetingId) async {
    final db = await AppDatabase.getInstance();
    final result = await db.query(
      'attendance',
      where: 'meeting_id = ?',
      whereArgs: [meetingId],
    );
    return result.map((map) => AttendanceData.fromMap(map)).toList();
  }

  Future<void> update(AttendanceData attendance) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'attendance',
      attendance.toMap(),
      where: 'meeting_id = ? AND peer_id = ?',
      whereArgs: [attendance.meetingId, attendance.peerId],
    );
  }
}

class AttendanceData {
  final String meetingId;
  final String peerId;
  final String status;
  final bool contributed;
  final DateTime? contributionTime;

  const AttendanceData({
    required this.meetingId,
    required this.peerId,
    this.status = 'absent',
    this.contributed = false,
    this.contributionTime,
  });

  Map<String, dynamic> toMap() => {
    'meeting_id': meetingId,
    'peer_id': peerId,
    'status': status,
    'contributed': contributed ? 1 : 0,
    'contribution_time': contributionTime?.millisecondsSinceEpoch,
  };

  factory AttendanceData.fromMap(Map<String, dynamic> map) => AttendanceData(
    meetingId: map['meeting_id'] as String,
    peerId: map['peer_id'] as String,
    status: map['status'] as String,
    contributed: (map['contributed'] as int) == 1,
    contributionTime: map['contribution_time'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['contribution_time'] as int)
        : null,
  );
}
