import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/meetings.dart';

import 'fixtures.dart';

void main() {
  group('Meeting', () {
    test('counts present and absent', () {
      final Meeting m = testMeeting(
        'm',
        attendance: const [
          Attendance(peerId: 'a', status: MeetingAttendanceStatus.present),
          Attendance(peerId: 'b', status: MeetingAttendanceStatus.absent),
          Attendance(peerId: 'c', status: MeetingAttendanceStatus.excused),
        ],
      );

      expect(m.presentCount, 1);
      expect(m.absentCount, 1);
      expect(m.validate().isOk, isTrue);
    });

    test('rejects blank ids and negative collections', () {
      expect(
        testMeeting('').validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testMeeting('m').copyWith(totalCollected: -1).validate().failure,
        isA<ValidationFailure>(),
      );
    });

    test('copyWith closes a meeting', () {
      final Meeting closed = testMeeting('m').copyWith(
        status: MeetingStatus.completed,
        totalCollected: 500,
        completedAt: DateTime.utc(2026, 3, 7, 12),
      );

      expect(closed.status, MeetingStatus.completed);
      expect(closed.totalCollected, 500);
    });

    test('equality is by value', () {
      expect(testMeeting('m'), testMeeting('m'));
      expect(testMeeting('m') == testMeeting('n'), isFalse);
    });
  });

  group('Attendance', () {
    test('defaults to absent without contribution', () {
      const Attendance a = Attendance(peerId: 'x');

      expect(a.status, MeetingAttendanceStatus.absent);
      expect(a.contributed, isFalse);
    });
  });
}
