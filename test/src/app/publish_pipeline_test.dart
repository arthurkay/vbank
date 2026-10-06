
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/publish_pipeline.dart';
import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/domain/core/failure.dart';
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
    AppHarness world,
    ServiceStack stack,
    FakeTransport transport,
    List<String> ledger,
    String peer,
  ) {
    return PublishPipeline(
      transport: transport,
      keys: world.keys,
      groups: stack.groups,
      invites: stack.invites,
      governance: stack.governance,
      ledgerRecord: (String groupId, String cid) async =>
          ledger.add(cid),
      ownAddrs: () => ['/ip4/1.1.1.1/tcp/4001/p2p/$peer'],
      memberKeyPair: () async => null,
      clock: () => world.now,
    )..bindSigningKey(() => world.keyFor(peer));
  }

  group('PublishPipeline', () {
    test('records seal, store and ledger with key versions', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final FakeTransport transport = FakeTransport('owner');
      final List<String> ledger = [];
      final PublishPipeline pipeline = pipelineFor(
        world,
        owner,
        transport,
        ledger,
        'owner',
      );

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'owner',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 50,
      ))
          .value;
      final String cid = (await pipeline.publishTransaction(tx)).value;

      expect(ledger, [cid]);
      final SyncEnvelope? envelope = SyncEnvelope.tryDecode(
        transport.blocks[cid]!,
      );
      expect(envelope, isNotNull);
      expect(envelope!.type, SyncPayloadType.transaction);
      expect(envelope.keyVersion, 1);
      final SecretKey key = (await world.keys.getKey(gid))!;
      expect(await envelope.open(key), containsPair('id', tx.id));
    });

    test('snapshots carry wraps, signature and group CID', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final FakeTransport transport = FakeTransport('owner');
      final List<String> ledger = [];
      final PublishPipeline pipeline = pipelineFor(
        world,
        owner,
        transport,
        ledger,
        'owner',
      );
      final SecretKey key = (await world.keys.getKey(gid))!;
      await owner.invites.createInvite(
        groupId: gid,
        groupCid: 'cid-1',
        groupTopic: 'vbank/group/$gid',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        groupKey: key,
      );

      final String cid = (await pipeline.publishSnapshot(
        groupId: gid,
        publisherPeerId: 'owner',
      ))
          .value;

      final SyncEnvelope envelope = SyncEnvelope.tryDecode(
        transport.blocks[cid]!,
      )!;
      expect(envelope.type, SyncPayloadType.groupSnapshot);
      expect(envelope.wraps.keys, hasLength(1));
      final Map<String, dynamic> body = await envelope.open(key);
      expect(body['publisher'], 'owner');
      expect(body['publisherAddrs'], contains('/ip4/1.1.1.1/tcp/4001/p2p/owner'));
      expect(
        (await owner.groups.getGroup(gid)).value.cid,
        cid,
      );

      // Members cannot publish snapshots.
      expect(
        (await world.stackFor('member').groups.getGroup(gid)).isOk,
        isTrue,
      );
      final PublishPipeline memberPipeline = pipelineFor(
        world,
        world.stackFor('member'),
        transport,
        ledger,
        'member',
      );
      expect(
        (await memberPipeline.publishSnapshot(
          groupId: gid,
          publisherPeerId: 'member',
        )).failure,
        isA<PermissionFailure>(),
      );
    });

    test('rotations publish rekeyed snapshots', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final FakeTransport transport = FakeTransport('owner');
      final List<String> ledger = [];
      final PublishPipeline pipeline = pipelineFor(
        world,
        owner,
        transport,
        ledger,
        'owner',
      );

      final String cid = (await pipeline.rotateGroupKey(
        groupId: gid,
        publisherPeerId: 'owner',
      ))
          .value;

      expect((await world.keys.ring(gid))!.currentVersion, 2);
      final SyncEnvelope envelope = SyncEnvelope.tryDecode(
        transport.blocks[cid]!,
      )!;
      expect(envelope.keyVersion, 2);
      // No member published an X25519 key: no rekeys yet.
      expect(envelope.rekeys, isEmpty);
    });

    test('keyless groups fail publishing', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final FakeTransport transport = FakeTransport('owner');
      final PublishPipeline pipeline = pipelineFor(
        world,
        owner,
        transport,
        [],
        'owner',
      );
      await world.keys.removeKey(gid);

      expect(
        (await pipeline.publishSnapshot(
          groupId: gid,
          publisherPeerId: 'owner',
        )).failure,
        isA<NotFoundFailure>(),
      );
    });
  });
}
