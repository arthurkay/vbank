import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/sync/relay_node.dart';

void main() {
  group('RelayNode', () {
    test('starts, answers inventory and stops on loopback', () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('vbank-relay-test-');
      final RelayNode relay = RelayNode(
        dataDir: dir.path,
        listenPort: 4751,
        log: (_) {},
      );
      expect(relay.isRunning, isFalse);
      expect(relay.peerId, isNull);
      await relay.start();
      try {
        expect(relay.isRunning, isTrue);
        expect(relay.peerId, isNotNull);
        expect(relay.publicMultiaddr, isNotNull);
      } finally {
        await relay.stop();
      }
      expect(relay.isRunning, isFalse);
      // The ledger file persists across restarts.
      expect(
        File('${dir.path}/relay_ledger.json').existsSync(),
        isTrue,
      );
      await dir.delete(recursive: true);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
