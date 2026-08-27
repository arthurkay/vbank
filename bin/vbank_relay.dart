/// vBank relay node — an always-on peer members reach over the internet.
///
///   dart run bin/vbank_relay.dart --data /var/lib/vbank-relay --port 4001 --public-ip 203.0.113.7
///
/// Build with `dart build cli -t bin/vbank_relay.dart -o build/relay`.
/// Environment variables VBANK_RELAY_DATA, VBANK_RELAY_PORT and
/// VBANK_RELAY_PUBLIC_IP are read when the flags are absent (used by the
/// Docker image in deploy/relay). Prints the multiaddr to hand to members.
library;

import 'dart:async';
import 'dart:io';

import 'package:vbank/core/relay/relay_node.dart';

void main(List<String> args) async {
  String? flag(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final env = Platform.environment;
  final data = flag('data') ?? env['VBANK_RELAY_DATA'] ?? 'vbank-relay-data';
  final port = int.tryParse(flag('port') ?? env['VBANK_RELAY_PORT'] ?? '') ?? 4001;
  final publicIp = flag('public-ip') ?? env['VBANK_RELAY_PUBLIC_IP'];
  final verbose = args.contains('--verbose') || env['VBANK_RELAY_VERBOSE'] == '1';

  if (publicIp == null || publicIp.isEmpty) {
    stderr.writeln('warning: no --public-ip / VBANK_RELAY_PUBLIC_IP; the printed address will be a local one');
  }

  final relay = RelayNode(dataDir: data, listenPort: port, publicIp: publicIp, debugLog: verbose);
  await relay.start();

  Timer.periodic(const Duration(minutes: 10), (_) {
    stdout.writeln('[relay] up · blocks stored this run: ${relay.blocksStored} · notifications forwarded: ${relay.notificationsForwarded}');
  });

  for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    sig.watch().listen((_) async {
      stdout.writeln('[relay] stopping…');
      await relay.stop();
      exit(0);
    });
  }
}
