import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/publish_pipeline.dart';
import 'package:vbank/src/app/signing_payloads.dart';
import 'package:vbank/src/crypto/invite_wrap.dart';
import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/sync/engine.dart';
import 'package:vbank/src/sync/ledger.dart';
import 'package:vbank/src/sync/record_codec.dart';

import '../sync/fakes.dart';
import 'harness.dart';

/// Two devices, three personas: owner and member1 live on device A,
/// member2 joins device B over an invite link and full sync rounds.
///
/// Keys cross the invite (wrap plus link secret); every signature verifies
/// against the roster because each peer is created exactly once.
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vbank-integ-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// One device: harness, transport, engine and pipelines over its own DB.
  Future<_Device> device(String name, String peerId) async {
    final AppHarness world = AppHarness();
    await world.init(dbPath: '${dir.path}/$name.db');
    final FakeTransport transport = FakeTransport(peerId);
    return _Device(world, transport, peerId);
  }

  group('device-to-device sync', () {
    test('join, contribute, dispute and roster converge', () async {
      final _Device deviceA = await device('a', 'owner');
      final _Device deviceB = await device('b', 'member2');
      deviceA.transport.network['member2'] = deviceB.transport;
      deviceB.transport.network['owner'] = deviceA.transport;
      deviceB.transport.network['member1'] = deviceA.transport;

      // A hosts owner and member1.
      final String gid = await deviceA.world.seedGroup(
        member: 'member1',
        memberName: 'Member One',
      );
      final ServiceStack ownerA = deviceA.world.stackFor('owner');

      // A invites member2; the link carries id, secret and nonce.
      final SecretKey aKey = (await deviceA.world.keys.getKey(gid))!;
      final CreatedInvite link = await _inviteLink(deviceA, ownerA, gid, aKey);

      // B unwraps the key from the snapshot header, bootstraps the group.
      final String snapshotCid = await deviceA.publishSnapshot(gid, 'owner');
      final Uint8List? snapshotBytes = await deviceB.transport.fetchBlock(
        snapshotCid,
        ['owner'],
      );
      expect(snapshotBytes, isNotNull);
      final SyncEnvelope? header = SyncEnvelope.tryDecode(snapshotBytes!);
      expect(header!.wraps.keys, [link.id]);
      final SecretKey? bKey = await InviteKeyWrap.unwrap(
        wrapped: header.wraps[link.id]!,
        secret: link.secret,
        groupId: gid,
        inviteId: link.id,
      );
      expect(bKey, isNotNull);
      await deviceB.world.keys.setKey(gid, bKey!);
      expect(
        await deviceB.apply(gid, snapshotCid, snapshotBytes),
        ApplyOutcome.applied,
      );
      await deviceB.ledger.record(gid, snapshotCid);

      // B announces the join; A admits, spends the invite, republishes.
      await deviceB.world.keyFor('member2');
      final Uint8List joinSig = await deviceB.world.signerFor('member2')(
        SigningPayloads.memberJoin(
          groupId: gid,
          peerId: 'member2',
          inviteId: link.id,
        ),
      );
      final Map<String, dynamic> joinPayload = {
        'member': RecordCodec.memberToJson(
          Member(
            peerId: 'member2',
            name: 'Member Two',
            joinedAt: deviceB.world.now,
            publicKey: deviceB.world.publicKeys['member2']!,
          ),
        ),
        'addrs': [deviceB.addr('member2')],
        'signature': joinSig,
        'inviteId': link.id,
        'nonce': base64Encode(link.nonce),
      };
      await deviceB.publishJoin(gid, joinPayload);
      final SyncEngine engineA = deviceA.engine([
        deviceB.addr('member2'),
      ]);
      final SyncReport joined = await engineA.synchronize(
        groupIds: [gid],
        relayAddrs: const [],
      );
      expect(joined.applied, 1);
      Group groupA = (await ownerA.groups.getGroup(gid)).value;
      expect(
        groupA.members.map((Member m) => m.peerId),
        contains('member2'),
      );
      await deviceA.publishSnapshot(gid, 'owner');

      // B pulls the new roster and the seeded history.
      final SyncEngine engineB = deviceB.engine([
        deviceA.addr('owner'),
      ]);
      await engineB.synchronize(groupIds: [gid], relayAddrs: const []);
      final Group groupB =
          (await deviceB.world.stackFor('member2').groups.getGroup(gid)).value;
      expect(
        groupB.members.map((Member m) => m.peerId),
        containsAll(['owner', 'member1', 'member2']),
      );

      // member1 contributes on A; B converges with balances. Earlier
      // records publish at creation in real flows; the seed bypassed
      // that, so the backlog goes out first.
      final Transaction tx = (await ownerA.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member1',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 250,
      ))
          .value;
      for (final Transaction earlier
          in (await ownerA.transactions.listByGroup(gid)).value) {
        if (earlier.id != tx.id) {
          await deviceA.publishTransaction(earlier);
        }
      }
      await deviceA.publishTransaction(tx);
      final SyncReport pulled = await engineB.synchronize(
        groupIds: [gid],
        relayAddrs: const [],
      );
      expect(pulled.applied, greaterThanOrEqualTo(1));
      final ServiceStack member2B = deviceB.world.stackFor('member2');
      expect(
        (await member2B.transactions.getById(tx.id)).value.amount,
        250,
      );
      final balancesB =
          await member2B.transactions.balances.listByGroup(gid);
      expect(
        balancesB.value.firstWhere((b) => b.peerId == 'member1').netBalance,
        350,
      );

      // member2 announces its encryption key; A files it on the roster.
      final Uint8List encKey = Uint8List.fromList([7, 7, 7]);
      final Map<String, dynamic> keyPayload = {
        'v': 1,
        'peerId': 'member2',
        'encKey': encKey,
        'signature': await deviceB.world.signerFor('member2')(
          SigningPayloads.memberKey(
            groupId: gid,
            peerId: 'member2',
            encKey: encKey,
          ),
        ),
      };
      final String keyCid = await deviceB.publishKeyAnnouncement(
        gid,
        keyPayload,
      );
      expect(keyCid, isNotEmpty);
      await engineA.synchronize(groupIds: [gid], relayAddrs: const []);
      groupA = (await ownerA.groups.getGroup(gid)).value;
      expect(
        groupA.members
            .where((Member m) => m.peerId == 'member2')
            .single
            .encKey,
        encKey,
      );

      // member1 disputes the 250 on A; the reversal reaches B and unwinds.
      final ServiceStack member1A = deviceA.world.stackFor('member1');
      final dispute = (await member1A.governance.requestReversal(
        groupId: gid,
        actingPeerId: 'member1',
        transactionId: tx.id,
        reason: 'should be 200',
      ))
          .value;
      await deviceA.publishReversal(dispute);
      final SyncReport disputed = await engineB.synchronize(
        groupIds: [gid],
        relayAddrs: const [],
      );
      expect(disputed.applied, 1);

      final decided = (await ownerA.governance.decideReversal(
        groupId: gid,
        actingPeerId: 'owner',
        reversalId: dispute.id,
        approve: true,
      ))
          .value;
      await deviceA.publishReversal(decided);
      expect(
        (await engineB.synchronize(groupIds: [gid], relayAddrs: const []))
            .applied,
        1,
      );

      for (final _Device d in [deviceA, deviceB]) {
        final ServiceStack stack = d.world.stackFor('owner');
        final ServiceStack reader = d.world.stackFor('member1');
        expect(
          (await stack.transactions.getById(tx.id)).value.status,
          TransactionStatus.reversed,
        );
        final balances = await reader.transactions.balances.listByGroup(gid);
        expect(
          balances.value.firstWhere((b) => b.peerId == 'member1').netBalance,
          100,
          reason: 'seed only on both devices',
        );
      }
    });
  });
}

