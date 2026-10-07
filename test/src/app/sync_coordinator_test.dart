import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/sync_coordinator.dart';
import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/sync/engine.dart';
import 'package:vbank/src/sync/ledger.dart';
import 'package:vbank/src/sync/peer_book.dart';
import 'package:vbank/src/sync/relay_directory.dart';
import 'package:vbank/src/sync/sync_node.dart';

import 'harness.dart';

/// A [SyncNode] that answers inventory with nothing and keeps blocks.
final class _QuietNode implements SyncNode {
  bool _started;

  /// Blocks by CID.
  final Map<String, Uint8List> blocks = {};

  /// Topics subscribed.
  final List<String> subscribed = [];

  /// Announcements `(topic, message)`.
  final List<(String, String)> published = [];

  /// Addresses dialed.
  final List<String> dials = [];

  _QuietNode({bool started = false}) : _started = started;

  @override
  String? get peerId =>
      '12D3KooWTestCoordinator000000000000000000000001';

  @override
  Future<Set<String>> get connectedPeers async => const {};

  @override
  bool get isRunning => _started;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> connect(
    String addr, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    dials.add(addr);
  }

  @override
  Future<Uint8List?> request(String peerId, Uint8List payload) async => null;

  @override
  Future<void> subscribe(String topic) async {
    subscribed.add(topic);
  }

  @override
  Future<String> addData(Uint8List bytes) async {
    final String cid = 'b${blocks.length}';
    blocks[cid] = bytes;
    return cid;
  }

  @override
  Future<Uint8List?> localBlock(String cid) async => blocks[cid];

  @override
  Future<Uint8List?> fetchBlock(String cid, List<String> peerIds) async =>
      blocks[cid];

  @override
  Future<void> publish(
    String topic,
    String message,
    List<String> peers,
  ) async {
    published.add((topic, message));
  }

  @override
  Stream<SyncNotification> get notifications => const Stream.empty();

  @override
  // ignore: avoid_setters_without_getters (matches SyncTransport)
  set onRequest(
    Future<Uint8List> Function(String from, Uint8List payload)? handler,
  ) {}
}

/// Builds a coordinator over [harness] acting as [peer].
SyncCoordinator _coordinator(AppHarness harness, SyncNode node, String peer) {
  final stack = harness.stackFor(peer);
  return SyncCoordinator(
    transport: node,
    groups: stack.groups,
    transactions: stack.transactions,
    loans: stack.loans,
    meetings: stack.meetings,
    governance: stack.governance,
    invites: stack.invites,
    keys: harness.keys,
    transactionRepository: harness.transactionRepo,
    loanRepository: harness.loanRepo,
    meetingRepository: harness.meetingRepo,
    peers: PeerBook(harness.settings),
    ledger: SyncLedger(harness.settings),
    relays: RelayDirectory(txtLookup: (_) async => const []),
    settings: harness.settings,
    sign: harness.signerFor(peer),
    ownPeerId: () => peer,
    memberKeyPair: () async => null,
    ownAddrs: () => const [],
    signingKey: () => harness.keyFor(peer),
    clock: () => harness.now,
  );
}

void main() {
  group('SyncCoordinator', () {
    test('ensureStarted brings the node up and subscribes topics', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String groupId = await h.seedGroup();
      final _QuietNode node = _QuietNode();
      final SyncCoordinator coordinator = _coordinator(h, node, 'owner');
      await coordinator.ensureStarted();
      expect(coordinator.state, SyncState.idle);
      expect(node.subscribed, contains(SyncEngine.topicFor(groupId)));
      await coordinator.dispose();
    });

    test('synchronizeNow runs an empty round over keyed groups', () async {
      final AppHarness h = AppHarness();
      await h.init();
      await h.seedGroup();
      final _QuietNode node = _QuietNode();
      final SyncCoordinator coordinator = _coordinator(h, node, 'owner');
      final SyncReport report = await coordinator.synchronizeNow();
      expect(report, SyncReport.empty);
      expect(coordinator.state, SyncState.idle);
      await coordinator.dispose();
    });

    test('publishRecord seals, stores and announces', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String groupId = await h.seedGroup();
      final _QuietNode node = _QuietNode();
      final SyncCoordinator coordinator = _coordinator(h, node, 'owner');
      await coordinator.ensureStarted();
      final result = await coordinator.publishRecord(
        groupId: groupId,
        type: SyncPayloadType.transaction,
        payloadJson: {
          'id': 'tx1',
          'groupId': groupId,
          'fromPeerId': 'owner',
          'toPeerId': 'owner',
          'type': 'contribution',
          'amount': 10.0,
          'currency': 'ZMW',
          'timestamp': '2026-01-05T10:00:00.000Z',
          'sequenceNumber': 1,
          'status': 'confirmed',
          'senderSignature': base64Encode(List.filled(64, 1)),
        },
      );
      expect(result.isOk, isTrue);
      expect(node.published, isNotEmpty);
      expect(node.published.first.$1, SyncEngine.topicFor(groupId));
      final Map<String, dynamic> note =
          jsonDecode(node.published.first.$2) as Map<String, dynamic>;
      expect(note['cid'], result.value);
      await coordinator.dispose();
    });

    test('publishSnapshot announces the roster', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final String groupId = await h.seedGroup();
      final _QuietNode node = _QuietNode();
      final SyncCoordinator coordinator = _coordinator(h, node, 'owner');
      await coordinator.ensureStarted();
      final result = await coordinator.publishSnapshot(groupId);
      expect(result.isOk, isTrue);
      await coordinator.dispose();
    });

    test('builtin relay toggle persists', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final _QuietNode node = _QuietNode();
      final SyncCoordinator coordinator = _coordinator(h, node, 'owner');
      expect(await coordinator.builtInRelayEnabled(), isTrue);
      await coordinator.setBuiltInRelayEnabled(false);
      expect(await coordinator.builtInRelayEnabled(), isFalse);
      await coordinator.dispose();
    });

    test('addRelays accumulates without duplicates', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final _QuietNode node = _QuietNode();
      final SyncCoordinator coordinator = _coordinator(h, node, 'owner');
      await coordinator.setBuiltInRelayEnabled(false);
      await coordinator.addRelays(const ['/dns4/a/tcp/4001/p2p/QmA']);
      await coordinator.addRelays(const ['/dns4/a/tcp/4001/p2p/QmA']);
      expect(
        await coordinator.relayAddresses(),
        ['/dns4/a/tcp/4001/p2p/QmA'],
      );
      await coordinator.dispose();
    });
  });
}
