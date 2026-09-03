/// Probes a relay from this machine: resolves the dnsaddr TXT record, dials the
/// relay and asks for an inventory. Usage: dart run tool/relay/probe.dart [host]
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vbank/core/ipfs/ipfs_node_host.dart';
import 'package:vbank/core/relay/relay_directory.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args.first : kBuiltInRelayHosts.first;
  final addrs = await RelayDirectory().resolve(host);
  stdout.writeln('dnsaddr → $addrs');
  if (addrs.isEmpty) exit(2);
  final addr = addrs.first;
  final resolved = await IpfsNodeHost.resolveMultiaddr(addr);
  stdout.writeln('resolved → $resolved');
  final dir = await Directory.systemTemp.createTemp('vbank-probe-');
  final node = IpfsNodeHost(
    ipfsDir: dir.path,
    listenPort: 4741,
    debugLog: true,
    onState: (s, id) => stdout.writeln('node $s $id'),
    onNotify: (_, _, _) {},
    onAddresses: (_) {},
    onRequest: (_, _) async => Uint8List(0),
  );
  await node.start();
  try {
    final sw = Stopwatch()..start();
    await node.connectToPeer(addr).timeout(const Duration(seconds: 15));
    stdout.writeln('connected in ${sw.elapsedMilliseconds} ms');
    final peer = addr.split('/p2p/').last;
    final reply = await node.request(
      peer,
      Uint8List.fromList(utf8.encode(jsonEncode({'op': 'inventory', 'groupId': 'probe'}))),
      const Duration(seconds: 15),
    );
    stdout.writeln('inventory reply → ${reply == null ? 'null (timeout/dial failure)' : utf8.decode(reply)}');
  } catch (e) {
    stdout.writeln('FAILED: $e');
  } finally {
    await node.stop();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
  exit(0);
}
