import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/invite_link.dart';
import 'package:vbank/src/app/sync_coordinator.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/sync/ipfs_transport.dart';
import 'package:vbank/src/sync/ledger.dart';
import 'package:vbank/src/sync/peer_book.dart';
import 'package:vbank/src/sync/relay_directory.dart';
import 'package:vbank/src/sync/relay_node.dart';

import 'harness.dart';

/// One device: real libp2p transport, world and coordinator. Personas
/// are the transports' own peer ids, exactly like production (where the
/// identity row carries the node id).
final class _RealDevice {
  /// Services, repos and keys.
  final AppHarness world;

  /// Real P2P node.
  final IpfsTransport transport;

  /// This device's peer id (transport identity).
  late final String peer;

  /// Sync coordinator.
  late final SyncCoordinator coordinator;

  _RealDevice(this.world, this.transport);

  /// Starts the node, then wires the coordinator around its peer id.
  Future<void> boot({required String relayAddr}) async {
    await transport.start();
    peer = transport.peerId!;
    await world.keyFor(peer);
    final stack = world.stackFor(peer);
    coordinator = SyncCoordinator(
      transport: transport,
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
      ownPeerId: () => transport.peerId,
      memberKeyPair: () async => null,
      ownAddrs: () => transport.dialableAddresses,
      signingKey: () => world.keyFor(peer),
      clock: () => world.now,
    );
    await coordinator.setBuiltInRelayEnabled(false);
    await coordinator.addRelays([relayAddr]);
    await coordinator.ensureStarted();
  }

}

/// Owner on device A seeds a group over real libp2p; member on device B
/// joins from a real invite link through a real relay. No fakes: real
/// dials, real inventory/put/fetch, real announcements, real sealed
/// envelopes.
void main() {
  group('real network sync', () {
    test('invite, join and converge over loopback', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'vbank-real-',
      );
      final RelayNode relay = RelayNode(
        dataDir: '${dir.path}/relay',
        listenPort: 4781,
        log: (_) {},
      );
      await relay.start();
      final String relayAddr =
          '/ip4/127.0.0.1/tcp/4781/p2p/${relay.peerId}';

      final AppHarness worldA = AppHarness();
      await worldA.init(dbPath: '${dir.path}/a.db');
      final AppHarness worldB = AppHarness();
      await worldB.init(dbPath: '${dir.path}/b.db');
      final _RealDevice deviceA = _RealDevice(
        worldA,
        IpfsTransport(ipfsDir: '${dir.path}/a-ipfs', listenPort: 4782),
      );
      final _RealDevice deviceB = _RealDevice(
        worldB,
        IpfsTransport(ipfsDir: '${dir.path}/b-ipfs', listenPort: 4783),
      );
      await deviceA.boot(relayAddr: relayAddr);
      await deviceB.boot(relayAddr: relayAddr);
      try {
        // A seeds offline, syncs, cuts an invite, syncs the wrap.
        final String gid = await worldA.seedGroup(
          owner: deviceA.peer,
          ownerName: 'Owner',
          member: 'reserve',
          memberName: 'Reserve',
        );
        // Direct addresses too: loopback dials, like one LAN.
        await deviceA.coordinator.peers.remember(
          gid,
          deviceB.transport.dialableAddresses,
        );
        await deviceB.coordinator.peers.remember(
          gid,
          deviceA.transport.dialableAddresses,
        );
        await deviceA.coordinator.synchronizeNow();
        final SecretKey aKey = (await worldA.keys.getKey(gid))!;
        final created = (await worldA
                .stackFor(deviceA.peer)
                .invites
                .createInvite(
                  groupId: gid,
                  groupCid: '',
                  groupTopic: 'vbank/group/$gid',
                  inviterPeerId: deviceA.peer,
                  inviterName: 'Owner',
                  groupKey: aKey,
                ))
            .value;
        await deviceA.coordinator.synchronizeNow();
        final groupA = (await worldA
                .stackFor(deviceA.peer)
                .groups
                .getGroup(gid))
            .value;
        expect(groupA.cid, isNotNull);
        final String link = InviteLink(
          groupId: gid,
          groupCid: groupA.cid!,
          inviterPeerId: deviceA.peer,
          inviteId: created.invite.id,
          secret: created.secret!,
          nonce: created.invite.nonce,
          expiresAt: created.invite.expiresAt,
        ).encode();

        // B joins from the link alone, over the relay.
        final joined = await deviceB.coordinator.joinWithLink(
          link: link,
          displayName: 'Member Two',
        );
        expect(
          joined.isOk,
          isTrue,
          reason: joined.isErr ? 'join: ${joined.failure}' : 'join ok',
        );
        expect(
          (await worldB
                  .stackFor(deviceB.peer)
                  .groups
                  .getGroup(gid))
              .isOk,
          isTrue,
        );

        // A admits on the next round; the invite spends. The join
        // announcement travels over PubSub, so poll for convergence
        // instead of asserting once: the round and the notification race.
        await deviceA.coordinator.synchronizeNow();
        final DateTime deadline = DateTime.now().add(
          const Duration(seconds: 15),
        );
        late Group roster;
        while (true) {
          roster = (await worldA
                  .stackFor(deviceA.peer)
                  .groups
                  .getGroup(gid))
              .value;
          if (roster.members.any((m) => m.peerId == deviceB.peer) ||
              DateTime.now().isAfter(deadline)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          roster.members.map((m) => m.peerId),
          contains(deviceB.peer),
        );
        final spent = (await worldA
                .stackFor(deviceA.peer)
                .invites
                .getById(created.invite.id))
            .value;
        expect(spent.used, isTrue);
      } finally {
        await deviceA.coordinator.dispose();
        await deviceB.coordinator.dispose();
        await deviceA.transport.stop();
        await deviceB.transport.stop();
        await relay.stop();
        await dir.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
