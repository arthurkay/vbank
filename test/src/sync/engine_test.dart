import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/sync/engine.dart';

import 'fakes.dart';

/// One side of a convergence test: an engine, its transport and its data.
final class FakeNode {
  /// Peer id.
  final String peerId;

  /// Transport wired to the other nodes' transports.
  final FakeTransport transport;

  /// Group keys held (null omits the group: unjoined).
  final Map<String, Uint8List> keys = {};

  /// CIDs held, newest first.
  final List<String> ledger = [];

  /// Block bytes by CID.
  final Map<String, Uint8List> blocks = {};

  /// CIDs the applier accepted, in fetch order.
  final List<String> applied = [];

  /// CIDs requested from this node's transport, in order.
  List<String> get fetchSequence => _fetchSequence;
  final List<String> _fetchSequence = [];

  /// Creates a node with [peerId].
  FakeNode(this.peerId) : transport = FakeTransport(peerId) {
    transport.blocks.addAll(blocks);
  }

  /// Block bytes for [cid].
  Uint8List bytesFor(String cid) =>
      Uint8List.fromList(utf8.encode('block-$cid'));

  /// Gives this node [cids] with bytes, newest first as listed. Also
  /// mirrors them into the transport's default inventory so nodes without
  /// an engine still serve what they hold.
  void seed(Iterable<String> cids) {
    for (final String cid in cids) {
      blocks[cid] = bytesFor(cid);
      ledger.add(cid);
    }
    transport.blocks.addAll(blocks);
    transport.inventoryCids..clear()..addAll(ledger);
  }

  /// Builds the engine under test: ledger, keys and applier all land here,
  /// so convergence is observable without crypto or storage.
  SyncEngine engine({
    required Map<String, List<String>> peerAddrs,
    SyncClock? clock,
    int maxCatchUpPerRound = 25,
    int maxPushPerRound = 40,
  }) {
    final SyncEngine engine = SyncEngine(
      transport: transport,
      peerAddrsFor: (String groupId) async => peerAddrs[groupId] ?? const [],
      groupKeyFor: (String groupId) async => keys[groupId],
      ledgerCids: (String groupId) async =>
          groupId == 'g' ? [...ledger] : const [],
      ledgerRecord: (String groupId, String cid) async {
        ledger..remove(cid)..insert(0, cid);
      },
      applyBlock: (String groupId, String cid, Uint8List block) async {
        _fetchSequence.add(cid);
        applied.add(cid);
        blocks[cid] = block;
        transport.blocks[cid] = block;
        return ApplyOutcome.applied;
      },
      localBlock: (String cid) async => blocks[cid],
      clock: clock,
      maxCatchUpPerRound: maxCatchUpPerRound,
      maxPushPerRound: maxPushPerRound,
    );
    transport.onRequest = engine.handleRequest;
    return engine;
  }

  /// Multiaddr dialable by other nodes' engines.
  String get addr => '/ip4/127.0.0.1/tcp/4001/p2p/$peerId';
}

/// Wires [nodes] so every transport routes to every other.
void mesh(List<FakeNode> nodes) {
  for (final FakeNode a in nodes) {
    for (final FakeNode b in nodes) {
      if (a != b) {
        a.transport.network[b.peerId] = b.transport;
      }
    }
  }
}

