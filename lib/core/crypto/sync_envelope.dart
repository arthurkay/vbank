import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../codec/wire_codec.dart';
import 'encryption.dart';

/// Kinds of payload that travel over IPFS. Stored in the cleartext header so
/// a receiver knows how to interpret the plaintext after decrypting.
enum SyncPayloadType {
  transaction,
  groupSnapshot,
  memberJoin,
  loan,
  meeting,
  reversal,

  /// A member publishing their X25519 public key (MemberKeys) so admins can
  /// re-key them after a rotation.
  memberKey,
}

/// Thrown when an envelope cannot be opened with the supplied group key.
class EnvelopeAuthException implements Exception {
  final String message;
  const EnvelopeAuthException(this.message);
  @override
  String toString() => message;
}

/// The on-IPFS format for every vBank payload (DESIGN_PLAN §9/§11), encoded
/// as CBOR (§5):
///
///     signed record (CBOR)  ──XChaCha20-Poly1305(group key)──►  ciphertext
///
/// The header (`v`, `type`, `groupId`) is cleartext — `groupId` is a random
/// UUID and tells a receiver which key to try — but it is bound into the
/// AEAD as associated data, so it cannot be altered without failing the MAC.
class SyncEnvelope {
  static const currentVersion = 2;

  final int version;
  final SyncPayloadType type;
  final String groupId;
  final EncryptedData data;

  /// Group snapshots only: the group key wrapped once per live invite
  /// (invite id → blob, see InviteKeyWrap), readable without the group key so
  /// a joiner holding an invite secret can unwrap and open the snapshot.
  final Map<String, Uint8List> wraps;

  /// Which group key version encrypted [data]. Version 1 is the key a group
  /// started with; rotations increment it.
  final int keyVersion;

  /// Group snapshots only: the current key ring sealed for each active member
  /// (peer id → blob, see MemberKeys) so a rotation reaches everyone but the
  /// removed member.
  final Map<String, Uint8List> rekeys;

  const SyncEnvelope({
    this.version = currentVersion,
    required this.type,
    required this.groupId,
    required this.data,
    this.wraps = const {},
    this.keyVersion = 1,
    this.rekeys = const {},
  });

  static List<int> _aad(int version, SyncPayloadType type, String groupId, [int keyVersion = 1]) =>
      utf8.encode(keyVersion <= 1 ? 'vbank:$version:${type.name}:$groupId' : 'vbank:$version:${type.name}:$groupId:k$keyVersion');

  /// Encrypts [plaintextJson] for [groupId] and returns the envelope bytes to
  /// hand to `IpfsService.addData`.
  static Future<Uint8List> seal({
    required SyncPayloadType type,
    required String groupId,
    required Map<String, dynamic> plaintextJson,
    required SecretKey groupKey,
    Map<String, Uint8List> wraps = const {},
    int keyVersion = 1,
    Map<String, Uint8List> rekeys = const {},
  }) async {
    final plaintext = WireCodec.encode(plaintextJson);
    final encrypted = await EncryptionService.encrypt(
      plaintext,
      groupKey,
      aad: _aad(currentVersion, type, groupId, keyVersion),
    );
    return SyncEnvelope(type: type, groupId: groupId, data: encrypted, wraps: wraps, keyVersion: keyVersion, rekeys: rekeys)
        .encode();
  }

  Uint8List encode() => WireCodec.encode({
        'v': version,
        'type': type.name,
        'groupId': groupId,
        'nonce': Uint8List.fromList(data.nonce),
        'mac': Uint8List.fromList(data.mac),
        'ciphertext': Uint8List.fromList(data.ciphertext),
        if (wraps.isNotEmpty) 'wraps': {for (final e in wraps.entries) e.key: Uint8List.fromList(e.value)},
        if (keyVersion > 1) 'kv': keyVersion,
        if (rekeys.isNotEmpty) 'rekeys': {for (final e in rekeys.entries) e.key: Uint8List.fromList(e.value)},
      });

  /// Parses the cleartext header. Returns null if [bytes] is not an envelope
  /// (e.g. garbage from the network). Accepts v1 (JSON/base64) envelopes.
  static SyncEnvelope? tryDecode(List<int> bytes) {
    final json = WireCodec.tryDecodeMap(bytes);
    if (json == null) return null;
    try {
      final typeName = json['type'] as String?;
      final type = SyncPayloadType.values.where((t) => t.name == typeName).firstOrNull;
      if (type == null) return null;
      return SyncEnvelope(
        version: json['v'] as int? ?? currentVersion,
        type: type,
        groupId: json['groupId'] as String,
        data: EncryptedData(
          nonce: _bytes(json['nonce']),
          mac: _bytes(json['mac']),
          ciphertext: _bytes(json['ciphertext']),
        ),
        wraps: {
          for (final e in ((json['wraps'] as Map?) ?? const {}).entries)
            e.key as String: Uint8List.fromList(_bytes(e.value)),
        },
        keyVersion: json['kv'] as int? ?? 1,
        rekeys: {
          for (final e in ((json['rekeys'] as Map?) ?? const {}).entries)
            e.key as String: Uint8List.fromList(_bytes(e.value)),
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// v1 envelopes carried base64 strings; v2 carry CBOR byte strings.
  static List<int> _bytes(Object? v) {
    if (v is String) return base64Decode(v);
    return (v as List).cast<int>();
  }

  /// Decrypts and parses the payload. Throws [EnvelopeAuthException] on a
  /// wrong key or tampering.
  Future<Map<String, dynamic>> open(SecretKey groupKey) async {
    try {
      final plaintext = await EncryptionService.decrypt(
        data,
        groupKey,
        aad: _aad(version, type, groupId, keyVersion),
      );
      final decoded = WireCodec.tryDecodeMap(plaintext);
      if (decoded == null) throw const EnvelopeAuthException('Payload is not a vBank record');
      return decoded;
    } on SecretBoxAuthenticationError {
      throw const EnvelopeAuthException(
        'Could not decrypt: wrong group key or tampered data',
      );
    }
  }
}
