import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/invite_service.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/invites.dart';
import 'package:vbank/src/domain/meetings.dart';

import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('MeetingService', () {
    test('schedules with absent rows, takes attendance, closes', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final Meeting meeting = (await owner.meetings.createMeeting(
        groupId: gid,
        actingPeerId: 'owner',
        scheduledAt: world.now.add(const Duration(days: 1)),
        notes: 'Weekly',
      ))
          .value;
      expect(meeting.attendance, hasLength(2));
      expect(
        (await member.meetings.recordAttendance(
          groupId: gid,
          actingPeerId: 'member',
          meetingId: meeting.id,
          peerId: 'member',
          status: MeetingAttendanceStatus.present,
          contributed: true,
        )).failure,
        isA<PermissionFailure>(),
        reason: 'members cannot take attendance',
      );

      expect(
        (await owner.meetings.recordAttendance(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: meeting.id,
          peerId: 'member',
          status: MeetingAttendanceStatus.present,
          contributed: true,
        )).isOk,
        isTrue,
      );
      expect(
        (await owner.meetings.completeMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: meeting.id,
          totalCollected: 200,
        )).isOk,
        isTrue,
      );
      final Meeting closed = (await owner.meetings.getById(meeting.id)).value;
      expect(closed.status, MeetingStatus.completed);
      expect(closed.presentCount, 1);

      // Closed meetings are frozen.
      expect(
        (await owner.meetings.recordAttendance(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: meeting.id,
          peerId: 'owner',
          status: MeetingAttendanceStatus.present,
        )).failure,
        isA<ConflictFailure>(),
      );

      // ... but cancelling still works on open ones.
      final Meeting second = (await owner.meetings.createMeeting(
        groupId: gid,
        actingPeerId: 'owner',
        scheduledAt: world.now.add(const Duration(days: 8)),
      ))
          .value;
      expect(
        (await owner.meetings.cancelMeeting(
          groupId: gid,
          actingPeerId: 'owner',
          meetingId: second.id,
        )).isOk,
        isTrue,
      );
      expect(
        (await owner.meetings.getById(second.id)).value.status,
        MeetingStatus.cancelled,
      );
    });
  });

  group('InviteService', () {
    test('creates signed invites with wrapped keys', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final secretKey = await world.keys.getKey(gid);

      final CreatedInvite created = (await owner.invites.createInvite(
        groupId: gid,
        groupCid: 'bafkrei-1',
        groupTopic: 'vbank/group/$gid',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        groupKey: secretKey!,
      ))
          .value;

      expect(created.invite.wrappedKey, isNotNull);
      expect(created.secret, isNotNull);
      expect(created.secretLink, isNotNull);

      final DateTime now = world.now;
      expect(
        (await owner.invites.liveInvites(gid, now: now)).value,
        hasLength(1),
      );

      // The invite verifies against the roster key and presented nonce.
      expect(
        (await InviteService.verify(
          created.invite,
          groupId: gid,
          presentedNonce: created.invite.nonce,
          inviterPublicKey: world.publicKeys['owner']!,
          now: now,
        )).isOk,
        isTrue,
      );
    });

    test('verification rejects the used, expired and forged', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final secretKey = await world.keys.getKey(gid);
      final CreatedInvite created = (await owner.invites.createInvite(
        groupId: gid,
        groupCid: 'cid',
        groupTopic: 't',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        groupKey: secretKey!,
      ))
          .value;
      Future<Failure> check(Invite i, {List<int>? nonce}) =>
          InviteService.verify(
            i,
            groupId: gid,
            presentedNonce: nonce ?? i.nonce,
            inviterPublicKey: world.publicKeys['owner']!,
            now: world.now,
          ).then((r) => r.failure);

      expect(
        await check(created.invite, nonce: [1, 2, 3]),
        isA<ValidationFailure>(),
      );
      expect(
        await InviteService.verify(
          created.invite,
          groupId: 'other',
          presentedNonce: created.invite.nonce,
          inviterPublicKey: world.publicKeys['owner']!,
          now: world.now,
        ).then((r) => r.failure),
        isA<ValidationFailure>(),
      );

      world.elapse(const Duration(hours: 13));
      expect(
        (await owner.invites.liveInvites(gid)).value,
        isEmpty,
        reason: '12 h expiry passed',
      );
      expect(
        await check(created.invite),
        isA<ConflictFailure>(),
        reason: 'expired reads as conflict',
      );
    });

    test('used flags merge without reverting', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final secretKey = await world.keys.getKey(gid);
      final CreatedInvite created = (await owner.invites.createInvite(
        groupId: gid,
        groupCid: 'cid',
        groupTopic: 't',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        groupKey: secretKey!,
      ))
          .value;

      await owner.invites.invites.markUsed(created.invite.id);
      expect(
        (await owner.invites.getById(created.invite.id)).value.used,
        isTrue,
      );

      // A snapshot claiming unused does not resurrect it.
      await owner.invites.mergeUsed([created.invite]);
      expect(
        (await owner.invites.getById(created.invite.id)).value.used,
        isTrue,
      );
    });
  });
}