void main() {
  final Uint8List groupKey = Uint8List.fromList(List.filled(32, 7));

  group('SyncEngine.handleRequest', () {
    test('serves inventory only with a key', () async {
      final FakeNode node = FakeNode('A');
      node.keys['g'] = groupKey;
      node.seed(['cid-2', 'cid-1']);
      final SyncEngine engine = node.engine(peerAddrs: const {});

      final Uint8List reply = await engine.handleRequest(
        'B',
        Uint8List.fromList(
          utf8.encode(jsonEncode({'op': 'inventory', 'groupId': 'g'})),
        ),
      );

      expect(
        jsonDecode(utf8.decode(reply)),
        {'v': 1, 'cids': ['cid-2', 'cid-1']},
      );
    });

    test('stays silent without a key, on garbage, off-protocol', () async {
      final FakeNode node = FakeNode('A');
      final SyncEngine engine = node.engine(peerAddrs: const {});
      Uint8List bytes(Map<String, Object?> json) =>
          Uint8List.fromList(utf8.encode(jsonEncode(json)));

      expect(
        await engine.handleRequest(
          'B',
          bytes({'op': 'inventory', 'groupId': 'g'}),
        ),
        isEmpty,
      );
      expect(await engine.handleRequest('B', Uint8List(0)), isEmpty);
      expect(
        await engine.handleRequest('B', bytes({'op': 'put'})),
        isEmpty,
      );
      expect(
        await engine.handleRequest('B', bytes({'op': 'inventory'})),
        isEmpty,
      );
    });
  });

  group('SyncEngine.synchronize', () {
    test('two nodes converge both ways', () async {
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')..keys['g'] = groupKey;
      a.seed(['cid-2', 'cid-1']);
      b.seed(['cid-3', 'cid-2']);
      mesh([a, b]);
      final SyncEngine engineA = a.engine(peerAddrs: {'g': [b.addr]});
      final SyncEngine engineB = b.engine(peerAddrs: {'g': [a.addr]});

      final SyncReport first = await engineA.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );
      expect(first.applied, 1);
      expect(a.applied, ['cid-3']);

      final SyncReport second = await engineB.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );
      expect(second.applied, 1);
      expect(b.applied, ['cid-1']);

      expect(a.ledger.toSet(), {'cid-1', 'cid-2', 'cid-3'});
      expect(b.ledger.toSet(), {'cid-1', 'cid-2', 'cid-3'});

      // A third round moves nothing: convergence is stable.
      final SyncReport third = await engineA.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );
      expect(third.applied, 0);
      expect(third.fetched, 0);
    });

    test('fetches oldest-first in dependency order', () async {
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')
        ..keys['g'] = groupKey
        ..seed(['cid-3', 'cid-2', 'cid-1']);
      mesh([a, b]);
      final SyncEngine engineA = a.engine(peerAddrs: {'g': [b.addr]});

      await engineA.synchronize(groupIds: ['g'], relayAddrs: const []);

      expect(a.fetchSequence, ['cid-1', 'cid-2', 'cid-3']);
    });

    test('catch-up is capped per round', () async {
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')
        ..keys['g'] = groupKey
        ..seed([for (var i = 30; i >= 1; i--) 'cid-$i']);
      mesh([a, b]);
      final SyncEngine engineA = a.engine(
        peerAddrs: {'g': [b.addr]},
        maxCatchUpPerRound: 25,
      );

      final SyncReport report = await engineA.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );

      expect(report.applied, 25);
    });

    test('silent peers back off on a pinned clock', () async {
      // Reassigned below to advance past backoff windows.
      DateTime now = DateTime.utc(2026, 1, 1);
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')..keys['g'] = groupKey;
      mesh([a, b]);
      a.transport.downPeers.add('B');
      final SyncEngine engineA = a.engine(
        peerAddrs: {'g': [b.addr]},
        clock: () => now,
      );

      final SyncReport first = await engineA.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );
      expect(first.unreachable, {'B'});
      expect(engineA.peerInBackoff('B'), isTrue);
      final int dials = a.transport.dials.length;

      // Inside the 15 s window: no redial, no re-request.
      now = now.add(const Duration(seconds: 14));
      await engineA.synchronize(groupIds: ['g'], relayAddrs: const []);
      expect(a.transport.dials, hasLength(dials));
      expect(a.transport.requests['B'], 1);

      // Past it: tries again, fails again, backs off longer.
      now = now.add(const Duration(seconds: 2));
      await engineA.synchronize(groupIds: ['g'], relayAddrs: const []);
      expect(a.transport.requests['B'], 2);

      // Recovery clears everything: the next push goes straight out.
      a.transport.downPeers.remove('B');
      now = now.add(const Duration(minutes: 6));
      final SyncReport recovered = await engineA.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );
      expect(recovered.unreachable, isEmpty);
      expect(engineA.peerInBackoff('B'), isFalse);
    });

    test('rejected blocks park for the session', () async {
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')
        ..keys['g'] = groupKey
        ..seed(['cid-9']);
      mesh([a, b]);
      var calls = 0;
      final SyncEngine engineA = SyncEngine(
        transport: a.transport,
        peerAddrsFor: (String groupId) async => [b.addr],
        groupKeyFor: (String groupId) async => groupKey,
        ledgerCids: (String groupId) async => const [],
        ledgerRecord: (String groupId, String cid) async {},
        applyBlock: (String groupId, String cid, Uint8List block) async {
          calls++;
          return ApplyOutcome.rejected;
        },
        localBlock: (String cid) async => null,
      );

      await engineA.synchronize(groupIds: ['g'], relayAddrs: const []);
      await engineA.synchronize(groupIds: ['g'], relayAddrs: const []);

      expect(calls, 1, reason: 'rejected once, parked after');
      expect(engineA.failedCids, {'cid-9'});
    });

    test('skips groups without a key and never dials self', () async {
      final FakeNode a = FakeNode('A');
      final FakeNode b = FakeNode('B')..keys['g'] = groupKey;
      mesh([a, b]);
      final SyncEngine engineA = a.engine(
        peerAddrs: {
          'g': [a.addr, b.addr],
          'unknown': [b.addr],
        },
      );

      final SyncReport report = await engineA.synchronize(
        groupIds: ['g', 'unknown'],
        relayAddrs: const [],
      );

      expect(report, SyncReport.empty);
      expect(report.hashCode, SyncReport.empty.hashCode);
      expect(a.transport.dials, isEmpty);
      expect(a.transport.requests.keys, isNot(contains('A')));
      expect(SyncEngine.topicFor('g'), 'vbank/group/g');
    });

    test('pushes missing blocks to relays, never to members', () async {
      final FakeNode member = FakeNode('M')..keys['g'] = groupKey;
      final FakeNode relay = FakeNode('R');
      // The relay is not a group member: no key, empty inventory.
      final FakeNode app = FakeNode('App')
        ..keys['g'] = groupKey
        ..seed(['cid-1', 'cid-2']);
      mesh([member, relay, app]);
      final SyncEngine engine = app.engine(
        peerAddrs: {
          'g': [member.addr],
        },
        maxPushPerRound: 40,
      );
      member.engine(peerAddrs: const {});

      final SyncReport report = await engine.synchronize(
        groupIds: ['g'],
        relayAddrs: ['/ip4/9.9.9.9/tcp/4001/p2p/R'],
      );

      expect(report.pushed, 2);
      expect(relay.transport.putsReceived, contains('cid-1'));
      expect(relay.transport.putsReceived, contains('cid-2'));
      expect(member.transport.putsReceived, isEmpty);
    });

    test('advertised blocks nobody can serve park as failed', () async {
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')..keys['g'] = groupKey;
      b.transport.inventoryCids.add('cid-ghost');
      mesh([a, b]);
      final SyncEngine engineA = a.engine(peerAddrs: {'g': [b.addr]});

      final SyncReport report = await engineA.synchronize(
        groupIds: ['g'],
        relayAddrs: const [],
      );

      expect(report.fetched, 0);
      expect(engineA.failedCids, {'cid-ghost'});
    });

    test('hearing from a peer clears its dial backoff', () async {
      final DateTime now = DateTime.utc(2026, 1, 1);
      final FakeNode a = FakeNode('A')..keys['g'] = groupKey;
      final FakeNode b = FakeNode('B')..keys['g'] = groupKey;
      mesh([a, b]);
      a.transport.downPeers.add('B');
      final SyncEngine engineA = a.engine(
        peerAddrs: {'g': [b.addr]},
        clock: () => now,
      );

      await engineA.synchronize(groupIds: ['g'], relayAddrs: const []);
      expect(engineA.peerInBackoff('B'), isTrue);

      // A request arriving from B proves reachability outright.
      await engineA.handleRequest(
        'B',
        Uint8List.fromList(
          utf8.encode(jsonEncode({'op': 'inventory', 'groupId': 'g'})),
        ),
      );

      expect(engineA.peerInBackoff('B'), isFalse);
    });

    test('pushes respect the per-round cap', () async {
      final FakeNode relay = FakeNode('R');
      final FakeNode app = FakeNode('App')
        ..keys['g'] = groupKey
        ..seed(['cid-1', 'cid-2', 'cid-3']);
      mesh([relay, app]);
      final SyncEngine engine = app.engine(
        peerAddrs: const {},
        maxPushPerRound: 2,
      );

      final SyncReport report = await engine.synchronize(
        groupIds: ['g'],
        relayAddrs: ['/ip4/9.9.9.9/tcp/4001/p2p/R'],
      );

      expect(report.pushed, 2);
    });
  });
}
