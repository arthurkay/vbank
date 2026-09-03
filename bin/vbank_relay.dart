/// vBank relay node — an always-on peer members reach over the internet.
///
///   dart run bin/vbank_relay.dart --data /var/lib/vbank-relay --port 4001 --public-host relay.example.com
///
/// `--public-host` gives members a /dns4/ address (preferred: survives IP
/// changes); `--public-ip` an /ip4/ one. `--public-port` when an external port
/// is mapped to the listen port; `--identity-seed` (base64, 32 bytes) pins the
/// peer id on hosts without persistent storage.
///
/// Build with `dart build cli -t bin/vbank_relay.dart -o build/relay`.
/// Environment variables VBANK_RELAY_DATA, VBANK_RELAY_PORT, VBANK_RELAY_PUBLIC_HOST,
/// VBANK_RELAY_PUBLIC_IP, VBANK_RELAY_PUBLIC_PORT and VBANK_RELAY_IDENTITY_SEED are
/// read when the flags are absent (used by the
/// Docker image in deploy/relay). Prints the multiaddr to hand to members.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final publicHost = flag('public-host') ?? env['VBANK_RELAY_PUBLIC_HOST'];
  final publicPort = int.tryParse(flag('public-port') ?? env['VBANK_RELAY_PUBLIC_PORT'] ?? '');
  final seedB64 = flag('identity-seed') ?? env['VBANK_RELAY_IDENTITY_SEED'];
  final verbose = args.contains('--verbose') || env['VBANK_RELAY_VERBOSE'] == '1';

  if ((publicHost == null || publicHost.isEmpty) && (publicIp == null || publicIp.isEmpty)) {
    stderr.writeln('warning: no --public-host / --public-ip; the printed address will be a local one');
  }
  Uint8List? seed;
  if (seedB64 != null && seedB64.isNotEmpty) {
    try {
      seed = base64Decode(seedB64.trim());
    } catch (_) {}
    if (seed == null || seed.length != 32) {
      stderr.writeln('error: identity seed must be 32 bytes, base64 (openssl rand -base64 32)');
      exit(64);
    }
  }

  final relay = RelayNode(
    dataDir: data,
    listenPort: port,
    publicIp: publicIp,
    publicHost: publicHost,
    publicPort: publicPort,
    identitySeed: seed,
    debugLog: verbose,
  );
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
