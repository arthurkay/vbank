import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vbank/src/sync/node_host.dart';
import 'package:vbank/src/sync/raw_cid.dart';

/// Exercises the relay like a member would: inventory, put, inventory,
//  fetch. Exits 0 only if a block round-trips through the relay.
Future<void> main() async {
  const relayId = '12D3KooWJS1crwXpCEyVgRKP11rXMtv1o1RLuP1s6FCzRegN7Her';
  const addr = '/ip4/41.63.62.125/tcp/4001/p2p/$relayId';
  const groupId = 'health-probe';
  final dir = await Directory.systemTemp.createTemp('vbank-health-');
  final node = IpfsNodeHost(
    ipfsDir: dir.path,
    listenPort: 4762,
    onState: (s, id) => stdout.writeln('node $s ${id ?? ''}'),
    onNotify: (_, _, _) {},
    onAddresses: (_) {},
    onRequest: (_, _) async => Uint8List(0),
  );
  Future<Uint8List?> ask(Map<String, Object?> req) => node
      .request(
        relayId,
        Uint8List.fromList(utf8.encode(jsonEncode(req))),
        const Duration(seconds: 15),
      )
      .timeout(const Duration(seconds: 20));
  try {
    await node.start().timeout(const Duration(seconds: 30));
    await node.connectToPeer(addr).timeout(const Duration(seconds: 20));
    stdout.writeln('connected');
    final block = Uint8List.fromList(
      utf8.encode('health ${DateTime.now().toUtc().toIso8601String()}'),
    );
    final cid = rawCidOf(block);
    final put = await ask({
      'op': 'put',
      'groupId': groupId,
      'cid': cid,
      'block': base64Encode(block),
      'addrs': <String>[],
    });
    stdout.writeln('put: ${put == null ? 'TIMEOUT' : utf8.decode(put)}');
    if (put == null) {
      exit(3);
    }
    final inv = await ask({'op': 'inventory', 'groupId': groupId});
    final listed = inv != null && utf8.decode(inv).contains(cid);
    stdout.writeln('inventory lists it: $listed');
    final fetched = await node
        .fetchFromPeers(cid, [relayId], const Duration(seconds: 15))
        .timeout(const Duration(seconds: 20));
    final ok = fetched != null && utf8.decode(fetched) == utf8.decode(block);
    stdout.writeln('fetch round-trips: $ok');
    exit(listed && ok ? 0 : 4);
  } catch (e) {
    stdout.writeln('FAILED: $e');
    exit(2);
  } finally {
    await node.stop().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
