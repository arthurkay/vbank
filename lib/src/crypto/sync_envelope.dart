import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encryption.dart';
import 'wire_codec.dart';

/// Kinds of payload that travel over IPFS. Stored in the cleartext header
/// so a receiver knows how to interpret the plaintext after decrypting.
enum SyncPayloadType {
  /// A signed transaction.
  transaction,

  /// The full group state (membership, config, sequence).
  groupSnapshot,

  /// A new member announcing themselves.
  memberJoin,

  /// A loan request or decision.
  loan,

  /// A meeting or attendance update.
  meeting,

  /// A correction request or decision.
  reversal,

  /// A member publishing their X25519 public key so admins can re-key
  /// them after a rotation.
  memberKey,
}

/// The open failure of [SyncEnvelope.open]: wrong key or tampered data.
/// Services map this to `IntegrityFailure`.
final class EnvelopeAuthException implements Exception {
  /// What could not be opened and why.
  final String message;

  /// Creates an envelope failure with [message].
  const EnvelopeAuthException(this.message);

  @override
  String toString() => message;
}

/// The on-IPFS format for every vBank payload, CBOR-encoded:
///
///     signed record (CBOR) ──XChaCha20-Poly1305(group key)──► ciphertext
///
/// The header (`v`, `type`, `groupId`) is cleartext — `groupId` is a random
/// UUID and tells a receiver which key to try — but it is bound into the
/// AEAD as associated data, so it cannot be altered without failing the MAC.
///
/// Byte-identical to the legacy format: old and rewritten nodes read each
/// other's records.
final class SyncEnvelope {
  /// Envelopes written by this code.
  static const int currentVersion = 2;

  /// Envelope version that sealed this payload.
  final int version;

  /// What kind of record the plaintext holds.
  final SyncPayloadType type;

  /// Which group's key opens it.
  final String groupId;

  /// The encrypted payload.
  final EncryptedData data;

  /// Group snapshots only: the group key wrapped once per live invite
  /// (invite id → blob), readable without the group key so a joiner holding
  /// an invite secret can unwrap and open the snapshot.
  final Map<String, Uint8List> wraps;

  /// Which group key version encrypted [data]. Version 1 is the key a group
  /// started with; rotations increment it.
  final int keyVersion;

  /// Group snapshots only: the current key ring sealed for each active
  /// member (peer id → blob) so a rotation reaches everyone but the
  /// removed member.
  final Map<String, Uint8List> rekeys;

  /// Creates an envelope.
  const SyncEnvelope({
    this.version = currentVersion,
    required this.type,
    required this.groupId,
    required this.data,
    this.wraps = const {},
    this.keyVersion = 1,
    this.rekeys = const {},
  });

  /// Associated data binding version, type, group and key version into the
  /// MAC. The exact strings are wire-critical: changing them orphans every
  /// record already on the network.
  static List<int> _aad(
    int version,
    SyncPayloadType type,
    String groupId, [
    int keyVersion = 1,
  ]) =>
      utf8.encode(
        keyVersion <= 1
            ? 'vbank:$version:${type.name}:$groupId'
            : 'vbank:$version:${type.name}:$groupId:k$keyVersion',
      );

  /// Encrypts [plaintextJson] for [groupId] and returns the envelope bytes
  /// to store and publish.
  static Future<Uint8List> seal({
    required SyncPayloadType type,
    required String groupId,
    required Map<String, dynamic> plaintextJson,
    required SecretKey groupKey,
    Map<String, Uint8List> wraps = const {},
    int keyVersion = 1,
    Map<String, Uint8List> rekeys = const {},
  }) async {
    final Uint8List plaintext = WireCodec.encode(plaintextJson);
    final EncryptedData encrypted = await EncryptionService.encrypt(
      plaintext,
      groupKey,
      aad: _aad(currentVersion, type, groupId, keyVersion),
    );
    return SyncEnvelope(
      type: type,
      groupId: groupId,
      data: encrypted,
      wraps: wraps,
      keyVersion: keyVersion,
      rekeys: rekeys,
    ).encode();
  }

  /// Encodes this envelope to bytes.
  Uint8List encode() => WireCodec.encode({
        'v': version,
        'type': type.name,
        'groupId': groupId,
        'nonce': Uint8List.fromList(data.nonce),
        'mac': Uint8List.fromList(data.mac),
        'ciphertext': Uint8List.fromList(data.ciphertext),
        if (wraps.isNotEmpty)
          'wraps': {
            for (final MapEntry<String, Uint8List> e in wraps.entries)
              e.key: Uint8List.fromList(e.value),
          },
        if (keyVersion > 1) 'kv': keyVersion,
        if (rekeys.isNotEmpty)
          'rekeys': {
            for (final MapEntry<String, Uint8List> e in rekeys.entries)
              e.key: Uint8List.fromList(e.value),
          },
      });

  /// Parses the cleartext header. Null when [bytes] is not an envelope
  /// (e.g. garbage from the network). Accepts v1 (JSON/base64) envelopes.
  static SyncEnvelope? tryDecode(List<int> bytes) {
    final Map<String, dynamic>? json = WireCodec.tryDecodeMap(bytes);
    if (json == null) {
      return null;
    }
    try {
      final String? typeName = json['type'] as String?;
      SyncPayloadType? type;
      for (final SyncPayloadType t in SyncPayloadType.values) {
        if (t.name == typeName) {
          type = t;
        }
      }
      if (type == null) {
        return null;
      }
      final Map<String, dynamic> wrapsJson =
          ((json['wraps'] as Map?) ?? const {}).cast<String, dynamic>();
      final Map<String, dynamic> rekeysJson =
          ((json['rekeys'] as Map?) ?? const {}).cast<String, dynamic>();
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
          for (final MapEntry<String, dynamic> e in wrapsJson.entries)
            e.key: Uint8List.fromList(_bytes(e.value)),
        },
        keyVersion: json['kv'] as int? ?? 1,
        rekeys: {
          for (final MapEntry<String, dynamic> e in rekeysJson.entries)
            e.key: Uint8List.fromList(_bytes(e.value)),
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// v1 envelopes carried base64 strings; v2 carry CBOR byte strings.
  static List<int> _bytes(Object? v) {
    if (v is String) {
      return base64Decode(v);
    }
    return (v as List).cast<int>();
  }

  /// Decrypts and parses the payload. Throws [EnvelopeAuthException] on a
  /// wrong key or tampering.
  Future<Map<String, dynamic>> open(SecretKey groupKey) async {
    try {
      final List<int> plaintext = await EncryptionService.decrypt(
        data,
        groupKey,
        aad: _aad(version, type, groupId, keyVersion),
      );
      final Map<String, dynamic>? decoded = WireCodec.tryDecodeMap(plaintext);
      if (decoded == null) {
        throw const EnvelopeAuthException('Payload is not a vBank record');
      }
      return decoded;
    } on SecretBoxAuthenticationError {
      throw const EnvelopeAuthException(
        'Could not decrypt: wrong group key or tampered data',
      );
    }
  }
}