/// An invite link's contents for join tests.
final class CreatedInvite {
  /// Invite id.
  final String id;

  /// One-time link secret.
  final Uint8List secret;

  /// The invite nonce, presented back in the join announcement.
  final Uint8List nonce;

  /// Creates the link handle.
  const CreatedInvite(this.id, this.secret, this.nonce);
}

/// Creates an invite on [deviceA] and returns its link contents.
Future<CreatedInvite> _inviteLink(
  _Device deviceA,
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
  return CreatedInvite(
    created.invite.id,
    created.secret!,
    created.invite.nonce,
  );
}

/// One test device: harness plus its transport and pipeline wiring.
final class _Device {
  /// Services, repos and keys.
  final AppHarness world;

  /// P2P endpoint, cross-wired per test.
  final FakeTransport transport;

  /// This device's persona for applying blocks.
  final String peerId;

  /// Ledger on this device's settings.
  late final SyncLedger ledger = SyncLedger(world.settings);

  /// Creates a device shell; call [engine] after meshing.
  _Device(this.world, this.transport, this.peerId);

  /// Dialable address for [peerId] on this device.
  String addr(String peerId) => '/ip4/127.0.0.1/tcp/4001/p2p/$peerId';

  /// This device's sync engine talking to [peerAddrs].
  SyncEngine engine(List<String> peerAddrs) {
    final SyncEngine engine = SyncEngine(
      transport: transport,
      peerAddrsFor: (String groupId) async => peerAddrs,
      groupKeyFor: (String groupId) async {
        final SecretKey? key = await world.keys.getKey(groupId);
        return key == null
            ? null
            : Uint8List.fromList(await key.extractBytes());
      },
      ledgerCids: ledger.cidsFor,
      ledgerRecord: ledger.record,
      applyBlock: apply,
      localBlock: transport.localBlock,
    );
    transport.onRequest = engine.handleRequest;
    return engine;
  }

