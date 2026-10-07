import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

/// Owner on device A seeds a group and contributes twice, all offline.
/// Member on device B holds the same roster and key. Rounds must carry
/// everything across with no manual publishing — and publish nothing
/// twice.
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vbank-reconcile-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('publish reconciler', () {
    test('offline writes converge on the next rounds', () async {
      final AppHarness worldA = AppHarness();
      await worldA.init(dbPath: '${dir.path}/a.db');
      final AppHarness worldB = AppHarness();
      await worldB.init(dbPath: '${dir.path}/b.db');
      final _Device deviceA = _Device(worldA, FakeNode('owner'), 'owner');
      final _Device deviceB = _Device(worldB, FakeNode('member'), 'member');
      deviceA.node.inner.network['member'] = deviceB.node.inner;
      deviceB.node.inner.network['owner'] = deviceA.node.inner;
      deviceA.node.mesh['member'] = deviceB.node;
      deviceB.node.mesh['owner'] = deviceA.node;

      // A seeds the group offline: roster, key and two contributions.
      final String gid = await worldA.seedGroup();
      final groupA =
          (await worldA.stackFor('owner').groups.getGroup(gid)).value;
      final SecretKey aKey = (await worldA.keys.getKey(gid))!;

      // B holds the same roster and key (joined earlier, out of band).
      await worldB.keyFor('member');
      await worldB
          .stackFor('member')
          .groups
          .saveGroup(groupA);
      await worldB.keys.setKey(
        gid,
        SecretKey(await aKey.extractBytes()),
      );

      await deviceA.coordinator.ensureStarted();
      await deviceB.coordinator.ensureStarted();
      await deviceA.coordinator.peers.remember(gid, [deviceB.addr]);
      await deviceB.coordinator.peers.remember(gid, [deviceA.addr]);

      // A's round publishes the snapshot and both contributions.
      await deviceA.coordinator.synchronizeNow();
      expect(deviceA.node.inner.mintedCids, hasLength(3));

      // B's round pulls everything: roster and both contributions.
      await deviceB.coordinator.synchronizeNow();
      final txsB =
          (await worldB.stackFor('member').transactions.listByGroup(gid))
              .value;
      expect(txsB, hasLength(2));
      final groupB =
          (await worldB.stackFor('member').groups.getGroup(gid)).value;
      expect(groupB.cid, isNotNull);

      // Nothing new to publish on either side: CIDs stay put.
      final int mintedA = deviceA.node.inner.mintedCids.length;
      final int mintedB = deviceB.node.inner.mintedCids.length;
      await deviceA.coordinator.synchronizeNow();
      await deviceB.coordinator.synchronizeNow();
      expect(deviceA.node.inner.mintedCids, hasLength(mintedA));
      expect(deviceB.node.inner.mintedCids, hasLength(mintedB));

      await deviceA.coordinator.dispose();
      await deviceB.coordinator.dispose();
    });
  });
}
