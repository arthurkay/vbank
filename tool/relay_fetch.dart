import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/sync/node_host.dart';

/// Fetches exact CIDs from the relay: proves whether the desktop's
/// snapshots actually landed there. Prints each block's envelope header
/// (type, group, key version) without needing any group key.
/// Usage: dart run tool/relay_fetch.dart cid [cid...]
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('usage: relay_fetch.dart <cid> [cid...]');
    exit(64);
  }
  const relayId = '12D3KooWJS1crwXpCEyVgRKP11rXMtv1o1RLuP1s6FCzRegN7Her';
  const addr = '/ip4/41.63.62.125/tcp/4001/p2p/$relayId';
  final dir = await Directory.systemTemp.createTemp('vbank-fetch-');
  final node = IpfsNodeHost(
    ipfsDir: dir.path,
    listenPort: 4763,
    onState: (_, _) {},
    onNotify: (_, _, _) {},
    onAddresses: (_) {},
    onRequest: (_, _) async => Uint8List(0),
  );
  try {
    await node.start().timeout(const Duration(seconds: 30));
    await node.connectToPeer(addr).timeout(const Duration(seconds: 20));
    for (final cid in args) {
      final bytes = await node
          .fetchFromPeers(cid, [relayId], const Duration(seconds: 15))
          .timeout(const Duration(seconds: 20));
      if (bytes == null) {
        stdout.writeln('MISSING $cid');
        continue;
      }
      final SyncEnvelope? header = SyncEnvelope.tryDecode(bytes);
      final String detail = header == null
          ? 'undecodable'
          : 'type=${header.type.name} group=${header.groupId} '
              'kv=${header.keyVersion}';
      stdout.writeln('FOUND ${bytes.length}B $cid $detail');
    }
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
