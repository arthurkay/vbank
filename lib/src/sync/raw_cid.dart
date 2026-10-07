import 'package:crypto/crypto.dart';

/// CIDv1 · raw · sha2-256 in lower-case base32 (`bafkrei…`): the form
/// dart_ipfs gives every block we add with `addFile`.
///
/// Used to check that a block a peer hands us over `/vbank/fetch` really is the
/// one we asked for. (dart_ipfs's exported `CID.fromContent` encodes
/// differently from the node's own, so this is computed here.)
String rawCidOf(List<int> data) {
  final digest = sha256.convert(data).bytes;
  // version 1, codec raw (0x55), multihash sha2-256 (0x12) of 32 bytes.
  final bytes = <int>[0x01, 0x55, 0x12, 0x20, ...digest];
  return 'b${_base32Lower(bytes)}';
}

String _base32Lower(List<int> input) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = StringBuffer();
  var bits = 0;
  var value = 0;
  for (final byte in input) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(alphabet[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
    value &= 0xFFFF; // keep the accumulator small
  }
  if (bits > 0) out.write(alphabet[(value << (5 - bits)) & 31]);
  return out.toString();
}
