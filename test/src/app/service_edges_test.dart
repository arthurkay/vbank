import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/signing_payloads.dart';
import 'package:vbank/src/app/transaction_service.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('GroupService edges', () {
    test('reads hit and miss', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      expect((await owner.groups.getGroup(gid)).value.id, gid);
      expect(
        (await owner.groups.getGroup('nope')).failure,
        isA<NotFoundFailure>(),
      );
      expect((await owner.groups.listGroups()).value, hasLength(1));
      expect(
        await owner.groups.getMember(gid, 'member'),
        isNotNull,
      );
      expect(await owner.groups.getMember(gid, 'ghost'), isNull);
      expect(await owner.groups.getMember('nope', 'member'), isNull);
    });

    test('addMember appends and bumps the sequence', () async {
      final String gid = await world.seedGroup();
      await world.keyFor('extra');
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;

      await owner.groups.addMember(
        group,
        Member(
          peerId: 'extra',
          name: 'Extra',
          joinedAt: world.now,
          publicKey: world.publicKeys['extra']!,
        ),
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(group.sequenceNumber, 2, reason: 'seed join bumped once already');
      expect(group.memberCount, 3);
    });

    test('approve and reject handle every state', () async {
      final String gid = await world.seedGroup();
      await world.keyFor('pending');
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      Group group = (await owner.groups.getGroup(gid)).value;

      // Non-managers cannot approve.
      expect(
        (await member.groups.approveMember(
          group: group,
          actingPeerId: 'member',
          peerId: 'pending',
        )).failure,
        isA<PermissionFailure>(),
      );
      // Missing targets fail lookups.
      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'ghost',
        )).failure,
        isA<NotFoundFailure>(),
      );
      // Approving an active member is a no-op success.
      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
        )).isOk,
        isTrue,
      );
      // Rejecting unknown or active members is a no-op success.
      expect(
        (await owner.groups.rejectMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'ghost',
        )).isOk,
        isTrue,
      );
      expect(
        (await owner.groups.rejectMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
        )).isOk,
        isTrue,
      );
      // Rejecting a pending join removes the row.
      await owner.groups.addMember(
        group,
        Member(
          peerId: 'pending',
          name: 'Pending',
          joinedAt: world.now,
          publicKey: world.publicKeys['pending']!,
          status: MemberStatus.pending,
        ),
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await owner.groups.rejectMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'pending',
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members.where((Member m) => m.peerId == 'pending'),
        isEmpty,
      );
    });

    test('renameMember renames everywhere, rejects blanks', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      expect(
        (await owner.groups.renameMember(peerId: 'member', name: '  ')).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await owner.groups.renameMember(peerId: 'member', name: 'Renamed'))
            .isOk,
        isTrue,
      );
      final Group group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members.where((Member m) => m.peerId == 'member').single.name,
        'Renamed',
      );
    });

    test('role and status edits guard every edge', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      final Group group = (await owner.groups.getGroup(gid)).value;

      // Non-owners cannot touch roles.
      expect(
        (await member.groups.updateMemberRole(
          group: group,
          actingPeerId: 'member',
          peerId: 'member',
          newRole: MemberRole.admin,
        )).failure,
        isA<PermissionFailure>(),
      );
      // Unknown targets fail lookups.
      expect(
        (await owner.groups.updateMemberRole(
          group: group,
          actingPeerId: 'owner',
          peerId: 'ghost',
          newRole: MemberRole.admin,
        )).failure,
        isA<NotFoundFailure>(),
      );
      // Removed status goes through removeMember.
      expect(
        (await owner.groups.updateMemberStatus(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newStatus: MemberStatus.removed,
        )).failure,
        isA<ValidationFailure>(),
      );
      // Unknown targets fail lookups.
      expect(
        (await owner.groups.updateMemberStatus(
          group: group,
          actingPeerId: 'owner',
          peerId: 'ghost',
          newStatus: MemberStatus.suspended,
        )).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('removal validates target, owner and reason', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Group group = (await owner.groups.getGroup(gid)).value;

      expect(
        (await owner.groups.removeMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'ghost',
          reason: 'x',
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.groups.removeMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'owner',
          reason: 'x',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.removeMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          reason: '  ',
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(await owner.groups.isBanned(gid, 'member'), isFalse);

      // Clean removals record a plain remove.
      final removal = (await owner.groups.removeMember(
        group: group,
        actingPeerId: 'owner',
        peerId: 'member',
        reason: 'moved away',
      ))
          .value;
      expect(removal.action, RemovalAction.remove);
      expect(removal.hasOutstandingLoan, isFalse);
      expect(await owner.groups.isBanned(gid, 'member'), isTrue);
    });

    test('enc keys store and miss cleanly', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Group group = (await owner.groups.getGroup(gid)).value;

      expect(
        (await owner.groups.setMemberEncKey(
          group,
          'ghost',
          Uint8List.fromList([1]),
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.groups.setMemberEncKey(
          group,
          'member',
          Uint8List.fromList([9, 9]),
        )).isOk,
        isTrue,
      );
      final Group updated = (await owner.groups.getGroup(gid)).value;
      expect(
        updated.members
            .where((Member m) => m.peerId == 'member')
            .single
            .encKey,
        Uint8List.fromList([9, 9]),
      );
    });

    test('config and rename validate and persist', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      Group group = (await owner.groups.getGroup(gid)).value;

      expect(
        (await member.groups.updateGroupConfig(
          group: group,
          actingPeerId: 'member',
          config: group.config,
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.updateGroupConfig(
          group: group,
          actingPeerId: 'owner',
          config: const GroupConfig(groupId: 'x', contributionAmount: 0),
        )).failure,
        isA<ValidationFailure>(),
      );
      const GroupConfig changed = GroupConfig(
        groupId: 'x',
        contributionAmount: 200,
        meetingTime: MeetingTime(hour: 18, minute: 30),
      );
      expect(
        (await owner.groups.updateGroupConfig(
          group: group,
          actingPeerId: 'owner',
          config: changed,
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(group.config.contributionAmount, 200);
      expect(group.config.groupId, gid);

      expect(
        (await owner.groups.renameGroup(
          group: group,
          actingPeerId: 'owner',
          name: '  ',
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await member.groups.renameGroup(
          group: group,
          actingPeerId: 'member',
          name: 'Taken',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.renameGroup(
          group: group,
          actingPeerId: 'owner',
          name: '  New Name ',
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(group.name, 'New Name');
    });

    test('transfers refuse non-admins and strangers', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      final Group group = (await owner.groups.getGroup(gid)).value;

      expect(
        (await member.groups.transferOwnership(
          group: group,
          actingPeerId: 'member',
          toPeerId: 'owner',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.transferOwnership(
          group: group,
          actingPeerId: 'owner',
          toPeerId: 'ghost',
        )).failure,
        isA<NotFoundFailure>(),
      );
      // Plain members cannot receive ownership.
      expect(
        (await owner.groups.transferOwnership(
          group: group,
          actingPeerId: 'owner',
          toPeerId: 'member',
        )).failure,
        isA<PermissionFailure>(),
      );
    });

    test('dissolved groups refuse roster writes', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      await owner.governance.dissolveGroup(
        groupId: gid,
        actingPeerId: 'owner',
      );
      final Group group = (await owner.groups.getGroup(gid)).value;

      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'x',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.updateMemberRole(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newRole: MemberRole.admin,
        )).failure,
        isA<PermissionFailure>(),
      );
    });
  });

  group('TransactionService edges', () {
    test('reads hit and miss', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      expect(
        (await owner.transactions.getById('nope')).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.transactions.listByGroup('empty')).value,
        isEmpty,
      );
      expect(
        (await owner.transactions.countContributions(gid, 'member')).value,
        1,
      );
      expect(
        (await owner.transactions.markReversed('nope')).failure,
        isA<NotFoundFailure>(),
      );
    });

    test('every type moves its side of the balance', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Future<void> record(
        String from,
        String to,
        TransactionType type,
        double amount,
      ) async {
        final result = await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: from,
          toPeerId: to,
          type: type,
          amount: amount,
        );
        assert(result.isOk);
      }

      await record('member', 'group', TransactionType.penalty, 10);
      await record('member', 'group', TransactionType.fee, 5);
      await record('group', 'member', TransactionType.withdrawal, 20);

      final balances = await owner.transactions.balances.listByGroup(gid);
      final member = balances.value.firstWhere((b) => b.peerId == 'member');
      // Seed 100, penalty 10, fee 5, withdrawal 20.
      expect(member.totalPenalties, 15);
      expect(member.totalWithdrawn, 20);
      expect(member.netBalance, 100 - 15 - 20);
    });

    test('remote reversed records skip balance effects', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;
      // A reversed-status record with a valid signature stores without
      // moving balances (status itself is unsigned: it mutates by design).
      final Transaction voided = Transaction(
        id: 'void-tx',
        groupId: tx.groupId,
        fromPeerId: tx.fromPeerId,
        toPeerId: tx.toPeerId,
        type: tx.type,
        amount: tx.amount,
        timestamp: tx.timestamp,
        sequenceNumber: tx.sequenceNumber + 1,
        senderSignature: tx.senderSignature,
        authorPeerId: tx.authorPeerId,
        status: TransactionStatus.reversed,
      );
      final Transaction signed = Transaction(
        id: voided.id,
        groupId: voided.groupId,
        fromPeerId: voided.fromPeerId,
        toPeerId: voided.toPeerId,
        type: voided.type,
        amount: voided.amount,
        timestamp: voided.timestamp,
        sequenceNumber: voided.sequenceNumber,
        senderSignature: await world.signerFor('owner')(
          SigningPayloads.transaction(voided),
        ),
        authorPeerId: voided.authorPeerId,
        status: TransactionStatus.reversed,
      );
      expect(
        (await owner.transactions.importRemote(
          signed,
          authorPublicKey: world.publicKeys['owner']!,
        ))
            .value,
        ImportResult.imported,
      );
      final balances = await owner.transactions.balances.listByGroup(gid);
      // Only the seed 100 + the confirmed 100 moved the member.
      expect(
        balances.value.firstWhere((b) => b.peerId == 'member').netBalance,
        200,
      );
    });

    test('remote zero amounts are rejected', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;
      final Transaction zero = Transaction(
        id: tx.id,
        groupId: tx.groupId,
        fromPeerId: tx.fromPeerId,
        toPeerId: tx.toPeerId,
        type: tx.type,
        amount: 0,
        timestamp: tx.timestamp,
        sequenceNumber: tx.sequenceNumber,
        senderSignature: tx.senderSignature,
        authorPeerId: tx.authorPeerId,
      );

      expect(
        (await owner.transactions.importRemote(
          zero,
          authorPublicKey: world.publicKeys['owner']!,
        )).failure,
        isA<ValidationFailure>(),
      );
    });
  });

  group('MeetingService edges', () {
    test('strangers and missing meetings fail lookups', () async {
      final String gid = await world.seedGroup();
      final ServiceStack stranger = world.stackFor('stranger');
      final ServiceStack owner = world.stackFor('owner');

      expect(
        (await stranger.meetings.createMeeting(
          groupId: gid,
          actingPeerId: 'stranger',
          scheduledAt: world.now,
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await stranger.meetings.createMeeting(
          groupId: 'nope',
          actingPeerId: 'stranger',
          scheduledAt: world.now,
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.meetings.recordAttendance(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'nope',
          peerId: 'member',
          status: MeetingAttendanceStatus.present,
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.meetings.completeMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'nope',
          totalCollected: 0,
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.meetings.cancelMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'nope',
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.meetings.getById('nope')).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await owner.meetings.completeMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'nope',
          totalCollected: -1,
        )).failure,
        isA<NotFoundFailure>(),
        reason: 'missing beats negative',
      );
    });

    test('remote meetings store verbatim', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Meeting meeting = (await owner.meetings.createMeeting(
        groupId: gid,
        actingPeerId: 'owner',
        scheduledAt: world.now,
      ))
          .value;

      expect((await owner.meetings.importRemote(meeting)).isOk, isTrue);
      expect(
        (await owner.meetings.listByGroup(gid)).value.map((m) => m.id),
        [meeting.id],
      );
    });
  });
}
