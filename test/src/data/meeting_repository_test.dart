import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/repositories/meeting_repository.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/meetings.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  group('SqlMeetingRepository', () {
    test('meetings carry their attendance sheet', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlMeetingRepository repo = SqlMeetingRepository(db);
      addTearDown(repo.close);
      final Meeting meeting = testMeeting(
        'm-1',
        attendance: const [
          Attendance(
            peerId: 'a',
            status: MeetingAttendanceStatus.present,
            contributed: true,
          ),
          Attendance(peerId: 'b'),
        ],
      );
      await repo.save(meeting);

      final Meeting found = (await repo.findById('m-1')).value;

      expect(found, meeting);
      expect(
        (await repo.listByGroup('g-1')).value.map((Meeting m) => m.id),
        ['m-1'],
      );
      expect(
        (await repo.findById('nope')).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('resaving replaces the attendance sheet', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlMeetingRepository repo = SqlMeetingRepository(db);
      addTearDown(repo.close);
      await repo.save(
        testMeeting(
          'm-1',
          attendance: const [Attendance(peerId: 'a'), Attendance(peerId: 'b')],
        ),
      );

      await repo.save(
        testMeeting(
          'm-1',
          attendance: const [Attendance(peerId: 'a')],
        ),
      );
      final Meeting found = (await repo.findById('m-1')).value;

      expect(found.attendance, hasLength(1));
    });

    test('watch follows new meetings', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlMeetingRepository repo = SqlMeetingRepository(db);
      addTearDown(repo.close);
      final List<List<Meeting>> seen = [];
      final StreamSubscription<List<Meeting>> sub =
          repo.watchByGroup('g-1').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.single, isEmpty);

      await repo.save(testMeeting('m-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.last, hasLength(1));
    });
  });
}
