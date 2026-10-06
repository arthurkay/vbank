import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encryption.dart';
import 'member_keys.dart';
import 'wire_codec.dart';

/// Per-invite wrapping of the group key.
///
/// Records are encrypted with a random data key. Instead of telling new
/// members a shared passphrase, an admin's invite carries a one-time
/// **secret** and the published group snapshot carries, in the clear, the
/// group key **wrapped** under a key derived from that secret — one entry
/// per live invite. The joiner unwraps, opens the snapshot and joins. When
/// the invite is used or expires, admins stop publishing its entry and the
/// secret unwraps nothing: a forwarded link dies with the invite.
abstract final class InviteKeyWrap {
  /// One-time secret length in bytes.
  static const int secretLength = 16;

  /// Generates a fresh one-time secret.
  static Uint8List randomSecret() {
    final Random rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(secretLength, (_) => rng.nextInt(256)),
    );
  }

  /// Encodes a secret for the invite link (unpadded base64url).
  static String encodeSecret(List<int> secret) =>
      base64UrlEncode(secret).replaceAll('=', '');

  /// Decodes a link secret, tolerating missing padding.
  static Uint8List decodeSecret(String s) {
    final String t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
    final String padded = t + '=' * ((4 - t.length % 4) % 4);
    return Uint8List.fromList(base64Decode(padded));
  }

  /// The wrap key is bound to the group and the invite, so a wrapped entry
  /// cannot be replayed under another invite id.
  static Future<SecretKey> _wrapKey(
    List<int> secret,
    String groupId,
    String inviteId,
  ) {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: utf8.encode('vbank-invite:$groupId'),
      info: utf8.encode(inviteId),
    );
  }

  static List<int> _aad(String groupId, String inviteId) =>
      utf8.encode('vbank-invite-wrap:$groupId:$inviteId');

  /// Wraps group key bytes for one invite.
  static Future<Uint8List> wrap({
    required SecretKey groupKey,
    required List<int> secret,
    required String groupId,
    required String inviteId,
  }) =>
      wrapBytes(
        plaintext: groupKey.extractBytes(),
        secret: secret,
        groupId: groupId,
        inviteId: inviteId,
      );

  /// Wraps arbitrary bytes (a [GroupKeyRing]) for one invite. CBOR blob of
  /// nonce, mac and ciphertext.
  static Future<Uint8List> wrapBytes({
    required Future<List<int>> plaintext,
    required List<int> secret,
    required String groupId,
    required String inviteId,
  }) async {
    final SecretKey wk = await _wrapKey(secret, groupId, inviteId);
    final EncryptedData enc = await EncryptionService.encrypt(
      await plaintext,
      wk,
      aad: _aad(groupId, inviteId),
    );
    return WireCodec.encode({
      'n': Uint8List.fromList(enc.nonce),
      'm': Uint8List.fromList(enc.mac),
      'c': Uint8List.fromList(enc.ciphertext),
    });
  }

  /// Unwraps to the raw bytes (a bare key or an encoded [GroupKeyRing]).
  /// Null when the secret does not fit this entry.
  static Future<Uint8List?> unwrapBytes({
    required List<int> wrapped,
    required List<int> secret,
    required String groupId,
    required String inviteId,
  }) async {
    final Map<String, dynamic>? m = WireCodec.tryDecodeMap(wrapped);
    if (m == null) {
      return null;
    }
    try {
      final SecretKey wk = await _wrapKey(secret, groupId, inviteId);
      final List<int> bytes = await EncryptionService.decrypt(
        EncryptedData(
          nonce: (m['n'] as List).cast<int>(),
          mac: (m['m'] as List).cast<int>(),
          ciphertext: (m['c'] as List).cast<int>(),
        ),
        wk,
        aad: _aad(groupId, inviteId),
      );
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Unwraps to a usable key. Null when the secret does not fit. A wrapped
  /// ring yields its current key.
  static Future<SecretKey?> unwrap({
    required List<int> wrapped,
    required List<int> secret,
    required String groupId,
    required String inviteId,
  }) async {
    final Uint8List? bytes = await unwrapBytes(
      wrapped: wrapped,
      secret: secret,
      groupId: groupId,
      inviteId: inviteId,
    );
    if (bytes == null) {
      return null;
    }
    if (bytes.length == 32) {
      return SecretKey(bytes);
    }
    final GroupKeyRing? ring = GroupKeyRing.decode(bytes);
    return ring == null ? null : SecretKey(ring.current);
  }
}
