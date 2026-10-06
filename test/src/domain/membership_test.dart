import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/membership.dart';

import 'fixtures.dart';

void main() {
  group('permissions', () {
    test('owner can do everything', () {
      const role = MemberRole.owner;

      expect(canWrite(role), isTrue);
      expect(canManageMembers(role), isTrue);
      expect(canPromote(role), isTrue);
      expect(canDemote(role), isTrue);
      expect(canRemove(role), isTrue);
      expect(canDissolve(role), isTrue);
    });

    test('admin can write and manage but not govern', () {
      const role = MemberRole.admin;

      expect(canWrite(role), isTrue);
      expect(canManageMembers(role), isTrue);
      expect(canPromote(role), isFalse);
      expect(canDemote(role), isFalse);
      expect(canRemove(role), isFalse);
      expect(canDissolve(role), isFalse);
    });

    test('member is read-only', () {
      const role = MemberRole.member;

      expect(canWrite(role), isFalse);
      expect(canManageMembers(role), isFalse);
      expect(canPromote(role), isFalse);
      expect(canDemote(role), isFalse);
      expect(canRemove(role), isFalse);
      expect(canDissolve(role), isFalse);
    });
  });

  group('Member', () {
    test('validates identifiers', () {
      expect(testMember('a').validate().isOk, isTrue);
      expect(
        testMember('').validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        testMember('a', name: '  ').validate().failure,
        isA<ValidationFailure>(),
      );
    });

    test('equality is by value including key bytes', () {
      final Member a = testMember('a');
      final Member b = testMember('a');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == testMember('b'), isFalse);
      expect(
        a == a.copyWith(role: MemberRole.admin),
        isFalse,
      );
    });

    test('copyWith replaces the given fields', () {
      final Member promoted = testMember('a').copyWith(
        role: MemberRole.admin,
        status: MemberStatus.suspended,
      );

      expect(promoted.role, MemberRole.admin);
      expect(promoted.status, MemberStatus.suspended);
      expect(promoted.peerId, 'a');
    });
  });
}
