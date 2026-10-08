import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vbank/src/sync/node_host.dart';

/// Minimal relay protocol check: dial the relay's advertised address and
/// ask for a group inventory. Exits 0 on a well-formed relay reply.
Future<void> main(List<String> args) async {
  final groupId = args.isNotEmpty ? args.first : 'probe';
  const addr =
      '/ip4/41.63.62.125/tcp/4001/p2p/12D3KooWJS1crwXpCEyVgRKP11rXMtv1o1RLuP1s6FCzRegN7Her';
  final dir = await Directory.systemTemp.createTemp('vbank-ping-');
  final node = IpfsNodeHost(
    ipfsDir: dir.path,
    listenPort: 4761,
    onState: (s, id) => stdout.writeln('node $s ${id ?? ''}'),
    onNotify: (_, _, _) {},
    onAddresses: (_) {},
    onRequest: (_, _) async => Uint8List(0),
  );
  try {
    await node.start().timeout(const Duration(seconds: 30));
    await node
        .connectToPeer(addr)
        .timeout(const Duration(seconds: 20));
    stdout.writeln('connected');
    final reply = await node
        .request(
          '12D3KooWJS1crwXpCEyVgRKP11rXMtv1o1RLuP1s6FCzRegN7Her',
          Uint8List.fromList(
            utf8.encode(jsonEncode({'op': 'inventory', 'groupId': groupId})),
          ),
          const Duration(seconds: 15),
        )
        .timeout(const Duration(seconds: 20));
    if (reply == null) {
      stdout.writeln('NO REPLY (timeout)');
      exit(3);
    }
    stdout.writeln('reply: ${utf8.decode(reply)}');
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
  exit(0);
}
