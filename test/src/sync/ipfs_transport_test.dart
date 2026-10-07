import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/sync/ipfs_transport.dart';

void main() {
  group('IpfsTransport', () {
    test('starts in a missing directory and stops', () async {
      final Directory before = Directory.current;
      final Directory base =
          await Directory.systemTemp.createTemp('vbank-transport-test-');
      final String ipfsDir = '${base.path}/nested/ipfs';
      expect(Directory(ipfsDir).existsSync(), isFalse);
      final IpfsTransport transport = IpfsTransport(
        ipfsDir: ipfsDir,
        listenPort: 4753,
        identitySeed: Uint8List.fromList(List.filled(32, 9)),
      );
      expect(transport.isRunning, isFalse);
      await transport.start();
      try {
        expect(transport.isRunning, isTrue);
        expect(transport.peerId, isNotNull);
        expect(transport.dialableAddresses, isNotEmpty);
      } finally {
        await transport.stop();
      }
      expect(transport.isRunning, isFalse);
      expect(Directory.current.path, before.path);
      await base.delete(recursive: true);
      expect(base.existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