  /// Applies a block as this device's persona.
  Future<ApplyOutcome> apply(String groupId, String cid, Uint8List block) =>
      world.pipelineFor(peerId).pipeline.apply(groupId, cid, block);

  /// Publishes a snapshot as [peer].
  Future<String> publishSnapshot(String gid, String peer) async =>
      (await _publish(peer).publishSnapshot(
        groupId: gid,
        publisherPeerId: peer,
      ))
          .value;

  /// Publishes one transaction as its author side.
  Future<String> publishTransaction(Transaction tx) async =>
      (await _publish(tx.authorPeerId).publishTransaction(tx)).value;

  /// Publishes a member-key announcement for tests.
  Future<String> publishKeyAnnouncement(
    String gid,
    Map<String, dynamic> keyPayload,
  ) async =>
      (await _publish(peerId).publishRaw(
        groupId: gid,
        type: SyncPayloadType.memberKey,
        payloadJson: keyPayload,
      ))
          .value;

  /// Publishes a member-join announcement (already signed by the joiner).
  Future<String> publishJoin(
    String gid,
    Map<String, dynamic> joinPayload,
  ) async {
    final _Publisher publisher = _Publisher(this, gid);
    return publisher.join(joinPayload);
  }

  /// Publishes one reversal.
  Future<String> publishReversal(TransactionReversal reversal) async =>
      (await _publish(
        reversal.requestedByPeerId,
      ).publishReversal(reversal))
          .value;

  PublishPipeline _publish(String peer) {
    final ServiceStack stack = world.stackFor(peer);
    return PublishPipeline(
      transport: transport,
      keys: world.keys,
      groups: stack.groups,
      invites: stack.invites,
      governance: stack.governance,
      ledgerRecord: ledger.record,
      ownAddrs: () => [addr(peer)],
      memberKeyPair: () async => null,
      clock: () => world.now,
    )..bindSigningKey(() => world.keyFor(peer));
  }
}

/// Join announcements need no service: seal the payload directly.
final class _Publisher {
  /// The publishing device.
  final _Device device;

  /// The group joining.
  final String groupId;

  /// Creates a join publisher.
  _Publisher(this.device, this.groupId);

  /// Seals, stores and ledgers the announcement.
  Future<String> join(Map<String, dynamic> payload) async {
    final SecretKey? key = await device.world.keys.getKey(groupId);
    final Uint8List bytes = await SyncEnvelope.seal(
      type: SyncPayloadType.memberJoin,
      groupId: groupId,
      plaintextJson: payload,
      groupKey: key!,
    );
    final String cid = await device.transport.addData(bytes);
    await device.ledger.record(groupId, cid);
    return cid;
  }
}
