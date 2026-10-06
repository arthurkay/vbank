import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/repositories/group_repository.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/membership.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  group('SqlGroupRepository', () {
    test('saves and finds a group with members', () async {
      final Database db = await openTestDb();
      final SqlGroupRepository repo = SqlGroupRepository(db);
      addTearDown(repo.close);
      final Group group = testGroup(
        'g',
        members: [
          testMember('o', role: MemberRole.owner),
          testMember('m'),
        ],
        sequenceNumber: 3,
      );

      expect((await repo.save(group)).isOk, isTrue);
      final Group found = (await repo.findById('g')).value;

      expect(found, group);
      expect(found.owner?.peerId, 'o');
      expect(found.memberCount, 2);
    });

    test('missing groups fail as not found', () async {
      final Database db = await openTestDb();
      final SqlGroupRepository repo = SqlGroupRepository(db);
      addTearDown(repo.close);

      expect(
        (await repo.findById('nope')).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('saving replaces the member set atomically', () async {
      final Database db = await openTestDb();
      final SqlGroupRepository repo = SqlGroupRepository(db);
      addTearDown(repo.close);
      await repo.save(testGroup('g', members: [testMember('a')]));

      await repo.save(testGroup('g', members: [testMember('b')]));
      final Group found = (await repo.findById('g')).value;

      expect(
        found.members.map((Member m) => m.peerId),
        ['b'],
      );
    });

    test('deleting cascades to members', () async {
      final Database db = await openTestDb();
      final SqlGroupRepository repo = SqlGroupRepository(db);
      addTearDown(repo.close);
      await repo.save(testGroup('g', members: [testMember('a')]));

      expect((await repo.delete('g')).isOk, isTrue);
      expect(
        (await repo.findById('g')).failure,
        isA<NotFoundFailure>(),
      );
      final List<Map<String, Object?>> members = await db.query('members');
      expect(members, isEmpty);
    });

    test('watch emits current state then changes', () async {
      final Database db = await openTestDb();
      final SqlGroupRepository repo = SqlGroupRepository(db);
      addTearDown(repo.close);
      final List<List<Group>> seen = [];
      final StreamSubscription<List<Group>> sub =
          repo.watchGroups().listen(seen.add);
      // Let the replayed current state land before writing.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.single, isEmpty);

      await repo.save(testGroup('g-1'));
      await repo.save(testGroup('g-2'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.last, hasLength(2));
    });
  });
}
