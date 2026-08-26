import 'dart:math';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:dart_ipfs/src/core/cid.dart' as node_cid;
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/ipfs/raw_cid.dart';

/// `IpfsService.fetchFromPeers` checks a peer's answer by recomputing its CID;
/// that must match what `IPFSNode.addFile` produced for the same bytes.
void main() {
  test('empty block has the well-known raw CID', () {
    expect(rawCidOf(const []), 'bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku');
  });

  test('matches the node\'s own CID for arbitrary data', () async {
    final rng = Random(7);
    for (final n in [1, 31, 32, 33, 1000, 1623]) {
      final data = Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
      final expected = (await node_cid.CID.fromContent(data, codec: 'raw')).toString();
      expect(rawCidOf(data), expected, reason: 'length $n');
    }
  });
}
