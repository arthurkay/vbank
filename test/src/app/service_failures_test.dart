import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/reports.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

/// Every service maps repository errors to failures instead of throwing.
/// One closed database per service proves all propagation branches at once.
void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('closed database maps to failures', () {
    test('group operations', () async {
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
      await world.closeDatabase();

      expect(
        (await owner.groups.getGroup(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.groups.listGroups()).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.groups.addMember(group, group.members.first)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.groups.approveMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.groups.removeMember(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
          reason: 'x',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.groups.liftRemoval(
          group: group,
          actingPeerId: 'owner',
          peerId: 'member',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.groups.transferOwnership(
          group: group,
          actingPeerId: 'owner',
          toPeerId: 'member',
        )).failure,
        isA<StorageFailure>(),
      );
    });

    test('money operations', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      await world.closeDatabase();

      expect(
        (await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'owner',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 10,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.transactions.listByGroup(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.transactions.markReversed('t')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.requestLoan(
          groupId: gid,
          borrowerPeerId: 'member',
          requestedAmount: 10,
          termWeeks: 4,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.listByGroup(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.getById('l')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.schedule('l')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.requestLoan(
          groupId: gid,
          borrowerPeerId: 'member',
          requestedAmount: 10,
          termWeeks: 4,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.approveLoan(
          loanId: 'l',
          approvedAmount: 10,
          approverPeerId: 'owner',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.rejectLoan(
          loanId: 'l',
          approverPeerId: 'owner',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.disburseLoan(
          loanId: 'l',
          adminPeerId: 'owner',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.recordRepayment(
          loanId: 'l',
          adminPeerId: 'owner',
          amount: 10,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.loans.refreshOverdue(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.meetings.listByGroup(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.meetings.getById('m')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.meetings.recordAttendance(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'm',
          peerId: 'member',
          status: MeetingAttendanceStatus.present,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.meetings.completeMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'm',
          totalCollected: 0,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.meetings.cancelMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: 'm',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.meetings.createMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          scheduledAt: world.now,
        )).failure,
        isA<StorageFailure>(),
      );
    });

    test('governance, invites, keys and reports', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      await world.closeDatabase();

      expect(
        (await owner.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'owner',
          transactionId: 't',
          reason: 'x',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.governance.dissolutionBlockers(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.governance.decideReversal(
          groupId: gid,
          actingPeerId: 'owner',
          reversalId: 'r',
          approve: true,
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.governance.reversalsForGroup(gid)).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.invites.getById('i')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.governance.dissolveGroup(
          groupId: gid,
          actingPeerId: 'owner',
        )).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await owner.invites.liveInvites(gid)).failure,
        isA<StorageFailure>(),
      );
      // Unreadable keys read as missing (enter the passphrase).
      expect(await world.keys.hasKey('unknown-group'), isFalse);
      expect(
        (await world.reports.generateGroupReport(
          groupId: gid,
          period: DateTimePeriod(
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 12, 31),
          ),
        )).failure,
        isA<StorageFailure>(),
      );
    });
  });
}
