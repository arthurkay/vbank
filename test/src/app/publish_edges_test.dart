import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/publish_pipeline.dart';
import 'package:vbank/src/crypto/member_keys.dart';
import 'package:vbank/src/crypto/signing.dart';
import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/transactions.dart';

import '../sync/fakes.dart';
import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  PublishPipeline pipelineFor(
    ServiceStack stack,
    FakeTransport transport,
    String peer, {
    Future<SimpleKeyPair?> Function()? memberKeyPair,
  }) {
    return PublishPipeline(
      transport: transport,
      keys: world.keys,
      groups: stack.groups,
      invites: stack.invites,
      governance: stack.governance,
      ledgerRecord: (String groupId, String cid) async {},
      ownAddrs: () => const [],
      memberKeyPair: memberKeyPair ?? () async => null,
      clock: () => world.now,
    )..bindSigningKey(() => world.keyFor(peer));
  }

  group('PublishPipeline edges', () {
    test('publishes every record type with versions', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      final FakeTransport transport = FakeTransport('owner');
      final PublishPipeline pipeline = pipelineFor(owner, transport, 'owner');
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
        requestedAmount: 100,
        termWeeks: 4,
      ))
          .value;
      final Meeting meeting = (await owner.meetings.createMeeting(
        groupId: gid,
        actingPeerId: 'owner',
        scheduledAt: world.now,
      ))
          .value;
      final List<Transaction> ledger =
          (await owner.transactions.listByGroup(gid)).value;
      final Transaction own = ledger.firstWhere(
        (Transaction t) => t.fromPeerId == 'member',
      );
      final reversal = (await member.governance.requestReversal(
        groupId: gid,
        actingPeerId: 'member',
        transactionId: own.id,
        reason: 'test',
      ))
          .value;

      for (final String cid in [
        (await pipeline.publishLoan(loan)).value,
        (await pipeline.publishMeeting(meeting, 'owner')).value,
        (await pipeline.publishReversal(reversal)).value,
        (await pipeline.publishMemberKey(
          groupId: gid,
          peerId: 'member',
          encKey: Uint8List.fromList([1]),
          keyPair: await world.keyFor('owner'),
        ))
            .value,
        (await pipeline.publishRaw(
          groupId: gid,
          type: SyncPayloadType.memberKey,
          payloadJson: const {'v': 1},
        ))
            .value,
      ]) {
        final SyncEnvelope? envelope = SyncEnvelope.tryDecode(
          transport.blocks[cid]!,
        );
        expect(envelope, isNotNull);
        expect(envelope!.keyVersion, 1);
      }
    });

    test('rekeys ride snapshots after rotation', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final FakeTransport transport = FakeTransport('owner');
      final SimpleKeyPair ownerEnc = await MemberKeys.fromIdentitySeed(
        await SigningService.extractSeed(await world.keyFor('owner')),
      );
      final PublishPipeline pipeline = pipelineFor(
        owner,
        transport,
        'owner',
        memberKeyPair: () async => ownerEnc,
      );

      // Member publishes a key, owner rotates, snapshot carries the seal.
      final Uint8List memberPub = await MemberKeys.publicKeyBytes(
        await MemberKeys.fromIdentitySeed(
          await SigningService.extractSeed(await world.keyFor('member')),
        ),
      );
      final group = (await owner.groups.getGroup(gid)).value;
      await owner.groups.setMemberEncKey(group, 'member', memberPub);
      final String cid = (await pipeline.rotateGroupKey(
        groupId: gid,
        publisherPeerId: 'owner',
      ))
          .value;
      final SyncEnvelope envelope = SyncEnvelope.tryDecode(
        transport.blocks[cid]!,
      )!;
      expect(envelope.keyVersion, 2);
      expect(envelope.rekeys.keys, ['member']);
    });

    test('missing groups, keys and bindings fail publishing', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final FakeTransport transport = FakeTransport('owner');
      final PublishPipeline pipeline = pipelineFor(owner, transport, 'owner');

      expect(
        (await pipeline.buildSnapshot(
          groupId: 'nope',
          publisherPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await pipeline.publishSnapshot(
          groupId: 'nope',
          publisherPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
      expect(
        (await pipeline.rotateGroupKey(
          groupId: 'nope',
          publisherPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );

      await world.keys.removeKey(gid);
      expect(
        (await pipeline.publishSnapshot(
          groupId: gid,
          publisherPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );

      final PublishPipeline unbound = PublishPipeline(
        transport: transport,
        keys: world.keys,
        groups: owner.groups,
        invites: owner.invites,
        governance: owner.governance,
        ledgerRecord: (String groupId, String cid) async {},
        ownAddrs: () => const [],
        memberKeyPair: () async => null,
        clock: () => world.now,
      );
      final Meeting meeting = (await owner.meetings.createMeeting(
        groupId: gid,
        actingPeerId: 'owner',
        scheduledAt: world.now,
      ))
          .value;
      expect(
        (await unbound.publishMeeting(meeting, 'owner')).failure,
        isA<StorageFailure>(),
      );
    });
  });
}
