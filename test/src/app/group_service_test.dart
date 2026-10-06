import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('GroupService.createGroup', () {
    test('creates an owned group with a key', () async {
      await world.keyFor('owner');
      final ServiceStack stack = world.stackFor('owner');

      final Group group = (await stack.groups.createGroup(
        name: '  Village Fund  ',
        config: const GroupConfig(groupId: 'template', contributionAmount: 50),
        ownerPeerId: 'owner',
        ownerName: 'Owner',
        ownerPublicKey: world.publicKeys['owner']!,
      ))
          .value;

      expect(group.name, 'Village Fund');
      expect(group.owner?.peerId, 'owner');
      expect(group.memberCount, 1);
      expect(await world.keys.hasKey(group.id), isTrue);
    });

    test('rejects bad input without writing', () async {
      await world.keyFor('owner');
      final ServiceStack stack = world.stackFor('owner');
      GroupConfig config(double amount) =>
          GroupConfig(groupId: 't', contributionAmount: amount);

      expect(
        (await stack.groups.createGroup(
          name: 'G',
          config: config(0),
          ownerPeerId: 'o',
          ownerName: 'O',
          ownerPublicKey: world.publicKeys['owner']!,
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await stack.groups.createGroup(
          name: 'G',
          config: config(10),
          ownerPeerId: '',
          ownerName: 'O',
          ownerPublicKey: world.publicKeys['owner']!,
        )).failure,
        isA<ValidationFailure>(),
      );
      expect(
        (await stack.groups.createGroup(
          name: 'G',
          config: config(10),
          passphrase: 'short',
          ownerPeerId: 'o',
          ownerName: 'O',
          ownerPublicKey: world.publicKeys['owner']!,
        )).failure,
        isA<ValidationFailure>(),
      );
      expect((await stack.groups.listGroups()).value, isEmpty);
    });
  });

  group('GroupService membership', () {
    test('owner promotes and demotes, members cannot', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      Group group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await member.groups.updateMemberRole(
          group: group,
          actingPeerId: 'member',
          peerId: 'member',
          newRole: MemberRole.admin,
        )).failure,
        isA<PermissionFailure>(),
      );

      expect(
        (await owner.groups.updateMemberRole(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newRole: MemberRole.admin,
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members
            .where((Member m) => m.peerId == 'member')
            .single
            .role,
        MemberRole.admin,
      );

      expect(
        (await owner.groups.updateMemberRole(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newRole: MemberRole.member,
        )).isOk,
        isTrue,
      );
    });

    test('ownership never moves by role edit', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Group group = (await owner.groups.getGroup(gid)).value;

      expect(
        (await owner.groups.updateMemberRole(
          group: group,
          actingPeerId: 'owner',
          peerId: 'owner',
          newRole: MemberRole.admin,
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.updateMemberRole(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newRole: MemberRole.owner,
        )).failure,
        isA<PermissionFailure>(),
      );
    });

    test('suspend rules protect owners and admins', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.updateMemberRole(
        group: group,
        actingPeerId: 'owner',
        peerId: 'member',
        newRole: MemberRole.admin,
      );

      // The admin cannot suspend the owner.
      group = (await owner.groups.getGroup(gid)).value;
      final ServiceStack admin = world.stackFor('member');
      expect(
        (await admin.groups.updateMemberStatus(
          group: group,
          actingPeerId: 'member',
          peerId: 'owner',
          newStatus: MemberStatus.suspended,
        )).failure,
        isA<PermissionFailure>(),
      );

      // The owner can suspend (and reinstate) the admin.
      expect(
        (await owner.groups.updateMemberStatus(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newStatus: MemberStatus.suspended,
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await owner.groups.updateMemberStatus(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          newStatus: MemberStatus.active,
        )).isOk,
        isTrue,
      );
    });

    test('suspended members lose write access', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.updateMemberStatus(
        group: group,
        actingPeerId: 'owner',
        peerId: 'member',
        newStatus: MemberStatus.suspended,
      );

      group = (await owner.groups.getGroup(gid)).value;
      expect(
        owner.groups.requireWriter(group, 'member').failure,
        isA<PermissionFailure>(),
      );
    });

    test('pending joins approve, reject and respect bans', () async {
      final String gid = await world.seedGroup();
      await world.keyFor('newcomer');
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;
      final Member pending = Member(
        peerId: 'newcomer',
        name: 'Newcomer',
        joinedAt: world.now,
        publicKey: world.publicKeys['newcomer']!,
        status: MemberStatus.pending,
      );
      await owner.groups.addMember(group, pending);

      group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'newcomer',
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members.where((Member m) => m.peerId == 'newcomer').single.status,
        MemberStatus.active,
      );

      // Banned peers cannot be approved until unbanned.
      await owner.groups.removeMember(
        group: group,
        actingPeerId: 'owner',
        peerId: 'newcomer',
        reason: 'test',
      );
      group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.addMember(
        group,
        pending.copyWith(status: MemberStatus.pending),
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'newcomer',
        )).failure,
        isA<PermissionFailure>(),
      );
      expect(
        (await owner.groups.liftRemoval(
          group: group,
          actingPeerId: 'owner',
          peerId: 'newcomer',
        )).isOk,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'newcomer',
        )).isOk,
        isTrue,
      );
    });

    test('removal refuses outstanding loans unless settled', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;

      // Give the member an open loan directly through the loan repo shape:
      // borrow via the loan service after qualifying contributions.
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        world.elapse(const Duration(days: 7));
        final result = await owner.transactions.createTransaction(
              groupId: gid,
              authorPeerId: 'owner',
              fromPeerId: 'member',
              toPeerId: 'group',
              type: TransactionType.contribution,
              amount: 100,
            );
        assert(result.isOk);
      }
      final loan = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 200,
        termWeeks: 4,
      ))
          .value;
      await owner.loans.approveLoan(
        loanId: loan.id,
        approvedAmount: 200,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(loanId: loan.id, adminPeerId: 'owner');

      group = (await owner.groups.getGroup(gid)).value;
      expect(
        (await owner.groups.removeMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          reason: 'leaving',
        )).failure,
        isA<PermissionFailure>(),
      );

      final removal = (await owner.groups.removeMember(
        group: group,
        actingPeerId: 'owner',
        peerId: 'member',
        reason: 'leaving, written off',
        settleOutstandingLoan: true,
      ))
          .value;
      expect(removal.action, RemovalAction.settleAndRemove);
      expect(removal.outstandingAmount, 200);
      expect(removal.hasOutstandingLoan, isTrue);

      group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members.where((Member m) => m.peerId == 'member').single.status,
        MemberStatus.removed,
      );
      final updated = (await owner.loans.getById(loan.id)).value;
      expect(updated.status, LoanStatus.defaulted);
    });

    test('ownership transfers to active admins with countersign', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.updateMemberRole(
        group: group,
        actingPeerId: 'owner',
        peerId: 'member',
        newRole: MemberRole.admin,
      );

      group = (await owner.groups.getGroup(gid)).value;
      final transfer = (await owner.groups.transferOwnership(
        group: group,
        actingPeerId: 'owner',
        toPeerId: 'member',
      ))
          .value;
      expect(transfer.newOwnerSignature, isEmpty);

      group = (await owner.groups.getGroup(gid)).value;
      expect(group.owner?.peerId, 'member');

      final ServiceStack exMember = world.stackFor('member');
      expect(
        (await exMember.groups.countersignTransfer(
          group: group,
          ownPeerId: 'member',
        ))
            .value,
        isTrue,
      );
      expect(
        (await exMember.groups.countersignTransfer(
          group: group,
          ownPeerId: 'member',
        ))
            .value,
        isFalse,
      );
    });
  });
}
