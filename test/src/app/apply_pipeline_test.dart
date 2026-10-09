import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/signing_payloads.dart';
import 'package:vbank/src/crypto/member_keys.dart';
import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/sync/engine.dart';
import 'package:vbank/src/sync/record_codec.dart';

import 'harness.dart';

/// Builds a signed join announcement for [peer] holding the link.
Future<Map<String, dynamic>> joinPayload(
  AppHarness world,
  String gid,
  CreatedInviteResult invite, {
  String peer = 'newcomer',
  String name = 'Newcomer',
}) async {
  await world.keyFor(peer);
  final Uint8List sig = await world.signerFor(peer)(
    SigningPayloads.memberJoin(
      groupId: gid,
      peerId: peer,
      inviteId: invite.id,
    ),
  );
  return {
    'member': RecordCodec.memberToJson(
      Member(
        peerId: peer,
        name: name,
        joinedAt: world.now,
        publicKey: world.publicKeys[peer]!,
        encKey: Uint8List.fromList([4, 4]),
      ),
    ),
    'addrs': ['/ip4/7.7.7.7/tcp/4001/p2p/$peer'],
    'signature': sig,
    'inviteId': invite.id,
    'nonce': base64Encode(invite.nonce),
  };
}



void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('ApplyPipeline envelopes', () {
    test('rejects garbage, strangers and tampering', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;

      expect(
        await harness.pipeline.apply(gid, 'cid-0', Uint8List.fromList([1])),
        ApplyOutcome.rejected,
      );
      // Unknown group defers (the join may still arrive).
      final Uint8List foreign = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: 'unknown',
        payload: const {},
        key: key,
      );
      expect(
        await harness.pipeline.apply('unknown', 'cid-1', foreign),
        ApplyOutcome.deferred,
      );
      // Known group without a key defers too.
      await world.keys.removeKey(gid);
      final Uint8List noKey = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: gid,
        payload: const {},
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-2', noKey),
        ApplyOutcome.deferred,
      );
    });

    test('defers unknown key versions, rejects wrong keys', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;

      final Uint8List future = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: gid,
        payload: const {},
        key: key,
        keyVersion: 9,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-9', future),
        ApplyOutcome.deferred,
      );

      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: gid,
        payload: RecordCodec.transactionToJson(
          (await world.stackFor('owner').transactions.listByGroup(gid)).value
              .first,
        ),
        key: SecretKey(List.filled(32, 9)),
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-x', sealed),
        ApplyOutcome.rejected,
      );
    });

    test('rejections log type and key version', () async {
      final List<String> logs = [];
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
      };
      addTearDown(() {
        debugPrint = originalPrint;
      });
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');

      expect(
        await harness.pipeline.apply(
          gid,
          'cid-garbage-000',
          Uint8List.fromList(const [1]),
        ),
        ApplyOutcome.rejected,
      );
      expect(logs.any((line) => line.contains('type=undecoded')), isTrue);
      expect(logs.any((line) => line.contains('cid-garbage')), isTrue);

      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: gid,
        payload: const {},
        key: SecretKey(List.filled(32, 9)),
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-wrongkey-0', sealed),
        ApplyOutcome.rejected,
      );
      expect(logs.any((line) => line.contains('type=transaction')), isTrue);
    });
  });

  group('ApplyPipeline transactions', () {
    test('stores signed contributions, rejects the rest', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');

      Future<Uint8List> envelopeFor(Transaction tx) => sealFor(
            type: SyncPayloadType.transaction,
            groupId: gid,
            payload: RecordCodec.transactionToJson(tx),
            key: key,
          );

      // A fresh contribution signed by the owner applies.
      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'owner',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 75,
      ))
          .value;
      // Already stored locally: duplicate still counts as applied.
      expect(
        await harness.pipeline.apply(gid, 'cid-tx', await envelopeFor(tx)),
        ApplyOutcome.applied,
      );

      // A member's signature carries no authority.
      await world.keyFor('intruder');
      final Transaction forged = Transaction(
        id: 'forged',
        groupId: gid,
        fromPeerId: 'intruder',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 1000,
        timestamp: world.now,
        sequenceNumber: 99,
        senderSignature: Uint8List(0),
        authorPeerId: 'intruder',
      );
      final Transaction signedForged = Transaction(
        id: forged.id,
        groupId: forged.groupId,
        fromPeerId: forged.fromPeerId,
        toPeerId: forged.toPeerId,
        type: forged.type,
        amount: forged.amount,
        timestamp: forged.timestamp,
        sequenceNumber: forged.sequenceNumber,
        senderSignature: await world.signerFor('intruder')(
          SigningPayloads.transaction(forged),
        ),
        authorPeerId: forged.authorPeerId,
      );
      expect(
        await harness.pipeline.apply(
          gid,
          'cid-forged',
          await envelopeFor(signedForged),
        ),
        ApplyOutcome.rejected,
      );

      // Group mismatch rejects.
      final Uint8List wrongGroup = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: 'other',
        payload: RecordCodec.transactionToJson(tx),
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-wg', wrongGroup),
        ApplyOutcome.rejected,
      );
    });
  });

  group('ApplyPipeline snapshots', () {
    test('applies newer rosters, keeps stale ones ledgered', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');

      // Owner adds a member locally, snapshots, and the member applies.
      await world.keyFor('newcomer');
      Group group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.addMember(
        group,
        Member(
          peerId: 'newcomer',
          name: 'Newcomer',
          joinedAt: world.now,
          publicKey: world.publicKeys['newcomer']!,
        ),
      );
      group = (await owner.groups.getGroup(gid)).value;
      final Map<String, dynamic> body = {
        'v': 2,
        'group': RecordCodec.groupToJson(group),
        'invites': const <Map<String, dynamic>>[],
        'transfers': const <Map<String, dynamic>>[],
        'removals': const <Map<String, dynamic>>[],
        'publisher': 'owner',
        'publisherAddrs': ['/ip4/9.9.9.9/tcp/4001/p2p/owner'],
        'publishedAt': world.now.toIso8601String(),
      };
      final Uint8List sig = await world.signerFor('owner')(
        utf8.encode(jsonEncode(body)),
      );
      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.groupSnapshot,
        groupId: gid,
        payload: {...body, 'signature': sig},
        key: key,
      );

      expect(
        await harness.pipeline.apply(gid, 'cid-snap', sealed),
        ApplyOutcome.applied,
      );
      expect(harness.remembered[gid], ['/ip4/9.9.9.9/tcp/4001/p2p/owner']);
      Group updated = (await owner.groups.getGroup(gid)).value;
      expect(
        updated.members.any((Member m) => m.peerId == 'newcomer'),
        isTrue,
      );

      // Replaying the same snapshot is stale but ledgered, not an error.
      expect(
        await harness.pipeline.apply(gid, 'cid-snap-2', sealed),
        ApplyOutcome.applied,
      );
      updated = (await owner.groups.getGroup(gid)).value;
      expect(updated.cid, 'cid-snap-2');
    });

    test('rejects unsigned, foreign and stale-authored snapshots', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final Group group = (await owner.groups.getGroup(gid)).value;
      final Map<String, dynamic> body = {
        'v': 2,
        'group': RecordCodec.groupToJson(group),
        'invites': const <Map<String, dynamic>>[],
        'transfers': const <Map<String, dynamic>>[],
        'removals': const <Map<String, dynamic>>[],
        'publisher': 'owner',
        'publisherAddrs': const <String>[],
        'publishedAt': world.now.toIso8601String(),
      };
      Future<Uint8List> sealBody(Map<String, dynamic> b) => sealFor(
            type: SyncPayloadType.groupSnapshot,
            groupId: gid,
            payload: b,
            key: key,
          );

      // Unsigned.
      expect(
        await harness.pipeline.apply(gid, 'c1', await sealBody(body)),
        ApplyOutcome.rejected,
      );
      // Signed by a plain member.
      final Uint8List memberSig = await world.signerFor('member')(
        utf8.encode(jsonEncode(body)),
      );
      expect(
        await harness.pipeline.apply(
          gid,
          'c2',
          await sealBody({...body, 'signature': memberSig}),
        ),
        ApplyOutcome.rejected,
      );
      // Malformed group body.
      final Uint8List ownerSig = await world.signerFor('owner')(
        utf8.encode(jsonEncode(body)),
      );
      expect(
        await harness.pipeline.apply(
          gid,
          'c3',
          await sealFor(
            type: SyncPayloadType.groupSnapshot,
            groupId: gid,
            payload: {
              ...body,
              'group': {'id': 'x'},
              'signature': ownerSig,
            },
            key: key,
          ),
        ),
        ApplyOutcome.rejected,
        reason: 'signature covers a different body',
      );
    });
  });

  group('ApplyPipeline joins', () {
    test('admins admit newcomers and spend invites', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('owner');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final CreatedInviteResult created =
          await _createInvite(world, owner, gid, key);

      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.memberJoin,
        groupId: gid,
        payload: await joinPayload(world, gid, created),
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-join', sealed),
        ApplyOutcome.applied,
      );

      final Group group = (await owner.groups.getGroup(gid)).value;
      final Member joined = group.members
          .where((Member m) => m.peerId == 'newcomer')
          .single;
      expect(joined.status, MemberStatus.active);
      expect(joined.role, MemberRole.member);
      expect(joined.encKey, Uint8List.fromList([4, 4]));
      expect(harness.remembered[gid], ['/ip4/7.7.7.7/tcp/4001/p2p/newcomer']);
      expect(
        (await owner.invites.getById(created.id)).value.used,
        isTrue,
      );
    });

    test('approval groups park joiners as pending', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.updateGroupConfig(
        group: group,
        actingPeerId: 'owner',
        config: group.config,
        requireApproval: true,
      );
      final PipelineHarness harness = world.pipelineFor('owner');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final CreatedInviteResult created =
          await _createInvite(world, owner, gid, key);

      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.memberJoin,
        groupId: gid,
        payload: await joinPayload(world, gid, created),
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-join', sealed),
        ApplyOutcome.applied,
      );

      group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members
            .where((Member m) => m.peerId == 'newcomer')
            .single
            .status,
        MemberStatus.pending,
      );
    });

    test('banned joiners stay out with spent invites', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      Group group = (await owner.groups.getGroup(gid)).value;
      await world.keyFor('newcomer');
      await owner.groups.addMember(
        group,
        Member(
          peerId: 'newcomer',
          name: 'Newcomer',
          joinedAt: world.now,
          publicKey: world.publicKeys['newcomer']!,
        ),
      );
      group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.removeMember(
        group: group,
        actingPeerId: 'owner',
        peerId: 'newcomer',
        reason: 'test',
      );
      final PipelineHarness harness = world.pipelineFor('owner');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final CreatedInviteResult created =
          await _createInvite(world, owner, gid, key);

      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.memberJoin,
        groupId: gid,
        payload: await joinPayload(world, gid, created),
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-join', sealed),
        ApplyOutcome.applied,
      );
      expect(
        (await owner.invites.getById(created.id)).value.used,
        isTrue,
      );
      group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members
            .where((Member m) => m.peerId == 'newcomer')
            .single
            .status,
        MemberStatus.removed,
      );
    });

    test('non-admin devices converge through snapshots', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final CreatedInviteResult created =
          await _createInvite(world, owner, gid, key);

      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.memberJoin,
        groupId: gid,
        payload: await joinPayload(world, gid, created),
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-join', sealed),
        ApplyOutcome.applied,
      );

      final Group group = (await owner.groups.getGroup(gid)).value;
      expect(
        group.members.any((Member m) => m.peerId == 'newcomer'),
        isFalse,
      );
      expect(
        (await owner.invites.getById(created.id)).value.used,
        isFalse,
      );
    });

    test('forged and incomplete joins reject', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('owner');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final CreatedInviteResult created =
          await _createInvite(world, owner, gid, key);
      Future<ApplyOutcome> applyJoin(Map<String, dynamic> payload) async =>
          harness.pipeline.apply(
            gid,
            'cid',
            await sealFor(
              type: SyncPayloadType.memberJoin,
              groupId: gid,
              payload: payload,
              key: key,
            ),
          );

      final Map<String, dynamic> good = await joinPayload(
        world,
        gid,
        created,
      );
      // Wrong link secret.
      expect(
        await applyJoin({...good, 'nonce': base64Encode([0])}),
        ApplyOutcome.rejected,
      );
      // Unknown invite.
      expect(
        await applyJoin({...good, 'inviteId': 'nope'}),
        ApplyOutcome.rejected,
      );
      // Missing fields.
      expect(
        await applyJoin({'member': good['member']}),
        ApplyOutcome.rejected,
      );
      // Tampered membership (role is forced server-side anyway, but the
      // signature must cover the announced bytes).
      final Map<String, dynamic> tampered = Map<String, dynamic>.from(good);
      tampered['signature'] = [0, 1, 2];
      expect(await applyJoin(tampered), ApplyOutcome.rejected);
    });
  });

  group('ApplyPipeline loans, meetings, reversals, keys', () {
    test('repayment records allocate their schedules', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }
      final LoanRequest loan = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 200,
        termWeeks: 2,
      ))
          .value;
      await owner.loans.approveLoan(
        loanId: loan.id,
        approvedAmount: 200,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(
        loanId: loan.id,
        adminPeerId: 'owner',
      );
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      // A repayment authored remotely (not stored locally): import stores
      // it and allocates the schedule in one motion.
      final Transaction unsigned = Transaction(
        id: 'repay-remote',
        groupId: gid,
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.repayment,
        amount: 110,
        timestamp: world.now,
        sequenceNumber: 99,
        senderSignature: Uint8List(0),
        authorPeerId: 'owner',
        loanId: loan.id,
      );
      final Transaction repayment = Transaction(
        id: unsigned.id,
        groupId: unsigned.groupId,
        fromPeerId: unsigned.fromPeerId,
        toPeerId: unsigned.toPeerId,
        type: unsigned.type,
        amount: unsigned.amount,
        timestamp: unsigned.timestamp,
        sequenceNumber: unsigned.sequenceNumber,
        senderSignature: await world.signerFor('owner')(
          SigningPayloads.transaction(unsigned),
        ),
        authorPeerId: unsigned.authorPeerId,
        loanId: unsigned.loanId,
      );
      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.transaction,
        groupId: gid,
        payload: RecordCodec.transactionToJson(repayment),
        key: key,
      );

      expect(
        await harness.pipeline.apply(gid, 'cid-repay', sealed),
        ApplyOutcome.applied,
      );
      final schedules = await owner.loans.schedule(loan.id);
      expect(
        schedules.value.firstWhere((s) => s.installmentNumber == 1).paidAmount,
        110,
      );
    });

    test('snapshots carry governance history', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final PipelineHarness harness = world.pipelineFor('member');
      Group group = (await owner.groups.getGroup(gid)).value;

      // A transfer then a removal ride the next snapshot.
      await owner.groups.updateMemberRole(
        group: group,
        actingPeerId: 'owner',
        peerId: 'member',
        newRole: MemberRole.admin,
      );
      group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.transferOwnership(
        group: group,
        actingPeerId: 'owner',
        toPeerId: 'member',
      );
      group = (await owner.groups.getGroup(gid)).value;
      final ServiceStack newOwner = world.stackFor('member');
      await newOwner.groups.removeMember(
        group: group,
        actingPeerId: 'member',
        peerId: 'owner',
        reason: 'test',
      );
      final Map<String, dynamic> body = {
        'v': 2,
        'group': RecordCodec.groupToJson(
          (await owner.groups.getGroup(gid)).value,
        ),
        'invites': const <Map<String, dynamic>>[],
        'transfers': [
          RecordCodec.transferToJson(
            (await owner.groups.governance.transfersByGroup(gid)).value.single,
          ),
        ],
        'removals': [
          RecordCodec.removalToJson(
            (await owner.groups.governance.removalsByGroup(gid)).value.single,
          ),
        ],
        'dissolution': RecordCodec.dissolutionToJson(
          GroupDissolution(
            id: 'd-1',
            groupId: 'g',
            initiatedByPeerId: 'owner',
            initiatedAt: DateTime.utc(2026, 6, 1),
          ),
        ),
        'publisher': 'member',
        'publisherAddrs': const <String>[],
        'publishedAt': world.now.toIso8601String(),
      };
      final Uint8List sig = await world.signerFor('member')(
        utf8.encode(jsonEncode(body)),
      );
      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.groupSnapshot,
        groupId: gid,
        payload: {...body, 'signature': sig},
        key: key,
      );

      expect(
        await harness.pipeline.apply(gid, 'cid-gov', sealed),
        ApplyOutcome.applied,
      );
      final Group updated = (await owner.groups.getGroup(gid)).value;
      expect(updated.owner?.peerId, 'member');
      expect(
        (await owner.groups.governance.transfersByGroup(gid)).value,
        hasLength(1),
      );
    });

    test('join re-announcements update keys in place', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final PipelineHarness harness = world.pipelineFor('owner');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final CreatedInviteResult created =
          await _createInvite(world, owner, gid, key);
      // The member rode in on a snapshot (keyless row), then announces
      // with a live invite: the roster gains the key, no duplicate row.
      await world.keyFor('newcomer');
      Group group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.addMember(
        group,
        Member(
          peerId: 'newcomer',
          name: 'Newcomer',
          joinedAt: world.now,
          publicKey: world.publicKeys['newcomer']!,
        ),
      );
      final Map<String, dynamic> announced = await joinPayload(
        world,
        gid,
        created,
      );
      Future<ApplyOutcome> applyJoin(Map<String, dynamic> payload) async =>
          harness.pipeline.apply(
            gid,
            'cid',
            await sealFor(
              type: SyncPayloadType.memberJoin,
              groupId: gid,
              payload: payload,
              key: key,
            ),
          );

      expect(await applyJoin(announced), ApplyOutcome.applied);
      group = (await owner.groups.getGroup(gid)).value;
      final List<Member> newcomers = group.members
          .where((Member m) => m.peerId == 'newcomer')
          .toList();
      expect(newcomers, hasLength(1));
      expect(newcomers.single.encKey, Uint8List.fromList([4, 4]));

      // Replaying the spent invite rejects instead.
      expect(await applyJoin(announced), ApplyOutcome.rejected);
    });

    test('loan records verify borrower and approver', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }
      Future<ApplyOutcome> applyLoan(LoanRequest loan) async =>
          harness.pipeline.apply(
            gid,
            'cid-${loan.id}',
            await sealFor(
              type: SyncPayloadType.loan,
              groupId: gid,
              payload: RecordCodec.loanToJson(loan),
              key: key,
            ),
          );

      final LoanRequest requested = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 200,
        termWeeks: 4,
      ))
          .value;
      // Already stored locally: duplicate path still applies.
      expect(await applyLoan(requested), ApplyOutcome.applied);

      // Unknown borrower rejects.
      await world.keyFor('ghost');
      final LoanRequest ghost = LoanRequest(
        id: 'ghost-loan',
        groupId: gid,
        borrowerPeerId: 'ghost',
        requestedAmount: 10,
        interestRate: 0.1,
        termWeeks: 4,
        requestedAt: world.now,
        borrowerSignature: Uint8List(0),
      );
      final LoanRequest signedGhost = ghost.copyWith(
        borrowerSignature: await world.signerFor('ghost')(
          SigningPayloads.loanRequest(ghost),
        ),
      );
      expect(await applyLoan(signedGhost), ApplyOutcome.rejected);

      // Approved records verify the approver too.
      final LoanRequest approved = (await owner.loans.approveLoan(
        loanId: requested.id,
        approvedAmount: 200,
        approverPeerId: 'owner',
      ))
          .value;
      expect(await applyLoan(approved), ApplyOutcome.applied);

      // Group mismatch rejects.
      final Uint8List wrongGroup = await sealFor(
        type: SyncPayloadType.loan,
        groupId: 'other',
        payload: RecordCodec.loanToJson(approved),
        key: key,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-wg', wrongGroup),
        ApplyOutcome.rejected,
      );
    });

    test('meetings verify the publishing admin', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final Meeting meeting = (await owner.meetings.createMeeting(
        groupId: gid,
        actingPeerId: 'owner',
        scheduledAt: world.now,
      ))
          .value;
      final Map<String, dynamic> meetingJson = RecordCodec.meetingToJson(
        meeting,
      );
      Future<Uint8List> wrap(
        Map<String, dynamic> wrap,
      ) =>
          sealFor(
            type: SyncPayloadType.meeting,
            groupId: gid,
            payload: wrap,
            key: key,
          );
      Future<Map<String, dynamic>> signedBy(String peer) async => {
            'v': 1,
            'meeting': meetingJson,
            'publisher': peer,
            'signature': await world.signerFor(peer)(
              utf8.encode(jsonEncode(meetingJson)),
            ),
          };

      expect(
        await harness.pipeline.apply(
          gid,
          'cid-m',
          await wrap(await signedBy('owner')),
        ),
        ApplyOutcome.applied,
      );
      expect(
        await harness.pipeline.apply(
          gid,
          'cid-m2',
          await wrap(await signedBy('member')),
        ),
        ApplyOutcome.rejected,
      );
      expect(
        await harness.pipeline.apply(
          gid,
          'cid-m3',
          await wrap({'v': 1}),
        ),
        ApplyOutcome.rejected,
      );
    });

    test('reversals apply through governance', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;
      final TransactionReversal reversal = (await member.governance
              .requestReversal(
        groupId: gid,
        actingPeerId: 'member',
        transactionId: tx.id,
        reason: 'wrong amount',
      ))
          .value;
      final Uint8List sealed = await sealFor(
        type: SyncPayloadType.reversal,
        groupId: gid,
        payload: RecordCodec.reversalToJson(reversal),
        key: key,
      );

      expect(
        await harness.pipeline.apply(gid, 'cid-r', sealed),
        ApplyOutcome.applied,
      );
      expect(
        await harness.pipeline.apply(gid, 'cid-r2', sealed),
        ApplyOutcome.applied,
        reason: 'idempotent re-application',
      );
    });

    test('member keys store after roster verification', () async {
      final String gid = await world.seedGroup();
      final PipelineHarness harness = world.pipelineFor('member');
      final SecretKey key = (await world.keys.getKey(gid))!;
      final Uint8List encKey = Uint8List.fromList([5, 5]);
      Future<Uint8List> wrap(Map<String, dynamic> payload) => sealFor(
            type: SyncPayloadType.memberKey,
            groupId: gid,
            payload: payload,
            key: key,
          );

      final Map<String, dynamic> good = {
        'peerId': 'member',
        'encKey': encKey,
        'signature': await world.signerFor('member')(
          SigningPayloads.memberKey(
            groupId: gid,
            peerId: 'member',
            encKey: encKey,
          ),
        ),
      };
      expect(
        await harness.pipeline.apply(gid, 'cid-k', await wrap(good)),
        ApplyOutcome.applied,
      );
      final ServiceStack owner = world.stackFor('owner');
      expect(
        (await owner.groups.getMember(gid, 'member'))!.encKey,
        encKey,
      );

      // Unknown members defer (their join/snapshot is still in flight);
      // forgeries reject.
      expect(
        await harness.pipeline.apply(
          gid,
          'cid-k2',
          await wrap({...good, 'peerId': 'ghost'}),
        ),
        ApplyOutcome.deferred,
      );
      expect(
        await harness.pipeline.apply(
          gid,
          'cid-k3',
          await wrap({...good, 'signature': [0]}),
        ),
        ApplyOutcome.rejected,
      );
    });

    test('rekeyed rings import for the recipient', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      // Member's X25519 pair from their identity seed.
      final SimpleKeyPair memberEnc =
          await MemberKeys.fromIdentitySeed(List.filled(32, 2));
      await world.keyFor('member');
      final SimpleKeyPair ownerEnc =
          await MemberKeys.fromIdentitySeed(List.filled(32, 1));

      // Owner rotates; the snapshot would carry the seal (phase 6). Here
      // the seal is applied directly with a trivial payload.
      final GroupKeyRing ring = (await world.keys.rotate(gid)).value;
      final Uint8List sealed = await MemberKeys.seal(
        plaintext: ring.encode(),
        sender: ownerEnc,
        recipientPublicKey: await MemberKeys.publicKeyBytes(memberEnc),
        groupId: gid,
        recipientPeerId: 'member',
      );
      // Seal a no-op transaction envelope carrying the rekey.
      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'owner',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 10,
      ))
          .value;
      final Uint8List envelope = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: gid,
        plaintextJson: RecordCodec.transactionToJson(tx),
        groupKey: (await world.keys.getKey(gid))!,
        keyVersion: 2,
        rekeys: {'member': sealed},
      );

      // The member pipeline needs its X25519 pair.
      final PipelineHarness withKeys = world.pipelineFor(
        'member',
        memberKeyPair: () async => memberEnc,
      );
      expect(
        await withKeys.pipeline.apply(gid, 'cid-rekey', envelope),
        ApplyOutcome.applied,
      );
      expect((await world.keys.ring(gid))!.currentVersion, 2);
    });
  });
}

/// Invite creation result for join tests: the link carries the invite id,
/// the one-time secret and the nonce; the join announcement presents the
/// nonce back to prove link possession.
final class CreatedInviteResult {
  /// Invite id.
  final String id;

  /// Link secret (unused by the join proof itself).
  final Uint8List secret;

  /// The invite nonce, presented back in the join announcement.
  final Uint8List nonce;

  /// Creates the test handle.
  const CreatedInviteResult(this.id, this.secret, this.nonce);
}

Future<CreatedInviteResult> _createInvite(
  AppHarness world,
  ServiceStack owner,
  String gid,
  SecretKey key,
) async {
  final created = (await owner.invites.createInvite(
    groupId: gid,
    groupCid: 'cid-$gid',
    groupTopic: 'vbank/group/$gid',
    inviterPeerId: 'owner',
    inviterName: 'Owner',
    groupKey: key,
  ))
      .value;
  return CreatedInviteResult(
    created.invite.id,
    created.secret!,
    created.invite.nonce,
  );
}


