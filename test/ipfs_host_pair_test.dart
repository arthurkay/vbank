@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:dart_ipfs/src/transport/libp2p_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/ipfs/ipfs_node_host.dart';

/// Two real nodes in one process, talking over loopback: proves the three
/// vBank protocols (notify, direct fetch, request/response) end to end
/// without a second device. Run with `flutter test test/ipfs_host_pair_test.dart`.
void main() {
  late Directory tmp;
  late IpfsNodeHost a, b;
  final notifiedA = <String>[];
  final requestsSeenByA = <String>[];

  setUpAll(() async {
    Libp2pRouter.debugLog = true;
    tmp = await Directory.systemTemp.createTemp('vbank-pair-');
    a = IpfsNodeHost(
      ipfsDir: '${tmp.path}/a',
      listenPort: 4611,
      debugLog: true,
      onState: (state, peerId) {},
      onNotify: (topic, content, sender) => notifiedA.add('$topic|$content'),
      onAddresses: (_) {},
      onRequest: (from, payload) async {
        requestsSeenByA.add(utf8.decode(payload));
        return Uint8List.fromList(utf8.encode('echo:${utf8.decode(payload)}'));
      },
    );
    b = IpfsNodeHost(
      ipfsDir: '${tmp.path}/b',
      listenPort: 4612,
      debugLog: true,
      onState: (state, peerId) {},
      onNotify: (topic, content, sender) {},
      onAddresses: (_) {},
      onRequest: (from, payload) async => Uint8List(0),
    );
    await Directory('${tmp.path}/a').create();
    await Directory('${tmp.path}/b').create();
    await a.start();
    await b.start();
    await b.connectToPeer('/ip4/127.0.0.1/tcp/4611/p2p/${a.peerId}');
  });

  tearDownAll(() async {
    await a.stop();
    await b.stop();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('direct fetch returns the block held by the other node', () async {
    final data = Uint8List.fromList(utf8.encode('hello village bank ${DateTime.now()}'));
    final cid = await a.addData(data);
    final got = await b.fetchFromPeers(cid, [a.peerId!], const Duration(seconds: 10));
    expect(got, isNotNull, reason: 'B should fetch A\'s block over /vbank/fetch');
    expect(utf8.decode(got!), utf8.decode(data));
  });

  test('request/response round-trips through the responder', () async {
    final reply = await b.request(a.peerId!, Uint8List.fromList(utf8.encode('ping')), const Duration(seconds: 10));
    expect(reply, isNotNull);
    expect(utf8.decode(reply!), 'echo:ping');
    expect(requestsSeenByA, contains('ping'));
  });

  // ipfs_libp2p keeps one process-wide notion of "self", so in a single
  // process only the most recently created node can dial out; everything is
  // therefore exercised from B towards A. (Real deployments run one node per
  // process; the two-device E2E covers both directions.)
  test('notify reaches the other node', () async {
    final delivered = await b.publish('vbank/topic', '{"hello":1}', [a.peerId!]);
    expect(delivered, 1);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(notifiedA, contains('vbank/topic|{"hello":1}'));
  });
}
