import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../codec/wire_codec.dart';
import 'encryption.dart';

/// Per-member encryption keys and the group key ring they carry.
///
/// Every identity already has an Ed25519 signing seed. From it we derive a
/// deterministic X25519 key pair (HKDF, separate label), whose public half a
/// member publishes in their roster entry (`Member.encKey`). Admins can then
/// hand a member new group keys that only that member can open — the
/// mechanism behind **key rotation**: when someone is removed, the owner
/// generates a new group key and the next snapshot carries it wrapped for each
/// remaining member; records published from then on use the new version and
/// the removed member's copy of the old keys decrypts none of them.
///
/// The **key ring** is the ordered set of a group's key versions
/// (`{version: key}`), so members who join later can still read history.
class MemberKeys {
  static final _x25519 = X25519();

  /// Deterministic X25519 key pair from the 32-byte identity seed.
  static Future<SimpleKeyPair> fromIdentitySeed(List<int> seed) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(seed),
      nonce: utf8.encode('vbank-member-x25519'),
    );
    return _x25519.newKeyPairFromSeed(await derived.extractBytes());
  }

  static Future<Uint8List> publicKeyBytes(SimpleKeyPair kp) async =>
      Uint8List.fromList((await kp.extractPublicKey()).bytes);

  static List<int> _aad(String groupId, String peerId) => utf8.encode('vbank-rekey:$groupId:$peerId');

  /// Seals [plaintext] for the member whose X25519 public key is
  /// [recipientPublicKey], from [sender]. CBOR: sender public key, nonce, mac,
  /// ciphertext. The recipient's peer id and the group are bound as AAD.
  static Future<Uint8List> seal({
    required List<int> plaintext,
    required SimpleKeyPair sender,
    required List<int> recipientPublicKey,
    required String groupId,
    required String recipientPeerId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: sender,
      remotePublicKey: SimplePublicKey(recipientPublicKey, type: KeyPairType.x25519),
    );
    final key = await _kdf(shared, groupId, recipientPeerId);
    final enc = await EncryptionService.encrypt(plaintext, key, aad: _aad(groupId, recipientPeerId));
    return WireCodec.encode({
      'from': await publicKeyBytes(sender),
      'n': Uint8List.fromList(enc.nonce),
      'm': Uint8List.fromList(enc.mac),
      'c': Uint8List.fromList(enc.ciphertext),
    });
  }

  /// Null when [recipient] is not the intended member or the blob is damaged.
  static Future<Uint8List?> open({
    required List<int> sealed,
    required SimpleKeyPair recipient,
    required String groupId,
    required String recipientPeerId,
  }) async {
    final m = WireCodec.tryDecodeMap(sealed);
    if (m == null) return null;
    try {
      final shared = await _x25519.sharedSecretKey(
        keyPair: recipient,
        remotePublicKey: SimplePublicKey((m['from'] as List).cast<int>(), type: KeyPairType.x25519),
      );
      final key = await _kdf(shared, groupId, recipientPeerId);
      final bytes = await EncryptionService.decrypt(
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

  static Future<SecretKey> _kdf(SecretKey shared, String groupId, String peerId) {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(secretKey: shared, nonce: utf8.encode('vbank-rekey:$groupId'), info: utf8.encode(peerId));
  }
}

/// A group's key versions, oldest first. Version 1 is the key a group was
/// created with; each rotation appends one.
class GroupKeyRing {
  final Map<int, Uint8List> keys;
  const GroupKeyRing(this.keys);

  int get currentVersion => keys.keys.fold(0, (a, b) => a > b ? a : b);
  Uint8List? operator [](int version) => keys[version];
  Uint8List get current => keys[currentVersion]!;

  Uint8List encode() => WireCodec.encode({for (final e in keys.entries) '${e.key}': e.value});

  /// Accepts a ring, or a bare 32-byte key (the pre-rotation wire form) as
  /// version 1.
  static GroupKeyRing? decode(List<int> bytes) {
    if (bytes.length == 32) return GroupKeyRing({1: Uint8List.fromList(bytes)});
    final m = WireCodec.tryDecodeMap(bytes);
    if (m == null) return null;
    try {
      final out = <int, Uint8List>{};
      for (final e in m.entries) {
        out[int.parse(e.key)] = Uint8List.fromList((e.value as List).cast<int>());
      }
      return out.isEmpty ? null : GroupKeyRing(out);
    } catch (_) {
      return null;
    }
  }
}
