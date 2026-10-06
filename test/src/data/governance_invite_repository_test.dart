import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/repositories/governance_repository.dart';
import 'package:vbank/src/data/repositories/invite_repository.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/invites.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  Invite testInvite() => Invite(
        id: 'i-1',
        groupId: 'g-1',
        groupCid: 'cid',
        groupTopic: 'vbank/group/g-1',
        inviterPeerId: 'a',
        inviterName: 'A',
        groupKey: Uint8List.fromList(const [9]),
        createdAt: DateTime.utc(2026, 4, 1),
        expiresAt: DateTime.utc(2026, 4, 8),
        nonce: Uint8List.fromList(const [7]),
        inviterSignature: testSignature(),
      );

  MemberRemoval testRemoval() => MemberRemoval(
        id: 'rm-1',
        groupId: 'g-1',
        removedPeerId: 'b',
        removedByPeerId: 'a',
        reason: 'moved away',
        action: RemovalAction.remove,
        removedAt: DateTime.utc(2026, 5, 1),
        adminSignature: testSignature(),
      );

  group('SqlInviteRepository', () {
    test('invites round-trip and consume once', () async {
      final Database db = await openTestDb();
      final SqlInviteRepository repo = SqlInviteRepository(db);
      addTearDown(repo.close);
      await repo.save(testInvite());

      expect((await repo.findById('i-1')).value.used, isFalse);
      expect(
        (await repo.listByGroup('g-1')).value.map((Invite i) => i.id),
        ['i-1'],
      );
      expect(
        (await repo.findById('nope')).failure,
        isA<NotFoundFailure>(),
      );

      expect((await repo.markUsed('i-1')).isOk, isTrue);
      expect((await repo.findById('i-1')).value.used, isTrue);
    });
  });

  group('SqlGovernanceRepository', () {
    test('removals record and lift bans', () async {
      final Database db = await openTestDb();
      final SqlGovernanceRepository repo = SqlGovernanceRepository(db);
      addTearDown(repo.close);
      await repo.saveRemoval(testRemoval());

      expect(
        (await repo.removalsByGroup('g-1')).value.map((r) => r.id),
        ['rm-1'],
      );

      expect((await repo.liftRemoval('rm-1')).isOk, isTrue);
      expect(
        (await repo.removalsByGroup('g-1')).value.first.lifted,
        isTrue,
      );
    });

    test('transfers and dissolutions persist', () async {
      final Database db = await openTestDb();
      final SqlGovernanceRepository repo = SqlGovernanceRepository(db);
      addTearDown(repo.close);
      final OwnershipTransfer transfer = OwnershipTransfer(
        id: 't-1',
        groupId: 'g-1',
        fromPeerId: 'a',
        toPeerId: 'b',
        transferredAt: DateTime.utc(2026, 5, 2),
        oldOwnerSignature: testSignature(),
        newOwnerSignature: testSignature(),
      );
      final GroupDissolution dissolution = GroupDissolution(
        id: 'd-1',
        groupId: 'g-1',
        initiatedByPeerId: 'a',
        initiatedAt: DateTime.utc(2026, 6, 1),
      );
      await repo.saveTransfer(transfer);
      await repo.saveDissolution(dissolution);

      expect(
        (await repo.transfersByGroup('g-1')).value.map((t) => t.id),
        ['t-1'],
      );
      expect(
        (await repo.dissolutionByGroup('g-1')).value.id,
        'd-1',
      );
      expect(
        (await repo.dissolutionByGroup('other')).failure,
        isA<NotFoundFailure>(),
      );
    });
  });
}
