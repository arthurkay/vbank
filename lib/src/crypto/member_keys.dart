import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encryption.dart';
import 'wire_codec.dart';

/// Per-member encryption keys and the group key ring they carry.
///
/// Every identity already has an Ed25519 signing seed. From it a
/// deterministic X25519 key pair is derived (HKDF, separate label), whose
/// public half a member publishes in their roster entry. Admins can then
/// hand a member new group keys that only that member can open — the
/// mechanism behind **key rotation**: when someone is removed, the owner
/// generates a new group key and the next snapshot carries it wrapped for
/// each remaining member; records published from then on use the new
/// version and the removed member's copy of the old keys decrypts none of
/// them.
///
/// The **key ring** is the ordered set of a group's key versions
/// (`{version: key}`), so members who join later can still read history.
abstract final class MemberKeys {
  /// The X25519 primitive.
  static final _x25519 = X25519();

  /// Deterministic X25519 key pair from the 32-byte identity seed.
  static Future<SimpleKeyPair> fromIdentitySeed(List<int> seed) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final SecretKey derived = await hkdf.deriveKey(
      secretKey: SecretKey(seed),
      nonce: utf8.encode('vbank-member-x25519'),
    );
    return _x25519.newKeyPairFromSeed(await derived.extractBytes());
  }

  /// Raw public-key bytes for roster storage.
  static Future<Uint8List> publicKeyBytes(SimpleKeyPair kp) async =>
      Uint8List.fromList((await kp.extractPublicKey()).bytes);

  static List<int> _aad(String groupId, String peerId) =>
      utf8.encode('vbank-rekey:$groupId:$peerId');

  /// Seals [plaintext] for the member holding [recipientPublicKey], sent
  /// from [sender]. CBOR: sender public key, nonce, mac, ciphertext. The
  /// recipient's peer id and the group are bound as AAD.
  static Future<Uint8List> seal({
    required List<int> plaintext,
    required SimpleKeyPair sender,
    required List<int> recipientPublicKey,
    required String groupId,
    required String recipientPeerId,
  }) async {
    final SecretKey shared = await _x25519.sharedSecretKey(
      keyPair: sender,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final SecretKey key = await _kdf(shared, groupId, recipientPeerId);
    final EncryptedData enc = await EncryptionService.encrypt(
      plaintext,
      key,
      aad: _aad(groupId, recipientPeerId),
    );
    return WireCodec.encode({
      'from': await publicKeyBytes(sender),
      'n': Uint8List.fromList(enc.nonce),
      'm': Uint8List.fromList(enc.mac),
      'c': Uint8List.fromList(enc.ciphertext),
    });
  }

  /// Opens a sealed blob. Null when [recipient] is not the intended member
  /// or the blob is damaged.
  static Future<Uint8List?> open({
    required List<int> sealed,
    required SimpleKeyPair recipient,
    required String groupId,
    required String recipientPeerId,
  }) async {
    final Map<String, dynamic>? m = WireCodec.tryDecodeMap(sealed);
    if (m == null) {
      return null;
    }
    try {
      final SecretKey shared = await _x25519.sharedSecretKey(
        keyPair: recipient,
        remotePublicKey: SimplePublicKey(
          (m['from'] as List).cast<int>(),
          type: KeyPairType.x25519,
        ),
      );
      final SecretKey key = await _kdf(shared, groupId, recipientPeerId);
      final List<int> bytes = await EncryptionService.decrypt(
        EncryptedData(
          nonce: (m['n'] as List).cast<int>(),
          mac: (m['m'] as List).cast<int>(),
          ciphertext: (m['c'] as List).cast<int>(),
        ),
        key,
        aad: _aad(groupId, recipientPeerId),
      );
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<SecretKey> _kdf(
    SecretKey shared,
    String groupId,
    String peerId,
  ) {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('vbank-rekey:$groupId'),
      info: utf8.encode(peerId),
    );
  }
}

/// A group's key versions, oldest first. Version 1 is the key a group was
/// created with; each rotation appends one.
final class GroupKeyRing {
  /// Version number → key bytes.
  final Map<int, Uint8List> keys;

  /// Creates a ring. Prefer [decode] for wire bytes.
  const GroupKeyRing(this.keys);

  /// Highest version present.
  int get currentVersion =>
      keys.keys.fold(0, (int a, int b) => a > b ? a : b);

  /// The key for [version], or null when never issued.
  Uint8List? operator [](int version) => keys[version];

  /// The newest key.
  Uint8List get current => keys[currentVersion]!;

  /// Encodes the ring to bytes.
  Uint8List encode() => WireCodec.encode({
        for (final MapEntry<int, Uint8List> e in keys.entries)
          '${e.key}': e.value,
      });

  /// Decodes a ring, or a bare 32-byte key (the pre-rotation wire form) as
  /// version 1. Null on garbage.
  static GroupKeyRing? decode(List<int> bytes) {
    if (bytes.length == 32) {
      return GroupKeyRing({1: Uint8List.fromList(bytes)});
    }
    final Map<String, dynamic>? m = WireCodec.tryDecodeMap(bytes);
    if (m == null) {
      return null;
    }
    try {
      final Map<int, Uint8List> out = {};
      for (final MapEntry<String, dynamic> e in m.entries) {
        out[int.parse(e.key)] = Uint8List.fromList(
          (e.value as List).cast<int>(),
        );
      }
      return out.isEmpty ? null : GroupKeyRing(out);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupKeyRing &&
          keys.length == other.keys.length &&
          keys.entries.every(
            (MapEntry<int, Uint8List> e) =>
                _equal(other.keys[e.key], e.value),
          );

  @override
  int get hashCode => Object.hashAll(
        keys.entries.map(
          (MapEntry<int, Uint8List> e) =>
              Object.hash(e.key, Object.hashAll(e.value)),
        ),
      );

  static bool _equal(Uint8List? a, Uint8List b) {
    if (a == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
