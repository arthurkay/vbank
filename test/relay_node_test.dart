@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/ipfs/ipfs_node_host.dart';
import 'package:vbank/core/ipfs/raw_cid.dart';
import 'package:vbank/core/relay/relay_node.dart';
// ignore: implementation_imports
import 'package:dart_ipfs/src/transport/libp2p_router.dart' show Libp2pRouter;

/// A relay and one device over loopback. Only the most recently created node
/// can dial out in-process (ipfs_libp2p keeps one "self"), so the relay is
/// created first and the device dials it — exactly the production direction:
/// devices behind NAT connect out, the relay answers over that connection.
void main() {
  late Directory tmp;
  late RelayNode relay;
  late IpfsNodeHost device;
  final notifiedDevice = <String>[];

  setUpAll(() async {
    Libp2pRouter.debugLog = true;
    tmp = await Directory.systemTemp.createTemp('vbank-relay-');
    relay = RelayNode(dataDir: '${tmp.path}/relay', listenPort: 4621, publicIp: '127.0.0.1', log: (l) => debugPrint('[relay] $l'));
    await relay.start();
    device = IpfsNodeHost(
      ipfsDir: '${tmp.path}/device',
      listenPort: 4622,
      debugLog: true,
      onState: (_, _) {},
      onNotify: (topic, content, sender) => notifiedDevice.add('$topic|$content|$sender'),
      onAddresses: (_) {},
      onRequest: (from, payload) async => Uint8List(0),
    );
    await Directory('${tmp.path}/device').create(recursive: true);
    await device.start();
    await device.connectToPeer(relay.publicMultiaddr!);
  });

  tearDownAll(() async {
    await device.stop();
    await relay.stop();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Uint8List json(Map<String, dynamic> m) => Uint8List.fromList(utf8.encode(jsonEncode(m)));

  test('relay address is public ip + port + peer id', () {
    expect(relay.publicMultiaddr, '/ip4/127.0.0.1/tcp/4621/p2p/${relay.peerId}');
  });

  test('device puts a block; relay lists it in the inventory and serves it back', () async {
    final block = Uint8List.fromList(utf8.encode('encrypted record ${DateTime.now()}'));
    final cid = rawCidOf(block);
    final reply = await device.request(
      relay.peerId!,
      json({'op': 'put', 'groupId': 'g1', 'cid': cid, 'block': base64Encode(block), 'addrs': <String>[]}),
      const Duration(seconds: 10),
    );
    expect(reply, isNotNull);
    expect(jsonDecode(utf8.decode(reply!)), containsPair('stored', true));

    final inv = await device.request(relay.peerId!, json({'op': 'inventory', 'groupId': 'g1'}), const Duration(seconds: 10));
    expect(inv, isNotNull);
    final decoded = jsonDecode(utf8.decode(inv!)) as Map;
    expect(decoded['cids'], [cid]);
    expect(decoded['relay'], isTrue);

    final got = await device.fetchFromPeers(cid, [relay.peerId!], const Duration(seconds: 10));
    expect(got, isNotNull);
    expect(got, block);

    // Other groups are untouched; malformed CIDs are refused.
    final other = await device.request(relay.peerId!, json({'op': 'inventory', 'groupId': 'g2'}), const Duration(seconds: 10));
    expect((jsonDecode(utf8.decode(other!)) as Map)['cids'], isEmpty);
    final bad = await device.request(
      relay.peerId!,
      json({'op': 'put', 'groupId': 'g1', 'cid': 'bafkreinotthecid', 'block': base64Encode(block)}),
      const Duration(seconds: 10),
    );
    expect(bad, isEmpty);
    expect(relay.blocksStored, 1);
  });

  test('ledger survives a restart of the relay', () async {
    final before = relay.blocksStored;
    await relay.stop();
    relay = RelayNode(dataDir: '${tmp.path}/relay', listenPort: 4621, publicIp: '127.0.0.1', log: (l) => debugPrint('[relay] $l'));
    await relay.start();
    expect(relay.blocksStored, 0, reason: 'counter is per run');
    // The ledger file is what matters.
    final ledger = jsonDecode(await File('${tmp.path}/relay/relay_ledger.json').readAsString()) as Map;
    expect((ledger['g1'] as List).length, before);
  });
}
