import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/invite_link.dart';
import 'package:vbank/src/app/sync_coordinator.dart';
import 'package:vbank/src/sync/ledger.dart';
import 'package:vbank/src/sync/peer_book.dart';
import 'package:vbank/src/sync/relay_directory.dart';

import '../sync/fakes.dart';
import 'harness.dart';

/// One device: world, node and coordinator acting as [peer].
final class _Device {
  /// Services, repos and keys.
  final AppHarness world;

  /// P2P endpoint.
  final FakeNode node;

  /// Acting persona.
  final String peer;

  /// Sync coordinator.
  late final SyncCoordinator coordinator;

  /// Dialable address for the persona.
  String get addr => '/ip4/127.0.0.1/tcp/4001/p2p/$peer';

  _Device(this.world, this.node, this.peer) {
    final stack = world.stackFor(peer);
    coordinator = SyncCoordinator(
      transport: node,
      groups: stack.groups,
      transactions: stack.transactions,
      loans: stack.loans,
      meetings: stack.meetings,
      governance: stack.governance,
      invites: stack.invites,
      transactionRepository: world.transactionRepo,
      loanRepository: world.loanRepo,
      meetingRepository: world.meetingRepo,
      keys: world.keys,
      peers: PeerBook(world.settings),
      ledger: SyncLedger(world.settings),
      relays: RelayDirectory(txtLookup: (_) async => const []),
      settings: world.settings,
      sign: world.signerFor(peer),
      ownPeerId: () => peer,
      memberKeyPair: () async => null,
      ownAddrs: () => [addr],
      signingKey: () => world.keyFor(peer),
      clock: () => world.now,
    );
  }

  /// Uses only the fake relay (no network DNS in tests).
  Future<void> useOnlyRelay(String relayAddr) async {
    await coordinator.setBuiltInRelayEnabled(false);
    await coordinator.addRelays([relayAddr]);
  }
}

/// Owner on device A seeds a group and cuts an invite link. Member on
/// device B joins from the link alone: snapshot, key, roster and join
/// announcement all converge, and the invite spends.
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vbank-join-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('invite join', () {
    test('link, snapshot, key, roster and announcement converge', () async {
      final AppHarness worldA = AppHarness();
      await worldA.init(dbPath: '${dir.path}/a.db');
      final AppHarness worldB = AppHarness();
      await worldB.init(dbPath: '${dir.path}/b.db');
      final _Device deviceA = _Device(worldA, FakeNode('owner'), 'owner');
      final _Device deviceB = _Device(worldB, FakeNode('member'), 'member');
      final FakeNode relay = FakeNode('relay1');
      const String relayAddr = '/ip4/127.0.0.1/tcp/4001/p2p/relay1';
      for (final _Device d in [deviceA, deviceB]) {
        d.node.inner.network['relay1'] = relay.inner;
        d.node.mesh['relay1'] = relay;
        await d.useOnlyRelay(relayAddr);
      }
      deviceA.node.inner.network['member'] = deviceB.node.inner;
      deviceB.node.inner.network['owner'] = deviceA.node.inner;
      deviceA.node.mesh['member'] = deviceB.node;
      deviceB.node.mesh['owner'] = deviceA.node;

      // A seeds the group and syncs so the relay holds the snapshot.
      final String gid = await worldA.seedGroup();
      await deviceA.coordinator.ensureStarted();
      await deviceB.coordinator.ensureStarted();
      await deviceA.coordinator.synchronizeNow();

      // A cuts an invite link carrying id, secret and nonce, then syncs
      // again so the fresh snapshot carries the wrap for it.
      final SecretKey aKey = (await worldA.keys.getKey(gid))!;
      final created = (await worldA
              .stackFor('owner')
              .invites
              .createInvite(
                groupId: gid,
                groupCid:
                    (await worldA.stackFor('owner').groups.getGroup(gid))
                        .value
                        .cid ??
                    '',
                groupTopic: 'vbank/group/$gid',
                inviterPeerId: 'owner',
                inviterName: 'Owner',
                groupKey: aKey,
              ))
          .value;
      expect(created.secret, isNotNull);
      await deviceA.coordinator.synchronizeNow();
      final groupA =
          (await worldA.stackFor('owner').groups.getGroup(gid)).value;
      expect(groupA.cid, isNotNull);
      final String link = InviteLink(
        groupId: gid,
        groupCid: groupA.cid!,
        groupTopic: 'vbank/group/$gid',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        inviteId: created.invite.id,
        secret: created.secret!,
        nonce: created.invite.nonce,
        expiresAt: created.invite.expiresAt,
      ).encode();

      // B joins from the link alone.
      await worldB.keyFor('member');
      final joined = await deviceB.coordinator.joinWithLink(
        link: link,
        displayName: 'Member Two',
      );
      expect(joined.isOk, isTrue);
      expect(
        (await worldB.stackFor('member').groups.getGroup(gid)).isOk,
        isTrue,
      );
      expect(await worldB.keys.getKey(gid), isNotNull);

      // B announced the join.
      final announces = deviceB.node.published
          .where((p) => (jsonDecode(p.$2) as Map)['kind'] == 'memberJoin')
          .toList();
      expect(announces, hasLength(1));

      // A learns the member on the next round; the invite spends.
      await deviceA.coordinator.peers.remember(gid, [deviceB.addr]);
      await deviceA.coordinator.synchronizeNow();
      final roster =
          (await worldA.stackFor('owner').groups.getGroup(gid)).value;
      expect(
        roster.members.map((m) => m.peerId),
        contains('member'),
      );
      final spent =
          (await worldA.stackFor('owner').invites.getById(created.invite.id))
              .value;
      expect(spent.used, isTrue);

      await deviceA.coordinator.dispose();
      await deviceB.coordinator.dispose();
    });

    test('rejects garbage, expired and unknown-invite links', () async {
      final AppHarness worldB = AppHarness();
      await worldB.init(dbPath: '${dir.path}/solo.db');
      final _Device deviceB = _Device(worldB, FakeNode('member'), 'member');
      await worldB.keyFor('member');

      expect(
        (await deviceB.coordinator.joinWithLink(
          link: 'not-a-link',
          displayName: 'Member Two',
        )).isErr,
        isTrue,
      );

      final Uint8List filler = Uint8List.fromList(List.filled(32, 7));
      final String expired = InviteLink(
        groupId: 'g',
        groupCid: 'c',
        groupTopic: 'vbank/group/g',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        inviteId: 'id-1',
        secret: filler,
        nonce: filler,
        expiresAt: DateTime.utc(2020, 1, 1),
      ).encode();
      expect(
        (await deviceB.coordinator.joinWithLink(
          link: expired,
          displayName: 'Member Two',
        )).isErr,
        isTrue,
      );

      await deviceB.coordinator.dispose();
    });
  });
}
