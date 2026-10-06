import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../../domain/repositories.dart';
import '../dto/group_dto.dart';
import 'repository.dart';

/// Groups and members on sqflite.
final class SqlGroupRepository extends SqlRepository
    implements GroupRepository {
  /// Creates a group repository on [db].
  SqlGroupRepository(super.db);

  @override
  Stream<List<Group>> watchGroups() => watch(listAll);

  /// All groups with members, newest business first by name.
  Future<Result<List<Group>>> listAll() async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'groups',
        orderBy: 'name ASC',
      );
      final List<Group> groups = [];
      for (final Map<String, Object?> row in rows) {
        final Result<Group> group = await _withMembers(row);
        if (group.isErr) {
          return Err(group.failure);
        }
        groups.add(group.value);
      }
      return Ok(groups);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Group>> findById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        return Err(NotFoundFailure('group:$id'));
      }
      return _withMembers(rows.first);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  @override
  Future<Result<Unit>> save(Group group) async {
    final Result<Unit> result = await attempt(() async {
      await db.transaction((Transaction txn) async {
        await txn.insert(
          'groups',
          GroupDto.toRow(group),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          'members',
          where: 'group_id = ?',
          whereArgs: [group.id],
        );
        for (final Member member in group.members) {
          await txn.insert(
            'members',
            MemberDto.toRow(group.id, member),
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

  @override
  Future<Result<Unit>> delete(String id) async {
    final Result<Unit> result = await attempt(() async {
      await db.delete('groups', where: 'id = ?', whereArgs: [id]);
      return unit;
    });
    if (result.isOk) {
      notify();
    }
    return result;
  }

  /// Attaches a group row's members, ordered with owners first.
  ///
  /// Database errors propagate: both callers ([findById], [listAll]) map
  /// them to `Err(StorageFailure)` themselves.
  Future<Result<Group>> _withMembers(Map<String, Object?> row) async {
    final Result<Group> group = GroupDto.fromRow(row);
    if (group.isErr) {
      return group;
    }
    final List<Map<String, Object?>> memberRows = await db.query(
      'members',
      where: 'group_id = ?',
      whereArgs: [group.value.id],
      orderBy: 'name ASC',
    );
    final List<Member> members = [];
    for (final Map<String, Object?> memberRow in memberRows) {
      final Result<Member> member = MemberDto.fromRow(memberRow);
      if (member.isErr) {
        return Err(member.failure);
      }
      members.add(member.value);
    }
    members.sort((Member a, Member b) {
      final int rank = a.role.index.compareTo(b.role.index);
      return rank != 0 ? rank : a.name.compareTo(b.name);
    });
    return Ok(group.value.copyWith(members: members));
  }
}
