import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';

/// Wire encoding for everything vBank puts on IPFS or in a backup file
/// (DESIGN_PLAN §5/§16: CBOR). Signatures are *not* computed over CBOR bytes
/// (CBOR re-encoding of a decoded structure is not guaranteed byte-identical);
/// they are computed over canonical JSON of the signed fields — see the
/// `signingPayload` helpers in the services.
class WireCodec {
  WireCodec._();

  /// CBOR-encodes a JSON-like structure (maps, lists, strings, numbers, bools,
  /// null, byte lists). `Uint8List` becomes a CBOR byte string; other
  /// `List<int>` stay arrays — both decode back to `List<int>`.
  static Uint8List encode(Object? value) => Uint8List.fromList(cborEncode(CborValue(value)));

  /// Decodes CBOR into plain Dart collections with `Map<String, dynamic>` maps
  /// so the models' `fromJson` factories work unchanged. Falls back to JSON
  /// for payloads written before the CBOR switch. Returns null if neither.
  static Object? tryDecode(List<int> bytes) {
    if (bytes.isEmpty) return null;
    // Legacy JSON payloads start with '{' or '['.
    if (bytes.first == 0x7b || bytes.first == 0x5b) {
      try {
        return jsonDecode(utf8.decode(bytes));
      } catch (_) {
        return null;
      }
    }
    try {
      return normalize(cborDecode(bytes).toObject());
    } catch (_) {
      return null;
    }
  }

  /// Same as [tryDecode] but requires a map at the top level.
  static Map<String, dynamic>? tryDecodeMap(List<int> bytes) {
    final v = tryDecode(bytes);
    return v is Map<String, dynamic> ? v : null;
  }

  /// Recursively converts `Map<Object?, Object?>` → `Map<String, dynamic>` and
  /// `List<Object?>` → `List<dynamic>`; byte strings become `Uint8List`.
  static Object? normalize(Object? v) {
    if (v is Map) {
      return <String, dynamic>{for (final e in v.entries) e.key.toString(): normalize(e.value)};
    }
    if (v is Uint8List) return v;
    if (v is List) return v.map(normalize).toList();
    return v;
  }
}
