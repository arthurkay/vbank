import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/sync_coordinator.dart';
import 'package:vbank/src/crypto/signing.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/sync_on_resume.dart';
import 'package:vbank/src/sync/ledger.dart';
import 'package:vbank/src/sync/peer_book.dart';
import 'package:vbank/src/sync/relay_directory.dart';
import 'package:vbank/src/sync/sync_node.dart';

import 'pump.dart';

/// A node that starts but knows nobody: rounds finish empty.
final class _StillNode implements SyncNode {
  /// Whether [start] ran.
  bool started = false;

  @override
  String? get peerId => '12D3KooWTestResume00000000000000000000001';

  @override
  Future<Set<String>> get connectedPeers async => const {};

  @override
  bool get isRunning => started;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> connect(
    String addr, {
    Duration timeout = const Duration(seconds: 8),
  }) async {}

  @override
  Future<Uint8List?> request(String peerId, Uint8List payload) async => null;

  @override
  Future<Uint8List?> fetchBlock(String cid, List<String> peerIds) async =>
      null;

  @override
  Future<String> addData(Uint8List bytes) async => 'test-cid';

  @override
  Future<Uint8List?> localBlock(String cid) async => null;

  @override
  Future<void> subscribe(String topic) async {}

  @override
  Future<void> publish(
    String topic,
    String message,
    List<String> peers,
  ) async {}

  @override
  Stream<SyncNotification> get notifications => const Stream.empty();

  @override
  // ignore: avoid_setters_without_getters (matches SyncTransport)
  set onRequest(
    Future<Uint8List> Function(String from, Uint8List payload)? handler,
  ) {}
}

/// Builds a coordinator over [world] with nobody to talk to.
SyncCoordinator _coordinator(PresentationWorld world, _StillNode node) =>
    SyncCoordinator(
      transport: node,
      groups: world.services.groups,
      transactions: world.services.transactions,
      loans: world.services.loans,
      meetings: world.services.meetings,
      governance: world.services.governance,
      invites: world.services.invites,
      transactionRepository: world.repositories.transactions,
      loanRepository: world.repositories.loans,
      meetingRepository: world.repositories.meetings,
      keys: world.services.keys,
      peers: PeerBook(world.repositories.settings),
      ledger: SyncLedger(world.repositories.settings),
      relays: RelayDirectory(txtLookup: (_) async => const []),
      settings: world.repositories.settings,
      sign: world.signAs('owner'),
      ownPeerId: () => 'owner',
      memberKeyPair: () async => null,
      ownAddrs: () => const [],
      signingKey: () async => SigningService.generateKeyPair(),
      clock: () => world.now,
    );

void main() {
  group('sync on resume', () {
    testWidgets('runs a round on open and on resume', (tester) async {
      final PresentationWorld world = PresentationWorld();
      final _StillNode node = _StillNode();
      final SyncCoordinator coordinator = _coordinator(world, node);
      final List<SyncState> states = [];
      // No cancel: awaiting a broadcast cancel never resolves under the
      // fake-async test zone. The subscription dies with the test.
      coordinator.states.listen(states.add);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          coordinator: coordinator,
          child: const MaterialApp(
            home: SyncOnResume(child: Text('home')),
          ),
        ),
      );
      await settle(tester);

      int rounds() =>
          states.where((state) => state == SyncState.syncing).length;
      expect(node.started, isTrue);
      expect(rounds(), 1);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await settle(tester);
      expect(rounds(), 2);

      // Backgrounding alone syncs nothing.
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await settle(tester);
      expect(rounds(), 2);
    });
  });
}
