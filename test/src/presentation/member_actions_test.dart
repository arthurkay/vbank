import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/presentation/member/member_actions.dart';

Member _member(MemberRole role, [MemberStatus status = MemberStatus.active]) =>
    Member(
      peerId: 'peer-${role.name}',
      name: role.name,
      joinedAt: DateTime.utc(2026, 1, 1),
      publicKey: Uint8List.fromList([1, 2, 3]),
      role: role,
      status: status,
    );

void main() {
  group('availableActions', () {
    test('owner manages members fully', () {
      expect(
        availableActions(MemberRole.owner, _member(MemberRole.member)),
        [MemberAction.promote, MemberAction.suspend, MemberAction.remove],
      );
    });

    test('owner demotes admins', () {
      expect(
        availableActions(MemberRole.owner, _member(MemberRole.admin)),
        [MemberAction.demote, MemberAction.suspend, MemberAction.remove],
      );
    });

    test('owner reinstates suspended members', () {
      expect(
        availableActions(
          MemberRole.owner,
          _member(MemberRole.member, MemberStatus.suspended),
        ),
        [MemberAction.promote, MemberAction.activate, MemberAction.remove],
      );
    });

    test('owner and removed members are untouchable', () {
      expect(
        availableActions(MemberRole.owner, _member(MemberRole.owner)),
        isEmpty,
      );
      expect(
        availableActions(
          MemberRole.owner,
          _member(MemberRole.member, MemberStatus.removed),
        ),
        isEmpty,
      );
    });

    test('admins suspend members only', () {
      expect(
        availableActions(MemberRole.admin, _member(MemberRole.member)),
        [MemberAction.suspend],
      );
      expect(
        availableActions(MemberRole.admin, _member(MemberRole.admin)),
        isEmpty,
      );
    });

    test('members act on nobody', () {
      expect(
        availableActions(MemberRole.member, _member(MemberRole.member)),
        isEmpty,
      );
    });
  });
}
