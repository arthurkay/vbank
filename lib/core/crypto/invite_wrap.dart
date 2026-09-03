import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../codec/wire_codec.dart';
import 'encryption.dart';

/// Per-invite wrapping of the group key.
///
/// A group's records are encrypted with a random data key. Instead of telling
/// new members a shared passphrase, an admin's invite carries a one-time
/// **secret** (in the link, `k=`) and the published group snapshot carries, in
/// the clear, the group key **wrapped** under a key derived from that secret —
/// one entry per live invite. The joiner unwraps, opens the snapshot and joins.
/// When the invite is used or expires, admins stop publishing its wrapped entry
/// and the secret unwraps nothing: a forwarded link dies with the invite.
class InviteKeyWrap {
  static const secretLength = 16;

  static Uint8List randomSecret() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(secretLength, (_) => rng.nextInt(256)));
  }

  static String encodeSecret(List<int> secret) => base64UrlEncode(secret).replaceAll('=', '');
  static Uint8List decodeSecret(String s) {
    var t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (t.length % 4 != 0) {
      t += '=';
    }
    return Uint8List.fromList(base64Decode(t));
  }

  /// The wrap key is bound to the group and the invite, so a wrapped entry
  /// cannot be replayed under another invite id.
  static Future<SecretKey> _wrapKey(List<int> secret, String groupId, String inviteId) {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: utf8.encode('vbank-invite:$groupId'),
      info: utf8.encode(inviteId),
    );
  }

  static List<int> _aad(String groupId, String inviteId) => utf8.encode('vbank-invite-wrap:$groupId:$inviteId');

  /// Group key bytes → wrapped blob (CBOR: nonce, mac, ciphertext).
  static Future<Uint8List> wrap({
    required SecretKey groupKey,
    required List<int> secret,
    required String groupId,
    required String inviteId,
  }) async {
    final wk = await _wrapKey(secret, groupId, inviteId);
    final enc = await EncryptionService.encrypt(await groupKey.extractBytes(), wk, aad: _aad(groupId, inviteId));
    return WireCodec.encode({
      'n': Uint8List.fromList(enc.nonce),
      'm': Uint8List.fromList(enc.mac),
      'c': Uint8List.fromList(enc.ciphertext),
    });
  }

  /// Null when the secret does not fit this wrapped entry.
  static Future<SecretKey?> unwrap({
    required List<int> wrapped,
    required List<int> secret,
    required String groupId,
    required String inviteId,
  }) async {
    final m = WireCodec.tryDecodeMap(wrapped);
    if (m == null) return null;
    try {
      final wk = await _wrapKey(secret, groupId, inviteId);
      final bytes = await EncryptionService.decrypt(
        EncryptedData(
          nonce: (m['n'] as List).cast<int>(),
          mac: (m['m'] as List).cast<int>(),
          ciphertext: (m['c'] as List).cast<int>(),
        ),
        wk,
        aad: _aad(groupId, inviteId),
      );
      return bytes.length == 32 ? SecretKey(bytes) : null;
    } catch (_) {
      return null;
    }
  }
}
