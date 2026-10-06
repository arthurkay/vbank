import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/governance.dart';

import 'fixtures.dart';

void main() {
  group('MemberRemoval', () {
    MemberRemoval testRemoval() => MemberRemoval(
          id: 'rm-1',
          groupId: 'g-1',
          removedPeerId: 'bob',
          removedByPeerId: 'alice',
          reason: 'moved away',
          action: RemovalAction.remove,
          removedAt: DateTime.utc(2026, 5, 1),
          adminSignature: testSignature(),
        );

    test('validates reason and money', () {
      expect(testRemoval().validate().isOk, isTrue);
      expect(
        MemberRemoval(
          id: 'x',
          groupId: 'g',
          removedPeerId: 'b',
          removedByPeerId: 'a',
          reason: '  ',
          action: RemovalAction.suspend,
          removedAt: DateTime.utc(2026, 5, 1),
          adminSignature: testSignature(),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
    });

    test('lifting the ban never reverts', () {
      final MemberRemoval lifted = testRemoval().copyWith(lifted: true);

      expect(lifted.lifted, isTrue);
      expect(lifted == testRemoval(), isFalse);
    });
  });

  group('OwnershipTransfer', () {
    OwnershipTransfer testTransfer() => OwnershipTransfer(
          id: 't-1',
          groupId: 'g-1',
          fromPeerId: 'alice',
          toPeerId: 'bob',
          transferredAt: DateTime.utc(2026, 5, 2),
          oldOwnerSignature: testSignature(),
          newOwnerSignature: testSignature(),
        );

    test('validates sides and rejects self-transfer', () {
      expect(testTransfer().validate().isOk, isTrue);
      expect(
        OwnershipTransfer(
          id: 'x',
          groupId: 'g',
          fromPeerId: 'a',
          toPeerId: 'a',
          transferredAt: DateTime.utc(2026, 5, 2),
          oldOwnerSignature: testSignature(),
          newOwnerSignature: testSignature(),
        ).validate().failure,
        isA<ValidationFailure>(),
      );
    });
  });

  group('GroupDissolution', () {
    test('walks the stages via copyWith', () {
      final GroupDissolution started = GroupDissolution(
        id: 'd-1',
        groupId: 'g-1',
        initiatedByPeerId: 'alice',
        initiatedAt: DateTime.utc(2026, 6, 1),
      );

      expect(started.validate().isOk, isTrue);
      expect(started.status, DissolutionStatus.initiating);

      final GroupDissolution done = started.copyWith(
        status: DissolutionStatus.completed,
        allLoansSettled: true,
        fundsDistributed: true,
        completedAt: DateTime.utc(2026, 6, 30),
      );

      expect(done.status, DissolutionStatus.completed);
      expect(done.allLoansSettled, isTrue);
    });
  });
}
